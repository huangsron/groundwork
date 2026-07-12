---
name: verify
description: Use when executing an APPROVED legacy build-repair plan (from /groundwork:plan) and confirming it works — applying the approved changes, then independently and repeatably verifying that the project compiles and launches without self-certification. Use when a repair "should be done" and needs an objective PASS/FAIL/BLOCKED verdict.
---

# Legacy Build Verify

## Overview

The execution + verification half of legacy build repair. It applies an **already-approved**
plan, then proves the result with **role-separated, repeatable** verification — never by the
editor judging their own work.

**Violating the letter of these rules is violating the spirit.**

## The Three Iron Rules (execution + verification)

1. **Only execute the approved plan.** Apply exactly what was approved. A new fact (a new
   missing dependency, a needed framework change, a new stub) is NOT yours to "just also fix":
   stop and route back to /groundwork:plan for re-approval.

2. **No self-verification.** The agent that made a change MUST NOT declare it passing. A PASS
   verdict comes only from an **independent verifier** (a different agent) running a frozen,
   repeatable harness on a **clean checkout**, emitting objective evidence. Your own runs are
   `LOCAL_CHECK` — never `PASS`.

3. **The harness owns the verdict, not your prose.** "It compiled and a window opened" is not
   a verdict; the harness's evidence is. A broken harness gets fixed and re-frozen — you NEVER
   edit product code to make a broken test green.

## Phases

| # | Phase | Gate / output |
|---|-------|---------------|
| 5 | **Execute** | ENTRY GATE (below), then apply the approved fixes; single-purpose commits |
| 6 | **Independent verify** | Verifier (≠ executor) runs the frozen harness on a clean checkout of the integration commit; emits evidence + verdict |
| 7 | **Report** | Summary first, details after |

**Phase 5 entry gate (before the FIRST edit).** Read the approval record
`_groundwork/_manifest.json` (written by /groundwork:plan). It must show an explicit approval
decision, the plan id, and the allowed paths. Honor `approved_except` exclusions — an excluded
fix is NOT approved. No record, or decision isn't an approval → STOP; a chat "ok" without the
record is not approval. Also read recent `_groundwork/feedback/ledger.jsonl` records — a
same-signature past failure changes what to watch for.

**Phase 5 execution modes.** Default: ONE executor applies fixes sequentially — simplest and
safe. Team mode (only when fixes are many and independent): one `git worktree` per agent, each
assigned whole fixes (never shared files); ONE integrator owns high-conflict files
(.sln/manifest/lockfile/toolchain) and merges. Either mode ends with the integrator (or sole
executor) committing the applied fixes and recording the **integration commit SHA** — that SHA
is what the verifier checks out and what `-ExpectedCommit` binds.

**The authoritative, language/OS-agnostic spec is `references/contract.md`** (verdict states,
PASS predicate, manifest/ledger schema, smoke gates, redaction, signature, honest limits). Any
adapter implements it; `adapters/windows/verify.ps1` is the **.NET/Windows reference
adapter** (PowerShell is native there — one adapter, not the universal mechanism). When no
matching adapter exists, follow the contract directly with the environment's own tools.
`references/verification-harness.md` holds adapter implementation notes.

## Iteration scorecard (run every loop; stops thrashing)

Score each verify loop objectively. **Improved** means: `errors_remaining` strictly down OR a
blocker closed, AND zero new regressions, AND scope adherence = yes — anything else is NOT
improvement (errors down while a regression appeared is a worse loop). If the score does not
improve for 2 consecutive loops, STOP and route back to /groundwork:plan — that is
trial-and-error, not progress.

| Metric | Measure |
|--------|---------|
| Build errors Δ | compile errors vs previous loop (down = good) |
| Blockers resolved Δ | approved blockers closed this loop |
| Verdict | one of the six contract states (PASS / LOCAL_CHECK / FAIL / INCONCLUSIVE / BLOCKED / ERROR) from the independent harness |
| Regressions | previously-passing gates now failing (any = bad) |
| Scope adherence | edits stayed within approved paths (must be yes) |

Record the scorecard in the evidence bundle each loop.

## Failure routing (not trial-and-error)

- **Implementation defect** (plan right, code wrong) → fix in Execute; verifier re-runs in full.
- **New fact / new dependency / scope change** → STOP, back to /groundwork:plan, RE-APPROVE.
- **Harness defect** → fix + re-freeze the harness. NEVER edit product code to satisfy it.
- **Environment blocked** (access/hardware/intranet/license) → report **BLOCKED**, not a product error.

Every loop adds: evidence → root-cause hypothesis → predicted fix → (approved) change.

## Rationalizations — STOP

| Excuse | Reality |
|--------|---------|
| "The script is objective, so me running it counts as independent." | Reproducibility ≠ independence. A different agent/verifier must run it on a clean checkout. Your run is `LOCAL_CHECK`. |
| "Realistically I just run the build and judge it myself." | Self-judgment is *the* documented failure mode. Verifier only. |
| "It's just a DLL / config / .csproj, not product code." | Any repair-related state change is execution. It must be in the approved plan. |
| "This new error is obviously part of the original plan." | New fact → re-approve. Don't expand scope mid-execution. |
| "It compiled and the window opened, so it works." | Compiles + launches ≠ works, especially through a stub. Report exactly what was verified and what was NOT. |
| "Clean checkout is too expensive; the dirty tree is equivalent." | A dirty tree can hide uncommitted fixes and stale artifacts. Verify on a clean checkout. |
| "I'll just tweak the harness so it passes." | Editing the harness to pass = self-verification. Harness changes are reviewed + re-frozen by the verifier. |

## Red Flags — STOP

- About to declare PASS based on a run *you* (the editor) did
- About to fix something outside the approved plan because you noticed it
- About to edit the harness or product code to turn a red gate green
- Reporting "launches" when only the process (not a window) was observed
- Scorecard flat/worse for 2 loops and still hand-patching errors

## `_report.md` layout (what the user reads — decide "did it work, can I trust it, what's unverified")

Lead with a verdict the user cannot misread. Skeleton:
```
# Verification report

Result: LOCAL_CHECK (partial verification)        ← plain words, not just the acronym
Env: <date> / <OS> / <conditions, e.g. no access to production DB>   ·   independence: <subagent/process-separated/CI/none>

(one line per verdict: PASS = all targets verified in this env; LOCAL_CHECK = passed here but not
independently/in production; FAIL = a target failed; INCONCLUSIVE = ran but evidence is ambiguous
— e.g. dialog-only window; BLOCKED = could not run — env/access missing; ERROR = the harness
itself failed. All six are defined in references/contract.md.)

## Per-item results   (one row per approved fix)
| Item | Result | Evidence (summary) |

## Verification scope   (three columns — keep them SEPARATE; merging them misleads)
- Verified:
- NOT verified:
- Residual risk:

## Honest limits   (3–5 lines, mandatory)
- LOCAL_CHECK is NOT a PASS. Reproducible ⇒ same verdict on the SAME environment only.
- Redaction (if any) is best-effort. Independence level stated above.

## Full evidence → _groundwork/runs/run-<id>/   (logs/manifest by link, not inlined)
```
`LOCAL_CHECK` must never be presented as a pass. Put only "summary + why the evidence is
credible" in the body; link the raw logs/manifest.

If `_groundwork/README.md` records an **output profile** (language/format, set by
/groundwork:architect), write `_report.md` in that language. Otherwise use the conversation
language.

## Collect (automatic) → feedback (separate skill)

Every run, the adapter calls `collect` automatically: it appends a **redacted** record to
`<project>/_groundwork/feedback/ledger.jsonl` (no network, no prompt, never changes the verdict).
This is the durable improvement data.

**Deciding whether to publish** a failure as a GitHub issue is a separate, user-decided step —
see the **`/groundwork:feedback`** skill. Nothing is filed automatically.
