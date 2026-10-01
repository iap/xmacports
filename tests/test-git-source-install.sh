#!/usr/bin/env bash
# Behavior checks for scripts/install-git-source.sh.
#
# The installer downloads and compiles software, so the suite never runs a real
# build. It exercises the decision logic instead: version comparison, the
# minimum-version gate, checksum-mismatch refusal, already-satisfied exits, and
# prerequisite detection. Everything runs against a temp prefix and a stubbed
# PATH, so nothing on the host is touched.
set -u
DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALLER="$DOTFILES_ROOT/scripts/install-git-source.sh"

pass=0
fail=0
ok() {
  echo "  ok   $1"
  pass=$((pass + 1))
}
bad() {
  echo "  FAIL $1"
  fail=$((fail + 1))
}

if [ ! -x "$INSTALLER" ]; then
  echo "  FAIL installer missing or not executable: $INSTALLER"
  exit 1
fi

# Run the installer with a given set of stubbed commands on PATH.
# Usage: run_installer <stub-dir|none> <args...>
run_installer() {
  local stubs="$1"
  shift
  if [ "$stubs" = "none" ]; then
    bash "$INSTALLER" "$@" 2>&1
  else
    PATH="$stubs:$PATH" bash "$INSTALLER" "$@" 2>&1
  fi
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# --- version comparison ------------------------------------------------------
# Sourced straight out of the installer so the tests cannot drift from it.
eval "$(sed -n '/^version_cmp()/,/^}/p; /^version_ge()/,/^}/p' "$INSTALLER")"

echo "version comparison is numeric, not lexical:"
vc() {
  local got
  got="$(version_cmp "$1" "$2")"
  if [ "$got" = "$3" ]; then
    ok "$1 vs $2 -> $got"
  else
    bad "$1 vs $2 -> $got (want $3)"
  fi
}
vc 2.37.1 2.38.0 -1
vc 2.38.0 2.38.0 0
vc 2.56.0 2.38.0 1
# The load-bearing case: a lexical compare would call 2.9.0 newer than 2.10.0.
vc 2.9.0 2.10.0 -1
vc 2.10.0 2.9.0 1
vc 2.56.0.rc1 2.56.0 0
vc 2.56 2.56.0 0

echo "version_ge gates on the minimum:"
if version_ge 2.38.0 2.38.0; then ok "2.38.0 >= 2.38.0"; else bad "2.38.0 >= 2.38.0"; fi
if version_ge 2.56.0 2.38.0; then ok "2.56.0 >= 2.38.0"; else bad "2.56.0 >= 2.38.0"; fi
if version_ge 2.37.1 2.38.0; then bad "2.37.1 must NOT satisfy >= 2.38.0"; else ok "2.37.1 < 2.38.0 rejected"; fi

# --- minimum-version refusal -------------------------------------------------
echo "refuses a version below the required minimum:"
out="$(run_installer none --check --version 2.37.0)"
rc=$?
if [ "$rc" -ne 0 ]; then ok "exits non-zero (rc=$rc)"; else bad "exited 0 for an unsupported version"; fi
if printf '%s' "$out" | grep -q "below the required minimum"; then
  ok "explains the minimum-version refusal"
else
  bad "missing minimum-version message: $out"
fi

# 2.38.0 is the documented Graphite floor and must be accepted.
out="$(run_installer none --check --version 2.38.0)"
if printf '%s' "$out" | grep -q "would build\|nothing to do"; then
  ok "accepts exactly 2.38.0"
else
  bad "rejected the documented minimum 2.38.0: $out"
fi

# --- checksum mismatch is fatal ----------------------------------------------
# Serve a tarball whose hash cannot match the pin and assert the build is
# refused before any compile step.
echo "refuses a tarball that fails checksum verification:"
BAD_SH="$T/badsh"
mkdir -p "$BAD_SH"
cat > "$BAD_SH/sha256sum" << 'STUB'
#!/bin/sh
# Stand-in for GNU coreutils' sha256sum. It must behave like the real tool:
# SHA-256 is the default and `-a` is NOT a valid option. A stub that quietly
# accepted `-a` would let the suite pass while the installer was broken on
# every host with coreutils installed, so the rejection is deliberate.
case "${1:-}" in
  -a | --algorithm)
    echo "sha256sum: invalid option -- '${1#-}'" >&2
    echo "Try 'sha256sum --help' for more information." >&2
    exit 1
    ;;
esac
# Always report a hash that cannot match the pinned value.
echo "0000000000000000000000000000000000000000000000000000000000000000  ${1:-?}"
exit 0
STUB
chmod +x "$BAD_SH/sha256sum"

# Build a PATH that has every build prerequisite the installer probes for, so the
# run reaches the checksum gate instead of stopping at the prerequisite gate.
# The CI image (Alpine) ships neither `cc` nor `xz`; without this the download
# never happens and the assertion below would pass for the wrong reason.
PREREQ_SH="$T/prereqpath"
mkdir -p "$PREREQ_SH"
for c in bash sh dash make cc gcc perl tar xz curl date sed awk grep rm rmdir \
  mkdir mktemp uname sysctl dirname cat tr head tail wc chmod cp mv ls find \
  sha256sum shasum ln env; do
  p="$(command -v "$c" 2> /dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$PREREQ_SH/$c"
done
# The stub must win over any real sha256sum on this host.
ln -sf "$BAD_SH/sha256sum" "$PREREQ_SH/sha256sum"
ln -sf "$BAD_SH/sha256sum" "$PREREQ_SH/shasum"

# Serve a local file:// tarball so the download is stubbed and the test never
# touches the network. GIT_SOURCE_DOWNLOAD_BASE redirects the fetch; the pinned
# SHA256 is still enforced, so a tampered local file must still be rejected.
SERVE_DIR="$T/serve"
mkdir -p "$SERVE_DIR"
# Deliberately wrong content: the stubbed checksum tool reports a hash that
# cannot match the pin, which is what this test asserts on.
printf 'not a real tarball\n' > "$SERVE_DIR/git-2.56.0.tar.xz"
printf '%s  git-2.56.0.tar.xz\n' \
  "0000000000000000000000000000000000000000000000000000000000000000" \
  > "$SERVE_DIR/sha256sums.asc"

# GIT_SOURCE_SKIP_PREREQ lets the run reach the checksum gate on an image with
# no compiler. Everything the checksum gate itself depends on is still real.
out="$(cd "$T" && PATH="$PREREQ_SH" \
  GIT_SOURCE_SKIP_PREREQ=1 \
  GIT_SOURCE_DOWNLOAD_BASE="file://$SERVE_DIR" \
  bash "$INSTALLER" --dry-run 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then ok "exits non-zero on mismatch (rc=$rc)"; else bad "exited 0 despite bad checksum"; fi
if printf '%s' "$out" | grep -q "checksum mismatch"; then
  ok "reports a checksum mismatch"
else
  bad "no mismatch message: $out"
fi
if printf '%s' "$out" | grep -q "Refusing to build"; then
  ok "refuses to build explicitly"
else
  bad "did not refuse to build: $out"
fi
# The refusal must come from the checksum gate, not from some earlier failure.
if printf '%s' "$out" | grep -q "missing build prerequisites"; then
  bad "stopped at the prerequisite gate before verifying the checksum: $out"
else
  ok "reached the checksum gate (no prerequisite failure first)"
fi

# --- the checksum tool is called correctly for each implementation -------------
# GNU coreutils' sha256sum and Perl's shasum are the same utility under two
# names, but they do NOT share a CLI: sha256sum defaults to SHA-256 and rejects
# `-a`, while shasum needs `-a 256`. Calling them interchangeably made the
# installer fail on any host with coreutils, and the previous stub accepted
# `-a` so the suite never noticed. Assert the real calling convention.
echo "passes no -a to GNU sha256sum (it rejects that flag):"
GNU_SH="$T/gnush"
mkdir -p "$GNU_SH"
cat > "$GNU_SH/sha256sum" << 'STUB'
#!/bin/sh
# Mimics GNU coreutils 9.x: `-a` is an invalid option, SHA-256 is the default.
for a in "$@"; do
  case "$a" in
    -a | --algorithm)
      echo "sha256sum: invalid option -- 'a'" >&2
      exit 1
      ;;
  esac
done
echo "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03  ${1:-?}"
exit 0
STUB
chmod +x "$GNU_SH/sha256sum"
if "$GNU_SH/sha256sum" -a 256 /dev/null > /dev/null 2>&1; then
  bad "test double accepts -a, so it cannot model GNU coreutils"
else
  ok "test double rejects -a like GNU coreutils does"
fi

# Drive the helper through the installer: a matching hash must NOT be reported
# as a mismatch, which can only happen if the tool was called correctly.
MATCH_SH="$T/matchpath"
mkdir -p "$MATCH_SH"
# Make the served tarball hash to exactly what the stub reports, so the installer
# proceeds past the checksum gate instead of reporting a mismatch.
PINNED_SHA="$(sed -n 's/^GIT_SHA256="\(.*\)"$/\1/p' "$INSTALLER")"
cat > "$MATCH_SH/sha256sum" << STUB
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    -a | --algorithm) echo "invalid option" >&2; exit 1 ;;
  esac
done
echo "$PINNED_SHA  \${1:-?}"
exit 0
STUB
chmod +x "$MATCH_SH/sha256sum"
match_out="$(cd "$T" && PATH="$MATCH_SH:$PATH" \
  GIT_SOURCE_SKIP_PREREQ=1 \
  GIT_SOURCE_DOWNLOAD_BASE="file://$SERVE_DIR" \
  bash "$INSTALLER" --dry-run 2>&1 || true)"
if printf '%s' "$match_out" | grep -q "checksum mismatch"; then
  bad "a matching hash was rejected as a mismatch: $match_out"
else
  ok "a matching hash is accepted (tool called with valid arguments)"
fi
if printf '%s' "$match_out" | grep -qi "invalid option"; then
  bad "the checksum tool rejected the installer's arguments: $match_out"
else
  ok "no invalid-option error from the checksum tool"
fi

# --- version and checksum must be overridden as a pair -------------------------
# --version alone would download a different tarball and verify it against the
# pinned checksum, failing as if the download were tampered. The pairing is
# validated at the download, not at argument parsing, so a real --check with a
# bare --version still works: only a run that would fetch needs both flags.
echo "requires --sha256 alongside --version for a real build:"
# A syntactically valid but wrong checksum. Built from a literal rather than
# `seq`, which busybox/alpine may not provide.
FAKE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
no_sha="$(cd "$T" && bash "$INSTALLER" --version 9.9.9 \
  --prefix "$T/pairing-prefix" --dry-run 2>&1 || true)"
if printf '%s' "$no_sha" | grep -q "only makes sense together with --sha256"; then
  ok "refuses --version without --sha256 before downloading"
else
  bad "accepted --version alone: $no_sha"
fi
# A --check must stay answerable with --version alone; it fetches nothing.
check_only="$(cd "$T" && bash "$INSTALLER" --check --version 2.37.0 2>&1 || true)"
if printf '%s' "$check_only" | grep -q "only makes sense together"; then
  bad "--check with a bare --version was rejected: $check_only"
else
  ok "--check still works with --version alone (no download)"
fi
# The pairing must be rejected before any gate that can exit first. On a host
# with no compiler the prerequisite gate dies before the download, so a check
# placed at the download would never run -- which is how this slipped through
# once already, green locally and failing in CI.
NOPREREQ_SH="$T/noprerq"
mkdir -p "$NOPREREQ_SH"
for c in bash sh dash awk sed grep rm mkdir date env dirname basename cat \
  printf id uname mktemp tr wc chmod ln find head tail; do
  p="$(command -v "$c" 2> /dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$NOPREREQ_SH/$c"
done
bare_out="$(cd "$T" && PATH="$NOPREREQ_SH" bash "$INSTALLER" --version 9.9.9 \
  --prefix "$T/noprerq-prefix" --dry-run 2>&1 || true)"
if printf '%s' "$bare_out" | grep -q "only makes sense together with --sha256"; then
  ok "refuses an unpaired --version on a host with no compiler"
else
  bad "an early gate hid the pairing check: $bare_out"
fi
sha_bare="$(cd "$T" && PATH="$NOPREREQ_SH" bash "$INSTALLER" \
  --sha256 "$FAKE_SHA" \
  --prefix "$T/noprerq-prefix" --dry-run 2>&1 || true)"
if printf '%s' "$sha_bare" | grep -q "only makes sense together with --version"; then
  ok "refuses an unpaired --sha256 on a host with no compiler"
else
  bad "an early gate hid the --sha256 check: $sha_bare"
fi
sha_alone="$(cd "$T" && bash "$INSTALLER" --sha256 \
  "$FAKE_SHA" --dry-run 2>&1 || true)"
if printf '%s' "$sha_alone" | grep -q "only makes sense together with --version"; then
  ok "refuses --sha256 without --version"
else
  bad "accepted --sha256 alone: $sha_alone"
fi
both="$(cd "$T" && bash "$INSTALLER" --version 9.9.9 \
  --sha256 "$FAKE_SHA" --dry-run 2>&1 || true)"
if printf '%s' "$both" | grep -q "only makes sense together"; then
  bad "refused a valid --version/--sha256 pair: $both"
else
  ok "accepts --version with --sha256"
fi
bad_sha="$(cd "$T" && bash "$INSTALLER" --version 9.9.9 --sha256 nothex \
  --dry-run 2>&1 || true)"
if printf '%s' "$bad_sha" | grep -q "invalid --sha256"; then
  ok "rejects a malformed --sha256"
else
  bad "accepted a malformed --sha256: $bad_sha"
fi

# --- already-installed short circuit -----------------------------------------
echo "short-circuits when the requested version is already installed:"
FAKE_PREFIX="$T/prefix"
mkdir -p "$FAKE_PREFIX/bin"
cat > "$FAKE_PREFIX/bin/git" << 'STUB'
#!/bin/sh
echo "git version 2.56.0"
STUB
chmod +x "$FAKE_PREFIX/bin/git"

out="$(run_installer none --check --prefix "$FAKE_PREFIX")"
rc=$?
if [ "$rc" -eq 0 ]; then ok "check mode exits 0 (rc=$rc)"; else bad "check mode exited $rc"; fi
if printf '%s' "$out" | grep -q "already in $FAKE_PREFIX"; then
  ok "reports the version as already present"
else
  bad "missing already-present message: $out"
fi

# Without --check it must also exit 0 and download nothing.
out="$(run_installer none --prefix "$FAKE_PREFIX")"
if printf '%s' "$out" | grep -q "use --force to rebuild"; then
  ok "install mode declines without --force"
else
  bad "expected a --force hint: $out"
fi

FAKE_PREFIX_NEW="$T/prefix-new"
mkdir -p "$FAKE_PREFIX_NEW"

echo "reports a version change under --check:"
out="$(run_installer none --check --prefix "$FAKE_PREFIX" --version 2.57.0)"
if printf '%s' "$out" | grep -q "would rebuild 2.56.0 -> 2.57.0"; then
  ok "describes the rebuild"
else
  bad "missing rebuild description: $out"
fi

# A prefix with no git at all must be described as a fresh build, not a rebuild.
out="$(run_installer none --check --prefix "$FAKE_PREFIX_NEW")"
if printf '%s' "$out" | grep -q "would build git"; then
  ok "describes a fresh build for an empty prefix"
else
  bad "missing fresh-build description: $out"
fi

# --- prerequisite detection --------------------------------------------------
echo "detects missing prerequisites:"
# Build a PATH containing every helper the script might probe for, EXCEPT the
# two this test withholds. The tool list is derived from the host rather than
# hardcoded, so the same assertions hold on macOS and on the Alpine CI image
# (which has no `cc` and no `xz`).
ALL_TOOLS="make cc perl tar xz curl shasum sha256sum bash sh dash date sed awk grep rm rmdir mkdir mktemp uname sysctl dirname cat tr head tail wc chmod cp mv ls find printf sleep ln env id basename expr test pwd readlink realpath"
WITHHELD="make cc"

link_tools() {
  local c p
  for c in $ALL_TOOLS; do
    case " $WITHHELD " in
      *" $c "*) continue ;;
    esac
    p="$(command -v "$c" 2> /dev/null || true)"
    [ -n "$p" ] && ln -sf "$p" "$STUB_SH/$c"
  done
}

STUB_SH="$T/stubpath"
mkdir -p "$STUB_SH"
link_tools

# Whichever of the withheld tools this host actually provides are now absent, so
# `--check` must still name at least one of them and fail.
out="$(cd "$T" && PATH="$STUB_SH" bash "$INSTALLER" --check 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then ok "check fails without build tools (rc=$rc)"; else bad "check passed with make/cc withheld"; fi
if printf '%s' "$out" | grep -qE '(^|[[:space:]])(make|cc)$'; then
  ok "names the missing build tool(s)"
else
  bad "did not name a missing build tool: $out"
fi
# The plan must be reported even when prerequisites are missing, so a caller on
# a tool-less host still learns what the script would do.
if printf '%s' "$out" | grep -q "would build git\|would rebuild"; then
  ok "reports the plan despite missing prerequisites"
else
  bad "withheld the plan when prerequisites were missing: $out"
fi

# And the inverse: with every probed tool present the same check must pass.
WITHHELD=""
link_tools
for c in $ALL_TOOLS; do
  if [ ! -e "$STUB_SH/$c" ]; then
    cat > "$STUB_SH/$c" << 'STUB'
#!/bin/sh
case "${1:-}" in
  -v | --version | version) echo "stub 1.0"; exit 0 ;;
esac
exit 0
STUB
    chmod +x "$STUB_SH/$c"
  fi
done
out="$(cd "$T" && PATH="$STUB_SH" bash "$INSTALLER" --check --prefix "$FAKE_PREFIX_NEW" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then ok "check passes once build tools exist (rc=$rc)"; else bad "check failed with build tools present: $out"; fi

echo "refuses a system or package-managed prefix:"
for p in /usr/local /opt/homebrew /opt/local /usr; do
  out="$(run_installer none --check --prefix "$p" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then ok "refuses $p (rc=$rc)"; else bad "accepted $p"; fi
  if printf '%s' "$out" | grep -qi "refusing to install"; then
    ok "explains the refusal for $p"
  else
    bad "no refusal message for $p: $out"
  fi
done

echo "still accepts a user-owned prefix:"
out="$(run_installer none --check --prefix "$FAKE_PREFIX_NEW" 2>&1)"
# A user prefix must never be refused for being a system path. The exit status
# still depends on whether the host has the build tools, so assert on the
# message, not the code.
if printf '%s' "$out" | grep -qi "refusing to install"; then
  bad "unexpectedly refused a user prefix: $out"
else
  ok "does not refuse a user prefix"
fi
if printf '%s' "$out" | grep -q "would build git"; then
  ok "reports the plan for a user prefix"
else
  bad "no plan reported for a user prefix: $out"
fi

echo "rejects a relative or root prefix:"
# A relative prefix resolves against whatever CWD the install runs in, and a
# bare "/" writes /bin/git. Both must be refused before any build work.
for p in "/" "." ".." "relative/path" ""; do
  out="$(run_installer none --check --prefix "$p" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then ok "refuses '$p' (rc=$rc)"; else bad "accepted '$p'"; fi
  if printf '%s' "$out" | grep -qE "refusing to install|must be an absolute"; then
    ok "explains the refusal for '$p'"
  else
    bad "no refusal message for '$p': $out"
  fi
done

echo "normalizes before matching a system prefix:"
# These are all the same directory as a refused prefix; a literal glob would
# let them through.
for p in "/usr/local/.." "/opt/local/." "/usr/./local"; do
  out="$(run_installer none --check --prefix "$p" 2>&1)"
  if printf '%s' "$out" | grep -qi "refusing to install"; then
    ok "refuses $p"
  else
    bad "accepted unnormalized $p: $out"
  fi
done

echo "accepts ordinary user prefixes:"
for p in "$HOME/.local" "$HOME/dev/git" "/Volumes/Work/git" "/private/tmp/git-sandbox"; do
  out="$(run_installer none --check --prefix "$p" 2>&1)"
  if printf '%s' "$out" | grep -qi "refusing to install"; then
    bad "wrongly refused a user prefix $p: $out"
  else
    ok "accepts $p"
  fi
done

# --- unknown flag is rejected -----------------------------------------------

# --- help works without a build ---------------------------------------------
echo "help is available:"
out="$(run_installer none --help 2>&1)"
if printf '%s' "$out" | grep -q -- "--dry-run"; then ok "documents --dry-run"; else bad "help missing --dry-run"; fi
if printf '%s' "$out" | grep -q -- "--check"; then ok "documents --check"; else bad "help missing --check"; fi

# --- the pin is present and well-formed --------------------------------------
echo "pins a version and a checksum:"
if grep -qE '^GIT_VERSION="[0-9]+\.[0-9]+\.[0-9]+"' "$INSTALLER"; then
  ok "GIT_VERSION is a concrete version"
else
  bad "GIT_VERSION is not a pinned release"
fi
if grep -qE '^GIT_SHA256="[0-9a-f]{64}"' "$INSTALLER"; then
  ok "GIT_SHA256 is a full SHA256"
else
  bad "GIT_SHA256 is not a 64-char hex digest"
fi
# The floor the toolchain needs must be documented in the script itself.
if grep -qE '^REQUIRED_MIN_VERSION="2\.38' "$INSTALLER"; then
  ok "REQUIRED_MIN_VERSION records the 2.38 floor"
else
  bad "REQUIRED_MIN_VERSION does not record the 2.38 floor"
fi

echo
echo "install-git-source tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
