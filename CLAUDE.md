# CLAUDE.md: pipeline agent orientation

Interpretable Context Methodology (ICM) workspace. This file is Layer 0, auto-loaded.

## What this is

A fork that converts a FaceScan-created UE 5.7 MetaHuman into a web-ready GLB via 5
deterministic stages: 51 ARKit blendshapes (Sequencer bake), baked scalp/hair AO,
and a three.js viewer with hair-card shading and a live tuning panel. The one
pipeline is `5.7/facescan-glb/`. It is hook-driven (scripts chain stages by exit
code), unlike the upstream `metahuman-to-glb`, which spawned a Haiku per stage.

## Export request

If the operator sends an asset path or says "export this character", read
`5.7/facescan-glb/RUN.md` and follow it. It is self-contained: bootstrap the
character, then run `tools/run_pipeline.ps1` in the background. The script drives;
you re-enter only when a stage fails. A normal run needs no other CONTEXT.md or
stage source.

## Layout

```
docs/                published viewer site (served by GitHub Pages)
_config/pipeline.yaml  shared UE + Blender paths
5.7/facescan-glb/
  RUN.md             operator entry point
  tools/             run_pipeline.ps1, bootstrap_character.py, serve_nocache.py
  stages/00..04/     each: CONTEXT.md (contract) + tools/ (launcher + scripts)
  characters/<id>/   manifest.json + stage outputs (gitignored)
```

## Rules

- Scripts (`.py`, `.ps1`) are deterministic and do the work. AI glues and verifies.
- Stage isolation: when diagnosing one stage, load only its CONTEXT.md, the files
  its Inputs name, and that character's folder. Nothing else.
- Each launcher updates only its own `stages.<NN>_<key>` manifest block. The runner
  owns cross-stage flow. AI never writes manifest state by hand.
- Fail loud with actionable errors. Never silently skip or force a stage green.
- Self-contained: code under `5.7/facescan-glb/` reaches outside only for
  `_config/pipeline.yaml`.

## Roles

- `run_pipeline.ps1`: chains stages 00 to 04 by exit code, skips done stages, stops
  loud on the first failure with an AI HANDOFF block. No timeouts.
- Stage launcher (`run_*.ps1`): runs one stage, self-updates its manifest block,
  exits with a meaningful code. No AI inside.
- AI: runs RUN.md, launches the runner in the background, and re-enters only on a
  stage failure to diagnose, fix the setup cause, and resume with `-From <key>`.
