# Verification Contract (language- and OS-agnostic)

This contract — **not any single script** — defines what a correct verification produces. Any
**adapter** (e.g. `adapters/windows/`) implements it with platform-native tools. When a
matching adapter exists, use it; otherwise follow this contract directly with whatever tools the
environment provides. The contract governs *behavior and schema*; adapters govern *how*.

The reference adapter `adapters/windows/*.ps1` is PowerShell because that is native to
Windows/.NET — it is **one adapter, not the universal mechanism**. Other ecosystems get their own.

## Verdict states (a verdict is exactly one)

| State | Meaning |
|-------|---------|
| `PASS` | All gates met **and** produced by an independent verifier on a clean checkout. |
| `LOCAL_CHECK` | Gates met, but **not independently confirmed** (same actor, or dirty tree, or unverified commit). **This is NOT a pass** — it is a distinct "needs independent confirmation" state. Never count it as PASS. |
| `FAIL` | A required gate failed (build errors, crash, wrong/no window, regression). |
| `INCONCLUSIVE` | Ran, but evidence is insufficient to decide (e.g. process alive but no window within the timeout). |
| `BLOCKED` | Could not run due to missing access/hardware/intranet/license — **never** disguised as a product failure. |
| `ERROR` | The harness/adapter itself failed. |

## PASS predicate

```
PASS =
  independent verifier (≠ the actor that made the change)
  AND clean checkout (no uncommitted edits)
  AND source commit == the approved commit (if an approved commit was given)
  AND adapter/harness identity recorded (hash) for audit
  AND build exit == 0 (0 compiler/build errors)
  AND required artifacts are FRESH (rebuilt this run, not stale)
  AND every required smoke gate passes
  AND no unapproved dependency or scope change
```
Any shortfall downgrades to `LOCAL_CHECK` (gates met, not independent) or `FAIL`/`BLOCKED`.

## Evidence manifest (schema)

Required fields (types): `verdict` (string enum above), `independence` (`subagent|process-separated|CI|none`),
`build_ok` (bool), `errors_remaining` (int), `error_delta` (int|null), `iteration` (int),
`launch` (string), `crash_detected` (bool), `tree_clean` (bool|null), `source_commit` (string),
`expected_commit` (string), `commit_match` (bool|null), `harness_hash` (string),
`artifact_fresh` (bool|null), `records_dir` (string), `plan_id` (string),
`limitations` (string[] — must serialize as `[]`, never null).

## Ledger record (schema, appended per run, redacted)

`schema_version` (int), `timestamp` (ISO-8601), `project_id` (string), `run_id` (string),
`skill_name`, `skill_version`, `verdict`, `iteration`, `errors_remaining`, `error_delta`,
`crash_detected`, `false_verdict` (int), `category` (string), `signature` (string),
`error_pattern` (redacted string), `harness_hash`.

## Smoke gates by program type (behavioral requirements, not implementation)

| Type | Gate (what must be observed) |
|------|------------------------------|
| Library | compiles; tests pass; (optional) API/ABI unchanged |
| CLI | expected exit code; stdout matches the agreed contract |
| **GUI** | process alive **and** a real top-level window owned by the process **and** (if known) title/class matches **and** no crash/error dialog, observed after a startup timeout and stable for a minimum duration. *Process-alive alone is necessary, not sufficient.* |
| Service | port open / health endpoint OK / startup within timeout |
| Web | builds; server reaches readiness; HTTP smoke passes |
| Native | links; architecture matches; runs (or emulator gate) |

## Dedup signature

`signature = short_hash( failure_category + skill_name + skill_version + normalized_error_pattern )`,
where `normalized_error_pattern` is the error skeleton with paths/line-cols/quoted-values removed.
Same problem → same signature (a stable fingerprint), regardless of run.

## Redaction rules (apply at collection time; **best-effort, not a guarantee**)

Strip before any record leaves memory: filesystem paths → `<path>`; IPv4 → `<ip>`;
fields whose key matches `password|secret|token|api[_-]?key|bearer` → `<redacted>`; do not collect
source code. These patterns are incomplete — **a human must still review before sharing externally.**

## Honest limits (state these; do not overclaim)

- **Reproducible ≠ cross-machine identical.** Same source + same adapter ⇒ same verdict **on the
  same environment**. Different SDKs, registry state, fonts, locale can change results.
- **Independence is procedural, not cryptographic** on a single machine. State the level.
- **`LOCAL_CHECK` is not a PASS.** It means "not yet independently confirmed."
- **Feedback issues are drafts.** Nothing is filed automatically; a human decides and submits.
