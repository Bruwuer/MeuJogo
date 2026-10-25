# Etapa 9 — Mundo vivo (design)

Data: 2026-10-24 · Status: aprovado pelo fluxo (o autor autorizou todas as decisões; cada uma vai como `Ruling:`)

## 1. Intenção (nas palavras do autor, resumidas)

"Sair tem consequências: se o jogador vai explorar, fundar outro reino ou visitar reinos que já existem, o
reino anterior continua." "Mundo vivo: reinos guerreiam entre si por conta própria." Roadmap: reinos NPC,
simulação resumida fora da tela, diplomacia e guerras, novos reinos.

Valem as regras: o jogador não é protagonista; nada do reino no HUD (só o que é dele); **tudo acontece de
verdade** (feitos com caminhada); só teclado; sorteios semeados; números em `GameConstants`.

## 2. Escopo

**Reinos NPC desde o começo.** Um mundo novo nasce com `REALM_NPC_START` (2) reinos NPC, longe do ponto onde o
jogador surge e longe um do outro (`REALM_MIN_GAP`). Cada um tem sede (cabana do reino), bandeira, fogueira,
uma fazenda, duas casas e `REALM_NPC_PEOPLE` moradores de duas famílias (que viram Casas sozinhas, como hoje).
O governo começa vago (`GOV_NOBODY`): o `GovSim` escolhe o primeiro governante com posse na sede, como na
etapa 8. Saves antigos ganham os reinos NPC no primeiro carregamento (uma vez, `state.realms_seeded`).

**Simulação fora da tela.** Já existe: `VillageSim`, `SocietySim`, `HouseSim` e `GovSim` rodam por hora para
todos os reinos, carregados ou não. Esta etapa só confere que nada assume um reino só.

**Quem fundou.** Reino ganha `founder` ("player" ou "npc"). Só reinos do jogador têm ausência, devolução e
o fundador reassumindo no interregno. Em reino NPC o jogador é visitante: não constrói nem demole ali; pode
doar (é um presente ao povo) a menos que o governante seja inimigo dele.

**O jogador funda outros reinos.** Uma Cabana construída fora de qualquer território e a pelo menos
`REALM_MIN_GAP` das outras sedes funda um reino novo do jogador (cor e nome próprios). O renascer vai para a
sede do reino do jogador mais perto.

**Diplomacia entre reinos.** Cada par de reinos tem uma relação (-1..1) e um estado (paz ou guerra), guardados
no `WorldState`. Uma vez por dia a relação deriva por motivos concretos:
- fronteira: sedes a menos de `REALM_BORDER` puxam para baixo, mais quanto mais perto;
- fome: reino com pouca comida cobiça o vizinho farto;
- governante: corajoso, ganancioso ou corrupto empurra para a hostilidade; generoso ou sociável, para a paz;
  num reino do jogador, conta o que o governante NPC do outro lado acha do jogador;
- comércio: os dois com comércio aproximam;
- guerra cansa (cada batalha e cada dia de guerra);
- tudo volta devagar ao neutro.

**Atos diplomáticos são feitos de enviados** (uma pessoa anda de uma sede à outra; o efeito vale quando ela
chega): **declaração de guerra**, **proposta de paz** (o outro lado aceita ou recusa pela regra) e **presente**
(leva `REALM_GIFT` do estoque; a relação sobe). O governante NPC declara guerra quando a relação está abaixo de
`REALM_WAR_AT` e a força dele (guardas) é pelo menos `REALM_WAR_RATIO` vezes a do outro; propõe paz quando o
cansaço passa de `REALM_PEACE_WEARY`.

**Guerra de verdade.** Em guerra, cada lado que tem guardas manda, de tempos em tempos, um **bando de guerra**:
os guardas livres andam até a sede inimiga (feito `march`). A batalha acontece quando o líder chega: força do
ataque (guardas do bando) contra a defesa (guardas do defensor com vantagem de defesa e um pouco dos adultos).
Quem vence saqueia parte do estoque do outro e queima uma construção (nunca a sede); o perdedor perde guardas
(morrem, com sucessão se era o governante). Tudo vai para o log do ADM. Um reino NPC em guerra sobe o decreto de
guarda (convoca).

**Novos reinos por êxodo.** Uma Casa com `REALM_EXODUS_ADULTS` adultos ou mais, cujo chefe odeia o governante
(relação abaixo de `REALM_EXODUS_AT`), ou num reino lotado, parte para fundar um reino: o chefe anda até um lugar
livre (feito `exodus`); ao chegar, funda o reino (sede e bandeira), e a Casa toda passa a morar lá; o chefe é o
primeiro governante. Teto de `REALM_MAX` reinos no mapa.

**O jogador na diplomacia.** No reino que governa, o painel P ganha uma linha por reino conhecido:
"Reino X: paz/guerra" e, com Enter, a ação escolhida com ←/→ (propor paz, declarar guerra, enviar presente),
cumprida por um enviado. O HUD mostra o nome e o governante do reino onde o jogador está (público); estoque e
moradores só nos reinos do próprio jogador.

## 3. Fora do escopo

- O jogador lutar contra pessoas (combate continua contra criaturas); cercos, prisioneiros, vassalagem, tributo
  e conquista de reino (fica para o acabamento ou etapa futura).
- Alianças militares entre três reinos.
- Rotas de comércio com mercadores andando (só o efeito na relação).

## 4. Decisões técnicas

- **Ruling:** `RealmRules` (puro): deriva da relação, quem declara guerra, quem aceita paz, força e resultado de
  batalha, escolha de lugar para reino novo. `RealmSim` (por hora, no fim do `VillageSim`, depois de todos os
  reinos) aplica: deriva diária, decisões dos governantes NPC, bandos de guerra, êxodos, feitos de enviados.
  Feitos novos (`envoy`, `march`, `exodus`) entram pelo `extra_deed` do `HouseSim`, como na etapa 8.
- **Ruling:** relações entre reinos ficam em `WorldState._realms` (chave "a:b" com a < b) e entram no save;
  `realms_seeded` também.
- **Ruling:** `NpcRealms.seed(state, gen, scatter, avoid)` cria os reinos NPC com `VillageRules.pick_site`
  (mesmas regras de terreno e de distância das tocas); casas e moradores já existem no começo (não é decisão de
  ninguém, é o mundo que já estava ali).
- **Ruling:** a fama do jogador (`state.fame`) passa a ser a média só dos reinos do jogador.
- **Ruling:** batalhas e saques são resolvidos por regra semeada `(seed, "battle", a, b, hora)`; nada de nós
  lutando entre si nesta etapa.

## 5. Pronto quando

- Testes cobrem: semeadura dos reinos NPC (distâncias, prédios, gente, governo vago → posse), fundação de reino
  novo pelo jogador, recusa de construir em reino NPC, deriva da relação por cada motivo, declaração e paz por
  enviado, bando de guerra e batalha (saque, queima, mortes), êxodo e fundação, painel de reinos, save antigo.
- Captura orgânica: o jogador visita um reino NPC; dias passam; o log do ADM mostra a vida dos reinos NPC e,
  se acontecer, guerra entre eles com feitos vistos.
- Revisão final por subagente, correções, merge.

## 7. Revisão final (2026-10-25): correções

- **Ruling (nomes):** nos reinos NPC o nome combina com quem a pessoa é (pai e filho homens, mãe mulher).
- **Ruling (êxodo):** vão juntos os cônjuges (mesmo de outra Casa) e os filhos menores; o lugar é conferido de novo
  na chegada (ninguém funda em cima de uma construção), os arbustos somem também na tela, e sem lugar livre a Casa
  tenta de novo no dia seguinte. Seis dias entre êxodos de um reino (a captura mostrou o mapa lotando em 2 semanas).
- **Ruling (declaração de guerra):** conferida na chegada do enviado (trégua, fundador de volta ao trono, reino sem
  governante a desfazem).
- **Ruling (guarda de guerra):** quando o fundador volta a governar, a convocação do regente é esquecida e o decreto é dele.
- **Ruling (fronteira):** 320 m e 0,08 por dia a cada 100 m (a captura mostrou relações paradas em zero).
- **Ruling (presente do visitante):** em reino NPC o governante não tem "jeito" com o jogador, então doar lá é sempre
  bem-vindo (a ressalva do governante inimigo só vale nos reinos do próprio jogador).
- **Ruling (baixas):** quem cai é sorteado (semeado), não sempre o líder.
- **Ruling (cabana sem reino):** perto demais de outra sede, a cabana é só cabana e o jogador é avisado.

## 6. Adendo após a revisão do design (2026-10-24)

- **Ruling (cortes):** reinos NPC só declaram guerra a reinos governados por NPC (um reino do jogador entra na
  guerra se, na ausência dele, um regente estiver governando). O jogador, quando governa, só **propõe paz** e
  **envia presente**; não declara guerra nesta etapa. Sem cobiça por fome.
- **Ruling (fundador):** `founder` = "player" | "npc" (saves antigos: "player"). Só reino do jogador tem
  ausência, devolução, fundador reassumindo no interregno ou na deposição, presentes e furtos das Casas ao
  jogador. Em reino NPC o governante não tem "jeito" com o jogador (`ruler_way = ""`; corrupção continua) e o
  jogador não constrói nem demole (doar pode, a menos que o governante seja inimigo).
- **Ruling (semeadura):** `World.seed_realms` (padrão ligado); roda depois de escolher o ponto de surgimento e
  antes de carregar os pedaços e dos primeiros lobos; semente `hash([seed, "realms"])`; um posicionador próprio
  no mapa (margem da borda ≥ raio do reino, `REALM_MIN_GAP` = 160 m das outras sedes e do surgimento). Prédios do
  reino NPC são do reino (`OWNER_KINGDOM`), casas dos moradores. `realms_seeded` vira verdadeiro mesmo se couber
  só um. Decreto inicial de guarda 2 (com 6 moradores, sobra quem trabalhe).
- **Ruling (relações):** `WorldState._realms`, chave `Vector2i(a, b)` com a < b: `{rel, war, since, weary_a,
  weary_b, truce_until}`; entra no save.
- **Ruling (números):** deriva diária limitada a ±0,08: fronteira −0,05 × (260 − d)/100 quando d < 260; traço do
  governante (corajoso, ganancioso, corrupto) −0,015 cada, (generoso, sociável) +0,015 cada; comércio dos dois
  +0,02; depois r × 0,97 (volta ao neutro). Guerra: relação < −0,6, força ≥ 1,5 × a do outro, ≥ 2 guardas, sem
  trégua (5 dias depois de uma paz). Cansaço: +1 por dia de guerra, +3 por batalha. Paz: propõe com cansaço ≥ 6;
  aceita com o próprio cansaço ≥ 4 ou governante generoso; depois da paz, relação ≥ −0,3. Batalha: manda até
  (guardas − 1) livres; força = guardas + 0,15 × outros adultos; cada lado × sorteio 0,7–1,3; defesa × 1,3;
  perdedor perde max(1, ⌈metade dos guardas⌉) guardas, vencedor perde a proporção; saque 30% de cada recurso;
  queima no máximo 1 construção, nunca a sede.
- **Ruling (feitos longos):** janela dos feitos entre reinos = início + distância / 44 m por hora × 1,5 + 2 h.
  Feito de outro sistema só vai para quem está livre. Fora da tela, resumido na hora em que começa (como sempre).
- **Ruling (cadeia de feitos):** `GovSim.complete_deed` passa adiante o que não conhece (`next_deed`), e o
  `RealmSim` pega dali. Só o líder do bando decide a batalha; quem já morreu não age.
- **Ruling (morte em batalha):** `SocietySim.kill(k, p)` público (casas passam adiante, sinal de morte, registro sai).
- **Ruling (êxodo):** Casa com ≥ 3 adultos, chefe com relação < −0,5 com o governante e que não é a Casa dele,
  ou reino com ≥ 14 moradores; riqueza da Casa ≥ `REALM_EXODUS_WEALTH` (paga o assentamento); um êxodo por vez por
  reino e 3 dias entre êxodos; só acontece com a Casa toda fora da tela (sem nós), e a Casa muda de reino ao fim do
  feito do chefe (`kingdom_id` das pessoas e da Casa, casas antigas passam adiante, feitos cancelados).
- **Ruling (prédios novos e queimados):** chegam aos pedaços carregados pelos sinais que já existem
  (`buildings_changed`) e por um sinal novo `building_burned`.
- **Ruling (painel):** ação nova `gov_confirm` só no Enter (Espaço é ataque). Reino "conhecido" = pedaço da sede
  já visitado.
- **Ruling (HUD):** linha de moradores e estoque só em reino do jogador; em reino NPC aparece só "Governo: Nome".
- **Ruling (bandos de criaturas):** a toca nova foge de todos os reinos, não só do mais perto.
