# CONTINUAR — passagem de bastão entre sessões

Este arquivo diz exatamente onde o trabalho parou. **Toda sessão (interativa ou automática) deve lê-lo
primeiro e atualizá-lo ao concluir cada tarefa** (seção "Estado atual").

## Pedido do autor (vale para todas as sessões)

- "Fluxo completo, faz tudo" e "me entrega todas as partes": fazer **todas as etapas restantes do
  roadmap (4 a 9)**, uma após a outra, **sem fazer perguntas**. O autor autorizou qualquer decisão;
  registre cada decisão como `Ruling:` no ledger e no design.
- Fluxo de cada etapa (skills superpowers): design curto em `docs/superpowers/specs/` → revisão do
  design por subagente → plano em `docs/superpowers/plans/` → execução direta (executing-plans) com
  TDD e ledger em `.superpowers/sdd/<plano>/progress.md` → capturas com janela (`tools/capture.ps1`)
  inspecionadas → revisão final por subagente (opus) → correções Critical/Important com teste RED→GREEN
  → merge fast-forward no `main` → apagar branch e workspace → atualizar este arquivo.
- Regras do projeto: `CLAUDE.md`. Testes: `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`.
- Comunicação com o autor é em português. Ao terminar uma etapa, escreva um resumo curto em
  `docs/ENTREGAS.md` (o que mudou, decisões, pendências, capturas).

## Estado atual

- Etapas 1, 2 e 3: concluídas e no `main` (176 testes passando).
- **Etapa 4 (criaturas e combate): EM ANDAMENTO.** Autor pediu: combate SÓ por teclado (Espaço ataca para onde o personagem olha, 1/2/3 ou Q troca arma, sem mira automática, sem mouse); construção também por teclado (mouse opcional). Ataques ao reino só com MOTIVO (fome, território, rancor, filhotes) — ver seção 6 do design.
  - Branch `etapa-4` criado a partir do `main`.
  - Design escrito e commitado: `docs/superpowers/specs/2026-10-24-etapa-4-criaturas-combate-design.md`
    (ainda sem revisão do design).
  - Design revisado (seção 7), plano em `docs/superpowers/plans/2026-10-24-etapa-4-criaturas-combate.md`.
  - Tarefas 1-4 prontas (genoma, peças, corpo montado + galeria `tests/visual/gallery.gd`, vida/cérebro/criatura). Próxima: Tarefa 5 (bandos, motivos, persistência, PackSim).
  - Execução: ver ledger `.superpowers/sdd/2026-10-24-etapa-4-criaturas-combate/progress.md` (linhas `Task N: complete`).
- Etapas 5 a 9: não iniciadas (ver roadmap no `CLAUDE.md`).

## Execução automática

`tools/auto_continue.ps1` roda a cada 30 min (tarefa agendada "MeuJogo-Continuar"). Ele só inicia uma
sessão nova se nenhum arquivo do projeto mudou nos últimos 20 min (ou seja, ninguém está trabalhando)
e se não há outra execução em andamento. Log em `logs/auto_continue_*.log`.
Quando todas as etapas estiverem prontas, escreva `TUDO PRONTO` na primeira linha de "Estado atual";
o script para de iniciar sessões.
