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
    @{ Script = "buildings.py"; Args = @("flag"); Out = "assets/models/flag.glb" },
    @{ Script = "buildings.py"; Args = @("house"); Out = "assets/models/house.glb" },
    @{ Script = "buildings.py"; Args = @("farm"); Out = "assets/models/farm.glb" },
    @{ Script = "buildings.py"; Args = @("market"); Out = "assets/models/market.glb" },
    @{ Script = "buildings.py"; Args = @("scaffold"); Out = "assets/models/scaffold.glb" },
    @{ Script = "buildings.py"; Args = @("stake"); Out = "assets/models/stake.glb" },
    @{ Script = "buildings.py"; Args = @("crest_banner"); Out = "assets/models/crest_banner.glb" },
    @{ Script = "weapons.py"; Args = @("sword"); Out = "assets/models/sword.glb" },
    @{ Script = "weapons.py"; Args = @("spear"); Out = "assets/models/spear.glb" },
    @{ Script = "weapons.py"; Args = @("bow"); Out = "assets/models/bow.glb" },
    @{ Script = "weapons.py"; Args = @("arrow"); Out = "assets/models/arrow.glb" }
)
$parts = @("body_canine", "body_bulky", "body_lizard", "body_deer",
    "head_wolf", "head_bear", "head_boar", "head_deer", "head_lizard", "head_horned",
    "leg_thin", "leg_thick", "leg_clawed", "tail_bushy", "tail_stub", "tail_long", "tail_spiked",
    "extra_antlers", "extra_horns", "extra_spikes", "extra_mane")
New-Item -ItemType Directory -Force (Join-Path $root "assets/models/parts") | Out-Null
foreach ($part in $parts) {
    $jobs += @{ Script = "creature_parts.py"; Args = @($part); Out = "assets/models/parts/$part.glb" }
}
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
