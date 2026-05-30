# CONTEXT.md — Pipeline Task Routing (Layer 1)

## Goal

Turn a UE MetaHuman into a web-ready GLB. Each UE version × pipeline type is a
fully-isolated self-contained pipeline.

## Pipeline root

This repo ships **one** pipeline: `5.7/facescan-glb/` — UE 5.7 FaceScan→GLB,
hook-driven (stages chained by exit code), ARKit blendshapes via Sequencer bake,
baked scalp/hair AO, three.js viewer with live tuning. (The other UE pipelines —
5.6/cinematic, 5.7/cinematic — live in the upstream `metahuman-to-glb` repo and
are not part of this fork.)

It is fully self-contained:

```
5.7/facescan-glb/
  RUN.md                   # operator entry point
  CONTEXT.md               # pipeline-scoped routing
  tools/                   # run_pipeline.ps1, bootstrap_character.py, serve_nocache.py
  stages/
    00-unreal-assemble/    { CONTEXT.md, tools/ }
    01-unreal-glb-export/  { CONTEXT.md, tools/ }
    02-blender-assemble/   { CONTEXT.md, tools/ }
    03-export-to-glb/      { CONTEXT.md, tools/ }
    04-webview-build/      { CONTEXT.md, tools/, templates/ }
  characters/
    _template/
    <id>/                  { manifest.json, source/, 01-glb/, 02-blend/, 03-glb/ }
  docs/                    # published site (stage 04 output)
```

## Workspace-wide (NOT per-pipeline)

| Folder | Purpose |
|---|---|
| `_config/pipeline.yaml` | Global tool paths (blender_exe, per-version UE editor binaries) |
| `skills/` | Reference material (MH asset layout, FBX rules) that applies across pipelines |
| `docs/` | GitHub Pages output — stage 04 of each pipeline publishes its characters into `docs/characters/<id>/` |

## Dispatch (hook-driven)

The active `5.7/facescan-glb/` pipeline is **script-driven**, not AI-dispatched.
`tools/run_pipeline.ps1` chains stages 00→04 by exit code; each stage launcher
self-updates its own manifest block. AI is **not** in the loop on the happy path
and never spawns a sub-agent per stage. AI only re-enters when a stage fails:
read that one stage's `CONTEXT.md` + manifest errors, fix the non-deterministic
cause, then resume with `-From <stage_key>`.

## Operator intents

| Operator says | Do |
|---|---|
| "export `<asset_path>`" or "export `<id>`" | Read `5.7/facescan-glb/RUN.md` and follow it: bootstrap the character, then launch `tools/run_pipeline.ps1` in the background. The script runs all 5 stages. |
| "redo stage `<N>` for `<id>`" | `tools/run_pipeline.ps1 -Char <id> -From <stage_key> -Force`. |
| "status of `<id>`" | Read `5.7/facescan-glb/characters/<id>/manifest.json`. |
| "add character `<id>`" (manual) | `python 5.7/facescan-glb/tools/bootstrap_character.py --id <id>`. |
| "serve / test local" | `python 5.7/facescan-glb/tools/serve_nocache.py 8000` (no-store dev server over `docs/`), then open `http://localhost:8000/characters/<id>/?tune=1`. |

## Active config

`_config/pipeline.yaml`:
- `active_pipeline` — default `<version>/<pipeline>` for single-char runs
- `active_character` — default character id
- `blender_exe` — path to blender.exe
- `ue_by_version` — per-version UE project + editor paths (`5.6.1`, `5.7`)
