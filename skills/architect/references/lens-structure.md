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
  { "text": "one claim", "kind": "<one of: fact | inference | unknown>",
    "evidence": "file:line, or command + output",
    "confidence": 0.0, "lens": "structure" }
]
No prose around the JSON. An area you could not inspect is a claim with kind "unknown" —
never guess.
