# Independent Verification (Phase 6) — adapter notes

> **`contract.md` is authoritative.** This file is implementation notes for an adapter (the
> reference one is `adapters/windows/verify.ps1`). Where this file and the contract
> differ, the contract wins. `LOCAL_CHECK` is a distinct "not yet independently confirmed" state,
> **not a PASS**. Reproducible ⇒ same verdict on the **same environment** only. Redaction is
> best-effort, not a guarantee.

The rule: **the agent that changed the code does not declare it passing.** A PASS verdict is
produced by an independent verifier running the frozen adapter on a clean checkout, emitting an
evidence bundle. The executor's own runs are `LOCAL_CHECK`, never `PASS`.

## Threat model (be honest about what this buys)

Role separation + reproducibility defends against the executor's **confirmation bias,
selective testing, and verbal misjudgment**. It does NOT defend against a single user tampering
on their own machine, collusion, or forged evidence. Reproducibility ≠ independence. State the
**independence level** in every report:

| Level | Meaning |
|-------|---------|
| `subagent` | A separate subagent ran the harness (same machine/user) |
| `process-separated` | Separate process/account, executor has no write access to evidence |
| `CI` | Permission-separated CI runner, executor cannot alter the run or logs |

If no role separation happened, the result is `LOCAL_CHECK`, not `PASS`.

## PASS predicate

```
PASS =
  source_commit matches the approved integration commit
  AND working tree is clean (no uncommitted edits)
  AND verification_harness hash matches the approved harness
  AND clean build exit code == 0
  AND required artifacts are FRESH (mtime/hash changed this run, not stale)
  AND every required smoke gate passes
  AND no unapproved dependency or scope change
```

Anything else is `FAIL` or `BLOCKED` (missing access/hardware/intranet/license — never
disguised as a product error).

## Verifier procedure

1. Verifier (≠ executor) checks out the approved integration commit into a fresh tree.
2. Confirm `git status` clean and record the commit SHA.
3. Run the frozen harness (record its hash). Executor must not have write access to the
   evidence directory.
4. Emit `manifest.json` (always — wrap in try/finally so a mid-run error still records).

## Evidence bundle (`manifest.json`)

Record: verdict, source SHA, working-tree-clean flag, harness SHA, exact commands, cwd, tool
versions (the actual MSBuild version string, not just a path — `vswhere -latest` drifts when
tools update), per-target exit codes, timestamps, artifact paths + hashes, and `limitations`
(what was NOT verified).

## Smoke gates by program type (pluggable)

| Type | Gate |
|------|------|
| Library | compile + tests + (API/ABI check) |
| CLI | exit code + stdout contract |
| **GUI** | process alive **AND** a real top-level window owned by the process **AND** (if known) title/class matches **AND** no crash/WER dialog, checked after a parameterized startup timeout and stable for a minimum duration |
| Service | port open / health endpoint / startup within timeout |
| Web | build + server readiness + HTTP smoke |
| Native | link map + architecture match + emulator gate |

> Weak-check traps: "the process didn't exit in N seconds" is NOT proof of launch (it may be
> blocked on a modal error dialog, or still inside a slow DB/network connect that hasn't drawn
> a window yet). Require a real window; allow a long enough startup timeout for apps that block
> on I/O at launch; treat an *unexpected* modal/error/WER dialog as FAIL, not PASS.

## Harness parameters & handoff

`verify.ps1` records the **plan id** (`-PlanId`, the approved-plan binding from
/groundwork:plan) and optionally checks the source commit (`-ExpectedCommit`) in the manifest,
so the run is traceable to the approval. It also records the harness's own SHA-256
(`harness_hash`) for audit. Map the approved **success level** to parameters: "compiles" →
omit `-Exe` (no launch gate); "launches" → pass `-Exe` (+ optional `-ExpectedWindowTitle`).

**Exit codes:** 0 = `PASS` or `LOCAL_CHECK`; 1 = `FAIL` / `INCONCLUSIVE` / `ERROR`.
Always read `manifest.json` `verdict` for the real distinction — a flat exit code is not the verdict.

## Reproducible harness

`scripts/verify.ps1` (.NET/MSBuild) is the reference implementation: discovers MSBuild
via `vswhere`, kills lingering app instances (avoids locked-output MSB3027), clears stale
artifacts, builds with a real exit code via `Start-Process -Wait -PassThru` (+ `/nodeReuse:false
/p:UseSharedCompilation=false`), enforces a parameterized GUI window/title/crash gate, records
working-tree cleanliness + commit + MSBuild version, and always writes `manifest.json`. Same
source + same harness ⇒ same verdict.
