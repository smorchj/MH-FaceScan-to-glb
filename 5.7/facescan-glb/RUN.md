# RUN: facescan-glb operator entry

The operator sends a UE MetaHumanCharacter asset path (or a character id) and asks
to export it. Produce a finished web-ready GLB.

## Driver model

A script drives, AI is the fallback. `tools/run_pipeline.ps1` runs stages 00 to 04
by exit code; each launcher is event-driven and self-updates its own manifest
block. So:

- No timeouts. Completion is a process-exit hook. Launch the runner in the
  background and let the harness notify you.
- No AI between stages on success. The script chains them. Do not spawn a
  sub-agent per stage.
- AI re-enters only on failure. The runner stops loud with an AI HANDOFF block
  naming the failed stage. That is the only place you step in.

## Setup (silent, no questions)

If `_config/pipeline.yaml` is missing or has any `<...>` placeholder, fill it
automatically:

1. `cp _config/pipeline.example.yaml _config/pipeline.yaml` if missing.
2. Auto-detect and write paths:
   - UE editor: highest `C:/Program Files/Epic Games/UE_*/.../UnrealEditor-Cmd.exe` matching `ue_version`.
   - UE project: walk up from the asset path to a `.uproject`, else the newest under `~/Documents/Unreal Projects/`.
   - Blender: highest `C:/Program Files/Blender Foundation/Blender */blender.exe`.

Only escalate if detection genuinely fails.

## Steps

1. Bootstrap the character folder:
   ```
   python 5.7/facescan-glb/tools/bootstrap_character.py --asset <asset_path>
   ```
   (`--id <id>` if given an id). Read the `[bootstrap] char_id: <X>` line for `<id>`.
   On exit 1 ("already exists"), ask whether to re-export, then re-run with `--force`.

2. Run the pipeline in the background (no timeout):
   ```powershell
   5.7/facescan-glb/tools/run_pipeline.ps1 -Char <id>
   ```
   It skips done stages and stops on the first failure. Wait for the process to exit.

3. On exit:
   - Exit 0: go to the report.
   - Non-zero: the runner printed an AI HANDOFF block. Read only the failed stage's
     `stages/<NN>-*/CONTEXT.md` and that stage's `manifest.json` errors. Diagnose the
     real cause (rig not applied, texture override unwired, missing groom, UE left
     open, wrong path). Fix the setup, then resume:
     ```powershell
     5.7/facescan-glb/tools/run_pipeline.ps1 -Char <id> -From <stage_key>
     ```
     Repeat until exit 0, or escalate with the concrete error. Never lower a
     threshold, skip an asset, or edit pipeline code to force a green.

4. Report: final GLB at `docs/characters/<id>/<id>.glb`, with size
   and tri count from `03-glb/glb_manifest.json`, and the local view URL
   (`python tools/serve_nocache.py 8000`, then `/characters/<id>/?tune=1`).

## Stages

| NN | manifest key | timing |
|---|---|---|
| 00 | `00_unreal_assemble` | ~1-2 min |
| 01 | `01_unreal_glb_export` | ~1-2 min |
| 02 | `02_blender_assemble` | ~60-90 s |
| 03 | `03_glb_export` | ~30-60 s |
| 04 | `04_webview_build` | ~5 s |

## Don't

- Spawn a sub-agent per stage on success.
- Wrap a launcher in a tool-call timeout.
- Read other characters' manifests or other stages' contracts while diagnosing.
- Hand-edit manifest state or pipeline code to force a stage green.
