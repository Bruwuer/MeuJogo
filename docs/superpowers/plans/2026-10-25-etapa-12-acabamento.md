# Etapa 12 — Acabamento: plano

> Execução: superpowers:executing-plans (inline), TDD, ledger em `.superpowers/sdd/2026-10-25-etapa-12-acabamento/progress.md`.

**Goal:** menu inicial e de pausa, 3 espaços de save, som gerado por script tocando no jogo, balanceamento.
**Spec:** `docs/superpowers/specs/2026-10-25-etapa-12-acabamento-design.md` (§4 adendo manda).

## Global Constraints
- Só teclado (setas, Enter, Esc). Textos em português; código em inglês. Constantes em `GameConstants`.
- Testes usam `main.tscn` direto com `save_path = ""`; nenhum erro de motor nos testes (sons só se existirem).
- Nada de evento do reino no HUD (regra 16 do CLAUDE.md).

## Review Focus
- Esc com construção, painel P ou painel do ADM aberto não abre a pausa.
- Pausa: o jogo para de verdade (simulação e relógio) e volta igual.
- "Novo jogo" num espaço usado não ressuscita o save antigo pelo `.bak`.
- Sair/Voltar ao menu com save que falhou não perde o jogo.
- Som com mil pessoas por perto não passa de 8 vozes.

### Task 1: Session + World nos espaços
- Autoload `Session` (`scripts/core/session.gd`): `slot := 0` (0 = sem menu → espaço 1), `new_game := false`.
- `World`: `save_path` padrão = `SaveSlots.new().path(slot)`; depois de um `save_now()` bom, `write_summary`.
- `tools/new_world.ps1` apaga os 3 espaços (e o antigo).

### Task 2: Esc
- Construção marca o Esc como usado (`get_viewport().set_input_as_handled()`); `Hud.esc_free()` diz se nada usa o Esc.

### Task 3: Menus
- `scenes/menu.tscn` + `scripts/ui/main_menu.gd` como cena principal: Continuar, Novo jogo, Carregar, Opções, Sair.
- `scripts/ui/pause_menu.gd` (no World, `PROCESS_MODE_ALWAYS`): Continuar, Salvar, Opções, Voltar ao menu, Sair.

### Task 4: Som
- Autoload `Sound`: canais, opções em `user://settings.cfg`, música e ambiente dia/noite com transição, chuva,
  vozes 3D (8), ouvinte no jogador, fogueiras, passos, golpes, coleta, cavar, cliques.

### Task 5: Balanceamento
- `tests/visual/long_world.gd`: rodar, ler, ajustar constantes.

### Task 6: Capturas, revisão final (subagente opus), docs, merge no `main`.
