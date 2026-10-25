# Deletes every saved world (the 3 slots, their backups and summaries, and the old single save)
# so the next run starts a brand-new world (new seed, new spawn).
$dir = Join-Path $env:APPDATA "Godot\app_userdata\MeuJogo"
$files = @(Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^save(_[1-3])?\.bin' })
if ($files.Count -eq 0) {
    Write-Output "Nenhum save encontrado em $dir."
} else {
    $files | Remove-Item
    Write-Output "Saves removidos ($($files.Count) arquivos) em $dir. O próximo jogo começa num mundo novo."
}
