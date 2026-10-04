## What changed

<!-- What this MR does, and why. One paragraph is usually enough. -->

## How it was verified

<!-- Name the lanes you actually ran and their result, not "tests pass":
     make test  make test-zsh  make verify  make audit
     make fmt-check  make shellcheck  make python-lint

     CI runs the authoritative set. This field is for anything checked locally
     that CI does not cover. -->

## Gates bypassed

<!-- If none, write "none" rather than deleting this section.

     --no-verify                  skips the local commit-msg and pre-push hooks
     SKIP_MR_ATTRIBUTION_CHECK=1  skips the MR description gate

     Both are auditable; state them here with the reason. An MR description is
     not part of git, so the commit-msg hook never sees it. That gap is why CI
     reads this field rather than trusting the diff. -->

## Notes for the reviewer

<!-- Anything better explained in words than in the diff: a trade-off rejected,
     a risk accepted, or follow-up left deliberately out of scope.

     Commits are expected to be signed. GitLab authors the merge commit itself
     and cannot sign it, so that single commit is unsigned by necessity and is
     not checked; every commit in this MR is. -->
