# CONTEXT: task routing (Layer 1)

One pipeline: `5.7/facescan-glb/` (UE 5.7 FaceScan to GLB, hook-driven). See
CLAUDE.md for the model and layout, RUN.md for the export flow.

## Operator intents

| Operator says | Do |
|---|---|
| "export `<asset>`" or "export `<id>`" | Follow `5.7/facescan-glb/RUN.md`: bootstrap, then run `tools/run_pipeline.ps1` in the background. |
| "redo stage `<N>` for `<id>`" | `tools/run_pipeline.ps1 -Char <id> -From <stage_key> -Force`. |
| "status of `<id>`" | Read `5.7/facescan-glb/characters/<id>/manifest.json`. |
| "add character `<id>`" | `python 5.7/facescan-glb/tools/bootstrap_character.py --id <id>`. |
| "serve / test local" | `python 5.7/facescan-glb/tools/serve_nocache.py 8000`, then open `http://localhost:8000/characters/<id>/?tune=1`. |

## Stage keys

`00_unreal_assemble`, `01_unreal_glb_export`, `02_blender_assemble`,
`03_glb_export`, `04_webview_build`. Use these with `-From`.

## Config

`_config/pipeline.yaml` (gitignored) holds the shared tool paths: `blender_exe`
and the per-version UE editor and project paths. Copy from
`_config/pipeline.example.yaml` and fill in.
