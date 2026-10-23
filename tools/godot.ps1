# Runs the Godot console executable against this project, forwarding all arguments.
# Uses $env:GODOT when set, otherwise the winget install.
$godot = $env:GODOT
if (-not $godot) {
    $godot = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine*\Godot_v4*_console.exe" |
        Sort-Object Name -Descending | Select-Object -First 1).FullName
}
if (-not $godot) { Write-Error "Godot 4 not found. Install it with: winget install GodotEngine.GodotEngine"; exit 2 }
& $godot --path (Split-Path $PSScriptRoot -Parent) @args
exit $LASTEXITCODE
