# Stage 04: Webview Build

Pure-Python stage (no Blender, no UE). Builds a static three.js viewer
site under `docs/` from stage 03's GLB plus its MetaHuman material map,
then render-validates it in headless Chromium.

## Scope (hard rule)

Run this stage's launcher and verify its outputs. Nothing else. Do not
edit pipeline code, other stages' contracts/manifests, or other
characters' artifacts. If a script throws, surface the real error. Never
work around it (try/except, skipping assets, lowering thresholds).

## Inputs

| Source | File | Why |
|---|---|---|
| Config | `_config/pipeline.yaml` (`characters_dir`) | Where characters live |
| Char manifest | `characters/<id>/manifest.json` (`character_id`, optional `gallery_category`) | Identify + group the character |
| Stage 03 GLB | `characters/<id>/03-glb/<id>.glb` | Asset to host |
| Stage 03 GLB manifest | `characters/<id>/03-glb/glb_manifest.json` (`tri_count`, `file_size_bytes`) | Gallery metadata |
| MH material map | `characters/<id>/03-glb/mh_materials.json` (optional) | Drives hair/skin shading |
| Sidecar textures | `characters/<id>/03-glb/textures/*` (optional) | Material textures |
| Templates | `stages/04-webview-build/templates/` | viewer.html, viewer.js, index.html, style.css |

## Preconditions (files on disk, not manifest status)

`<id>.glb` and `glb_manifest.json` must exist. If missing, abort with an
actionable message ("stage 03 output missing: <path>"). Do not read or
"fix" prior stages' status fields.

## Process

Invoke `tools/run_site.ps1 -Char <id>` (runs `build_site.py`). Two phases:

BUILD: copy GLB, `mh_materials.json`, and textures into
`docs/characters/<id>/`; render the per-character page from
`viewer.html`; rebuild `docs/index.html` (gallery, grouped by
`gallery_category`, static thumbnails); copy `viewer.js` + `style.css`
into `docs/assets/`; write `docs/.nojekyll`. All URLs are cache-busted.

The three.js viewer (`viewer.js`) shades hair cards: alpha-to-coverage
primary with a two-pass blend fallback, anisotropic strand specular,
per-strand seed variance, root darkening, and a root-spec-kill that
mattes hair near the scalp. It reads baked AO from `COLOR_0` (R = broad
AO, G = hair-root contact AO) and shapes it live. With `?tune=1` it
exposes a live tuning panel (lighting, skin, hair sections) whose "copy
JSON" output feeds per-character `HAIR_OVERRIDES` and viewer defaults.

VALIDATE (skip with `--skip-validate`): serve `docs/` on a free port,
open the page in headless Chromium (Playwright), wait for `window.__viewer`
(GLB mounted + first frame), capture console errors, write `preview.png`,
tear down. Fails the stage if the viewer never mounts or console errors fire.

Local viewing: `tools/serve_nocache.py` serves `docs/` with no-store headers.

## Outputs

| Artifact | Location |
|---|---|
| Per-character viewer + GLB | `docs/characters/<id>/index.html`, `<id>.glb`, `mh_materials.json`, `textures/`, `thumbnail.png` |
| Render-validation screenshot | `docs/characters/<id>/preview.png` |
| Gallery index | `docs/index.html` |
| Shared assets | `docs/assets/viewer.js`, `docs/assets/style.css` |
| Jekyll opt-out | `docs/.nojekyll` |
| Updated manifest | `characters/<id>/manifest.json` (`stages.04_webview_build` only) |

## Completion signal

Exit 0 and `stages.04_webview_build.status = "done"` (plus `started_at`,
`completed_at`, `errors = []`). On failure: nonzero exit (1 build, 2
render-validation), `status = "failed"`, actionable message appended to
`errors[]`. Touch only this stage's manifest block.

## Tooling

Validation needs Playwright + Chromium: `pip install playwright` then
`playwright install chromium` (one-time, ~300 MB). Missing → stage fails
with an actionable error; use `--skip-validate` on browserless CI.
