#!/bin/bash
# Build and install a pinned upstream git into a user-owned prefix.
#
# Why this exists: some tools (e.g. the Graphite CLI) require a git newer than
# the one Apple's CLT ships. On this host the system git is 2.37.1 and no
# supported package manager is available, so git is built from the official
# tarball into a user-owned prefix. No sudo, no system directories touched.
#
# Usage:
#   scripts/install-git-source.sh [--version X.Y.Z --sha256 HEX]
#                                 [--prefix DIR] [--force] [--check] [--dry-run]
#
#   --check     report what is installed and what would change; install nothing
#   --dry-run   download, verify and build, but skip `make install`
#   --force     rebuild even when the requested version is already installed
#   --version   build a version other than the pinned one; requires --sha256
#   --sha256    checksum for that version; requires --version
#
# Version and checksum are pinned below. Bumping either is a deliberate edit:
# the SHA256 is reviewed in the commit and cross-checked against the upstream
# signed manifest at build time. --version and --sha256 override the pair and
# must be given together.

set -euo pipefail

# --- Pinned inputs -----------------------------------------------------------

GIT_VERSION="2.56.0"
GIT_SHA256="26c56c296b38c0695b26fa95f475f1d01704d2d38e73465ca30b0b2f5dc789d3"
# The pinned pair above is the trust anchor. --version/--sha256 may override both,
# but only together: a different tarball has a different checksum, and pairing one
# flag without the other silently verifies the new tarball against the old pin.
# Remember the defaults so the pairing check below compares against them instead
# of re-stating them.
PINNED_VERSION="$GIT_VERSION"
GIT_VERSION_OVERRIDDEN=0
GIT_SHA256_OVERRIDDEN=0

# Upstream release tarball plus the checksum manifest that lists it. Both may be
# redirected with GIT_SOURCE_DOWNLOAD_BASE, which the test suite uses to serve a
# local file:// URL instead of hitting the network. The pinned SHA256 is the
# trust anchor either way, so overriding the host cannot weaken verification.
DOWNLOAD_BASE="${GIT_SOURCE_DOWNLOAD_BASE:-https://mirrors.edge.kernel.org/pub/software/scm/git}"
SHA256_MANIFEST="${DOWNLOAD_BASE}/sha256sums.asc"

# Install prefix. Must stay ahead of /usr/bin and /usr/local/bin on PATH;
# shared/platform.sh already orders ~/.local/bin above both.
PREFIX="${HOME}/.local"

# Minimum git required by the Graphite CLI. The build is refused below this,
# and the comparison is numeric rather than lexical.
REQUIRED_MIN_VERSION="2.38.0"

# MacPorts prefix. Used for libcurl/expat/zlib when present, because macOS ships
# no /usr/lib/libcurl and an unqualified build can end up without working HTTP
# remotes.
PORT_PREFIX="/opt/local"

# --- Runtime state -----------------------------------------------------------

SCRIPT_NAME="${0##*/}"
WORK_DIR=""

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1"; }
warn() { log "WARNING: $1" >&2; }
die() {
  log "ERROR: $1" >&2
  exit 1
}

cleanup() {
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

# --- Helpers -----------------------------------------------------------------

# Print the names of any missing commands, one per line. Never installs: this
# repo keeps installation out of bootstrap and startup paths (AGENTS.md,
# "No Package Manager Automation").
missing_prereq() {
  local missing=() cmd
  for cmd in "$@"; do
    command -v "$cmd" > /dev/null 2>&1 || missing+=("$cmd")
  done
  [ ${#missing[@]} -gt 0 ] && printf '%s\n' "${missing[@]}"
  return 0
}

# Compare dotted versions numerically. Prints -1, 0 or 1 for a<b, a==b, a>b.
# Trailing pre-release suffixes are ignored so 2.56.0.rc1 sorts as 2.56.0.
version_cmp() {
  local a="${1%%-*}" b="${2%%-*}"
  local -a A B
  IFS='.' read -r -a A <<< "$a"
  IFS='.' read -r -a B <<< "$b"
  local i x y
  for i in 0 1 2; do
    x="${A[i]:-0}"
    y="${B[i]:-0}"
    x="${x//[!0-9]/}"
    y="${y//[!0-9]/}"
    x="${x:-0}"
    y="${y:-0}"
    if [ "$x" -lt "$y" ]; then
      printf '%s' "-1"
      return 0
    fi
    if [ "$x" -gt "$y" ]; then
      printf '%s' "1"
      return 0
    fi
  done
  printf '%s' "0"
}

# True when $1 >= $2.
version_ge() {
  [ "$(version_cmp "$1" "$2")" != "-1" ]
}

# Report the git currently visible on PATH, or nothing when absent.
current_git_version() {
  command -v git > /dev/null 2>&1 || return 0
  git --version 2> /dev/null | awk '{print $3}'
}

# Locate a SHA256 tool; shasum and sha256sum are the same utility under two names.
find_sha_tool() {
  local c
  for c in sha256sum shasum; do
    if command -v "$c" > /dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

# Print the SHA256 of a file. The two tools are NOT interchangeable: GNU
# coreutils' sha256sum defaults to SHA-256 and rejects `-a` ("invalid option"),
# while Perl's shasum needs `-a 256` to select the algorithm.
sha256_of() {
  local tool="$1" file="$2"
  case "$tool" in
    sha256sum) sha256sum "$file" | awk '{print $1}' ;;
    shasum) shasum -a 256 "$file" | awk '{print $1}' ;;
    *) die "unknown sha256 tool: $tool" ;;
  esac
}

# Parallel job count, honouring MAKEFLAGS from a login shell when it carries -j.
detect_jobs() {
  local jobs="${MAKEFLAGS:-}"
  jobs="${jobs#-j}"
  jobs="${jobs%% *}"
  if [[ "$jobs" =~ ^[0-9]+$ ]] && [ "$jobs" -ge 1 ]; then
    printf '%s' "$jobs"
    return 0
  fi
  if command -v nproc > /dev/null 2>&1; then
    nproc 2> /dev/null || echo 2
    return 0
  fi
  sysctl -n hw.ncpu 2> /dev/null || echo 2
}

# --- Argument parsing --------------------------------------------------------

FORCE=0
CHECK_ONLY=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      [ $# -ge 2 ] || die "--version needs a value"
      GIT_VERSION="$2"
      GIT_VERSION_OVERRIDDEN=1
      shift 2
      ;;
    --sha256)
      [ $# -ge 2 ] || die "--sha256 needs a value"
      GIT_SHA256="$2"
      GIT_SHA256_OVERRIDDEN=1
      shift 2
      ;;
    --prefix)
      [ $# -ge 2 ] || die "--prefix needs a value"
      PREFIX="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (try --help)"
      ;;
  esac
done

TARGET_GIT="$PREFIX/bin/git"

# --- Validate the pin ---------------------------------------------------------

# A checksum must be 64 lowercase hex characters; anything else cannot match a
# real SHA256 and would fail later with a confusing "mismatch" instead of a
# clear argument error.
case "$GIT_SHA256" in
  *[!0-9a-f]* | "")
    die "invalid --sha256: expected 64 lowercase hex characters, got '$GIT_SHA256'"
    ;;
esac
[ "${#GIT_SHA256}" -eq 64 ] ||
  die "invalid --sha256: expected 64 hex characters, got ${#GIT_SHA256}"

# --version and --sha256 describe one artefact, so they must be supplied as a
# pair. Overriding only the version would download a different tarball and
# verify it against the pinned checksum, failing the build for a reason that
# looks like tampering.
#
# The two halves are checked at different points, because they differ:
#   * --sha256 alone is always meaningless -- the pinned version's checksum is
#     already in GIT_SHA256 -- so it is rejected immediately, before any
#     download or "already installed" short circuit can hide the mistake.
#   * --version alone is legitimate for --check, which answers a question about
#     a version without fetching anything. It is rejected only on a path that
#     would actually download and verify a tarball.
if [ "$GIT_SHA256_OVERRIDDEN" -eq 1 ] && [ "$GIT_VERSION_OVERRIDDEN" -eq 0 ]; then
  die "--sha256 only makes sense together with --version.
  A checksum describes one tarball, and the pinned version's checksum is
  already in GIT_SHA256. Re-pin GIT_VERSION and GIT_SHA256 in the script,
  or pass both flags."
fi

validate_pin_pairing() {
  if [ "$GIT_VERSION_OVERRIDDEN" -eq 0 ]; then
    return 0
  fi
  if [ "$GIT_VERSION" = "$PINNED_VERSION" ] && [ "$GIT_SHA256_OVERRIDDEN" -eq 0 ]; then
    # Still the pinned version, so the pinned checksum is correct for it.
    return 0
  fi
  if [ "$GIT_SHA256_OVERRIDDEN" -eq 0 ]; then
    die "--version $GIT_VERSION only makes sense together with --sha256.
  A different tarball has a different checksum, and verifying it against the
  pinned GIT_SHA256 would fail as if the download were tampered.
  Re-pin GIT_VERSION and GIT_SHA256 in the script, or pass both flags."
  fi
}

# --- Report current state ----------------------------------------------------

PATH_GIT="$(command -v git 2> /dev/null || true)"
PATH_VERSION=""
[ -n "$PATH_GIT" ] && PATH_VERSION="$(current_git_version)"

log "script:     $SCRIPT_NAME"
log "prefix:     $PREFIX"
log "requested:  git $GIT_VERSION"
log "on PATH:    ${PATH_VERSION:-<none>} (${PATH_GIT:-not found})"

if [ -x "$TARGET_GIT" ]; then
  PREFIX_VERSION="$("$TARGET_GIT" --version 2> /dev/null | awk '{print $3}')"
  log "prefix git: $PREFIX_VERSION"
else
  PREFIX_VERSION=""
  log "prefix git: <not installed>"
fi

# Refuse to build something the toolchain would reject anyway.
if ! version_ge "$GIT_VERSION" "$REQUIRED_MIN_VERSION"; then
  die "requested git $GIT_VERSION is below the required minimum $REQUIRED_MIN_VERSION"
fi

# --- Check-only mode ---------------------------------------------------------

# Refuse a prefix that this script would destructively clean. It replaces
# <prefix>/bin/git and <prefix>/libexec/git-core, so a package-managed or shared
# prefix would be damaged. The promise in AGENTS.md is a user-owned prefix;
# enforce it.
#
# Normalize before matching, and require an absolute path. Without this,
# `--prefix /usr/local/..` slips past a literal glob, a bare `--prefix /` matches
# no pattern at all (and would write /bin/git), and a relative prefix resolves
# against whatever directory the install happens to run in.
if [ "${PREFIX#/}" = "$PREFIX" ]; then
  die "--prefix must be an absolute path (got '$PREFIX')
  A relative prefix would resolve against the current directory at install time.
  Use something like \$HOME/.local."
fi

# Canonicalize so symlinks and dot segments cannot disguise a system prefix.
# Fall back to the literal value when the path does not exist yet (a fresh
# prefix is normal) or python3 is unavailable; the literal match still applies.
NORMALISED_PREFIX="$PREFIX"
if command -v python3 > /dev/null 2>&1; then
  NORMALISED_PREFIX="$(python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$PREFIX" 2> /dev/null || printf '%s' "$PREFIX")"
fi

case "$NORMALISED_PREFIX" in
  / | /usr | /usr/* | /bin | /bin/* | /sbin | /sbin/* | /etc | /etc/* | /System | /System/* | /Library | /Library/* | /Applications | /Applications/* | /private/etc | /private/var | /dev | /dev/*)
    die "refusing to install into system path: $NORMALISED_PREFIX
  This script replaces <prefix>/bin/git and <prefix>/libexec/git-core.
  Use a user-owned prefix such as \$HOME/.local."
    ;;
  /opt/homebrew | /opt/homebrew/* | /opt/local | /opt/local/* | /sw | /sw/* | /nix | /nix/*)
    die "refusing to install into a package-managed prefix: $NORMALISED_PREFIX
  This script replaces <prefix>/bin/git and <prefix>/libexec/git-core.
  Use a user-owned prefix such as \$HOME/.local."
    ;;
esac

if [ "$CHECK_ONLY" -eq 1 ]; then
  # Distinct name from the missing_prereq function: a variable called `missing`
  # collides with it in shellcheck's view and hides real findings.
  # perl is not optional: git's configure refuses to run without it
  # ("You cannot use git without perl") and GIT-VERSION-FILE is generated by a
  # perl script, so a host without perl fails deep into the build.
  prereq_gaps="$(missing_prereq make cc perl tar xz curl)"
  sha_tool="$(find_sha_tool || true)"
  if [ -z "$sha_tool" ]; then
    prereq_gaps="${prereq_gaps:+$prereq_gaps +}sha256sum-or-shasum"
  fi

  if [ "$FORCE" -eq 0 ] && [ "$PREFIX_VERSION" = "$GIT_VERSION" ]; then
    log "check: git $PREFIX_VERSION already in $PREFIX — nothing to do"
    exit 0
  fi

  # Report the intended action before the prerequisite verdict. `--check` is a
  # reporting mode: a caller on a host that lacks a build tool still needs to
  # know what the script *would* do, so the plan is never withheld. This also
  # keeps the mode useful on CI images without a compiler.
  #
  # The forecast must match what a plain run would actually do. A plain run only
  # short-circuits when the *prefix* already has the pinned version, so a
  # sufficiently new git on PATH is NOT a reason to say "nothing to do" — this
  # script would still build into the prefix. Never exit 0 on the PATH state.
  if [ -n "$PREFIX_VERSION" ]; then
    log "check: would rebuild $PREFIX_VERSION -> $GIT_VERSION"
  else
    if [ -n "$PATH_VERSION" ] && version_ge "$PATH_VERSION" "$GIT_VERSION"; then
      log "check: note: PATH already has git $PATH_VERSION, but the pinned build still installs into $PREFIX"
    fi
    log "check: would build git $GIT_VERSION into $PREFIX"
  fi

  if [ -n "$prereq_gaps" ]; then
    warn "check: missing prerequisites (the build would fail until these exist):"
    printf '%s\n' "$prereq_gaps" | sed 's/^/  /' >&2
    exit 1
  fi

  log "check: prerequisites present (sha tool: ${sha_tool:-none})"
  exit 0
fi

# --- Already satisfied -------------------------------------------------------

if [ "$FORCE" -eq 0 ] && [ "$PREFIX_VERSION" = "$GIT_VERSION" ]; then
  log "git $PREFIX_VERSION is already installed in $PREFIX; use --force to rebuild"
  exit 0
fi

# --- Prerequisites -----------------------------------------------------------

HAVE_SHA="$(find_sha_tool || true)"
[ -n "$HAVE_SHA" ] || die "need sha256sum or shasum to verify the download"

# Escape hatch for the test suite: skip only the *build-tool* prerequisite gate
# so the checksum gate can be exercised on an image that has no compiler (the
# CI image is Alpine, which ships neither `cc` nor `xz`). It suppresses nothing
# else — the checksum is still verified against the pin, and a mismatch is still
# fatal. Never set this for a real install.
if [ "${GIT_SOURCE_SKIP_PREREQ:-0}" = "1" ]; then
  log "WARNING: GIT_SOURCE_SKIP_PREREQ=1 — skipping the build-tool check"
else
  # perl is not optional: git's configure refuses to run without it
  # ("You cannot use git without perl") and GIT-VERSION-FILE is generated by a
  # perl script, so a host without perl fails deep into the build.
  prereq_gaps="$(missing_prereq make cc perl tar xz curl)"
  if [ -n "$prereq_gaps" ]; then
    die "missing build prerequisites: $(printf '%s' "$prereq_gaps" | tr '\n' ' ')"
  fi
fi

# --- Fetch and verify --------------------------------------------------------

TARBALL="git-${GIT_VERSION}.tar.xz"
TARBALL_URL="${DOWNLOAD_BASE}/${TARBALL}"

# The pin is about to be consumed against a real download, so this is the point
# where an unpaired override must stop the run.
validate_pin_pairing

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-git-src.XXXXXX")"
DOWNLOAD_DIR="$WORK_DIR/download"
mkdir -p "$DOWNLOAD_DIR"

log "downloading $TARBALL_URL"
curl -fsSL --retry 3 --retry-delay 2 -o "$DOWNLOAD_DIR/$TARBALL" "$TARBALL_URL" ||
  die "download failed: $TARBALL_URL"

# Verify against the pinned checksum first. This is the value reviewed in the
# commit, so it is the trust anchor; the manifest check below is a cross-check.
ACTUAL_SHA="$(sha256_of "$HAVE_SHA" "$DOWNLOAD_DIR/$TARBALL")"
if [ "$ACTUAL_SHA" != "$GIT_SHA256" ]; then
  die "checksum mismatch for $TARBALL
  pinned: $GIT_SHA256
  actual: $ACTUAL_SHA
  Refusing to build. If upstream re-released this version, re-derive the
  checksum from $SHA256_MANIFEST and update GIT_SHA256 deliberately."
fi
log "checksum matches the pinned value"

# Cross-check the pin against upstream's published manifest when reachable.
#
# Trust model, stated precisely: the real trust anchor is GIT_SHA256 pinned in
# this file and reviewed in the commit that changed it. This manifest fetch is a
# convenience cross-check that catches a mistyped pin or a re-released tarball.
# The manifest is fetched over HTTPS from the same host as the tarball and its
# PGP signature is NOT verified here — that would require git's release key to be
# present in the operator's keyring, which this script does not manage. So treat
# a match as corroboration, never as independent proof.
#
# A network failure must not block an install whose tarball already matched the
# reviewed pin, so an unreachable manifest is a warning. A *disagreement* is
# always fatal.
if curl -fsSL --retry 2 --max-time 60 -o "$DOWNLOAD_DIR/sha256sums.asc" "$SHA256_MANIFEST" 2> /dev/null; then
  UPSTREAM_SHA="$(awk -v t="$TARBALL" '$2 == t || $2 == "./" t {print $1; exit}' "$DOWNLOAD_DIR/sha256sums.asc")"
  if [ -z "$UPSTREAM_SHA" ]; then
    warn "no entry for $TARBALL in the upstream manifest; continuing on the pinned checksum alone"
  elif [ "$UPSTREAM_SHA" != "$GIT_SHA256" ]; then
    die "upstream manifest disagrees with the pinned checksum for $TARBALL
  pinned:   $GIT_SHA256
  upstream: $UPSTREAM_SHA
  Reconcile by hand before building."
  else
    log "corroborated by upstream manifest (signature not verified; pin remains the trust anchor)"
  fi
else
  warn "could not fetch the upstream manifest; continuing on the pinned checksum alone"
fi

# --- Build -------------------------------------------------------------------
#
# git must be configured IN-TREE. Its build system does not support a separate
# build directory: `configure` writes ./Makefile next to its own source, so an
# out-of-tree run completes successfully but leaves no Makefile where make
# expects it ("make: *** No targets specified and no makefile found"). So the
# configure/make/install steps all run inside $SRC_DIR, and the extracted tree is
# discarded by the cleanup trap.
SRC_DIR="$WORK_DIR/src"
mkdir -p "$SRC_DIR"

log "extracting"
tar -xJf "$DOWNLOAD_DIR/$TARBALL" -C "$SRC_DIR" --strip-components=1

# Only point the build at MacPorts when it actually provides the headers, so the
# script still works on a host without MacPorts.
#
# --without-perl is deliberately NOT used: git refuses to configure without perl
# ("You cannot use git without perl") because the perl build is load-bearing for
# several subcommands. --without-tcltk only skips the optional GUI.
CONFIGURE_FLAGS=(--prefix="$PREFIX" --without-tcltk)
if [ -d "$PORT_PREFIX/include/curl" ]; then
  CONFIGURE_FLAGS+=(--with-curl="$PORT_PREFIX")
  log "configure: using MacPorts libcurl from $PORT_PREFIX"
else
  log "configure: no MacPorts prefix, using the platform libcurl"
fi
if [ -f "$PORT_PREFIX/include/expat.h" ]; then
  CONFIGURE_FLAGS+=(--with-expat="$PORT_PREFIX")
fi

# git's configure exits outright when it cannot find a working libcurl, which is
# the single most common failure on a host with no system libcurl. Fail with a
# readable message instead of a configure error dump.
# git needs libcurl headers, but they are not always in one obvious place:
#   - MacPorts puts them under $PORT_PREFIX/include/curl
#   - the Xcode/CLT SDK ships them inside the SDK, which is NOT /usr/include
# So probe the SDK too rather than assuming /usr/include/curl exists. Getting
# this wrong would reject a perfectly buildable no-MacPorts host.
curl_headers_present() {
  [ -d "$PORT_PREFIX/include/curl" ] && return 0
  [ -f /usr/include/curl/curl.h ] && return 0
  local sdk
  sdk="$(xcrun --show-sdk-path 2> /dev/null || true)"
  [ -n "$sdk" ] && [ -f "$sdk/usr/include/curl/curl.h" ] && return 0
  return 1
}

if ! curl_headers_present; then
  die "no libcurl headers found (looked in $PORT_PREFIX/include/curl, /usr/include/curl, and the active SDK).
  git cannot be built without libcurl. Install curl's headers, or point
  PORT_PREFIX at a prefix that provides them."
fi

log "configuring (prefix=$PREFIX)"
# Run configure/make/install with their output written to a log and replayed, so
# the real exit status is preserved. Under `set -o pipefail` a plain
# `configure | sed` reports the *last* stage's status, which would mask a
# configure failure and resurface it as a confusing make error.
if ! (cd "$SRC_DIR" && ./configure "${CONFIGURE_FLAGS[@]}") > "$WORK_DIR/configure.log" 2>&1; then
  log "configure failed; last 40 lines:"
  tail -n 40 "$WORK_DIR/configure.log" | sed 's/^/  [configure] /' >&2
  die "git configure did not complete"
fi
sed 's/^/  [configure] /' "$WORK_DIR/configure.log"

# git's own advice: a successful in-tree configure always leaves a Makefile.
if [ ! -f "$SRC_DIR/Makefile" ]; then
  die "configure reported success but produced no Makefile in $SRC_DIR"
fi

JOBS="$(detect_jobs)"
log "building with -j$JOBS (a few minutes)"
# git's po/*.po -> .mo step needs msgfmt at build time, so a host without
# gettext-tools dies with "msgfmt: command not found" (make error 127). git has
# no --without-gettext configure flag; the supported switch is the NO_GETTEXT
# make variable (INSTALL: "Set NO_GETTEXT to disable localization support"),
# which empties MOFILES and makes the locale step a no-op. Only used when
# msgfmt is genuinely absent, so a host with gettext keeps translations.
#
# Rust is a second optional dependency: git 2.56 vendors a small Rust library
# (libgitcore) and its Makefile builds it via `cargo build`, so a host without
# cargo dies with "cargo: command not found" (error 127). git's own Makefile
# documents NO_RUST for exactly this ("Rust is still an optional feature...
# With Git 3.0 though, Rust will always be enabled"), and it drops the rust lib
# from GITLIBS. Applied only when cargo is genuinely absent.
MAKE_FLAGS=()
if ! command -v msgfmt > /dev/null 2>&1; then
  MAKE_FLAGS+=(NO_GETTEXT=YesPlease)
  log "build: msgfmt not found, building with NO_GETTEXT (English only)"
fi
if ! command -v cargo > /dev/null 2>&1; then
  MAKE_FLAGS+=(NO_RUST=YesPlease)
  log "build: cargo not found, building with NO_RUST"
fi
#
# git derives CURL_LDFLAGS from `curl-config --libs`, so without curl-config on
# PATH the http helpers link with undefined _curl_* symbols and the link fails
# even though configure found libcurl. When a MacPorts/opt prefix provides curl
# but curl-config is not reachable, pass the flags explicitly.
if [ -z "${CURL_LDFLAGS:-}" ] && ! command -v curl-config > /dev/null 2>&1; then
  if [ -d "$PORT_PREFIX/lib" ]; then
    MAKE_FLAGS+=(CURL_LDFLAGS="-L$PORT_PREFIX/lib -lcurl")
    log "build: curl-config not found, setting CURL_LDFLAGS from $PORT_PREFIX"
  fi
fi

if ! (cd "$SRC_DIR" && make -j"$JOBS" "${MAKE_FLAGS[@]+"${MAKE_FLAGS[@]}"}") > "$WORK_DIR/make.log" 2>&1; then
  log "build failed; last 40 lines:"
  # Replay the log BEFORE dying: the EXIT trap removes $WORK_DIR, so anything
  # read afterwards would fail and, under `set -u`, mask the real error.
  tail -n 40 "$WORK_DIR/make.log" | sed 's/^/  [make] /' >&2
  die "git build failed"
fi
tail -n 5 "$WORK_DIR/make.log" | sed 's/^/  [make] /'

# Record the built version now, while the tree still exists. The EXIT trap
# deletes $SRC_DIR on the way out, so the dry-run report cannot re-read it.
BUILT_VERSION=""
if [ -x "$SRC_DIR/git" ]; then
  BUILT_VERSION="$("$SRC_DIR/git" --version 2> /dev/null | awk '{print $3}' || true)"
fi

# --- Install -----------------------------------------------------------------

if [ "$DRY_RUN" -eq 1 ]; then
  log "dry-run: build succeeded, skipping 'make install'"
  log "dry-run: built binary reports ${BUILT_VERSION:-unknown}"
  exit 0
fi

# git's upgrade advice is to remove the old bin/git and libexec/git-core
# wholesale. A bare `make install` overlays the new tree and leaves stale
# helpers behind, so remove the git-owned paths first.
#
# The removal is staged: the old tree is moved aside, not deleted, and restored
# if `make install` fails. Deleting first would leave the prefix with no git at
# all when the install errors out (full disk, unwritable prefix), which is worse
# than the stale-helper problem this cleanup exists to prevent.
if [ -d "$PREFIX/libexec/git-core" ] || { [ -e "$TARGET_GIT" ] || [ -L "$TARGET_GIT" ]; }; then
  BACKUP_DIR="$WORK_DIR/previous-git"
  mkdir -p "$BACKUP_DIR"
  if [ -d "$PREFIX/libexec/git-core" ]; then
    log "moving previous $PREFIX/libexec/git-core aside"
    mv "$PREFIX/libexec/git-core" "$BACKUP_DIR/git-core"
  fi
  if [ -e "$TARGET_GIT" ] || [ -L "$TARGET_GIT" ]; then
    log "moving previous $TARGET_GIT aside"
    mv "$TARGET_GIT" "$BACKUP_DIR/git"
  fi
  # Restore on any failure between here and a successful install.
  restore_previous_git() {
    if [ -d "$BACKUP_DIR/git-core" ] && [ ! -e "$PREFIX/libexec/git-core" ]; then
      mkdir -p "$PREFIX/libexec"
      log "restoring previous $PREFIX/libexec/git-core"
      mv "$BACKUP_DIR/git-core" "$PREFIX/libexec/git-core" || true
    fi
    if [ -e "$BACKUP_DIR/git" ] && [ ! -e "$TARGET_GIT" ]; then
      log "restoring previous $TARGET_GIT"
      mv "$BACKUP_DIR/git" "$TARGET_GIT" || true
    fi
  }
else
  BACKUP_DIR=""
  restore_previous_git() { :; }
fi

log "installing to $PREFIX"
if ! (cd "$SRC_DIR" && make install) > "$WORK_DIR/install.log" 2>&1; then
  log "install failed; last 40 lines:"
  tail -n 40 "$WORK_DIR/install.log" | sed 's/^/  [install] /' >&2
  # Put the previous git back before bailing out, so a failed upgrade never
  # leaves the prefix without a working git.
  restore_previous_git
  die "git install failed${BACKUP_DIR:+ (previous git restored)}"
fi
tail -n 3 "$WORK_DIR/install.log" | sed 's/^/  [install] /'

# --- Verify ------------------------------------------------------------------

[ -x "$TARGET_GIT" ] || die "install finished but $TARGET_GIT is missing"

INSTALLED_NOW="$("$TARGET_GIT" --version 2> /dev/null | awk '{print $3}')"
[ "$INSTALLED_NOW" = "$GIT_VERSION" ] ||
  die "expected git $GIT_VERSION after install, found $INSTALLED_NOW"

log "installed git $INSTALLED_NOW -> $TARGET_GIT"

# A newer git that cannot reach a remote is worse than no upgrade at all, so
# prove the libraries resolve before declaring success.
if command -v otool > /dev/null 2>&1; then
  if otool -L "$TARGET_GIT" 2> /dev/null | grep -q 'libcurl'; then
    log "dynamic links resolved (libcurl present)"
  else
    warn "$TARGET_GIT does not link libcurl — HTTPS remotes may not work"
    warn "inspect with: otool -L $TARGET_GIT"
  fi
fi

# Confirm a fresh shell would actually see the new git, otherwise the upgrade
# stays invisible until PATH is re-ordered.
ACTIVE_GIT="$(command -v git 2> /dev/null || true)"
if [ -n "$ACTIVE_GIT" ] && [ "$ACTIVE_GIT" != "$TARGET_GIT" ]; then
  warn "git on PATH is still $ACTIVE_GIT ($("$ACTIVE_GIT" --version 2> /dev/null | awk '{print $3}'))"
  warn "ensure $PREFIX/bin precedes /usr/local/bin and /usr/bin"
  warn "shared/platform.sh already orders it — start a new login shell to pick it up"
else
  log "git on PATH resolves to $TARGET_GIT"
fi

cat << EOF

Done.

  Installed: $TARGET_GIT (git $INSTALLED_NOW)
  Minimum:   $REQUIRED_MIN_VERSION (required by the Graphite CLI)

Next:
  1. Open a new login shell, or run: hash -r
  2. Confirm:  git --version
  3. Re-auth:  gt auth --token <token>

To change the pinned version, edit GIT_VERSION and GIT_SHA256 at the top of
$SCRIPT_NAME, then re-run it. Re-derive the checksum from:
  $SHA256_MANIFEST
EOF
