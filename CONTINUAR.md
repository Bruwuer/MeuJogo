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

- Etapas 1 a 6: concluídas e no `main` (409 testes passando). Resumo em `docs/ENTREGAS.md`.
- **Próxima: Etapa 7 (governo)** — decisões com efeito, sucessão, governante NPC (corrupção, lealdade, culto ou
  inimizade). Criar o branch `etapa-7` a partir do `main` e começar pelo design curto em `docs/superpowers/specs/`.
  A etapa 6 deixou prontos: famílias com chefe (`head_id`), posição de cada pessoa e família (`stance`:
  aliado/inimigo), relações entre pessoas e entre casas (`PeopleManager.family_relation`) e `kingdom_id` nas famílias.
  Pedidos do autor continuam valendo: combate e construção só por teclado; ataques ao reino só com motivo.
  Pendências menores da etapa 6 estão em `docs/ENTREGAS.md`.
- Etapas 7 a 9: não iniciadas (ver roadmap no `CLAUDE.md`).

## Execução automática

**DESLIGADA pelo autor em 2026-10-24** (tarefa agendada removida). Não religar sem pedido dele.

`tools/auto_continue.ps1` roda a cada 30 min (tarefa agendada "MeuJogo-Continuar"). Ele só inicia uma
sessão nova se nenhum arquivo do projeto mudou nos últimos 20 min (ou seja, ninguém está trabalhando)
e se não há outra execução em andamento. Log em `logs/auto_continue_*.log`.
Quando todas as etapas estiverem prontas, escreva `TUDO PRONTO` na primeira linha de "Estado atual";
o script para de iniciar sessões.
