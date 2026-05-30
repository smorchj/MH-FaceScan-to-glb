# Stage 00 - UE Assemble (5.7)

Build an unrigged `MetaHumanCharacter` asset into saved in-engine
SkeletalMesh + texture assets under `/Game/<Name>/`, then FBX-export them
so stage 01 has source meshes and textures.

## Scope (hard rule)

Run this stage's launcher and verify its outputs. Do not edit pipeline
code (`*.py`, `*.ps1`, `_config/`, `RUN.md`, `CLAUDE.md`), other stages,
or other characters. If a script errors, surface the real error. Do not
work around it (no silent try/except, skipped assets, or lowered gates).

## Precondition

- UE 5.7 project with the MetaHumanCharacter plugin enabled.
- The `MetaHumanCharacter` asset exists at the manifest's `mh_folder`.
- UE editor CLOSED (launcher boots a GUI editor `-unattended` and drives
  it via `-ExecCmds`; GUI is required because the build needs Slate ticks).

## Inputs

| Source | File | Why |
|---|---|---|
| Workspace config | `_config/pipeline.yaml` (`ue_by_version[5.7]`) | `editor_cmd`, `project_path` |
| Character manifest | `characters/<id>/manifest.json` | `mh_folder`, optional `ue_project_path` |

## Process

1. Pre-build, standalone Python extracts the `.uasset` Content Browser
   thumbnail to `source/thumbnail.jpg` (operator review gate, non-fatal).
2. Launcher runs `build_metahuman.py` in the editor via a tick-driven
   state machine (STARTING > RIGGING > REQUESTED > WAITING > BUILDING >
   SAVING > EXPORTING > DONE/FAILED), writing progress to a status JSON.
3. If the face mesh has no morph targets, `request_auto_rigging`
   (JOINTS_AND_BLEND_SHAPES, Epic cloud) so the result is ARKit-drivable.
4. `request_texture_sources` (Epic cloud hi-res body + face textures).
5. Two-phase gate before building: wait for `can_build_meta_human` AND
   `has_high_resolution_textures`, then a post-hi-res streaming grace so
   the bake uses real hi-res content (not upsampled 256 previews).
   Escape hatches: 120s hi-res, 90s streaming.
6. `build_meta_human` (pipeline `cinematic`), save `/Game/<Name>/`, then
   FBX-export each new SkeletalMesh plus referenced textures (TGA) into
   the output dir with an `mh_manifest.json`.

## Outputs

| Artifact | Location | Notes |
|---|---|---|
| SkeletalMesh + textures | `<UE project>/Content/<Name>/` | Saved in-engine |
| FBX + TGA + mh_manifest.json | output dir (`C:/tmp/mh/out`) | Stage 01 input |
| Thumbnail | `characters/<id>/source/thumbnail.jpg` | Pre-build review |
| Reference screenshot | `characters/<id>/source/reference.png` | Best-effort, if a HighResShot landed |
| Status JSON | `C:/tmp/mh/status.json` | Transient progress |

## Completion

Launcher derives its exit code from the final status phase (not UE's
process code, which is unreliable after a force-kill) and writes the
`stages.00_unreal_assemble` block in `characters/<id>/manifest.json`:
`DONE` = 0, `FAILED` = 2, non-terminal = 3, unparseable = 4, no status
written = 5.

## Launcher

```powershell
./tools/run_assemble.ps1 -Char <id>
```
