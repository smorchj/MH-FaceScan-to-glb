# Stage 02 / 5.7 facescan-glb: Blender Assemble + ARKit + AO Bake

Headless Blender. Imports stage 01's per-mesh GLBs, bakes 51 ARKit shape
keys onto the face mesh (and propagates them to eyebrow / mustache /
beard cards), wires hair-card materials, bakes Cycles ambient occlusion
into face vertex colors, and saves a `.blend` for stage 03.

## Scope (hard rule)

Run this stage's launcher and verify outputs. Nothing else. Do not edit
pipeline code (`stages/*/tools/*`, `tools/*.ps1`, `_config/`, `RUN.md`,
`CLAUDE.md`), other stages' contracts, or other characters' artifacts. If
a script errors, surface the real error. Do not work around it (no
try/except swallowing, no skipping assets, no lowering thresholds). Touch
only the `stages.02_blender_assemble` manifest block.

## Inputs

| Source | File | Use |
|---|---|---|
| Workspace config | `_config/pipeline.yaml` | `blender_exe` path |
| Char manifest | `characters/<id>/manifest.json` | `character_id` only (do not read other stages' status) |
| Stage 01 manifest | `characters/<id>/01-glb/mh_manifest.json` | `assets[]`, sidecar textures, groom params |
| Stage 01 GLBs | `characters/<id>/01-glb/*.glb` | per-mesh geometry + textures |
| Stage 01 LSE FBX | `characters/<id>/01-glb/LS_arkit_full.fbx` | ARKit shape-key source (must be > 5 MB) |
| Stage 01 pose list | `characters/<id>/01-glb/arkit_pose_names.json` | frame N to ARKit pose name |
| Stage 01 textures | `characters/<id>/01-glb/textures/*.png` | hair / brow / lash atlases |

Verify these files exist on disk before running (files are ground truth,
not manifest status). If any is missing, abort with an actionable message
("stage 01 output missing: <path>, run stage 01 first").

## Process

1. Read `blender_exe` from `_config/pipeline.yaml`.
2. Run launcher: `tools/run_assemble.ps1 -Char <id>`. It invokes
   `<blender_exe> --background --python tools/import_glb.py -- --char <id> --workspace <root>`
   and blocks until Blender exits. Exit code must be 0.
3. The script, in order:
   - Imports every GLB in `mh_manifest.assets[]`; hides non-LOD0 / collision meshes.
   - Bakes 51 ARKit shape keys onto the face mesh: replays the LSE FBX
     bone animation per frame, captures the deformed mesh, transfers to
     the GLB face by kdtree position match (same UE SKM, 0.00mm).
   - Propagates those shape keys onto groom card meshes (eyebrows,
     mustache, beard, stubble) via k=4 inverse-distance weighting.
     Eyelashes ride along as a face material slot.
   - Reconstructs hair-card / brow / lash materials from sidecar atlases.
   - Bakes Cycles AO into the face mesh COLOR_0 (the viewer multiplies it
     into skin): channel R = broad hemisphere AO (hair cards as
     occluders), channel G = a tight hair-root / scalp contact layer
     (proximity to hair-card verts). B unused.
   - Parents hair-card meshes to the head bone.
   - Emits `mh_materials.json` for the stage 04 viewer.
4. Verify outputs, then set `stages.02_blender_assemble`: `status="done"`,
   `started_at`, `completed_at`, `errors=[]`. On failure set
   `status="failed"` and append an actionable message to `errors[]`,
   leaving artifacts in place. Only ever touch this stage's block.

## Outputs

| Artifact | Location |
|---|---|
| Assembled blend | `characters/<id>/02-blend/<id>.blend` |
| Material spec | `characters/<id>/02-blend/mh_materials.json` |
| Scene manifest | `characters/<id>/02-blend/blend_manifest.json` |
| Updated char manifest | `characters/<id>/manifest.json` (this stage's block only) |

## Idempotency / failure modes

Unconditional overwrite of `02-blend/`, re-running is safe. Common
failures: missing `mh_manifest.json` or LSE FBX (stage 01 did not run or
did not bake), LSE import yields no MESH (corrupt / empty bake), kdtree
match max > 5mm (LSE and GLB faces from different SKM builds, re-run
stage 01).
