# Stage 01 / 5.7 facescan-glb: UE export + ARKit Sequencer bake

## Purpose

Export per-mesh GLBs from the assembled MetaHuman in UE 5.7, and bake the 52
ARKit poses by driving a transient Level Sequence at 24fps (RigLogic runs
natively) out to an LSE FBX for stage 02 to transfer.

## Scope (hard rule)

Run the launcher and verify its outputs. Do not modify pipeline code
(`*.py`, `*.ps1`, `_config/`, `RUN.md`, `CLAUDE.md`), other stages, or other
characters. On error, surface the real message. Never work around it.

## Preconditions

- Stage 00 done: `/Game/<output_name>/` holds the assembled MetaHuman (face +
  body SkeletalMesh, hair-card StaticMeshes), face carries the 858 raw RigLogic
  morphs. Project state on disk is ground truth, not the manifest status field.
- UE editor closed (commandlet locks the project).
- If `/Game/<output_name>/` missing, abort: "UE assets not found, run stage 00".

## Inputs

| Source | Location | Why |
|---|---|---|
| Config | `_config/pipeline.yaml` (`ue_by_version.5.7`, `glb_constraints`) | UE project + editor exe, max texture size |
| Char manifest | `characters/<id>/manifest.json` | `character_id`, `output_name` (fallback `<id>`). Read only. |
| ARKit AnimSequence | `/MetaHumanCharacter/Face/ARKit/AS_MetaHuman_ARKit_Mapping` | Curve-driven mapping, 24fps, 1 frame per pose |
| ARKit PoseAsset | `/MetaHumanCharacter/Face/ARKit/PA_MetaHuman_ARKit_Mapping` | Defines pose order stage 02 expects |

## Process

1. Read config + char manifest (id / output_name only).
2. Verify `/Game/<output_name>/` exists.
3. Run `tools/run_export.ps1 -Char <id>`. It invokes UnrealEditor-Cmd with
   `-run=pythonscript export_glb.py` plus `-AllowCommandletRendering`
   (mandatory: both the GLTF `USE_MESH_DATA` material bake and the Sequencer
   FBX export need a renderer, else empty bakes / `MeshObject` assertion).
4. Launcher blocks until UE exits, then writes the manifest block itself and
   exits with UE's code. The agent only verifies outputs.

The 24fps display rate is mandatory: at the default 30fps the bake would
interpolate between adjacent poses and stage 02 would capture blends.

## Outputs (`characters/<id>/01-glb/`)

| Artifact | Notes |
|---|---|
| `*.glb` | One per SkeletalMesh / hair-card StaticMesh. Materials baked via `USE_MESH_DATA`; morphs disabled (replaced by LSE FBX). |
| `textures/*.png` | Hair-card / eyebrow / eyelash atlases from `/Game/<id>/Grooms/Textures/`. Stage 02 rewires these. |
| `LS_arkit_full.fbx` | The ARKit-shape source: mesh + skeleton + per-frame bone keys for all poses, RigLogic + correctives applied. |
| `arkit_pose_names.json` | Ordered pose names. Frame N = pose N. |
| `arkit_pose_curves.json` | Per-pose `{curve: weight}`. Reference only. |
| `mh_manifest.json` | Machine-readable index; `arkit_sources` block points stage 02 at each file. |

Debug-only extras (not consumed by stage 02): `SKM_<id>_FaceMesh.fbx`,
`AS_MetaHuman_ARKit_Mapping.fbx`, `arkit_pose_bones.json`.

## Completion signal

UE exit code 0, all required outputs present (every `*.glb` plus
`LS_arkit_full.fbx`, `arkit_pose_names.json`, `arkit_pose_curves.json`,
`mh_manifest.json`). The launcher writes `stages.01_unreal_glb_export` in
`characters/<id>/manifest.json`: `status` = "done" (or "failed" with an
actionable `errors[]`), plus `started_at` / `completed_at`. Touch only this block.

## Failure modes

- `/Game/<output_name>/` missing: stage 00 not done.
- UE editor running: project locked, ask user to close it.
- No `LS_arkit_full.fbx` / `MeshObject` assertion: `-AllowCommandletRendering`
  was missing (launcher always passes it; only fails on direct UE invocation).
- LSE FBX under 5 MB: empty bake, Sequencer bind missed the actor.

## Idempotency

Re-running overwrites `01-glb/`. The transient `/Game/Temp/LS_arkit_export`
Level Sequence is left in the project (harmless, overwrites next run).
