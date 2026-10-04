#!/bin/sh
# Reject false third-party attribution in a commit message or PR/MR body.
#
# Why this is a gate and not a reminder: three separate incidents appended a
# footer naming a tool that did not write the change - hermes-agent#70306,
# builder#17, xmacports!37. Every one was a PR-DESCRIPTION convention
# reproduced from training data ("Generated with [Claude Code](...)"), not a
# decision, and prose warnings in the agent docs failed to stop all three. Only
# a check that can fail constrains a pattern that otherwise completes itself.
#
# It is a provenance check too. Naming a company that did not write the work,
# in permanent public history, misattributes authorship to a third party that
# never consented to it.
#
# What is forbidden unconditionally, and what is merely checked:
#   - generator footers naming a tool            FORBIDDEN
#   - Signed-off-by:                             FORBIDDEN
#   - Co-authored-by: <a tool name> <address>    allowed only for a creditable
#                                               address; see attribution-allow.sh
#
# Crediting the owner of this repository is not misattribution, but a gate cannot
# know that from the display name - "Hermes" is a real GitHub organization. The
# address is the identity anchor, so that is what gets decided.
#
# Usage:
#   scripts/check-attribution.sh --message-file <file>
#   scripts/check-attribution.sh --stdin            # reads stdin
#
# Exit 0 = clean, 1 = rejected, 2 = usage error.
#
# Deliberate opt-out, for when a truthful credit was actually requested:
#   SKIP_ATTRIBUTION_CHECK=1 scripts/check-attribution.sh ...
# There is no implicit opt-out; the variable must be set explicitly.

set -u

src=""
case "${1:-}" in
  --message-file)
    [ "$#" -eq 2 ] || {
      echo "usage: $0 --message-file <file> | --stdin" >&2
      exit 2
    }
    if [ ! -r "$2" ]; then
      echo "ERROR: cannot read message file: $2" >&2
      exit 2
    fi
    src="$2"
    ;;
  --stdin)
    src=stdin
    ;;
  *)
    echo "usage: $0 --message-file <file> | --stdin" >&2
    exit 2
    ;;
esac

# Only the exact value 1 opts out. Testing "!= 0" let any incidental value (2,
# true, an empty-but-set var) disable the gate, so a typo silently turned a
# blocking check into a no-op.
if [ "${SKIP_ATTRIBUTION_CHECK:-0}" = "1" ]; then
  echo "attribution check skipped (SKIP_ATTRIBUTION_CHECK=1)" >&2
  exit 0
fi

# Generator footers. Match, then print the offending lines so the author sees
# what to remove.  - the Claude Code generator footer, with or without a markdown
# link, plus the bare host so a mangled link is still caught;  - any
# "Generated with <assistant>" naming a known tool.
#
# Every pattern is anchored to the START of a line, because a footer is a whole
# line and prose is not. Without the anchor the gate blocks honest documentation
# that merely quotes the convention - a commit body explaining that this footer
# is rejected was itself rejected, which is the over-blocking this anchor exists
# to prevent.
#
# The optional prefix covers footer decoration only - an emoji such as the one
# Claude Code writes. It deliberately excludes markdown structure characters
# (blockquotes, list bullets, emphasis, code fences, headings), so a documented
# example like "> Generated with ChatGPT" reads as the quotation it is instead
# of being mistaken for a real footer.
# Known limitation: a fenced code block whose content line is EXACTLY the footer
# is still rejected, because a single-line regex cannot know it is inside a
# fence. Document an example with trailing text or an indent instead. This is a
# deliberate trade: unblocking it needs fence-state tracking, and the cost of a
# false positive (one extra line of prose) is far below the cost of a missed
# footer.
#
# Case-insensitive: casing varies freely and does not change the attribution.
pattern_gen='^[[:space:]]*([^[:alnum:]"'\''>|*+#`_~+-][[:space:]]*)?(Generated[[:space:]]+with[[:space:]]+(\[[^]]+\]|(Claude Code|Cursor|Copilot|ChatGPT|Gemini|Aider|Codex))|https?://claude\.com/claude-code)'
pattern_coauth='^[[:space:]]*Co-authored-by:'
pattern_signoff='^[[:space:]]*Signed-off-by:'

# The allowlist is a separate module: it answers only "is this address
# creditable", and it needs the trust boundary - whose address counts - in one
# reviewable place. A read failure there is fatal, never an empty list.
_attr_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 2
if [ ! -r "$_attr_dir/attribution-allow.sh" ]; then
  echo "ERROR: cannot read scripts/attribution-allow.sh" >&2
  exit 2
fi
# shellcheck source=scripts/attribution-allow.sh
. "$_attr_dir/attribution-allow.sh" || exit 2

_tmp=$(mktemp "${TMPDIR:-/tmp}/attrcheck.XXXXXX") || exit 2
# The allowlist parse must redirect from a file: a piped read loop runs in a
# subshell and every address it collected would be lost.
_scratch=$(mktemp "${TMPDIR:-/tmp}/attrallow.XXXXXX") || {
  rm -f "$_tmp"
  exit 2
}
trap 'rm -f "$_tmp" "$_scratch"' EXIT INT TERM

if [ "$src" = stdin ]; then
  cat > "$_tmp" || exit 2
else
  # `cat` can still fail after -r passes: a directory is readable, but reading it
  # as a file errors. Without this check the temp file stays empty, grep finds
  # nothing, and the gate exits 0 - a fail-open on the one input most likely to
  # be a mistake.
  cat "$src" > "$_tmp" || {
    echo "ERROR: could not read message file: $src" >&2
    exit 2
  }
fi

_attr_build "$_scratch" || exit 2

# _attr_trailer_address <trailer value>
# Print the single address a Co-authored-by value carries, or fail if it does
# not carry exactly one.
#
# A trailer is one party. Taking the LAST <...> instead would let an unlisted
# address ride along behind a creditable one:
#   Co-authored-by: Evil <stranger@example.com> <iap@users.noreply.github.com>
# names only the second, so the unlisted party was credited under a name the
# allowlist never approved.
#
# So the value must be a display name followed by exactly ONE bracketed address
# at the end. A second pair, trailing text after the bracket, a nested bracket,
# or a single unmatched bracket is malformed and rejected rather than guessed at.
#
# No brackets at all is legitimate ("Co-authored-by: Hermes"); the value is still
# judged, never treated as an empty address that trivially matches.
_attr_trailer_address() {
  # Two exhaustive shapes, and [^<>]* in both is what makes them exhaustive:
  # anything containing a bracket matches neither. A display name then exactly
  # one bracketed address at the end; or no bracket at all, so the value itself
  # is the address. Everything else prints nothing and is rejected.
  #
  # Two separate -n scripts, not one chain: chaining lets an earlier s/p print
  # and then feeds its own output to the next expression, which printed the
  # address twice.
  _attr_trimmed=$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  _attr_addr=$(printf '%s' "$_attr_trimmed" |
    sed -n 's/^[^<>]*<\([^<>]*\)>$/\1/p')
  if [ -z "$_attr_addr" ]; then
    _attr_addr=$(printf '%s' "$_attr_trimmed" | sed -n 's/^\([^<>]*\)$/\1/p')
  fi
  [ -n "$_attr_addr" ] || return 1
  printf '%s' "$_attr_addr"
}

# reject <reason> <why+remedy> <offending lines>
# The reason and remedy are arguments, not one shared blurb: the three rejection
# paths have genuinely different remedies, and a single canned message told a
# contributor to "ask for it explicitly" when the gate would have accepted the
# address already.
reject() {
  {
    echo "ERROR: rejected - $1"
    echo
    printf '%s\n' "$2"
    echo
    echo "Offending line(s):"
    printf '%s\n' "$3" | sed 's/^/  /'
    echo
    echo "Deliberate override: SKIP_ATTRIBUTION_CHECK=1"
  } >&2
  exit 1
}

_why_generator="This repo's AGENTS.md requires attribution trailers only when explicitly
requested, and naming a tool that did not write the change misattributes
authorship in permanent public history.

Remove the trailer. If a truthful credit is wanted, ask for it explicitly."

_why_signoff="Signed-off-by asserts authorship under this project's terms, which
is not what a co-credit is and is not a convention this repository uses.

Remove it. Use Co-authored-by for a contributor, if their address is creditable."

_why_coauth="This repository credits only an address it can verify: the configured git
identity, an entry in .attribution-allow, or ATTRIBUTION_ALLOWLIST. A display
name is not an identity, and \"Hermes\" is also a real GitHub organization.

To credit a real contributor, add their address to .attribution-allow. That is
an attribution-policy change, so review it like one."

if hits=$(grep -Ein "$pattern_gen" "$_tmp"); then
  reject "third-party attribution trailer." "$_why_generator" "$hits"
fi

if hits=$(grep -Ein "$pattern_signoff" "$_tmp"); then
  reject "Signed-off-by trailer." "$_why_signoff" "$hits"
fi

# Co-authored-by is judged per line: an unlisted address is rejected, and every
# line is checked even when an earlier one passed, so one good trailer cannot
# launder a bad one alongside it. Same "if grep finds it" idiom as above; the
# read loop is fed by a heredoc because a pipe would run it in a subshell and
# every rejected line would be lost with it.
if coauth=$(grep -Ein "$pattern_coauth" "$_tmp"); then
  bad=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if address=$(_attr_trailer_address "${line#*:}"); then
      _attr_is_allowed "$address" || bad="$bad$line
"
    else
      bad="$bad$line
"
    fi
  done << EOF
$coauth
EOF
  [ -z "$bad" ] || reject "third-party attribution trailer." "$_why_coauth" "$bad"
fi

exit 0
