# Project conventions — groundwork

## Temporary data lives in `.tmp/` (only there)

`.tmp/` at the repo root is **the** directory for all temporary / scratch / staging data
(drafts, notes pending GitHub upload, experiment output, throwaway files).

- **Put every temporary file under `.tmp/`.** Do **not** scatter temp data anywhere else in
  the repo, and do not create other temp directories.
- `.tmp/` is **git-ignored** — its contents are never committed. When something in `.tmp/` is
  ready to keep, move it to its proper home (e.g. `docs/`, a GitHub issue) first.
