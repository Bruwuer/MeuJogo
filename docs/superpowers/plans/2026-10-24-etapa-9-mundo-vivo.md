# Etapa 9 — Mundo vivo (plano)

Design: `docs/superpowers/specs/2026-10-24-etapa-9-mundo-vivo-design.md` (§2 escopo, §6 rulings).
Cada tarefa: teste que falha primeiro → código → suíte inteira verde → commit pequeno.

1. **Base de vários reinos.** Constantes `REALM_*`; `founder`; `WorldState._realms` + save + `realms_seeded`;
   cor por reino; fama só dos reinos do jogador; renascer na sede do jogador mais perto.
2. **Portões do fundador.** Fundar reino novo do jogador com Cabana longe; recusa de construir em reino NPC;
   `GovSim`/`SocietySim` só tratam o jogador como fundador onde ele é; HUD só mostra moradores e estoque do
   jogador; toca nova foge de todos os reinos.
3. **Reinos NPC no mapa.** `NpcRealms.seed` + ligação no `World` (ordem, sinal para pedaços).
4. **`RealmRules`** (puro): deriva, guerra, paz, força, batalha, êxodo, lugar para reino novo.
5. **`RealmSim`:** deriva diária, enviados (declaração, paz, presente), bandos de guerra e batalhas (saque,
   queima, mortes), guarda em guerra, `SocietySim.kill`, cadeia de feitos.
6. **Êxodo** e fundação de reino novo.
7. **Painel P: reinos** (presente e proposta de paz por enviado, Enter) e linha do ADM.
8. Captura orgânica, docs, revisão final por subagente, correções, merge.
