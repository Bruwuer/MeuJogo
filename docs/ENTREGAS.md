# Entregas

Resumo curto de cada etapa do roadmap: o que mudou, decisões, pendências e capturas.
As capturas saem de `powershell -ExecutionPolicy Bypass -File tools/capture.ps1` (pasta `captures/`, fora do git).

## Etapa 1 — Fundação jogável

- Mapa em chunks com terreno gerado em thread, humanoide do Blender (parado/andar/correr), WASD + Shift,
  câmera ortográfica isométrica seguindo o jogador e testes headless.

## Etapa 2 — Mundo com conteúdo

- Biomas (planície, floresta, pedregoso), árvores, rochas e arbustos em MultiMesh, coleta com E,
  dia e noite, mapa de 24×24 chunks e persistência delta por chunk (só o que mudou vai para o save).

## Etapa 3 — Construção

- Inventário, construções pré-feitas com custo realista (Cabana, Fogueira, Depósito, Cerca, Poço),
  fantasma verde/vermelho com o motivo do bloqueio, demolição com 50 % de volta, e a primeira Cabana
  funda o reino (nome, cor e bandeira).

## Etapa 4 — Criaturas e combate

**O que mudou**
- **Genoma:** 8 espécies (Lobo, Urso, Javali, Cervo e as inventadas Espinhudo, Chifrudo, Rastejante e
  Uivante). Cada criatura tem genes de corpo (peças, tamanho, cores) e de comportamento (dieta,
  agressividade, bando, velocidade, vida, dano, percepção, hábito noturno). Duas criaturas nunca saem iguais.
- **Corpo por peças:** o Blender gera 21 peças (corpos, cabeças, patas, caudas, chifres, espinhos, juba).
  A Godot monta cada criatura pelo genoma e a anima por código. Um filhote herda peças de cada pai, e um
  híbrido ganha nome composto ("Lobo-uivante").
- **Comportamento:** vagar, pastar, caçar, atacar, fugir, dormir (de dia as noturnas, à noite as outras),
  seguir o líder e procurar par. Os carnívoros caçam herbívoros e os mais agressivos brigam por território.
  Os herbívoros fogem; os javalis bravos enfrentam quem chega perto.
- **Cruzamento:** adultos calmos e alimentados se procuram e têm filhotes, que crescem em 2 dias de jogo.
  Há um teto de população por região.
- **Bandos com motivos:** cada bando tem toca e quatro motivos (fome, território, rancor, filhotes). Um
  ataque ao reino só acontece com motivo forte, e o HUD diz qual é ("Os lobos famintos rondam o Reino de X:
  a caça acabou na região"). Com o reino longe, o ataque é resumido e contado na volta ("Enquanto você
  estava fora…"). A sede nunca cai.
- **Combate só por teclado:** Espada (arco curto), Lança (alcance maior) e Arco (flechas com gravidade).
  Espaço ataca para onde o personagem olha, 1/2/3 ou Q trocam a arma, F faz flechas e H come. A arma
  aparece na mão.
- **Vida e morte:** 100 de vida, que regenera depois de 6 s sem dano. Morrer leva de volta à sede (ou ao
  ponto inicial) sem perder nada.
- **Persistência:** criaturas, bandos, chunks já visitados e a vida das construções vão para o save.
  Criaturas fora dos chunks carregados ficam congeladas.

**Decisões principais** (lista completa no ledger da etapa e na seção 7 do design)
- As criaturas não colidem entre si (uma esfera por criatura). Cápsulas deitadas colidindo custavam 10 ms
  por frame.
- No máximo 2 criaturas são criadas por frame, para o streaming não engasgar.
- Carnívoros atacam o reino à noite; herbívoros territoriais, de dia.
- O arco fica na mão direita (só ela tem encaixe de arma).

**Pendências**
- Ajuste fino visual (pescoço do cervo, cabeças de lagarto pequenas) e o balanceamento de dano e vida.
- Um pico de ~90 ms logo depois de teletransportes nas capturas, que já existia antes desta etapa.

**Capturas:** `13_first_wolves`, `14_hybrid_family`, `15_sword_swing`, `16_arrow_flight`,
`17_raid_night`, `gallery_species`, `gallery_hybrids` e `gallery_walk`.

**Revisão final (subagente opus):** foram corrigidos, cada um com teste, o índice de criaturas por chunk
(estava preso ao chunk de origem e furava o teto de população), o ciclo de mortes na sede durante um
ataque, os ataques "fantasmas" anunciados sem bando por perto, a fome do bando que ignorava as caçadas e
as construções destruídas à distância que continuavam visíveis.
Ficaram para depois três pontos menores: o filhote que cresce mantém a colisão pequena, um cadáver pode
cair se o chunk descarregar, e com 40 criaturas ativas uma criatura próxima não toma a vaga de uma distante.

## Etapa 5 — Pessoas (2026-10-24)

**O que mudou**
- **Gerador de pessoas:** nome e sobrenome medievais portugueses, idade, dois traços de pares opostos
  (trabalhador/preguiçoso, corajoso/medroso, generoso/ganancioso, sociável/solitário, devoto/cético),
  profissão (lenhador, pedreiro, agricultor, coletor, construtor, comerciante), cores de pele, cabelo e
  roupa, altura e opinião inicial sobre você (puxada pelos traços e pela sua fama).
- **Viajantes:** com o reino fundado, chega um viajante 1 hora depois e então a cada 6 horas (4 com um
  Comércio), até 12 moradores. Ele surge a 60–90 m, anda até a sede, olha o reino e decide. O HUD diz o
  motivo: "Ana Ferreira decidiu ficar: há comida guardada" ou "Bento do Vale seguiu viagem: não há onde
  morar". As duas primeiras pessoas sempre ficam.
- **Necessidades:** comem 2 vezes por dia do estoque do reino (Comida antes de Frutas), dormem das 21h às
  6h (em casa ou junto à fogueira), e o contentamento sobe ou desce a cada hora. Quem passa um dia inteiro
  infeliz vai embora com aviso ("Carla deixou o Reino de X: passava fome").
- **Estoque do reino:** separado do seu inventário. Começa com 20 de madeira e 24 frutas. **G** doa até 10
  de cada recurso e melhora a opinião de quem está perto.
- **Trabalho de verdade:** cada um trabalha na profissão quando o estoque precisa (madeira até 60, pedra até
  30, frutas se a comida dura menos de 3 dias); senão ajuda na obra ou busca o que falta. Cortar, quebrar e
  colher removem o objeto do mapa e a pessoa leva o que pegou ao Depósito ou à sede.
- **Construção autônoma:** uma obra por vez, nesta ordem: Fazenda se a comida está acabando, Casa para os
  sem-teto, Fazenda se a produção não cobre o consumo, Comércio (4 moradores), Poço (3) e Depósito. O lugar
  é escolhido em espiral perto da sede, com corredor livre e longe de tocas quando possível. A obra aparece
  como canteiro (andaime e a construção subindo). A casa pronta é "assinada" pelo primeiro sem-teto.
- **Novos modelos do Blender:** Casa (3 moradores), Fazenda (lavoura que se atravessa), Comércio
  (barraca listrada) e o andaime.
- **Falar:** **E** perto de alguém (tem prioridade sobre a coleta) abre um cartão com nome, idade, reino,
  profissão, traços, o que está fazendo, do que precisa e o que acha de você.
- **Opinião sobre você:** sobe com doações e quando você mata um atacante dentro do reino; volta devagar
  para o neutro enquanto você está longe. A média vira a sua fama, que pesa nos próximos viajantes.
- **Medo:** fogem de carnívoros por perto e se escondem em casa durante ataques. Herbívoros fogem das
  pessoas. As criaturas ainda não atacam pessoas, e obras não são alvo de ataque.
- **Mundo sem você:** o `VillageSim` roda a cada hora para todos os reinos. Com o reino longe, o trabalho é
  resumido (inclusive removendo árvores e rochas de verdade) e as notícias ficam para a volta (as 3 últimas
  e quantas mais aconteceram).
- **HUD:** dentro do reino, a linha "Moradores: 5 · Estoque: Madeira 12, Pedra 3, Comida 8, Frutas 4".
- **Persistência:** pessoas, estoque, donos e progresso das obras, e a fama vão para o save. Saves da
  etapa 4 continuam abrindo.

**Decisões principais** (lista completa no ledger da etapa e na seção 5 do design)
- Você não pode demolir casas ou obras dos moradores.
- Quem tem nó trabalha de verdade; quem não tem é resumido pelo `VillageSim`, sem trabalho em dobro. Ao
  perder o nó, o que a pessoa carregava vai para o estoque.
- Um reino fundado dentro do território de uma toca também constrói (o lugar fora do território é só a
  preferência), senão ele nunca cresceria.
- Pessoas desviam por raios no joelho e no peito; se ficam sem progresso, dão um passo de lado e, presas por
  6 s, aparecem no destino. Isso veio das capturas, onde moradores encalhavam no degrau da base da sede.

**Pendências**
- Criaturas usam só raios na altura do corpo e podem encalhar em bases baixas como as pessoas encalhavam.
- O balanceamento (ritmo de chegada, comida, tempo das obras) precisa de horas de jogo de verdade.

**Capturas:** `18_traveler_arrives`, `19_village_working`, `20_site_rising`, `21_person_card` e
`22_village_night`.

**Revisão final (subagente opus):** nenhum problema crítico. Foram corrigidos, cada um com um teste que
falhava antes, cinco pontos importantes e um bug achado nas capturas:
- viajantes que se repetiam depois de recarregar o jogo;
- profissões paradas quando acabavam as rochas ou árvores por perto (agora ajudam na obra);
- a salvaguarda de pessoa presa, que podia pôr alguém dentro de uma construção;
- obras que podiam emparedar o jogador ou um morador;
- reinos de saves antigos sem estoque inicial, que nunca cresciam;
- o erro do agricultor ativo antes da primeira hora resumida (achado nas capturas).

Ficaram para depois doze pontos menores, listados no ledger. Os principais:
- trabalho perdido quando o resumo corta uma árvore que alguém está cortando;
- o custo por pessoa a cada decisão;
- falta uma mensagem de "viajante chegando";
- a doação de 1 fruta já rende opinião cheia;
- a fila de notícias não tem limite.

Suíte: 342 testes passando.
