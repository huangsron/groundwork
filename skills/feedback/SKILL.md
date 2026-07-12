---
name: feedback
description: Use when deciding whether to report a verify failure as improvement data — after /groundwork:verify ends FAIL/INCONCLUSIVE/ERROR, or crashed, or hit a false verdict. Reads the verify run manifest (and the ledger for dedup/recurrence) and (user-decided) drafts a redacted GitHub issue with two ways to file. Use to turn recurring failures into actionable, deduplicated reports.
---

# Feedback — turn failures into improvement data

## Overview

Two layers, deliberately separated:

1. **Collect (automatic, already done by verify).** Every `/groundwork:verify` run appends a
   **redacted** record to `<project>/_groundwork/feedback/ledger.jsonl` (via the adapter's
   `collect`). No network, no platform, no prompt. This is the durable improvement data; this
   skill does **not** re-collect.

2. **Publish (this skill — user-decided).** When a run ends `FAIL`/`INCONCLUSIVE`/`ERROR`,
   `crash`, or `false_verdict > 0`, **the user decides** whether to open an issue. Nothing is
   filed automatically. (`BLOCKED` is deliberately excluded — a missing local environment is
   the user's to fix, not plugin improvement data.)

   `false_verdict` never sets itself: when a human finds a recorded verdict was wrong, append a
   correction record first — `collect.ps1 -Manifest <that run>/manifest.json -FalseVerdict 1`
   (same `run_id`) — then decide whether to publish it.

Kept separate from verify because the decision happens at a different time and may aggregate
across several verify runs.

## Use it

Reference adapter (.NET/Windows): `adapters/windows/feedback.ps1 -Manifest <records>\manifest.json -Repo <owner/repo> -ExpectedVsActual "<one line>"`.
For other ecosystems, follow the same contract with the environment's tools.

It prints a **dedup search** (`sig:<hash>` = `category+skill+version+normalized-error`), then
**two ways to file**:
- (A) a ready-to-paste `gh issue create` (returns the issue URL), or
- (B) a **prefilled GitHub new-issue URL** for the browser (no `gh` needed).
Plus a `gh issue comment` if an open issue already matches the sig.

Config (repo, label, mode, cooldown) lives at plugin root `feedback.config.json`. Publishing is
a **swappable sink** — GitHub is one adapter, not the mechanism.

## Rules

- **Redaction is best-effort, not a guarantee.** Paths/IPs/secret-keyed fields are stripped at
  collection time, but the rules are incomplete — a human reviews before sharing externally.
- **Dedup first.** Same problem → same `signature`; comment on the existing issue instead of
  opening a duplicate.
- **Cooldown** (`feedback_cooldown_days`): the same signature already recorded within N days →
  comment on the existing issue, don't open a new one. `feedback_mode: off` disables publishing
  entirely; `draft` (default) = human files; `auto` is reserved for high-signal categories and
  never includes `false_verdict`.
- **Team:** when multiple agents each produce a manifest, only the aggregating leader publishes —
  workers do not each open issues.
- **Never auto-file `false_verdict`** — confirm it isn't an environment fluke first.

## Close the loop (don't just collect)

Before planning a retry, read recent same-`signature` / same-`project_id` ledger records to spot
recurring failures and feed them back into `/groundwork:plan`. Collection without a reader is not
a feedback loop.
