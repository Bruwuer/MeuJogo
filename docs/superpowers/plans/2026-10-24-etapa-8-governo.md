# Etapa 8 — Governo (plano)

Design: `docs/superpowers/specs/2026-10-24-etapa-8-governo-design.md` (§2 escopo, §6 rulings).
Cada tarefa: teste que falha primeiro → código → suíte inteira verde → commit pequeno.

1. **Constantes e campos do reino.** `GameConstants` (GOV_*), `WorldState._kingdom_defaults` com `ruler_id`,
   `ruler_way`, `ruler_corrupt`, `ruler_since`, `decrees` (duplicado), `away_hours`, `ruler_skimmed`.
   Teste: reino novo e save antigo ganham os padrões.
2. **`GovRules` (puro).** `support`, `choose_regent`, `heir_of`, `ruler_way`, `is_corrupt`, `gives_back`,
   `npc_decrees`, `wants_deposition`, `decree_opinion` (efeito de mudar um decreto numa pessoa).
3. **Decretos na vila.** `snapshot` leva os decretos; `eat` usa a ração; `hourly_contentment` ganha imposto e
   ração; `next_project` usa a preferência de obra quando dá.
4. **`GovSim`: ausência e sucessão.** Chamado pelo `VillageSim` depois do `HouseSim`; `away_hours`; posse
   (`crowning`) como feito; governante que morreu ou saiu é substituído; `HouseSim.complete_deed` delega o
   ramo padrão ao `GovSim`.
5. **Volta do jogador e estrangeiro.** `handover` quando o jogo devolve; senão construir, demolir e doar
   dentro do reino são recusados com o nome do governante.
6. **Imposto como feito** (`tax`).
7. **Guarda: convocação (`muster`) e dispensa.**
8. **Governante NPC:** decretos pelo jeito; o corrupto desvia de madrugada (`skim` da etapa 7) e soma
   `ruler_skimmed`.
9. **Opinião com regente** (alvo da deriva pelo jeito) e **culto** (`worship`).
10. **Deposição** (`depose`, segredo com testemunhas).
11. **Painel P** (HUD, setas, jogador parado) com efeito na opinião ao mudar decreto; rótulo do reino com o
    governo; ADM F10 com a linha do governo; dica de teclas.
12. **Captura orgânica** (governa, muda decretos, sai, volta), docs, revisão final por subagente, correções,
    merge.
