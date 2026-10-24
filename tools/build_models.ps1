# Regenerates every model from tools/blender/*.py (headless Blender), then re-imports into Godot.
# Uses $env:BLENDER when set, otherwise the default Program Files install.
$root = Split-Path $PSScriptRoot -Parent
$blender = $env:BLENDER
if (-not $blender) {
    $blender = (Get-ChildItem "C:\Program Files\Blender Foundation\Blender*\blender.exe" |
        Sort-Object FullName -Descending | Select-Object -First 1).FullName
}
if (-not $blender) { Write-Error "Blender not found. Install it with: winget install BlenderFoundation.Blender"; exit 2 }

# One job per output file: script, extra args, output.
$jobs = @(
    @{ Script = "humanoid.py"; Args = @(); Out = "assets/models/humanoid.glb" },
    @{ Script = "props.py"; Args = @("oak"); Out = "assets/models/oak.glb" },
    @{ Script = "props.py"; Args = @("pine"); Out = "assets/models/pine.glb" },
    @{ Script = "props.py"; Args = @("rock"); Out = "assets/models/rock.glb" },
    @{ Script = "props.py"; Args = @("bush"); Out = "assets/models/bush.glb" },
    @{ Script = "buildings.py"; Args = @("cabin"); Out = "assets/models/cabin.glb" },
    @{ Script = "buildings.py"; Args = @("campfire"); Out = "assets/models/campfire.glb" },
    @{ Script = "buildings.py"; Args = @("storage"); Out = "assets/models/storage.glb" },
    @{ Script = "buildings.py"; Args = @("fence"); Out = "assets/models/fence.glb" },
    @{ Script = "buildings.py"; Args = @("well"); Out = "assets/models/well.glb" },
    @{ Script = "buildings.py"; Args = @("flag"); Out = "assets/models/flag.glb" }
)
foreach ($job in $jobs) {
    # Export to a temp file and replace the committed model only on success.
    $out = Join-Path $root $job.Out
    $tmp = "$out.tmp.glb"
    if (Test-Path $tmp) { Remove-Item $tmp }
    $scriptArgs = @($job.Args) + @($tmp)
    & $blender -b --factory-startup --python (Join-Path $PSScriptRoot "blender\$($job.Script)") -- @scriptArgs 2>&1 |
        Select-String -Pattern "EXPORTED|Error|Traceback|rror:" | ForEach-Object { $_.Line }
    if (-not (Test-Path $tmp)) { Write-Error "Model not produced, kept previous: $out"; exit 1 }
    Move-Item -Force $tmp $out
}
& "$PSScriptRoot\godot.ps1" --headless --import 2>&1 | Out-Null
Write-Output "Models built and imported."
exit 0
