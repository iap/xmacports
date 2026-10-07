# Documentation style guide

This file holds the conventions this repository follows for documentation.
It is extracted from CONTRIBUTING.md so that style rules live in one place.

## Alert syntax

Use GitHub/GitLab alert syntax. Alerts also render in MR and issue bodies, but
**never** in commit messages — messages travel as plain text (git log,
terminals, email), where the syntax shows up as literal clutter.

```markdown
> [!NOTE]
> Supplemental information that's not critical to follow.

> [!TIP]
> Helpful suggestion for a better workflow or outcome.

> [!IMPORTANT]
> Critical information the reader must follow to avoid breakage.

> [!WARNING]
> Potential risk — data loss, security issue, or irreversible action.

> [!CAUTION]
> Stronger than WARNING — destructive or dangerous if ignored.
```

## Formatting

- Wrap prose at roughly 80 columns. Tables are exempt: a cell wide enough to read
  beats a column narrow enough to abbreviate.
- Tag every fenced code block with its language. An untagged fence is a defect.
- Use ATX headings (`#`), never setext underlines.
- Prefer relative links between documents in this repository so they survive a
  rename or a move.

## Sync rule

Keep docs, tests, and code in sync. When file names, paths, or startup order
change, update every document that mentions them in the same change set.
