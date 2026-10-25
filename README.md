# MeuJogo — reino vivo medieval (Godot 4)

Jogo 2.5D isométrico low-poly de mundo aberto medieval. O jogador é só mais um no mundo: pessoas
chegam, decidem ficar, trabalham, formam famílias e Casas com brasões, têm ambições, segredos e
intrigas — tudo acontece de verdade no mundo, sem aparecer na tela do jogador (fica no log do ADM).

Regras de desenvolvimento, arquitetura e roadmap: [`CLAUDE.md`](CLAUDE.md).
Onde o trabalho parou: [`CONTINUAR.md`](CONTINUAR.md). Entregas por etapa: [`docs/ENTREGAS.md`](docs/ENTREGAS.md).

## Rodar em outra máquina (Windows)

1. **Instalar o Godot 4.7** (versão usada no projeto):
   ```powershell
   winget install GodotEngine.GodotEngine
   ```
   Os scripts acham o Godot instalado pelo winget sozinhos. Se ele estiver em outro lugar, aponte a
   variável `GODOT` para o executável *console*, por exemplo
   `$env:GODOT = "C:\Godot\Godot_v4.7-stable_win64_console.exe"`.

2. **Baixar o projeto:**
   ```powershell
   git clone https://github.com/<seu-usuario>/MeuJogo.git
   cd MeuJogo
   ```

3. **Importar e abrir** (a primeira vez demora: o Godot importa os modelos `.glb`):
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/godot.ps1 --import
   powershell -ExecutionPolicy Bypass -File tools/godot.ps1 -e
   ```
   No editor, **F5** roda o jogo. Para rodar direto, sem editor:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/godot.ps1
   ```

4. **Conferir que está tudo certo** (testes headless, deve terminar com `RESULT: N passed, 0 failed`):
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

O save fica em `user://` (no Windows: `%APPDATA%\Godot\app_userdata\MeuJogo\`). Mundo novo (apaga o save):
`powershell -ExecutionPolicy Bypass -File tools/new_world.ps1`.

### Opcional

- **Blender** (só para regerar os modelos a partir de `tools/blender/*.py`; os `.glb` já vêm no repositório):
  `winget install BlenderFoundation.Blender`, depois
  `powershell -ExecutionPolicy Bypass -File tools/build_models.ps1`. Outro caminho: variável `BLENDER`.
- **Capturas de tela** com janela (saem em `captures/`, junto com `adm_log.txt`):
  `powershell -ExecutionPolicy Bypass -File tools/capture.ps1`.
- **Continuar o desenvolvimento com o Claude Code:** abra o Claude Code na pasta do projeto; ele lê o
  `CLAUDE.md` e o `CONTINUAR.md`. O fluxo usa o plugin *superpowers* e a skill *godot*
  (`skills-lock.json` lista as skills).

## Controles (só teclado)

| Tecla | Ação |
|---|---|
| WASD / Shift | anda / corre |
| E | fala com quem está perto (cartão) ou coleta (árvore, rocha, arbusto) |
| G | doa ao reino (até 10 de madeira, pedra e frutas) |
| B, 1–5, R, E/clique, Esc | modo construção: escolhe, gira, constrói, sai (a primeira Cabana funda o reino) |
| X | demole (devolve 50 %) |
| Espaço | ataca para onde o personagem olha |
| 1/2/3, Q | Espada / Lança / Arco, troca |
| F / H | faz 5 flechas com 1 madeira / come 1 fruta |
| Z / C / V | perto de um mercador: compra pão / compra flechas / vende madeira |
| P, setas, Enter, Esc | governo: decretos de imposto, ração, guarda e obra; presente ou paz a outros reinos (Enter envia) |
| F9 / F10 | **só ADM:** crônica do reino com segredos / Casas do reino |

O log do ADM com tudo o que acontece no reino fica em `%APPDATA%\Godot\app_userdata\MeuJogo\adm_log.txt`.

## Estado

Etapas 1 a 10 no `main` (630 testes). Próximas: 11 (Cotidiano) e 12 (Acabamento) — ver o roadmap no `CLAUDE.md`.
