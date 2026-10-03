#!/bin/sh
# Creditable-address allowlist for the attribution gates. Sourced, not executed.
#
# Split out of check-attribution.sh so the trust boundary - deciding WHO this
# repository is entitled to credit - lives in one reviewable place instead of
# being rebuilt inline. Nothing here returns a verdict; it answers one question:
# is this address creditable?
#
# Sourced by a script that has already parsed its own arguments. Every failure
# path returns non-zero rather than quietly yielding an empty allowlist: an
# allowlist that cannot be read must never be mistaken for "no restriction".

# Normalize CR, case, and edge whitespace. Every comparison runs through this,
# so an allowlist line and a trailer cannot drift onto different rules.
# awk's {$1=$1} also squeezes internal whitespace runs, so an entry written with
# a stray double space still matches the same address written with one.
_attr_norm() {
  printf '%s' "$1" | tr -d '\r' | tr '[:upper:]' '[:lower:]' | awk '{$1=$1};1'
}

# Empty values are skipped: an unset git config must never become a catch-all
# entry that matches any address.
_attr_allow_add() {
  [ -n "$1" ] || return 0
  _attr_n=$(_attr_norm "$1")
  [ -n "$_attr_n" ] || return 0
  _ATTR_ALLOWED="$_ATTR_ALLOWED $_attr_n"
}

# Resolve the tracked allowlist and copy its raw lines into <scratch>, or return
# non-zero without touching the allowlist. The caller owns <scratch> because the
# parse loop below must redirect from a file: a piped loop runs in a subshell and
# every address it added would be lost.
#
# In the MR CI job the checkout IS the branch under review, so an allowlist read
# from the working tree would let an MR widen the allowlist and spend the credit
# in the same MR. There the TARGET branch is the only authority; a file the MR
# adds takes effect on the next merge, not in the MR that introduces it. An
# unreadable file on the target branch is still fatal - only its ABSENCE yields
# an empty (fail-closed) list.
_attr_read_tracked() {
  _attr_scratch=$1
  _attr_ref="${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}"
  if [ -n "${CI_MERGE_REQUEST_IID:-}" ] && [ -n "$_attr_ref" ]; then
    # Resolve the ref BEFORE testing the path. A typo, or a ref the runner never
    # fetched, is indistinguishable from "the file is absent" and would silently
    # downgrade the policy to an empty file-sourced list with nothing in the log
    # to explain it.
    if ! git rev-parse --verify --quiet "${_attr_ref}^{commit}" > /dev/null 2>&1; then
      echo "ERROR: cannot resolve the MR target branch '${_attr_ref}'." >&2
      echo "The attribution allowlist would be read as empty; refusing." >&2
      return 2
    fi
    if git cat-file -e "${_attr_ref}:.attribution-allow" 2> /dev/null; then
      if ! git show "${_attr_ref}:.attribution-allow" > "$_attr_scratch" 2> /dev/null; then
        echo "ERROR: cannot read .attribution-allow from ${_attr_ref}" >&2
        return 2
      fi
      _ATTR_ALLOW_SOURCE="${_attr_ref}:.attribution-allow"
    else
      : > "$_attr_scratch" || return 2
      _ATTR_ALLOW_SOURCE="${_attr_ref}:.attribution-allow (absent: no file-sourced credits)"
    fi
    return 0
  fi

  # An unresolvable root is NOT fatal here: this is also driven by the MR CI job,
  # where a checkout may not exist at all. The commit-msg hook fails closed on an
  # unresolvable root before reaching this point, so the local path stays
  # fail-closed by construction.
  _attr_root=$(git rev-parse --show-toplevel 2> /dev/null || true)
  if [ -z "$_attr_root" ] || [ ! -e "$_attr_root/.attribution-allow" ]; then
    : > "$_attr_scratch" || return 2
    return 0
  fi
  if [ ! -r "$_attr_root/.attribution-allow" ] || [ ! -f "$_attr_root/.attribution-allow" ]; then
    # The path exists but is not a readable regular file - a directory, or a
    # permission problem. Failing closed matches how an unreadable MESSAGE is
    # handled: a gate that quietly passes when it cannot establish its own
    # allowlist reports safety it does not have.
    echo "ERROR: cannot read allowlist: $_attr_root/.attribution-allow" >&2
    return 2
  fi
  cat "$_attr_root/.attribution-allow" > "$_attr_scratch" 2> /dev/null || {
    echo "ERROR: cannot read allowlist: $_attr_root/.attribution-allow" >&2
    return 2
  }
  _ATTR_ALLOW_SOURCE="$_attr_root/.attribution-allow"
  return 0
}

# _attr_build <scratch>
# Populate _ATTR_ALLOWED. Sources, in order:
#   1. git config user.email (local, then global) - crediting yourself.
#   2. ATTRIBUTION_ALLOWLIST - whitespace separated, an untracked override.
#   3. the tracked allowlist - the auditable record of who may be credited.
#
# Every variable here is _attr_-prefixed: POSIX sh has no `local`, so these would
# otherwise clobber the caller's loop variables.
_attr_build() {
  _ATTR_ALLOWED=""
  _ATTR_ALLOW_SOURCE=""
  _attr_scratch=$1

  for _attr_cfg in --local --global; do
    _attr_e=$(git config "$_attr_cfg" user.email 2> /dev/null || true)
    _attr_allow_add "${_attr_e:-}"
  done

  for _attr_e in ${ATTRIBUTION_ALLOWLIST:-}; do
    _attr_allow_add "$_attr_e"
  done

  _attr_read_tracked "$_attr_scratch" || return 2

  while IFS= read -r _attr_line || [ -n "$_attr_line" ]; do
    _attr_line="${_attr_line%%#*}"
    _attr_allow_add "$_attr_line"
  done < "$_attr_scratch"

  return 0
}

# Word-boundary match against the assembled list. The list is the case SUBJECT
# and the candidate is quoted inside the pattern, so an address containing glob
# characters is compared literally rather than expanded as a pattern.
_attr_is_allowed() {
  case " $_ATTR_ALLOWED " in
    *" $(_attr_norm "$1") "*) return 0 ;;
  esac
  return 1
}
