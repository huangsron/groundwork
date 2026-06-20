---
name: plan
description: Use when a legacy or inherited project fails to build/compile with missing or broken dependencies (missing project references, absent DLLs, outdated target framework or toolchain) and you must produce an approved repair plan BEFORE any edits — even under deadline pressure or "just fix it, don't ask" autonomy. Pairs with /groundwork:verify for execution.
---

# Legacy Build Plan

## Overview

The planning half of legacy build repair. It produces an **approved, evidence-backed repair
plan** and changes NOTHING. Execution happens later via **/groundwork:verify**, and only
after the plan is approved.

Planning a legacy build fix fails in predictable ways under pressure: you fix the first error
you see, and you skip getting the plan approved because you were told "don't ask." This skill
forbids both.

**Violating the letter of these rules is violating the spirit.** "Full autonomy" / "don't
bother me" does NOT waive the approval gate.

## The Two Iron Rules (planning)

1. **Dependencies first, edits never (in this skill).** Change NO product code here. Inventory
   the dependency closure for the target scope; every missing dependency gets a search record.
   Searching the repo, git history, build outputs, caches, and (with approval) the machine for
   a real artifact — sibling source or a prebuilt DLL — is REQUIRED before you plan to
   reconstruct or stub anything.

2. **No execution before approval.** The deliverable is a written plan you hand to the user for
   explicit approval. "Don't ask questions / full autonomy" means make reversible decisions
   without hand-holding; it does NOT mean skip the plan gate, and it does NOT mean start editing.

## Phases

| # | Phase | Output / gate |
|---|-------|---------------|
| 0 | **Contract** | Scope; success level (compiles / packages / launches / core-flow works — pick one, don't conflate); allowed & forbidden changes; search roots |
| 1 | **Inventory + baseline** (team, READ-ONLY) | `INVENTORY_COMPLETE` (see below) |
| 2 | **Plan** | Per blocker: root cause + evidence, files to change, predicted result, rollback, verification gate, risk, restoration choice |
| 3 | **Independent review** | Reviewer ≠ planner: missed deps, premature stubs, more faithful restorations, risks |
| 4 | **Approval handoff** | Plan record ready for the user to approve; nothing executes here |

`INVENTORY_COMPLETE`: every declared & transitive dependency classified
(`resolved / optional / runtime-only / missing-approved`); every missing one has a search
record (roots, patterns, permission, result); baseline failure reproduced. See
`references/dependency-probes.md`.

## Dependency restoration priority (drives the plan)

```
real source / original binary  >  official package/artifact  >  provenance-checked compatible version
  >  rebuild from existing source  >  adapter  >  stub (last resort, requires approval)
```

## Approval record (handoff to /groundwork:verify)

The plan the user approves must be referenceable: a plan id/hash, the scope, the chosen
success level, allowed paths, and the verification harness that will judge it. Silence,
generic autonomy, or past authorization do NOT count as approval.

## Rationalizations — STOP

| Excuse | Reality |
|--------|---------|
| "They said don't ask, so I won't wait for approval." | Autonomy covers the reversible *how*, not skipping the plan gate. Hand the plan over and wait. |
| "I'll just start editing while I plan." | This skill produces a plan and edits nothing. Edits live in /groundwork:verify, post-approval. |
| "My instinct is to fix the first error." | First error ≠ root cause. Inventory the dependency closure first. |
| "No real DLL exists, plan a stub." | Unproven until you searched repo + git history + build outputs + caches + machine. Stub is last resort and must be called out for approval. |

## Red Flags — STOP

- About to edit product code (wrong skill — that's /groundwork:verify, after approval)
- About to finalize a plan before the dependency inventory is complete
- Planning to stub/reconstruct a dependency you have NOT searched disk + git history for
- Treating "don't ask" as approval

## `_plan.md` layout (what the user reads — decide "do I approve this?")

The user must be able to sign off: for every fix they see the root cause, what it touches, and
what happens if it's wrong. Skeleton:
```
# Repair plan

## Summary            (N fixes, blast radius, overall risk)

## Open questions     (must be resolved BEFORE approval — list them above the approval box)
1. …

## Fixes
### F-01: <title>
- Root cause:        (one sentence — not a symptom)
- Evidence:          (file:line / log)
- Disposition:       (what to do; which files; per restoration priority)
- Predicted result:
- Risk:              (what a wrong/unexpected change does)
- Allowed to touch:  (the boundary; beyond it needs re-approval)

## Excluded (deliberately NOT touched this round)   ← prevents misunderstanding

## Approval decision
- [ ] Approve all
- [ ] Approve except: ___
- [ ] Reject, reason: ___
- [ ] Need more info: ___
```
Every fix needs all six fields or it isn't approvable. Link the full dependency matrix / evidence
into `_groundwork/`; don't inline diffs or long alternatives.
