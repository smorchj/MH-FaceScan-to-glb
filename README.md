# MH-FaceScan → GLB

Turn a FaceScan-created UE 5.7 MetaHuman into a web-ready GLB: 51 ARKit
blendshapes, baked scalp/hair AO, hair-card shading, viewed in a three.js
viewer with a live tuning panel.

Hook-driven fork of [metahuman-to-glb](https://github.com/smorchj/metahuman-to-glb),
trimmed to just the FaceScan path.

## Pipeline

Five stages chained by exit code (`tools/run_pipeline.ps1`). No AI in the loop on
the happy path; it only re-enters if a stage fails.

```
00  UE assemble          build/load the MetaHuman             (~1-2 min)
01  UE GLB + ARKit bake  Sequencer LSE FBX + per-mesh GLB     (~1-2 min)
02  Blender assemble     ARKit shape keys, grooms, baked AO   (~60-90 s)
03  GLB export           Draco GLB, AO in COLOR_0             (~30-60 s)
04  viewer build         three.js site into docs/            (~5 s)
```

Output: `docs/characters/<id>/<id>.glb` (~40 MB).

## Setup

```
cp _config/pipeline.example.yaml _config/pipeline.yaml   # fill in local paths
```

Needs: `.uproject`, `UnrealEditor-Cmd.exe` (UE 5.7), `blender.exe` (5.x).
`_config/pipeline.yaml` is gitignored.

## Run

```powershell
5.7/facescan-glb/tools/run_pipeline.ps1 -Char <id>
5.7/facescan-glb/tools/run_pipeline.ps1 -Char <id> -From 02_blender_assemble -Force
```

In Claude Code: `export /Game/<Name>/<asset>` (follows `5.7/facescan-glb/RUN.md`).

## View locally

```
python 5.7/facescan-glb/tools/serve_nocache.py 8000
```

Open `http://localhost:8000/characters/<id>/?tune=1` for the tuning panel
(lighting, skin AO, hair AO, hair-card shading).

## Layout

```
docs/               published viewer site (GitHub Pages)
5.7/facescan-glb/
  RUN.md            operator entry point
  tools/            run_pipeline.ps1, bootstrap_character.py, serve_nocache.py
  stages/00..04/    each: CONTEXT.md (contract) + tools/
  characters/<id>/  manifest.json + stage outputs (gitignored)
```

## How it works

- **Hook-driven.** `run_pipeline.ps1` chains stages by exit code; each launcher
  updates only its own manifest block.
- **ARKit.** UE Sequencer bakes the ARKit poses to an FBX (RigLogic native);
  Blender transfers them to the GLB face by KDTree position match.
- **AO.** Cycles bakes scalp/hair AO into vertex colors (R = broad, G = hair-root
  contact), exported as COLOR_0 and shaped live in the viewer.

## License

MIT. See [LICENSE](LICENSE).
