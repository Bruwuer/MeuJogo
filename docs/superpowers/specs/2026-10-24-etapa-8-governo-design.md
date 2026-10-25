# Etapa 8 — Governo (design)

Data: 2026-10-24 · Status: aprovado pelo fluxo (o autor autorizou todas as decisões; cada uma vai como `Ruling:`)

## 1. Intenção (nas palavras do autor, resumidas)

"Ficar = governar: se o jogador permanece, ele administra. As decisões dele impactam o reino para o bem ou
para o mal." "Sair tem consequências: um morador pode assumir o governo e ser favorável ou contrário ao
jogador, chegando a adorá-lo como deus ou a tratá-lo como inimigo mortal. O governante pode ser corrupto,
enriquecendo enquanto o reino definha." Roadmap: decisões com efeito, sucessão, governante NPC
(corrupção, lealdade, culto ou inimizade).

Valem as regras de sempre: nada do reino no HUD (só o que é do jogador), tudo no log do ADM; **as coisas
acontecem de verdade** (feitos com caminhada, CLAUDE.md regra 17); só teclado; sorteios semeados.

## 2. Escopo

**Quem governa.** Cada reino tem `ruler_id`: `-1` é o jogador (o fundador), `>= 0` é um morador.
O reino tem também `decrees` (as decisões em vigor) e `away_since` (hora em que o jogador saiu).

**Decretos do jogador** (só quando ele governa e está dentro do reino). Painel do governo na tecla **P**
(fora da dica de teclas não: é do jogador, entra na dica). Com o painel aberto o personagem não anda;
↑/↓ escolhe o decreto, ←/→ muda o valor, P ou Esc fecha. Quatro decretos:

| Decreto | Valores | Efeito real |
|---|---|---|
| Imposto | nenhum / baixo / alto | uma vez por dia o chefe de cada Casa leva a parte da riqueza da Casa à sede (feito de dia); ao chegar, a parte vira estoque do reino. Imposto alto pesa no contentamento e na opinião; nenhum agrada. |
| Ração | farta / normal / curta | quanto cada um come por refeição (mais comida gasta, mais contentamento; curta economiza e entristece). |
| Guarda | 0 a 4 guardas | quantos guardas o reino quer. Faltando, um adulto sem Casa de tradição guerreira contrária é convocado: anda até a sede e recebe a lança (feito); sobrando, o guarda mais novo é dispensado. |
| Obra | livre / casa / fazenda / poço / depósito / comércio | o que os moradores constroem primeiro quando houver recursos (livre = como hoje). |

Cada mudança de decreto é anunciada (crônica) e mexe na opinião de quem é afetado: quem ganha gosta, quem
perde não gosta (Casas ricas e o imposto; guerreiros e a guarda; famílias grandes e a ração).

**Sucessão quando o jogador sai.** Fora do reino por `GOV_ABSENCE_HOURS` (2 dias de jogo), o reino escolhe
um **regente**: o chefe de Casa com maior apoio (prestígio + riqueza + membros adultos + relação das
outras Casas com ele). A posse é uma **cerimônia na sede** (feito do escolhido e dos chefes das Casas).
Até a posse, nada muda. Se o reino não tem nenhum adulto, ninguém assume.

**Sucessão quando o governante morre ou vai embora.** O herdeiro adulto mais velho da Casa dele assume
(cerimônia); sem herdeiro, nova escolha por apoio.

**Personalidade do governante NPC** (calculada na posse, guardada no reino como `ruler_way`):
- **Leal** (opinião do jogador alta): mantém os decretos do jogador e devolve o governo quando ele volta.
- **Culto** (opinião muito alta e traço devoto): leal, e o reino passa a cultuar o fundador: ao entardecer
  os devotos vão até a bandeira da sede e rezam (feito diário, real); a opinião de quem vai sobe.
- **Corrupto** (traço ganancioso ou valores da Casa voltados à riqueza): imposto alto e, de madrugada, leva
  parte do estoque do reino para a própria Casa (feito noturno ao depósito, o mesmo desvio da etapa 7, com
  testemunhas). A Casa dele enriquece enquanto o estoque do reino cai.
- **Inimigo** (opinião baixa): declara o fundador inimigo do reino. A opinião dos moradores sobre o jogador
  cai devagar enquanto ele governa; quando o jogador volta, não devolve o governo.
Leal e culto não excluem corrupção: um governante pode ser leal e corrupto ao mesmo tempo (`corrupt` é à parte).

**Volta do jogador.** Governante leal ou culto: na primeira manhã com o jogador dentro do reino, cerimônia
na sede e o governo volta ao jogador (os decretos do regente ficam até o jogador mudar). Governante inimigo:
o jogador vira **estrangeiro** no próprio reino — não constrói nem demole dentro do território, não doa ao
estoque, e o painel P mostra só "Você não governa o Reino de X" com o nome do governante. O HUD do jogador
mostra quem governa (é público).

**Deposição.** Governante NPC odiado (média da relação dos chefes de Casa com ele abaixo de
`GOV_DEPOSE_AT`, ou contentamento médio do reino abaixo de `GOV_DEPOSE_CONTENT`) é deposto: os chefes das
Casas que o odeiam se reúnem de madrugada perto da sede (feito secreto, com testemunhas como sempre) e, ao
fim, ele perde o governo. Se o jogador está no reino e a opinião média dele é boa, o governo volta ao
jogador; senão, nova escolha por apoio (que pode escolher alguém amigo do jogador — é assim que o jogador
recupera um reino perdido: indiretamente, pelas pessoas).

**Painel do ADM (F10)** ganha uma linha do governo: governante, jeito, decretos, quanto já desviou.

## 3. Fora do escopo (fica para depois)

- Guardas atacarem o jogador, guerra civil, prisão e julgamentos (etapa 9 traz guerra).
- Mais de um reino (a etapa 9 cria reinos NPC; a sucessão já funciona para qualquer reino).
- Estátuas/templos com modelo novo do Blender: o culto usa a bandeira da sede (não há Blender nesta máquina).

## 4. Decisões técnicas

- **Ruling:** `GovRules` (puro, sem cena) decide apoio, escolha de regente, jeito do governante, decretos do
  NPC, efeitos de decreto na opinião e a deposição. `GovSim` (chamado pelo `VillageSim` a cada hora, depois
  do `HouseSim`) aplica, cria os feitos e escreve na crônica. Feitos novos (`tax`, `muster`, `crowning`,
  `handover`, `worship`, `depose`) entram no `HouseSim.complete_deed` via `GovSim.complete_deed`.
- **Ruling:** campos novos do reino (`ruler_id`, `ruler_way`, `ruler_corrupt`, `decrees`, `away_since`,
  `skimmed`) entram em `_kingdom_defaults`: save antigo vira "governado pelo jogador, decretos padrão".
- **Ruling:** a ração muda só a quantidade de comida por refeição (`VillageRules.eat`) e o bônus de
  contentamento; não mexe na fome (evita morte por fome nova).
- **Ruling:** imposto é tirado da `wealth` da Casa e entra no estoque como comida/madeira/pedra na proporção
  do que o reino tem menos (um imposto "em espécie"), arredondado; Casa sem riqueza não paga.
- **Ruling:** decretos do jogador só pelo painel P; números todos em `GameConstants`.
- **Ruling:** a ausência conta só horas inteiras simuladas (`VillageSim`), então pular dias fora do reino
  (captura) funciona igual a jogar.

## 5. Pronto quando

- Testes cobrem: escolha do regente, jeito do governante, cada decreto (efeito e opinião), imposto como
  feito, convocação, sucessão por morte, volta do jogador (leal e inimigo), deposição, culto, desvio do
  governante corrupto, save antigo.
- Captura orgânica: o jogador governa, muda decretos, sai por dias; volta e encontra um regente (com o jeito
  que o reino escolheu sozinho); feitos de governo aparecem acontecendo (posse, imposto, convocação, culto ou
  desvio).
- Revisão final por subagente, correções, merge.

## 6. Adendo após a revisão do design (2026-10-24)

- **Ruling (jeito do governante):** pela opinião do próprio regente sobre o jogador, na posse:
  `>= ALLY_AT` leal; `<= ENEMY_AT` inimigo; senão neutro. Culto = leal + traço devoto + opinião
  `>= GOV_CULT_OPINION`. Corrupto (`ruler_corrupt`, à parte) = traço ganancioso ou valor de riqueza da Casa
  `>= GOV_CORRUPT_WEALTH`. Nada sorteado. `ruler_way` ∈ {"", "leal", "culto", "neutro", "inimigo"}.
- **Ruling (volta do jogador):** leal e culto devolvem; neutro devolve se a opinião média dos adultos sobre o
  jogador for `>= 0`; inimigo nunca devolve.
- **Ruling (opinião enquanto ausente):** com regente, a deriva de ausência vai para um alvo que depende do
  jeito: culto `+GOV_CULT_TARGET`, inimigo `GOV_ENEMY_TARGET` (negativo), os outros 0 (como hoje).
- **Ruling (ausência):** `k.away_hours` soma cada hora simulada com o jogador fora e volta a 0 quando ele
  está dentro; a sucessão começa em `GOV_ABSENCE_HOURS`.
- **Ruling (apoio):** `HouseSim.prestige_of` + `GOV_SUPPORT_MEMBER` por adulto + `GOV_SUPPORT_RELATION` × relação
  média dos outros chefes com o candidato. Empate: menor id. Só chefes de Casa adultos e residentes.
- **Ruling (feitos de governo, todos individuais, nunca coletivos):** `crowning` (o novo governante vai à sede
  na janela de cerimônia; efeito ao chegar), `handover` (o regente vai à sede de dia com o jogador no reino;
  efeito ao chegar), `tax` (um adulto livre da Casa leva o imposto à sede de dia), `muster` (o convocado vai à
  sede de dia; ao chegar vira guarda), `worship` (devoto livre vai à bandeira ao entardecer; ao chegar, a
  opinião sobe), `depose` (o chefe que mais odeia o governante vai de madrugada à sede; segredo com
  testemunhas; ao chegar, o governante cai). Feitos de governo **nunca substituem** outro feito: só pessoas
  sem feito recebem um; se ninguém está livre, fica para o dia seguinte. Fora da tela são resumidos na hora em
  que começam (como na etapa 7). Entram por `GovSim.complete_deed`, chamado pelo ramo padrão do
  `HouseSim.complete_deed`.
- **Ruling (imposto):** riqueza vira estoque à taxa `SKIM_VALUE` (a mesma do desvio): baixo `GOV_TAX_RATE.low`
  e alto `GOV_TAX_RATE.high` da riqueza da Casa por dia, no recurso que o reino tem menos. Casa abaixo de
  `GOV_TAX_FLOOR` de riqueza não paga.
- **Ruling (ração):** inteira, sem fração de comida: farta = come já com fome `HUNGER_MEAL × GOV_RATION_EAT_AT.farta`
  (come mais vezes); curta = só come com fome `HUNGER_MEAL × GOV_RATION_EAT_AT.curta` (menos vezes). O decreto
  entra no `snapshot` e em `VillageRules.eat`; `hourly_contentment` ganha os termos de imposto e ração.
- **Ruling (obra):** a preferência entra no `snapshot`; `next_project` a usa quando não há obra aberta e o
  estoque paga; senão o plano normal segue (nunca trava).
- **Ruling (guarda):** convocados vêm de Casas guerreiras, depois de quem tem traço corajoso ou vocação de
  guarda, depois de adultos sem Casa; nunca crianças. Dispensado volta à vocação (ou à profissão da tradição,
  ou construtor). Sem candidato, nada acontece.
- **Ruling (deposição):** só pela relação média dos chefes de Casa com o governante `< GOV_DEPOSE_AT`, depois
  de `GOV_MIN_REIGN_HOURS` de reinado (sem gatilho de contentamento).
- **Ruling (morte/saída):** `GovSim` confere toda hora se o governante ainda é residente; se não, sucessão
  (herdeiro adulto mais velho da Casa; senão, apoio).
- **Ruling (culto, versão enxuta):** só o feito `worship` diário dos devotos; nenhuma mecânica a mais.
- **Ruling (HUD e regra 16):** posse, imposto, convocação, deposição e culto vão só para a crônica. O jogador
  só vê o que é dele: a linha "Governo: você" / "Governo: Nome" no rótulo do reino, o painel P e a resposta às
  ações dele ("O Reino de X não é seu: Nome governa").
- **Ruling (painel P):** dono é o HUD (como F9/F10), ações novas `gov_panel` (P) e as `ui_up/ui_down/
  ui_left/ui_right` (setas); com o painel aberto o jogador fica `frozen` e o HUD consome as teclas.
- **Ruling (desvio do governante):** usa o `skim` da etapa 7 na Casa do governante (mesmas testemunhas e
  escândalo) e soma `k.ruler_skimmed`.
