# Regenerates every model from tools/blender/*.py (headless Blender), then re-imports into Godot.
# Uses $env:BLENDER when set, otherwise the default Program Files install.
$root = Split-Path $PSScriptRoot -Parent
$blender = $env:BLENDER
if (-not $blender) {
    $blender = (Get-ChildItem "C:\Program Files\Blender Foundation\Blender*\blender.exe" |
        Sort-Object FullName -Descending | Select-Object -First 1).FullName
}
if (-not $blender) { Write-Error "Blender not found. Install it with: winget install BlenderFoundation.Blender"; exit 2 }

$models = @{ "humanoid.py" = "assets/models/humanoid.glb" }
foreach ($script in $models.Keys) {
    # Export to a temp file and replace the committed model only on success.
    $out = Join-Path $root $models[$script]
    $tmp = "$out.tmp.glb"
    if (Test-Path $tmp) { Remove-Item $tmp }
    & $blender -b --factory-startup --python (Join-Path $PSScriptRoot "blender\$script") -- $tmp 2>&1 |
        Select-String -Pattern "EXPORTED|Error|Traceback|rror:" | ForEach-Object { $_.Line }
    if (-not (Test-Path $tmp)) { Write-Error "Model not produced, kept previous: $out"; exit 1 }
    Move-Item -Force $tmp $out
}
& "$PSScriptRoot\godot.ps1" --headless --import 2>&1 | Out-Null
Write-Output "Models built and imported."
exit 0
