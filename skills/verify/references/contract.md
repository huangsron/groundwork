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
  AND clean checkout — no uncommitted edits OTHER than the verifier's own run records/reports
      (judge cleanliness EXCLUDING tool output; report raw dirtiness separately)
  AND source commit == the approved commit (if an approved commit was given)
  AND adapter/harness identity recorded (hash) for audit
  AND build exit == 0 (0 compiler/build errors)
  AND required artifacts are FRESH (rebuilt this run, not stale)
  AND every required smoke gate passes
  AND no unapproved dependency or scope change
```
Any shortfall downgrades to `LOCAL_CHECK` (gates met, not independent) or `FAIL`/`BLOCKED`.
**Unknown is not clean:** if cleanliness/commit cannot be determined (no git, git failed), that is
a downgrade to `LOCAL_CHECK` with a limitation — never treat missing evidence as passing evidence.

## Evidence manifest (schema)

Required fields (types): `verdict` (string enum above), `independence` (`subagent|process-separated|CI|none`),
`build_ok` (bool), `errors_remaining` (int), `error_delta` (int|null), `iteration` (int),
`launch` (string), `crash_detected` (bool), `tree_clean` (bool|null), `source_commit` (string),
`expected_commit` (string), `commit_match` (bool|null), `harness_hash` (string),
`artifact_fresh` (bool|null), `records_dir` (string), `project_root` (string — the git toplevel
when available, else the project dir; anchors `_groundwork/`), `plan_id` (string),
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
| **GUI** | process alive **and positive evidence of a usable app UI**: a credible top-level application window owned by the process, stable for a minimum duration, no crash/WER. *A window that is ONLY an error/MessageBox-style dialog is ambiguous → `INCONCLUSIVE`, not PASS — even when its TITLE matches the expected one (error boxes carry the app's name); only a non-dialog window confirms.* Process-alive alone is necessary, not sufficient. |
| Service | port open / health endpoint OK / startup within timeout |
| Web | builds; server reaches readiness; HTTP smoke passes |
| Native | links; architecture matches; runs (or emulator gate) |

## Failure categories (closed taxonomy — do not invent others)

Assign the FIRST matching category, in this order:

| Category | When |
|----------|------|
| `false_verdict` | a human confirmed a recorded verdict was wrong (retro-correction, see below) |
| `env_blocked` | verdict `BLOCKED` — environment/toolchain/access missing |
| `harness_error` | verdict `ERROR` — the harness itself failed |
| `startup_crash` | crash detected at launch |
| `build_failure` | build gate failed |
| `launch_failure` | build ok, launch gate failed |
| `launch_inconclusive` | launch evidence ambiguous (no window / dialog-only) |
| `ok` | verdict `PASS` or `LOCAL_CHECK` |
| `unknown` | none of the above |

**`false_verdict` source:** nothing sets it automatically. When a human later determines a recorded
verdict was wrong, re-run the collector against that run's manifest with the false-verdict count
(reference adapter: `collect.ps1 -Manifest <run>/manifest.json -FalseVerdict 1`) — it appends a
correction record with the same `run_id`.

## Dedup signature (exact algorithm — same on every platform, or dedup breaks)

`signature = lowercase(hex(SHA-256(UTF-8(category + "|" + skill_name + "|" + skill_version + "|" + normalized_error_pattern))))[0..11]`
(first 12 hex chars). `normalized_error_pattern` = first error line (or the launch-gate string if
no build error), after redaction, then normalized in this order:
1. `(\d+,\d+)` → `(<lc>)` (line/col)
2. `\S+\(<lc>\)` → `<file>(<lc>)` (source path before the line/col)
3. `'…'` quoted values → `'<v>'`
4. `/…/` regex literals → `/<re>/`
5. digits not preceded by a letter or digit → `<n>` (timeouts/exit codes; keeps `CS0246`-style codes)

Same problem → same signature (a stable fingerprint), regardless of run.

## Redaction rules (apply at collection time; **best-effort, not a guarantee**)

Strip before any record leaves memory: filesystem paths → `<path>`; IPv4 → `<ip>`;
fields whose key matches `password|secret|token|api[_-]?key|bearer` → `<redacted>`; do not collect
source code. These patterns are incomplete — **a human must still review before sharing externally.**

## Minimal adapter checklist (any platform — e.g. a POSIX shell adapter)

An adapter on any OS is correct when it does ALL of the following; nothing here needs PowerShell:

1. **Run dir**: create `<project>/_groundwork/runs/run-<UTC yyyyMMddTHHmmssZ>-<6 random hex>/` with
   `logs/` inside. `<project>` = the git toplevel when available, else the built project's dir —
   the SAME `_groundwork/` architect/plan write to (one tree, not one per subproject).
2. **Cleanliness**: record `source_commit` (`git rev-parse HEAD`) and `tree_clean` from
   `git status --porcelain` at the **repo toplevel**, excluding `_groundwork/**`; git absent/failed →
   `tree_clean = null` (unknown ≠ clean).
3. **Build**: run the ecosystem's build (make/gradle/cargo/npm…), capture exit code + full log into
   `logs/`; `errors_remaining` = count of **distinct** error lines.
4. **Smoke gate**: apply the program-type gate from the table above.
5. **Verdict**: apply the PASS predicate exactly; emit the manifest with every required field
   (missing evidence → `null`, `limitations` entry) as **UTF-8 without BOM**.
6. **Collect**: append one redacted ledger record (schema above, signature algorithm above) to
   `<project>/_groundwork/feedback/ledger.jsonl`, one compact JSON object per line, UTF-8 **without BOM**.
7. **Iteration state**: keep `runs/iteration-state.json` (`last_errors`, `iteration`) to compute `error_delta`.
8. **Exit code**: 0 for `PASS`/`LOCAL_CHECK`, 1 otherwise; the manifest `verdict` field is the real verdict.

## Honest limits (state these; do not overclaim)

- **Reproducible ≠ cross-machine identical.** Same source + same adapter ⇒ same verdict **on the
  same environment**. Different SDKs, registry state, fonts, locale can change results.
- **Independence is procedural, not cryptographic** on a single machine. State the level.
- **`LOCAL_CHECK` is not a PASS.** It means "not yet independently confirmed."
- **Feedback issues are drafts.** Nothing is filed automatically; a human decides and submits.
