<#
.SYNOPSIS
  Master deterministic pipeline runner for 5.7/facescan-glb.

  Chains stages 00 -> 01 -> 02 -> 03 -> 04 by EXIT CODE. The script is
  the driver. AI is NOT in the loop on the happy path.

.USAGE
  ./run_pipeline.ps1 -Char sander_head__3_
  ./run_pipeline.ps1 -Char sander_head__3_ -Force         # re-run done stages
  ./run_pipeline.ps1 -Char sander_head__3_ -From 02_blender_assemble

.DESIGN (why this exists)
  Every stage launcher (stages/<NN>/tools/run_*.ps1) is ALREADY
  event-driven: it blocks on its child process exiting + a status
  sentinel, then self-updates its own manifest block via
  tools/_update_manifest.py. So stage chaining is pure exit-code logic
  with no AI and no timeouts.

  - NO TIMEOUTS here. This runner blocks on each child launcher exiting.
    Completion is a hook (process exit), never a guessed duration.
  - NO AI here. Scripts hook into the next script. On the first stage
    that fails, the runner STOPS LOUD and prints an AI HANDOFF block.
    The orchestrator (AI) then re-enters scoped to ONLY that stage's
    CONTEXT.md to diagnose the non-deterministic case, fix it, and
    resume. MetaHuman assets vary (rig state, texture overrides, outfit
    setups) in ways a script cannot fully cover; that variance is
    exactly where AI earns its place, as a fallback supervisor, not the
    driver.
  - IDEMPOTENT RESUME. Stages already "done" in the manifest are
    skipped unless -Force. After AI fixes a failed stage, re-running the
    same command continues the chain from where it stopped.

.NOTES
  Each stage launcher ends with `exit <code>`. They MUST be invoked in a
  CHILD powershell process, otherwise that `exit` would terminate this
  master runner after stage 00. We launch each via
  `powershell -File <launcher>` and read $LASTEXITCODE.
#>
param(
    [Parameter(Mandatory=$true)][string]$Char,
    [switch]$Force,
    [string]$From
)

$ErrorActionPreference = "Stop"

$ToolsDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Workspace = (Resolve-Path (Join-Path $ToolsDir "..")).Path     # pipeline root: 5.7/facescan-glb
$StagesDir = Join-Path $Workspace "stages"
$Manifest  = Join-Path $Workspace "characters\$Char\manifest.json"

if (-not (Test-Path $Manifest)) {
    Write-Host "[pipeline] FATAL: no manifest at $Manifest"
    Write-Host "[pipeline] Run tools/bootstrap_character.py for '$Char' first."
    exit 1
}

# Ordered stage table. Each launcher takes -Char <id>. Launcher file
# names differ per stage (assemble/export/site), so they are explicit.
$Stages = @(
    [pscustomobject]@{ Num = '00'; Dir = '00-unreal-assemble';  Launcher = 'run_assemble.ps1'; Key = '00_unreal_assemble'   }
    [pscustomobject]@{ Num = '01'; Dir = '01-unreal-glb-export'; Launcher = 'run_export.ps1';   Key = '01_unreal_glb_export'  }
    [pscustomobject]@{ Num = '02'; Dir = '02-blender-assemble';  Launcher = 'run_assemble.ps1'; Key = '02_blender_assemble'   }
    [pscustomobject]@{ Num = '03'; Dir = '03-export-to-glb';     Launcher = 'run_export.ps1';   Key = '03_glb_export'         }
    [pscustomobject]@{ Num = '04'; Dir = '04-webview-build';     Launcher = 'run_site.ps1';     Key = '04_webview_build'      }
)

function Get-StageStatus([string]$Key) {
    try {
        $m = Get-Content $Manifest -Raw | ConvertFrom-Json
        return $m.stages.$Key.status
    } catch {
        return $null
    }
}

Write-Host "[pipeline] char      : $Char"
Write-Host "[pipeline] workspace : $Workspace"
Write-Host "[pipeline] driver    : script (AI re-enters only on stage failure)"
if ($From)  { Write-Host "[pipeline] from      : $From" }
if ($Force) { Write-Host "[pipeline] force     : re-running done stages" }

$started = -not $From

foreach ($s in $Stages) {
    if (-not $started) {
        if ($s.Key -eq $From) { $started = $true }
        else {
            Write-Host "[pipeline] $($s.Num) $($s.Key) - skipped (before -From $From)"
            continue
        }
    }

    $status = Get-StageStatus $s.Key
    if ($status -eq "done" -and -not $Force) {
        Write-Host "[pipeline] $($s.Num) $($s.Key) - already done, skipping (use -Force to re-run)"
        continue
    }

    $launcherPath = Join-Path (Join-Path $StagesDir $s.Dir) "tools\$($s.Launcher)"
    if (-not (Test-Path $launcherPath)) {
        Write-Host "[pipeline] FATAL: launcher not found: $launcherPath"
        exit 1
    }

    Write-Host ""
    Write-Host "==================================================================="
    Write-Host "[pipeline] STAGE $($s.Num)  ->  $($s.Key)"
    Write-Host "[pipeline] launcher: $launcherPath"
    Write-Host "==================================================================="

    # Child process: the launcher's terminal `exit` must NOT kill this
    # runner. $LASTEXITCODE is the hook that drives the chain.
    & powershell -NoProfile -ExecutionPolicy Bypass -File $launcherPath -Char $Char
    $code = $LASTEXITCODE

    Write-Host "[pipeline] stage $($s.Num) launcher exit code: $code"

    # The launcher already wrote the manifest. Manifest is source of truth.
    $status = Get-StageStatus $s.Key
    if ($code -ne 0 -or $status -ne "done") {
        Write-Host ""
        Write-Host "[pipeline] STAGE $($s.Num) ($($s.Key)) FAILED."
        Write-Host "[pipeline]   launcher exit  : $code"
        Write-Host "[pipeline]   manifest status: $status"
        Write-Host "[pipeline] STOPPING. The chain did NOT advance and did NOT retry."
        Write-Host "[pipeline] ----------------------------------------------------------------"
        Write-Host "[pipeline] AI HANDOFF (fallback supervisor): diagnose stage $($s.Num) ONLY."
        Write-Host "[pipeline]   contract : stages/$($s.Dir)/CONTEXT.md"
        Write-Host "[pipeline]   manifest : characters/$Char/manifest.json -> stages.$($s.Key).errors"
        Write-Host "[pipeline]   then resume : tools/run_pipeline.ps1 -Char $Char -From $($s.Key)"
        Write-Host "[pipeline] ----------------------------------------------------------------"
        exit $code
    }

    Write-Host "[pipeline] stage $($s.Num) done."
}

Write-Host ""
Write-Host "[pipeline] ALL STAGES DONE for '$Char'."
$glb = Join-Path $Workspace "docs\characters\$Char\$Char.glb"
if (Test-Path $glb) {
    $kb = [math]::Round((Get-Item $glb).Length / 1KB)
    Write-Host "[pipeline] final GLB: $glb (${kb} KB)"
} else {
    Write-Host "[pipeline] WARNING: expected final GLB not found at $glb"
}
exit 0
