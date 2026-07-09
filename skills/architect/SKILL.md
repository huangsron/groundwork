---
name: architect
description: Use when you need to understand an unfamiliar or legacy codebase as a system before changing it — produce a systems-architect briefing so later tools share one ground truth. Use when "I don't know what this project is / how it fits together / what it needs to run." Produces the shared _map.md that /groundwork:plan consumes.
---

# Architect — understand the system first

## Overview

Read the project the way a **systems architect** would: not a file listing, but *what the system
is, how its parts fit, and what it needs to run*. Output a concise briefing that gives every later
tool (`/groundwork:plan`, `:verify`) one shared ground truth.

**Read-only. Change nothing.** Every claim is tagged: **fact** (cited evidence), **inference**
(reasoned, with confidence), or **unknown** (state it; don't guess).

## Output (handoff)

Write to `<project>/_groundwork/`:
- `_map.md` — the briefing (sections below). Lead with a 3–5 sentence plain-language summary.
- `_claims.json` — one list of claims, each `{ text, kind: fact|inference|unknown, evidence, confidence, lens, corroboration: agreed|conflicted|single, verdict: confirmed|refuted|unverifiable }` — `verdict` only on claims that went through adversarial verification. (One file — not separate claims/verdicts/audit files.)

## `_map.md` layout (what the user reads — decide "is this worth taking on, where are the traps")

Lead with the decision part; push detail down. Skeleton:
```
# System map

> One sentence: type, size, main stack.

## Risk traffic-lights        (the part a user reads in 30 seconds)
| Level | Risk | Basis |
|-------|------|-------|
| HIGH/MED/LOW | one line | direct-read / inference / unknown |   ← show credibility, simplified

## Component sketch           (ASCII or bullets; main parts + boundaries — not a file list)

## Not analyzed / unknowns    (what you could NOT see — be honest)

## Details → `_groundwork/_map-detail.md`   (link only — keep the full briefing OUT of the decision view)
```
Keep `_map.md` to the decision view above; write the full 6-section briefing to a separate
`_groundwork/_map-detail.md` and link it. Show a simplified credibility tag on each risk
(`direct-read` vs `inference` vs `unknown`) so the user knows what to trust vs verify. Link long
lists (full deps, schemas, file paths) into `_groundwork/`, don't inline them.

## Briefing sections (write these into `_map-detail.md`; minimum; trim to an appendix)

1. **System positioning & boundary** — purpose, users, core capabilities, in/out of scope, architecture style.
2. **Components & responsibilities** — main layers/subsystems, each one's job, dependency direction. *Not a per-file dump.*
3. **Key flows & data** — 2–5 main execution/data flows, who owns state, the important data stores.
4. **External integration & runtime topology** — DB, files, FTP, services, batch; process/host relations; how it deploys.
5. **Cross-cutting concerns** — config, auth/secrets, logging, error handling, transactions, observability.
6. **Risks & unknowns** — high coupling, single points of failure, tech debt, where evidence is thin → verification priorities.

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

## Red flags — STOP

- Producing a per-file list instead of a component/responsibility view
- Stating layering/topology as fact without evidence (it's an inference)
- Filling "unknown" with a guess to look complete
