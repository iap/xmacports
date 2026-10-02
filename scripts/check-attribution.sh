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

# Match, then print the offending lines so the author sees what to remove.
#  - the Claude Code generator footer, with or without a markdown link, plus
#    the bare host so a mangled link is still caught
#  - any "Generated with <assistant>" naming a known tool
#  - Co-authored-by / Signed-off-by trailers (AGENTS.md requires an explicit
#    request before either)
#
# Every pattern is anchored to the START of a line, because a trailer is a
# whole line and prose is not. Without the anchor the gate blocks honest
# documentation that merely quotes the convention - a commit body explaining
# that this footer is rejected was itself rejected, which is the over-blocking
# this anchor exists to prevent.
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
pattern='^[[:space:]]*([^[:alnum:]"'\''>|*+#`_~+-][[:space:]]*)?(Generated[[:space:]]+with[[:space:]]+\[?(Claude Code|Cursor|Copilot|ChatGPT|Gemini|Aider|Codex)\]?|https?://claude\.com/claude-code)|^[[:space:]]*(Co-authored-by|Signed-off-by):'

_tmp=$(mktemp "${TMPDIR:-/tmp}/attrcheck.XXXXXX") || exit 2
trap 'rm -f "$_tmp"' EXIT INT TERM

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

hits=$(grep -Ein "$pattern" "$_tmp")

if [ -n "$hits" ]; then
  {
    echo "ERROR: rejected - third-party attribution trailer."
    echo
    echo "This repo's AGENTS.md requires attribution trailers only when explicitly"
    echo "requested, and naming a tool that did not write the change misattributes"
    echo "authorship in permanent public history."
    echo
    echo "Offending line(s):"
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo
    echo "Remove the trailer. If a truthful credit is wanted, ask for it explicitly."
    echo "Deliberate override: SKIP_ATTRIBUTION_CHECK=1"
  } >&2
  exit 1
fi

exit 0
