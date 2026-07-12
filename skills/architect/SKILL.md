---
name: architect
description: Use when you need to understand an unfamiliar or legacy codebase as a system before changing it — produce a systems-architect briefing so later tools share one ground truth. Use when "I don't know what this project is / how it fits together / what it needs to run." Produces the shared _groundwork/ documentation set that readers and /groundwork:plan consume.
---

# Architect — understand the system first

## Overview

Read the project the way a **systems architect** would: not a file listing, but *what the system
is, how its parts fit, and what it needs to run*. Output a concise briefing that gives every later
tool (`/groundwork:plan`, `:verify`) one shared ground truth.

**Read-only. Change nothing.** Every claim is tagged: **fact** (cited evidence), **inference**
(reasoned, with confidence), or **unknown** (state it; don't guess).

## Output (handoff)

Audience: someone reading the project for the first time who must quickly understand purpose,
architecture, main flows, data model, external dependencies, launch conditions, risks, and
where to verify each claim.

**Output profile (chosen in Phase 0, recorded in `_groundwork/README.md`):**

| Profile | Files produced |
|---------|----------------|
| `full` ⭐ | the complete set below |
| `compact` | `README.md` + `PROJECT_OVERVIEW_REPORT.md` + `_claims.json` only — every completeness-gate element lives inside the single report |
| `full+exec` | the complete set below plus `EXEC_SUMMARY.md` (≤1 page: what the system is, traffic-light risk table, go/no-go recommendation, top 3 unknowns) |

**Language:** write all documents in the conversation's language unless the user chose otherwise
in Phase 0. Record both choices as the profile line in `_groundwork/README.md` (e.g.
`profile: full+exec · zh-TW`) — re-runs and later skills (/groundwork:plan, :verify reports)
honor it.

Write to `<project>/_groundwork/`:

| File | Contents |
|------|----------|
| `README.md` | table of contents, reading order, format conventions — nothing else; do not duplicate report content |
| `01_PROJECT_OVERVIEW.md` | project purpose, core code areas, external dependencies, cautions before modifying |
| `02_ARCHITECTURE.md` | C4-style architecture diagrams, component relations, main runtime flows, data model — all diagrams in Mermaid |
| `03_READINESS_CHECKLIST.md` | launch preconditions, health checks, how to read PASS/FAIL/WARN |
| `04_RISK_REGISTER.md` | HIGH/MEDIUM/LOW risks, impact, suggested handling; lead with a traffic-light table; each risk carries a credibility tag (`direct-read` / `inference` / `unknown`) |
| `05_EVIDENCE_INDEX.md` | every important conclusion → its source-code / SQL / config-file evidence; ends with a **Coverage** section: evidence touched X of Y inventoried files, declared-skipped list, remaining blind-spot list |
| `06_DEV_ENVIRONMENT.md` | local verification environment; docker/init/setup scripts and how to run them |
| `PROJECT_OVERVIEW_REPORT.md` | the complete single-file report (full reading version) |
| `_claims.json` | machine handoff: `{ generated_at, source_commit, profile, claims: [...] }` — header first (staleness detection: consumers compare `source_commit` to HEAD and warn on mismatch), then one list of claims, each `{ text, kind: fact\|inference\|unknown, evidence, files: [paths actually opened], confidence, lens, corroboration: agreed\|conflicted\|single, verdict: confirmed\|refuted\|unverifiable }` — `verdict` only on claims that went through adversarial verification. (One file — not separate claims/verdicts/audit files.) |

**Re-run behavior:** if `_groundwork/` already exists, overwrite the whole set in place (it is
generated output, and the header records vintage) — never leave a mixed-vintage set; if the user
wants the old one, they move it first.

Style: professional, clear, maintainable. Not a chat log or an analysis narrative; no draft
tone, no mojibake, no repeated sections. Absorb important existing content fully — don't
reduce it to a summary. Uncertain external systems or black-box DLLs are marked
**Unknown / 待確認** — never pretend to know.

**Completeness gate** — before finishing, check `_groundwork/` contains: an architecture
diagram, a flow diagram, a data model, launch checks, a risk register, an evidence index,
and the Coverage section (in `compact` profile, all of these inside
`PROJECT_OVERVIEW_REPORT.md`). Anything missing → go back and fill it in.

## Content mapping (where each briefing topic lands)

1. **System positioning & boundary** — purpose, users, core capabilities, in/out of scope, architecture style → `01`
2. **Components & responsibilities** — main layers/subsystems, each one's job, dependency direction; *not a per-file dump* → `02`
3. **Key flows & data** — 2–5 main execution/data flows, who owns state, the important data stores → `02`
4. **External integration & runtime topology** — DB, files, FTP, services, batch; process/host relations; how it deploys → `02` + `06`
5. **Cross-cutting concerns** — config, auth/secrets, logging, error handling, transactions, observability → `PROJECT_OVERVIEW_REPORT.md` (cautions echoed in `01`)
6. **Risks & unknowns** — high coupling, single points of failure, tech debt, thin evidence → `04`; launch conditions → `03`

`PROJECT_OVERVIEW_REPORT.md` integrates all six topics as one document. What you could NOT
see goes in a "Not analyzed / unknowns" section (in `01` and the report) — be honest. Every
important conclusion in any doc must be traceable in `05_EVIDENCE_INDEX.md` and exist as a
claim in `_claims.json`.

### Launch-crash probe (always check; a static scan often misses this)

The probe lives in `references/lens-risk.md` (the risk scanner runs it in team mode). In
single-pass mode, read that file and run the probe yourself — it is required either way.

## Universal (language/OS-agnostic)

Model the system in **architecture concepts** — components, responsibilities, dependencies, data
flow, processes, stores, external endpoints, deployment — **not** framework-specific folders.
Per-ecosystem scanners may supply evidence, but synthesize a *unified fact model* (entry points,
dependencies, config sources, data access), not `.csproj`- or `package.json`-specific rules.
Depth comes from **cross-validating multiple kinds of evidence** (source deps, config, deploy
files, DB access, process startup, docs) — not from more platform rules. Where layering/topology
is uncertain, mark it inference with confidence; don't force every system into UI/BLL/DAL.

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

Model overrides are preferences: when the harness has no model-override support or a model is
unavailable, spawn with the session's model and continue — never treat a missing model as a blocker.

### Phase 0 — mode & output profile
Ask the user (one question at a time):
- Q1 mode: 1. ⭐ full multi-agent pipeline 2. single-pass scan (one synthesis pass by a
  single agent; skip Phases 1–3; the launch-crash probe, the depth contract, and the coverage
  reconciliation still apply — the single agent builds the inventory, obeys the contract, and
  writes the Coverage section itself). In single-pass mode every claim gets
  corroboration: single and no verdict.
- Q2 output profile: 1. ⭐ full 8-doc set 2. compact single report 3. full set + executive
  summary. Language defaults to the conversation language — offer an override option only if
  the audience plausibly differs (e.g. handoff to another team).

If the user has waived questions ("don't ask", full autonomy) or doesn't answer: take every ⭐
default, note `(defaulted)` beside the profile line in `_groundwork/README.md`, and proceed.

### Phase 1 — parallel scan

**Baseline inventory first.** The dispatcher runs ONE read-only command —
`git ls-files --cached --others --exclude-standard` (tracked AND untracked files; plain
`git ls-files` silently hides untracked ones — loose DLLs, local configs). Non-git fallback:
a recursive file listing (`find <root> -type f` / `Get-ChildItem -Recurse -File`). Then declare
**rule-based exclusions** — conventional vendored/generated trees present in this project
(`node_modules/`, `bin/`, `obj/`, `packages/`, `vendor/`, `dist/`, `.git/`, build caches) —
subtract them from the inventory, and record them in the Coverage section as
"excluded by rule", NOT as blind spots. Keep the remaining list plus counts by class
(source / SQL / config / scripts / docs / other). This list is the ground truth for "was
everything scanned"; it is the only file-level act the dispatcher performs (it never opens
file contents).

Spawn all 5 haiku scanners in ONE message. Each prompt: "You are the <lens> scanner. Read
`<skill-dir>/references/lens-<lens>.md` and follow it exactly. Scan root: <project path>.
Excluded by rule (do not scan): <exclusion list>. Depth contract: (1) start by enumerating
the full tree (`git ls-files --cached --others --exclude-standard` or equivalent) —
never sample by guessing what exists; (2) OPEN AND READ — not just list — every file
relevant to your lens among: solution/project/manifest files, config files, SQL/schema
files, scripts, docs, and entry-point source; (3) every claim's `files` array lists the
files you actually OPENED for it — coverage accounting depends on this field, so never
leave it empty when the evidence came from a file; (4) your LAST claim must be a coverage
claim whose text starts with 'coverage:', naming the areas you inspected and the areas you
skipped; each skipped area also gets its own kind:'unknown' claim. Your final reply must be
ONLY the claims JSON." Lenses: `structure`, `dependencies`, `dataflow`, `runtime`, `risk`.
A scanner that dies or returns nothing → its lens goes to "Not analyzed / unknowns"; never
fill the gap by guessing.

### Phase 2 — cross-compare
Send all claims **plus the baseline inventory** to the synthesizer subagent.

**Coverage reconciliation (mechanical, first).** Union every path in every claim's `files`
array (fallback for a scanner that ignored the field: paths parsed out of its `evidence`
strings that exactly match inventory entries) with the areas declared skipped in coverage
claims and the rule-based exclusions; diff against the inventory. Files in neither set are
**silent blind spots**. The synthesizer returns the blind-spot list with its other outputs;
the dispatcher re-dispatches ONE targeted scan (suitable lens, blind-spot paths listed in
the prompt) to cover them. The targeted scan's claims are NOT merged by the dispatcher —
hold them and attach them to the Phase 4 message so the synthesizer dedups, corroboration-tags,
and folds them into `_claims.json` like any other claims. Still uncovered after that → they
go into "Not analyzed / unknowns". Never shrink the blind-spot list by guessing.

Then it merges duplicates and tags every claim
`corroboration: agreed|conflicted|single` (multi-lens agreement / contradiction between
lenses, both sides kept with their evidence / seen by one lens only), and returns the merged
claims plus a conflict list and a HIGH-risk list (HIGH = claims prefixed "HIGH launch-crash risk:" plus anything the synthesizer judges launch-blocking or data-loss-risking). It does NOT write the report yet. If the synthesizer dies or returns nothing, re-dispatch it once with the same input; if it fails again, stop and report partial results to the user (same rule applies in Phase 4).

### Phase 3 — adversarial verification
Ask the user for scope, with real counts filled in ("N conflicted, M HIGH — that's ~K
verifier agents"):
1. ⭐ verify HIGH + conflicted only 2. verify all claims 3. HIGH + conflicted, plus a random
sample of 10 of the rest. Spawn sonnet verifiers in parallel, **batched: 5–10 claims per
verifier, at most 10 verifiers in flight** (one-claim-per-agent does not scale to hundreds of
claims). Each prompt: "Read `<skill-dir>/references/adversarial-verify.md`. Your job is to
REFUTE each of these claims independently: <claims JSON array>. Your final reply must be ONLY
the JSON array of verdicts, one per claim, same order." A verifier that dies or returns
nothing → its claims keep no verdict and are treated as unverifiable (no `verdict` field in
`_claims.json`).

### Phase 4 — report
SendMessage the SAME synthesizer (it keeps its Phase-2 context), attaching all verdicts plus
any targeted-scan claims from Phase 2. If the harness cannot continue a finished subagent,
spawn a fresh synthesizer with the complete input instead: merged claims + baseline inventory
+ verdicts + targeted-scan claims.
Integration rules: `refuted` → drop from the report or downgrade to unknown, and note
"adversarial verification refuted N claims" in the credibility marks; `unverifiable` → keep,
tagged unknown/low-confidence. It writes the full `_groundwork/` documentation set (see
Output) plus `_claims.json`, then runs the completeness gate.

## Red flags — STOP

- Producing a per-file list instead of a component/responsibility view
- Stating layering/topology as fact without evidence (it's an inference)
- Filling "unknown" with a guess to look complete
