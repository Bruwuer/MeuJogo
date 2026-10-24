# Resumes the roadmap in a fresh headless Claude Code session when nobody is working on the project.
# Meant to run every 30 min from Task Scheduler ("MeuJogo-Continuar"). Safe to run anytime:
#   - skips if another run is in progress (lock file with a live PID)
#   - skips if any project file changed in the last $QuietMinutes (an interactive session is active)
#   - skips when CONTINUAR.md says "TUDO PRONTO"
# If the usage limit is reached, the session just ends; the next scheduled run tries again.
param([switch]$DryRun, [int]$QuietMinutes = 20, [string]$TestPrompt = "")

$root = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path $root "logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$lock = Join-Path $logDir "auto_continue.lock"
$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$log = Join-Path $logDir "auto_continue_$stamp.log"

function Say($msg) { $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"; Write-Output $line; if (-not $DryRun) { Add-Content $log $line } }

if (Test-Path $lock) {
    $lockPid = Get-Content $lock -ErrorAction SilentlyContinue
    if ($lockPid -and (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)) { Say "skip: run in progress (pid $lockPid)"; exit 0 }
    Remove-Item $lock -Force
}

$state = Get-Content (Join-Path $root "CONTINUAR.md") -Raw
if ($state -match "(?ms)## Estado atual\s+-?\s*TUDO PRONTO") { Say "skip: all stages done"; exit 0 }

$cutoff = (Get-Date).AddMinutes(-$QuietMinutes)
$recent = Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(\.godot|logs|captures|\.git)\\' -and $_.LastWriteTime -gt $cutoff } |
    Select-Object -First 1
if ($recent) { Say "skip: project active ($($recent.FullName) changed $($recent.LastWriteTime))"; exit 0 }

$prompt = @'
Você está retomando, sem ninguém acompanhando, o desenvolvimento do jogo em D:\MeuJogo.
Leia primeiro CONTINUAR.md e CLAUDE.md e siga-os exatamente: continue de onde o trabalho parou
(confira git status/log e o ledger em .superpowers/sdd), no fluxo completo descrito lá, sem fazer
perguntas, tomando e registrando as decisões. Atualize CONTINUAR.md ao concluir cada tarefa.
Faça commits pequenos com frequência para que nada se perca se a sessão for interrompida.
'@

if ($DryRun) { Say "dry-run: would start a session now"; exit 0 }
if ($TestPrompt) { $prompt = $TestPrompt }

# The prompt goes through stdin: multi-line arguments do not survive Start-Process quoting.
$promptFile = Join-Path $logDir "prompt.txt"
Set-Content -Path $promptFile -Value $prompt -Encoding utf8
$claude = (Get-Command claude).Source
Say "starting headless session"
Set-Location $root
$p = Start-Process -FilePath $claude -ArgumentList @("-p", "--dangerously-skip-permissions", "--output-format", "text") `
    -NoNewWindow -PassThru -RedirectStandardInput $promptFile -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err"
$null = $p.Handle # keeps the process handle so ExitCode is available after exit
Set-Content $lock $p.Id
try { $p.WaitForExit() } finally { Remove-Item $lock -Force -ErrorAction SilentlyContinue }
Say "session ended with exit code $($p.ExitCode)"
