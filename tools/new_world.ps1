# Deletes the saved world so the next run starts a brand-new world (new seed, new spawn).
$save = Join-Path $env:APPDATA "Godot\app_userdata\MeuJogo\save.bin"
if (Test-Path $save) {
    Remove-Item $save
    Write-Output "Save removido: $save. O próximo jogo começa num mundo novo."
} else {
    Write-Output "Nenhum save encontrado em $save."
}
