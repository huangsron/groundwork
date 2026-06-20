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
- `_claims.json` — one list of claims, each `{ text, kind: fact|inference|unknown, evidence, confidence }`. (One file with a `kind` field — not separate claims/verdicts/audit files.)

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

## Universal (language/OS-agnostic)

Model the system in **architecture concepts** — components, responsibilities, dependencies, data
flow, processes, stores, external endpoints, deployment — **not** framework-specific folders.
Per-ecosystem scanners may supply evidence, but synthesize a *unified fact model* (entry points,
dependencies, config sources, data access), not `.csproj`- or `package.json`-specific rules.
Depth comes from **cross-validating multiple kinds of evidence** (source deps, config, deploy
files, DB access, process startup, docs) — not from more platform rules. Where layering/topology
is uncertain, mark it inference with confidence; don't force every system into UI/BLL/DAL.

## Team (when the project is large / parallelizable)

Workers gather **traceable facts** in parallel (scan, inventory, probe). A single **architect
synthesizer** cross-infers and integrates them into `_map.md`. The same actor must not both scan
and conclude (it amplifies local bias). For small projects, one synthesis pass is enough — a
separate agent is only worth it at scale.

## Red flags — STOP

- Producing a per-file list instead of a component/responsibility view
- Stating layering/topology as fact without evidence (it's an inference)
- Filling "unknown" with a guess to look complete
