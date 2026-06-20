# Dependency Probes (Phase 1)

Goal: **prove the dependency closure for the target scope has converged** — not the
impossible "found every dependency." Every dependency gets: status, source, compatibility,
disposition. READ-ONLY and parallelizable across a team.

## Probe layers

1. **Declared** — project/solution references, `ProjectReference`/`PackageReference`,
   `packages.config`, lockfiles (`packages.lock.json`, `project.assets.json`), build
   imports/targets (`Directory.Build.props/targets`, custom MSBuild tasks, SDK/workloads),
   `HintPath`s.
2. **Source-implicit** — `import`/`using`, reflection, dynamic load (`LoadLibrary`/`dlopen`/
   `DllImport`/`Assembly.Load`), external process calls, config/registry/env reads, DB
   providers, COM, report engines, plugin folders.
3. **Binary** — managed references + public key tokens; PE/ELF native imports
   (`dumpbin /dependents`); processor architecture; COM CLSIDs (32/64-bit registry view,
   `InprocServer32`, reg-free manifests, PIAs); transitive native DLLs (delay-load too).
4. **Binding** (.NET Framework) — `app.config`/`web.config` `bindingRedirect`, `codeBase`,
   `probing privatePath`, publisher policy; GAC by name AND CLR (2 vs 4) AND bitness.
5. **Toolchain** — compiler/SDK/targeting pack, build-tool version, resource/signing tools,
   and whether each is actually installed here. Modern: `global.json`, `.deps.json`,
   `.runtimeconfig.json`, RID assets, shared framework.
6. **Runtime** — loader/Fusion log, Process Monitor, clean startup, supported config/platform
   matrix, required services/DB/network. A managed assembly that P/Invokes a missing native
   DLL loads fine but throws on first use — probe this, don't assume.

## Missing-dependency search order (do ALL applicable BEFORE deciding to stub)

1. This repo + sibling directories + in-repo backups / old build outputs (`bin/`, `obj/`) /
   installers / archives
2. **git history / tags / submodules / LFS** (`git log --all --full-history -- <path>`)
3. Company artifact repository / package feeds
4. Package caches (NuGet global/`~/.nuget`), SDK, GAC, already-installed products
5. **User-approved machine-wide search roots** (ask before scanning the whole disk)
6. Original vendor / official source

For each candidate record: SHA-256 + signature/provenance; assembly name/version/public key
token; exported types / contract match against call sites; architecture; license.

> Common miss: reconstructing a missing dependency from scratch, THEN discovering the genuine
> binary already sitting in a sibling build-output / backup folder — search-order step 1 the
> whole time. Finishing the search before editing skips the rework.

## Stop conditions (gate `INVENTORY_COMPLETE`)

- Every edge classified: `resolved / optional / runtime-only / missing-approved`
- Every newly found binary has had its transitive deps probed; work queue empty
- Every missing edge has a search record (roots, patterns, permission, result)
- Every configuration/platform **listed in the Phase 0 contract** probed (don't let "every
  supported config" expand scope without bound)
- No unresolved *required* edge (if one remains → report **BLOCKED**, do not stub silently)

## Disposition priority

```
real source / original binary  >  official package/artifact  >  provenance-checked compatible version
  >  rebuild from existing source  >  adapter  >  stub (last resort, requires approval)
```

A reconstructed/stubbed dependency is load-bearing fiction: document exactly what it fakes and
which call paths are therefore unverified.
