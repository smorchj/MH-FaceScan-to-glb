# RUN.md — 5.7 facescan-glb pipeline orchestrator (entry point)

The operator sent a UE MetaHumanCharacter asset path (or a character id)
and asked you to export it. Turn that into a finished web-ready GLB.

## Driver model (read this first)

**A script is the driver. AI is the fallback supervisor.**

The whole stage chain runs inside one deterministic script,
`tools/run_pipeline.ps1`, which runs stages 00 -> 01 -> 02 -> 03 -> 04 by
exit code. Each stage launcher is already event-driven (it blocks on its
child process exiting plus a status sentinel, then self-updates its own
manifest block). So:

- **No timeouts.** Completion is a hook (process exit), never a guessed
  duration. Do not wrap launchers in tool-call timeouts. Launch the
  master runner in the BACKGROUND and let the harness notify you when it
  exits.
- **No AI between stages on the happy path.** The script hooks into the
  next script itself. You do NOT spawn a sub-agent per stage.
- **AI re-enters only on failure.** MetaHuman assets vary (rig state,
  texture overrides, outfit/groom setups) in ways a script cannot fully
  cover. When a stage fails, the runner stops loud and prints an AI
  HANDOFF block naming the failed stage. THAT is when you dispatch a
  scoped sub-agent to diagnose, fix, and resume.

## Setup (silent — no operator interaction)

The operator only ever sends a file/asset path and says "export". Handle
everything else automatically. Do **not** ask the operator any questions
during setup.

### A. Resolve absolute paths

- `<workspace>` = the worktree root (`pwd`)
- `<pipeline_root>` = `<workspace>/5.7/facescan-glb`

### B. Ensure `_config/pipeline.yaml` is ready (auto-detect, no asking)

If `_config/pipeline.yaml` is missing OR contains any `<...>`
placeholder, populate it silently:

1. `cp _config/pipeline.example.yaml _config/pipeline.yaml` (if missing).
2. **Auto-detect** the paths and write them in:
   - **UE editor cmd**: glob `C:/Program Files/Epic Games/UE_*/Engine/Binaries/Win64/UnrealEditor-Cmd.exe`. Pick the highest version matching `ue_version` (e.g. `UE_5.7`). If only one UE is installed, use it.
   - **UE project**: walk up from the operator's asset path until you hit a `.uproject`. If the operator gave only a `/Game/...` in-engine path, glob `~/Documents/Unreal Projects/**/*.uproject` and pick the most recently modified.
   - **Blender exe**: glob `C:/Program Files/Blender Foundation/Blender */blender.exe`, pick the highest version.
3. Edit the placeholders in `_config/pipeline.yaml` with the detected
   paths. Don't ask the operator to confirm; if a sane default exists,
   use it.

Only escalate if auto-detection genuinely fails (no UE install, no
Blender install, multiple equally-valid `.uproject` candidates with no
asset-path hint).

## Operator inputs (one of)

- UE asset path: `/Game/Ada/MHC_Ada` (most common)
- UE folder path: `/Game/Ada`
- Just an id: `ada` (assumes `/Game/Ada` exists in the project)

## Step 1 — Bootstrap the character folder

```
python 5.7/facescan-glb/tools/bootstrap_character.py --asset <asset_path>
```

(or `--id <id>` if the operator gave just an id).

Read the `[bootstrap] char_id: <X>` line to learn the derived `<id>`.
Use that `<id>` for the rest of this run. If the script exits 1
("character already exists"), ask the operator whether to re-export; if
yes, re-run with `--force`.

## Step 2 — Run the pipeline (the script drives)

Launch the master runner **in the background** (set the tool's
`run_in_background: true`). Do not set a timeout.

```powershell
5.7/facescan-glb/tools/run_pipeline.ps1 -Char <id>
```

The runner blocks on each stage's process-exit hook, self-skips stages
already `done`, and stops loud on the first failure. You will be notified
when the background process exits.

## Step 3 — On completion, branch on exit code

**Exit 0** — every stage reported `done`. Go to Step 5 (final report).

**Non-zero** — the runner stopped at a failed stage and printed an
`AI HANDOFF` block (which stage, the contract path, the manifest errors,
the resume command). This is the ONLY place AI re-enters the chain.

1. Read the failed stage's `stages/<NN>-<name>/CONTEXT.md` and the
   failed block in `characters/<id>/manifest.json` (`stages.<key>.errors`).
   Load nothing else — stage isolation still holds.
2. Diagnose the **actual** failure. Common non-deterministic causes:
   rig not applied, texture override not wired, missing outfit/groom,
   UE editor left open, Blender path wrong. Surface the real error;
   never lower a threshold or skip an asset to force a green.
3. If it is a fixable setup issue, fix it (re-point a path, re-run a
   prep step, correct the asset wiring). For routine, well-scoped fixes
   you may dispatch a Haiku sub-agent scoped to that single stage. For
   genuinely ambiguous MetaHuman-setup variance, diagnose as Opus.
4. Resume the chain from the fixed stage:
   ```powershell
   5.7/facescan-glb/tools/run_pipeline.ps1 -Char <id> -From <stage_key>
   ```
   (Done stages are skipped automatically, so a bare re-run also works.)
5. Repeat until exit 0, or until the failure genuinely needs the
   operator (then escalate with the concrete error — do not loop
   forever or fake success).

## Step 4 — Stage reference (the runner already knows these)

| `<NN>` | `<stage_name>` | manifest key | typical timing |
|---|---|---|---|
| 00 | `unreal-assemble` | `00_unreal_assemble` | ~1-2 min (UE startup + assemble) |
| 01 | `unreal-glb-export` | `01_unreal_glb_export` | ~1-2 min (UE GLB + Sequencer bake) |
| 02 | `blender-assemble` | `02_blender_assemble` | ~60-90 s |
| 03 | `export-to-glb` | `03_glb_export` | ~30-60 s |
| 04 | `webview-build` | `04_webview_build` | ~5 s |

## Step 5 — Final report

When the runner exits 0, tell the operator:

- Final GLB path: `5.7/facescan-glb/docs/characters/<id>/<id>.glb`
- File size + tri count from `characters/<id>/03-glb/glb_manifest.json`
- Where to view it: `<file:// path or http://localhost URL>`

## Things you must NOT do

- Do NOT spawn a sub-agent per stage on the happy path. The script
  chains stages; AI only handles failures.
- Do NOT wrap a launcher in a tool-call timeout. Run the master runner
  in the background and wait for the process-exit hook.
- Do NOT read other characters' manifests, or stage CONTEXT.md files
  other than the one stage you are actively diagnosing.
- Do NOT "fix" stale manifest state by hand. The launchers own their own
  manifest blocks; the runner owns the chain.
- Do NOT modify pipeline code (`stages/*/tools/*`, `tools/*.ps1`,
  `_config/pipeline.yaml`) to force a stage green. If a script is
  genuinely broken, escalate to the operator (or to Opus) with the real
  error.
