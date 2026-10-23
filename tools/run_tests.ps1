# Imports the project, then runs every headless test. Optional args filter test files by substring.
# Exit code 0 = all tests passed.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Filter)
& "$PSScriptRoot\godot.ps1" --headless --import 2>&1 | Out-Null
& "$PSScriptRoot\godot.ps1" --headless -s res://tests/run_tests.gd '--' @Filter
exit $LASTEXITCODE
