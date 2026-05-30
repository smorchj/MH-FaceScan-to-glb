# CLAUDE.md — Pipeline Agent Orientation

You are an agent in an **Interpretable Context Methodology (ICM)** workspace
(Van Clief / Model Workspace Protocol). This file is Layer 0: system orientation.

## What this workspace does

Converts a UE MetaHuman character (including FaceScan-created MetaHumans) into a
web-ready GLB via 5 deterministic stages. The pipeline is **`5.7/facescan-glb/`**
(UE 5.7, native-GLB output, ARKit-52 blendshapes baked via UE Sequencer, baked
scalp/hair AO + hair-card shading in the web viewer).

This repo is a fork focused on the FaceScan-to-GLB path; it is **hook-driven**
(scripts chain the stages by exit code), unlike the upstream `metahuman-to-glb`
native-glb pipeline which used an Opus-orchestrator-spawning-Haiku-per-stage
model. The other UE pipelines (5.6/cinematic, 5.7/cinematic) are not in this fork.

## When the operator asks you to export a character

If the operator's request is anything like *"export this character"*, *"please run
the pipeline on `<asset>`"*, or just sends a UE asset path, **read
`5.7/facescan-glb/RUN.md` and follow it exactly**. RUN.md is fully self-contained:
it tells you to bootstrap the character folder and then run the deterministic
master runner (`tools/run_pipeline.ps1`) in the background. The script drives the
stage chain by exit code; you only re-enter when a stage fails.

You do not need to read any other CONTEXT.md, the per-stage Python sources, or
the operator's UE project. RUN.md handles all of that.

## How the workspace is organized

```
<worktree>/
  CONTEXT.md                           ← root task routing
  CLAUDE.md                            ← this file (auto-loaded)
  _config/pipeline.yaml                ← shared config (UE + Blender paths)
  5.7/facescan-glb/                      ← active pipeline
    RUN.md                             ← operator entry point ★
    tools/bootstrap_character.py       ← character-folder scaffolder
    stages/00-unreal-assemble/
      CONTEXT.md                       ← stage contract (AI reads only this, and only on a stage failure)
      tools/run_assemble.ps1           ← stage launcher
    stages/01-unreal-glb-export/
    stages/02-blender-assemble/
    stages/03-export-to-glb/
    stages/04-webview-build/
    characters/_template/              ← copied per character
    characters/<id>/                   ← per-character working artifacts
      manifest.json                    ← per-stage status
      source/, 01-glb/, 02-blend/, 03-glb/   ← stage outputs (gitignored)
```

## Stage isolation (the hard rule)

When running a single stage, **only load** that stage's `CONTEXT.md` + the files
it names in its Inputs table + the current character's `characters/<id>/`.
Do not load other stages' contracts, other characters' manifests, or pipeline
code outside `stages/<NN>/tools/`.

Each stage **launcher** (`run_*.ps1`) updates **only** its own
`stages.<NN>_<key>` block in the character manifest — never another stage's
status. The master runner (`run_pipeline.ps1`) owns cross-stage flow. AI never
writes manifest state; it only reads a failed stage's CONTEXT.md + errors when
the chain stops, fixes the non-deterministic cause, and resumes.

## Roles

| Actor | Job |
|---|---|
| `tools/run_pipeline.ps1` (the driver) | Chain stages 00→04 by exit code. Block on each launcher's process-exit hook (no timeouts). Skip done stages. Stop loud on first failure with an AI HANDOFF block. |
| Stage launcher (`stages/<NN>/tools/run_*.ps1`) | Run one stage event-driven, self-update its own manifest block, exit with a meaningful code. No AI inside. |
| AI orchestrator (fallback supervisor) | Read RUN.md, run bootstrap, launch the master runner in the background. Re-enter ONLY when a stage fails: read that one stage's CONTEXT.md + manifest errors, fix the non-deterministic cause, resume with `-From <key>`. |
| Opus (you, when invoked) | Edit contracts, add stages, add pipelines, design the runner, diagnose ambiguous MetaHuman-setup failures the chain can't. |

## Rules

- Scripts (`*.py`, `*.ps1`) are deterministic. LLMs glue and verify; scripts transform.
- Every stage writes a machine-readable manifest. Stages don't read each other.
- Fail loud with actionable messages. Never silently skip.
- The pipeline is self-contained: code under `5.7/facescan-glb/` does not reach
  outside it except for the shared `_config/pipeline.yaml` (UE + Blender paths).
