# Stage 03: Blender → GLB

Headless Blender. Opens stage 02's `.blend` and exports one web-ready,
Draco-compressed GLB (LOD0 meshes, armatures, embedded textures, baked AO).

## Scope (hard rule)

Run this stage's launcher and verify its outputs. Nothing else. Do not edit
pipeline code (`stages/*/tools/*`, `tools/*.ps1`, `_config/`, `RUN.md`,
`CLAUDE.md`), other stages' contracts/manifest blocks, or other characters'
artifacts. If a script throws, surface the real error to the operator. Do not
work around it (no try/except hiding, no skipping assets, no lowered limits).

## Inputs

| Source | File | Section |
|---|---|---|
| Config | `_config/pipeline.yaml` | `blender_exe`, `glb_constraints.{max_texture_px, draco_compression}` |
| Stage 02 blend | `characters/<id>/02-blend/<id>.blend` | full scene |
| Stage 02 manifest | `characters/<id>/02-blend/blend_manifest.json` | LOD0 / hidden mesh info |

## Preconditions

Files on disk are ground truth (do not read prior-stage `status`). Abort with
an actionable message if `<id>.blend` is missing ("run stage 02 first").

## Process

1. `tools/run_export.ps1 -Char <id>` reads `blender_exe`, then runs
   `blender --background <blend> --python tools/export_glb.py -- --char <id> --workspace <abs>`.
2. `export_glb.py` operates on the in-memory scene (source `.blend` untouched):
   - Deletes hidden (non-LOD0) meshes.
   - Flips the G channel on DirectX-convention normal maps (outfit normals);
     MH-baked skin/eye/body normals are already +Y up and are skipped.
   - Downsamples any image whose largest dimension exceeds `max_texture_px`
     (cap 1024; teeth forced to 256), then repacks it.
   - Pre-bakes hair-card / eyebrow Base Color Multiply chains to a single PNG
     and rewires BC (the glTF exporter would otherwise drop the ramp).
   - Runs `bpy.ops.export_scene.gltf` (`GLB`, `export_apply=True`, `use_visible=True`,
     Draco if enabled, skins + morphs).
     - **`export_vertex_color='ACTIVE'` + `export_all_vertex_colors=False`** is
       load-bearing: it puts the active "Col" attribute (stage-02 baked AO) into
       COLOR_0 where three.js reads it. The default MATERIAL mode emits a white
       COLOR_0 and demotes the AO to the ignored COLOR_1.
   - Copies the viewer sidecar (`mh_materials.json` + alpha textures) into `03-glb/`.
   - Patches the GLB so morph `targetNames` sit per-primitive (three.js reads
     them there, not per-mesh).
   - Writes `<id>.glb` + `glb_manifest.json`.
3. Launcher blocks until Blender exits, then writes the manifest block.

## Outputs

| Artifact | Location |
|---|---|
| Web-ready GLB | `characters/<id>/03-glb/<id>.glb` |
| Export manifest | `characters/<id>/03-glb/glb_manifest.json` (`file_size_bytes`, `tri_count`, `mesh_count`, `material_count`, `image_count`, `max_texture_px_used`, `draco`) |
| Char manifest | `characters/<id>/manifest.json` → `stages.03_glb_export` only |

## Completion signal

Launcher exits 0 and `stages.03_glb_export.status = "done"` (with `started_at`,
`completed_at`, `errors: []`). On failure: exit nonzero, `status = "failed"`,
actionable message in `errors[]`, artifacts left in place. Touch only this
stage's block. Re-running is safe (outputs are overwritten).
