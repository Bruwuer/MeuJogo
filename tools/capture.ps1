# Runs the game in a real window, drives the player and saves screenshots to captures/.
& "$PSScriptRoot\godot.ps1" --import 2>&1 | Out-Null
& "$PSScriptRoot\godot.ps1" -s res://tests/visual/capture.gd 2>&1 |
    Select-String -Pattern "CAPTURED|WORST_FRAME_MS|SKIPPED|PEOPLE|ERROR|SCRIPT ERROR" | ForEach-Object { $_.Line }
$code = $LASTEXITCODE
& "$PSScriptRoot\godot.ps1" -s res://tests/visual/gallery.gd 2>&1 |
    Select-String -Pattern "CAPTURED|ERROR|SCRIPT ERROR" | ForEach-Object { $_.Line }
exit $code
