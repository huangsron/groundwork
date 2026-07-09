# Architect Multi-Agent Scan Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the architect skill's two-sentence "Team" note into a real four-phase pipeline (parallel lens scan → cross-compare → adversarial verify → report), per the approved spec `design/architect-team-flow.md`.

**Architecture:** All deliverables are markdown prompt documents. `skills/architect/SKILL.md` keeps the flow and rules; each scanner/verifier subagent reads one file under `skills/architect/references/`. No code, no engine — same pattern as the repo's adapters ("an adapter = a document").

**Tech Stack:** Markdown only. Verification = file existence + cross-file consistency greps.

## Global Constraints

- Read-only principle everywhere: every prompt file must forbid modifying the scanned project.
- Claim schema (verbatim, all files must match): `{ text, kind: fact|inference|unknown, evidence, confidence, lens, corroboration: agreed|conflicted|single, verdict: confirmed|refuted|unverifiable }` — `lens` set by scanners; `corroboration` by the synthesizer; `verdict` only on verified claims.
- Lens names (verbatim): `structure`, `dependencies`, `dataflow`, `runtime`, `risk`.
- Models: scanners = haiku, verifiers = sonnet, synthesizer = inherit session model.
- Separation of duties: scanners don't conclude, synthesizer doesn't scan, verifiers don't write the report.
- Reference files are written in English (matching the existing SKILL.md); keep each under ~60 lines.

---

### Task 1: Five lens reference files

**Files:**
- Create: `skills/architect/references/lens-structure.md`
- Create: `skills/architect/references/lens-dependencies.md`
- Create: `skills/architect/references/lens-dataflow.md`
- Create: `skills/architect/references/lens-runtime.md`
- Create: `skills/architect/references/lens-risk.md`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: the scanner output contract — final reply is ONLY a JSON array of `{ text, kind, evidence, confidence, lens }`. Task 3's SKILL.md rewrite references these exact filenames.

- [ ] **Step 1: Write `lens-structure.md`**

```markdown
# Lens: structure — components & boundaries

You are one of five scanners. Scan the FULL tree under the given root through this lens only.
You gather traceable facts; you do NOT conclude, rank, or write any report.
Read-only: change nothing in the scanned project.

## What to find
- Main components/layers/subsystems above the file level (projects, packages, modules,
  services) and each one's single job.
- Boundaries: what references what; dependency direction between components.
- Entry points: executables, main functions, service hosts, UI shells.
- Circular references between components (they shape change risk).

## How
- Start from solution/workspace/manifest files (*.sln, package.json workspaces, pom modules,
  Cargo workspace, CMake targets…) — they are the truth source for "what units exist".
- Confirm dependency direction from actual references/imports, not folder names.
- A folder named "BLL"/"core"/"utils" is NOT evidence of layering — layering without
  reference evidence is `inference`, with confidence.

## Traps
- No per-file listings; claims are about components and responsibilities.
- Do not force UI/BLL/DAL onto a system that doesn't show it.

## Output — your final reply is ONLY this JSON array
[
  { "text": "one claim", "kind": "fact|inference|unknown",
    "evidence": "file:line, or command + output",
    "confidence": 0.0, "lens": "structure" }
]
No prose around the JSON. An area you could not inspect is a claim with kind "unknown" —
never guess.
```

- [ ] **Step 2: Write `lens-dependencies.md`**

```markdown
# Lens: dependencies — build chain & external packages

You are one of five scanners. Scan the FULL tree under the given root through this lens only.
You gather traceable facts; you do NOT conclude, rank, or write any report.
Read-only: change nothing in the scanned project. Never run installs or builds; read-only
version probes (`tool --version`) are allowed.

## What to find
- Toolchain demanded vs present: target framework/engine/JDK versions in manifests, build
  scripts, CI definitions.
- Declared external packages (manifests, lock files) and vendored binaries (DLLs/jars/libs).
- Broken references: project references to paths that don't exist, HintPaths outside the repo,
  imports/usings with no matching declared dependency.
- Native/licensed dependencies: COM, P/Invoke/FFI, vendor SDKs, drivers — one claim each.

## How
- Read every manifest and lock file; where possible diff "declared" vs "present on disk".
- Grep imports for namespaces no declared dependency covers.
- Distinguish "referenced" from "actually imported somewhere".

## Traps
- A lock file proves what resolved once, not what this machine has — availability here is
  `unknown` unless probed.

## Output — your final reply is ONLY this JSON array
[
  { "text": "one claim", "kind": "fact|inference|unknown",
    "evidence": "file:line, or command + output",
    "confidence": 0.0, "lens": "dependencies" }
]
No prose around the JSON. An area you could not inspect is a claim with kind "unknown" —
never guess.
```

- [ ] **Step 3: Write `lens-dataflow.md`**

```markdown
# Lens: dataflow — flows, state & stores

You are one of five scanners. Scan the FULL tree under the given root through this lens only.
You gather traceable facts; you do NOT conclude, rank, or write any report.
Read-only: change nothing in the scanned project.

## What to find
- 2–5 main execution/data flows end-to-end (user action → … → store).
- State ownership: which component reads/writes which store; shared mutable state.
- Data stores: databases, files, queues, caches — with whatever schema/shape evidence exists.
- Transaction/consistency boundaries where visible.

## How
- Trace from entry points (handlers, main, controllers, form events) down to I/O calls.
- Search for SQL strings, ORM configs, file open/write, network sends.

## Traps
- A flow you can only partly trace = partial fact + an `unknown` claim for the missing segment.
- Don't invent a canonical "data layer" — cite the actual call sites.

## Output — your final reply is ONLY this JSON array
[
  { "text": "one claim", "kind": "fact|inference|unknown",
    "evidence": "file:line, or command + output",
    "confidence": 0.0, "lens": "dataflow" }
]
No prose around the JSON. An area you could not inspect is a claim with kind "unknown" —
never guess.
```

- [ ] **Step 4: Write `lens-runtime.md`**

```markdown
# Lens: runtime — config, integrations & topology

You are one of five scanners. Scan the FULL tree under the given root through this lens only.
You gather traceable facts; you do NOT conclude, rank, or write any report.
Read-only: change nothing in the scanned project.

## What to find
- Config sources: config files, env vars, registry, connection strings, hardcoded
  paths/IPs/ports/machine names.
- External integrations: DBs, FTP/network shares, web services, third-party endpoints.
- Process/host topology: how many processes/services, what starts what, scheduled/batch jobs.
- Deployment evidence: installers, deploy scripts, CI/CD, expected OS/runtime.

## How
- Grep for config APIs, connection strings, URLs, ports, absolute paths.
- Read installers/deploy scripts/CI as evidence of intended runtime — tag it as such.

## Traps
- A hardcoded absolute path or machine name is always worth a claim.
- Repo config may be overridden at deploy — state which one you actually saw.
- Secrets: report WHERE credentials live (file:line); never copy a secret value into a claim.

## Output — your final reply is ONLY this JSON array
[
  { "text": "one claim", "kind": "fact|inference|unknown",
    "evidence": "file:line, or command + output",
    "confidence": 0.0, "lens": "runtime" }
]
No prose around the JSON. An area you could not inspect is a claim with kind "unknown" —
never guess.
```

- [ ] **Step 5: Write `lens-risk.md`** (launch-crash probe moves here verbatim from SKILL.md)

```markdown
# Lens: risk — launch blockers, coupling & debt

You are one of five scanners. Scan the FULL tree under the given root through this lens only.
You gather traceable facts; you do NOT rank or write any report — severity candidates only.
Read-only: change nothing in the scanned project.

## Launch-crash probe (always run this check)

Flag as a **HIGH launch-crash risk**: a resource backed by a **native or external driver** —
a DB client, a COM object, a P/Invoke / FFI wrapper, a licensed/vendor SDK — that is initialized
**eagerly** (field initializer, constructor, or static/type initializer) rather than lazily.
Its initializer runs **before the UI is shown**, so if the native driver/runtime is missing the
app crashes **before any window appears**. Look for: instance/`static` fields constructed at
declaration; such objects built in a form/page constructor or a global/singleton; type
initializers that touch native code.

Report it as a launch blocker whose fix is **lazy / guarded initialization** (construct on first
use, inside a try) — NOT merely "verify at launch" or "set the platform bitness". This is generic
across stacks (.NET type initializers, JVM static blocks, native dlopen at load, etc.).

## Other risks to find
- Single points of failure: one class/module everything routes through; god objects.
- High coupling: two-way references between components; change amplification.
- Tech debt markers: dead code, commented-out blocks kept "just in case", TODO/FIXME/HACK.
- Evidence-thin areas nothing explains → name them as verification priorities.

## Output — your final reply is ONLY this JSON array
[
  { "text": "one claim (prefix launch blockers with 'HIGH launch-crash risk:')",
    "kind": "fact|inference|unknown",
    "evidence": "file:line, or command + output",
    "confidence": 0.0, "lens": "risk" }
]
No prose around the JSON. An area you could not inspect is a claim with kind "unknown" —
never guess.
```

- [ ] **Step 6: Verify files and schema consistency**

Run: `ls skills/architect/references/ && grep -c '"lens"' skills/architect/references/lens-*.md`
Expected: 5 files listed; each lens file reports count 1 (schema block present).

Run: `grep -L 'Read-only' skills/architect/references/lens-*.md`
Expected: no output (every file carries the read-only rule).

- [ ] **Step 7: Commit**

```bash
git add skills/architect/references/
git commit -m "architect: add five scan-lens reference files"
```

---

### Task 2: Adversarial verification manual

**Files:**
- Create: `skills/architect/references/adversarial-verify.md`

**Interfaces:**
- Consumes: the claim shape produced by Task 1 scanners (`{ text, kind, evidence, confidence, lens }`).
- Produces: the verifier output contract — final reply is ONLY `{ "verdict": "confirmed|refuted|unverifiable", "reason", "counter_evidence" }`. Task 3 references this filename and the verdict values.

- [ ] **Step 1: Write `adversarial-verify.md`**

```markdown
# Adversarial verification — try to refute the claim

You are given ONE claim `{ text, kind, evidence, confidence, lens }`. Your job is to REFUTE it.
You succeed by showing it false, mis-cited, or unsupported — not by agreeing with it.
Read-only: change nothing in the scanned project.

## Attack sequence
1. **Check the citation.** Open the cited file:line (or re-run the read-only command). Does it
   exist? Does it say what the claim says? A citation that doesn't support the text = refuted,
   even if the claim might be true some other way.
2. **Hunt counter-evidence.** Search for facts that contradict the claim: a config that
   overrides it, a second implementation, a newer file, a code path that bypasses it.
3. **Attack the inference.** If kind is "inference": is the step valid? Could the same evidence
   support a different conclusion? Name the alternative.
4. **Reproduce cheaply.** If a read-only command can settle it (version probe, grep count),
   run it.

## Verdicts
- `confirmed` — citation checks out AND no counter-evidence found after a real search.
- `refuted` — citation false/missing, or counter-evidence found (include it).
- `unverifiable` — cannot be settled read-only from this machine; say what would settle it.

If still uncertain after real work: bad citation on a fact → refuted; otherwise → unverifiable.
Never confirm out of politeness.

## Output — your final reply is ONLY this JSON
{ "verdict": "confirmed|refuted|unverifiable",
  "reason": "one sentence",
  "counter_evidence": "file:line or command output; empty string if none" }
```

- [ ] **Step 2: Verify verdict values match the global schema**

Run: `grep -o 'confirmed|refuted|unverifiable' skills/architect/references/adversarial-verify.md | head -1`
Expected: `confirmed|refuted|unverifiable`

- [ ] **Step 3: Commit**

```bash
git add skills/architect/references/adversarial-verify.md
git commit -m "architect: add adversarial verification manual"
```

---

### Task 3: Rewrite SKILL.md — pipeline, schema, probe pointer

**Files:**
- Modify: `skills/architect/SKILL.md` (three edits: `_claims.json` schema line ~21; launch-crash probe section ~56–68; Team section ~81–85)

**Interfaces:**
- Consumes: exact filenames from Tasks 1–2 (`references/lens-structure.md`, `lens-dependencies.md`, `lens-dataflow.md`, `lens-runtime.md`, `lens-risk.md`, `adversarial-verify.md`); claim/verdict field values from Global Constraints.
- Produces: the final skill entry point; nothing depends on it downstream.

- [ ] **Step 1: Edit the `_claims.json` schema line**

Old:
```markdown
- `_claims.json` — one list of claims, each `{ text, kind: fact|inference|unknown, evidence, confidence }`. (One file with a `kind` field — not separate claims/verdicts/audit files.)
```
New:
```markdown
- `_claims.json` — one list of claims, each `{ text, kind: fact|inference|unknown, evidence, confidence, lens, corroboration: agreed|conflicted|single, verdict: confirmed|refuted|unverifiable }` — `verdict` only on claims that went through adversarial verification. (One file — not separate claims/verdicts/audit files.)
```

- [ ] **Step 2: Replace the launch-crash probe section body with a pointer**

Old (the whole section under `### Launch-crash probe (always check; a static scan often misses this)`, three paragraphs):
```markdown
### Launch-crash probe (always check; a static scan often misses this)

Flag as a **HIGH launch-crash risk**: a resource backed by a **native or external driver** —
a DB client, a COM object, a P/Invoke / FFI wrapper, a licensed/vendor SDK — that is initialized
**eagerly** (field initializer, constructor, or static/type initializer) rather than lazily.
Its initializer runs **before the UI is shown**, so if the native driver/runtime is missing the
app crashes **before any window appears**. Look for: instance/`static` fields constructed at
declaration; such objects built in a form/page constructor or a global/singleton; type
initializers that touch native code.

Report it as a launch blocker whose fix is **lazy / guarded initialization** (construct on first
use, inside a try) — NOT merely "verify at launch" or "set the platform bitness". This is generic
across stacks (.NET type initializers, JVM static blocks, native dlopen at load, etc.).
```
New:
```markdown
### Launch-crash probe (always check; a static scan often misses this)

The probe lives in `references/lens-risk.md` (the risk scanner runs it in team mode). In
single-pass mode, read that file and run the probe yourself — it is required either way.
```

- [ ] **Step 3: Replace the Team section with the four-phase pipeline**

Old:
```markdown
## Team (when the project is large / parallelizable)

Workers gather **traceable facts** in parallel (scan, inventory, probe). A single **architect
synthesizer** cross-infers and integrates them into `_map.md`. The same actor must not both scan
and conclude (it amplifies local bias). For small projects, one synthesis pass is enough — a
separate agent is only worth it at scale.
```
New:
```markdown
## Team pipeline (scan → cross-compare → adversarial verify → report)

The dispatcher (main conversation) never scans files and never draws conclusions; it asks the
user, spawns subagents, and relays results. Separation of duties is absolute: **scanners don't
conclude, the synthesizer doesn't scan, verifiers don't write the report.**

| Role | Runs as | Model | Job |
|------|---------|-------|-----|
| Dispatcher | main conversation | (session) | ask the user, spawn, relay |
| Scanner ×5 | subagent | haiku | one lens each, full-tree scan, return claims |
| Synthesizer | subagent | inherit session model | cross-compare, then write the report |
| Verifier ×N | subagent | sonnet | try to refute assigned claims |

### Phase 0 — mode
Ask the user (one question): 1. ⭐ full multi-agent pipeline 2. single-pass scan (one
synthesis pass by a single agent; skip Phases 1–3; the launch-crash probe still runs).

### Phase 1 — parallel scan
Spawn all 5 haiku scanners in ONE message. Each prompt: "You are the <lens> scanner. Read
`<skill-dir>/references/lens-<lens>.md` and follow it exactly. Scan root: <project path>.
Your final reply must be ONLY the claims JSON." Lenses: `structure`, `dependencies`,
`dataflow`, `runtime`, `risk`. A scanner that dies or returns nothing → its lens goes to
"Not analyzed / unknowns"; never fill the gap by guessing.

### Phase 2 — cross-compare
Send all claims to the synthesizer subagent. It merges duplicates and tags every claim
`corroboration: agreed|conflicted|single` (multi-lens agreement / contradiction between
lenses, both sides kept with their evidence / seen by one lens only), and returns the merged
claims plus a conflict list and a HIGH-risk list. It does NOT write the report yet.

### Phase 3 — adversarial verification
Ask the user for scope, with real counts filled in ("N conflicted, M HIGH"):
1. ⭐ verify HIGH + conflicted only 2. verify all claims 3. HIGH + conflicted, plus a random
sample of 10 of the rest. Spawn one sonnet verifier per claim, in parallel. Each prompt:
"Read `<skill-dir>/references/adversarial-verify.md`. Your job is to REFUTE this claim:
<claim JSON>. Your final reply must be ONLY the verdict JSON."

### Phase 4 — report
SendMessage the SAME synthesizer (it keeps its Phase-2 context), attaching all verdicts.
Integration rules: `refuted` → drop from the map or downgrade to unknown, and note
"adversarial verification refuted N claims" in the credibility marks; `unverifiable` → keep,
tagged unknown/low-confidence. It writes `_map.md`, `_map-detail.md`, and `_claims.json`.
```

- [ ] **Step 4: Verify all referenced files exist and names are consistent**

Run: `grep -o 'references/[a-z-]*\.md' skills/architect/SKILL.md | sort -u`
Expected: `references/adversarial-verify.md` and `references/lens-risk.md` (the lens-<lens> pattern is templated; that's fine).

Run: `for f in structure dependencies dataflow runtime risk; do test -f "skills/architect/references/lens-$f.md" || echo "MISSING $f"; done`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add skills/architect/SKILL.md
git commit -m "architect: rewrite Team section as four-phase multi-agent pipeline"
```
