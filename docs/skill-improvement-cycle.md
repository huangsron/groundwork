# Skill improvement cycle (repeatable)

How groundwork's skills get better: run the plugin on a real project, find where the **skill**
(not the target project) underperformed, make one minimal skill edit, and re-validate. A meta-loop
over the skills, driven by ground truth + the verify ledger.

> This document is the **method**. Any concrete validation corpus, case data, fixes, paths, or
> client/project specifics are **kept out of this repo** (this is a public repo) — hold them in a
> local, git-ignored location (`.tmp/`), not in tracked docs.

## What makes a usable corpus

- **Variety** — different languages, project topologies, dependency types, failure categories.
- **Ground truth** — at least some cases have a known root cause, correct minimal fix, and an
  acceptable verification result.
- **Difficulty gradient** — from one project / one root cause to multi-project / external deps.
- **Reproducible** — fixed commit, toolchain, initial state; always run from a clean copy.
- **Honest scope** — a handful of cases finds obvious defects; it does **not** prove
  generalization. State the gaps (which ecosystems/OSes are not exercised).

## The cycle (one round = one failure mode)

| Phase | Input | Output | Pass gate |
|---|---|---|---|
| 0 **Freeze case** | pre-fix commit, env, allowed commands | read-only fixture id, ground truth, verifiable ceiling | re-runnable from the same initial state |
| 1 **Baseline run** | current skills, case **with the answer hidden** | full architect→plan→change→verify trace + ledger | run completes; traceable evidence even if verdict ≠ PASS |
| 2 **Human score** | baseline trace vs ground truth | **1–3 concrete skill defects** (never "rewrite all skills") | scored on: root-cause recall, error categorization, fix minimality, verification honesty, no unrelated changes |
| 3 **Minimal skill edit** | one reproducible failure mode | one skill edit, keyed to `category`/`signature` (no case-specific names/paths embedded) | edit addresses exactly one failure mode |
| 4 **Regression** | edited skills | re-run the failing case + ≥1 different-category case | target metric improves; held-out shows no new `false_verdict` / no clear `iterations` regression |
| 5 **Keep or revert** | round results | decision + evidence | KEEP iff ground-truth recall ↑ AND verification still honest AND held-out not worse; else REVERT |

**Held-out:** with few cases, do **not** make a permanent train/test split → **rotate** held-out
by category; change only one case per round.

**Stop a round when:** one clear failure mode is handled, OR there isn't enough evidence to
justify a skill edit. Do not endlessly tweak prompts.

## Objective triggers — when the ledger says "fix a skill" (priority order)

1. `false_verdict > 0` (ledger int; set by a human correction record — see contract.md) → **highest**; fix the verify/verdict contract first.
2. a stubbed dependency (plan record: disposition = stub) AND `verdict = PASS` → treat as a false verdict (this is judged from the plan record + manifest; it is not a ledger field).
3. same `signature`, `error_delta ≥ 0` for 2 consecutive runs → plan/diagnosis missed the root cause.
4. `iteration` at PASS above baseline AND repeating one `category/signature` → skill lacks a convergence rule.
5. `error_delta` drops but a NEW `category` appears → maybe only surface errors removed; verify by hand.

Routing: a known-required root cause absent from architect/plan → fix architect/plan; root cause
found but verify ran no matching check → fix verify; unstable `category/signature` across runs →
**fix the classification rules first, or every metric is unusable.**

## "Genuinely better" (not overfit)

- Ground-truth case: required-fix recall ↑, no extra high-risk edits, `false_verdict` not ↑.
- Held-out case: not worse — especially no new false PASS.
- **Hard vetoes** (cannot be outweighed): `false_verdict`, stub-as-real, breaking a held-out case.
- **Do NOT compute a weighted total score** — it hides false verdicts.

## Minimal first round

1. Freeze a **pre-fix** snapshot of a ground-truth case, its known-correct patch, tool versions,
   allowed verify scope.
2. Hide the answer; run architect → plan → change → verify in full; keep every output + ledger.
3. Score against the known root causes.
4. Check for unrelated refactors, stub-as-real, false PASS; when the real runtime env is
   unavailable, the honest result is `LOCAL_CHECK`, not PASS.
5. Pick the single clearest failure mode → one minimal skill edit.
6. Re-run from a clean snapshot.
7. KEEP if root-cause identification or verification honesty improved with no new regression; else REVERT.

**First-round success is NOT "auto-fixed everything."** It is: groundwork **finds the known root
causes, proposes a minimal plan, and does not lie about what it could not verify.**

## Over-engineering to avoid

Benchmark platform before fixtures are reliable; statistical significance / weighted scores on a
few samples; auto-converting ledger metrics into prompt edits; permanent train/test split;
requiring every case to fully build (an honest constrained verdict IS the correct artifact when
the real env is missing); editing multiple skills in one round (breaks attribution);
auto-filing feedback issues.
