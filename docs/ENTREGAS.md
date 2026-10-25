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

## Etapa 6 — Sociedade (2026-10-24)

**O que mudou**
- **Famílias (casas):** todo morador pertence a uma família. Quem decide ficar funda a sua ("Casa Ferreira")
  ou, se já existe uma casa com o mesmo sobrenome, entra nela como parente. A família tem chefe (quem fundou;
  depois, o adulto mais velho) e se desfaz quando não sobra ninguém ("A Casa do Vale se desfez").
- **Brasões gerados por código:** escudo com divisão (pleno, partido, cortado, em banda, esquartelado, em
  asna), duas cores heráldicas (metal sobre cor) e uma figura (besante, cruz, losango, estrela, crescente).
  A imagem de 32 × 40 é desenhada pixel a pixel; nunca há dois brasões iguais no mesmo reino.
- **Estandarte nas casas:** modelo novo do Blender (`crest_banner`, poste com pendão em forma de escudo) que
  recebe o brasão da família do dono, no canto da casa que a câmera vê.
- **Relações:** a cada hora alguns moradores se encontram (mais quem mora junto, é da família ou tem a mesma
  profissão). Traços iguais aproximam, opostos afastam, sociável aproxima, solitário afasta. Daí saem amigos
  e rivais.
- **Casamentos:** adultos solteiros, sem parentesco, que se gostam muito, se casam ("Ana Ferreira e Bento do
  Vale se casaram"), entram na mesma família (a maior) e vão morar juntos, levando os filhos pequenos.
- **Filhos:** casal de mulher e homem, contente, com comida e cama livre em casa pode ter filhos ("Nasceu
  Inês, filha de…"). O filho herda um traço de cada pai, a pele de um e o cabelo do outro. Criança não
  trabalha (brinca perto de casa), aparece menor e cresce; aos 16 ganha a profissão de que o reino precisa
  ("Inês Ferreira cresceu e agora é lenhadora"). A partir dos 70 os velhos podem morrer; o cônjuge fica viúvo.
- **Rupturas:** quem vira rival forte do chefe rompe e funda a própria casa, com brasão novo e sobrenome
  novo ("Martim Ferreira rompeu com a Casa Ferreira e fundou a Casa do Monte"). Família grande solta um
  ramo em paz, com brasão derivado (mesmo escudo, outra figura).
- **Opinião sobre você:** além de doações e proteção, agora muda sozinha: quem vive bem pensa melhor de você,
  a família puxa todos para a média dela, amigos se influenciam e rivais se contrariam. Conversar (E) agrada
  uma vez por dia o sociável e irrita o solitário.
- **Aliados e inimigos:** com opinião alta a pessoa ou família vira aliada; baixa, inimiga ("A Casa Ferreira
  agora é sua aliada", "Rui Couto agora é seu inimigo"). A família aliada dá um presente por dia (madeira ou
  pedra do estoque); um inimigo rouba um pouco do que você tem mais. Só com você no reino.
- **Interface:** o cartão do **E** mostra família e brasão, cônjuge, pais ou filhos, melhor amigo, pior rival
  e se a pessoa é sua aliada ou inimiga. **C** abre o painel de famílias do reino (brasão, pessoas, chefe,
  posição e rival de outra casa). A linha do povoado mostra "Famílias: N".
- **Mundo sem você:** tudo roda no `VillageSim` horário para todos os reinos; as notícias de reino longe
  ficam para a volta (agora no máximo 40, as mais antigas contam em "mais N coisas").
- **Persistência:** famílias, relações e os campos novos das pessoas vão para o save. Saves da etapa 5 abrem.
- **Pendências da etapa 5 resolvidas:** fila de notícias com limite, doação rende opinião proporcional e aviso
  "Um viajante se aproxima do Reino de X".

**Decisões principais** (lista completa na seção 5 do design e no ledger da etapa)
- Casa passa a ter 4 camas (casal e dois filhos); teto do reino sobe para 16, e nascimentos param em 14 para
  sobrar lugar para viajantes.
- Crianças crescem 2 anos por dia de jogo (adultas em ~1 hora de jogo); adultos envelhecem 0,25 ano por dia.
- Quem vai embora infeliz leva o cônjuge e os filhos pequenos; a casa passa ao adulto mais velho que mora nela.
- Qualquer casal de adultos pode se casar; filhos só de mulher (18 a 45) e homem; sem divórcio nem adoção.
- O estandarte fica no canto que a câmera vê, virado para ela (as capturas mostraram estandartes escondidos
  atrás das casas); o cartão e o painel crescem para cima e para baixo para caber na tela.

**Pendências**
- Nascimentos podem passar o teto em 1 ou 2 quando já há viajantes a caminho.
- Casa cujo dono morre com só crianças dentro fica do reino e não volta a ter estandarte quando elas crescem.
- Ainda não há cache de membros por família (custo cresce com muitos reinos; rever na etapa 8).
- No primeiro carregamento de um save da etapa 5, cada morador com sobrenome repetido anuncia que entrou na
  família de parentes; em casa de órfãos o chefe pode ser uma criança.
- Pequenos textos: "Filhos:" no plural para um filho só.

**Capturas:** `23_family_card`, `24_couple_children`, `25_house_crests`, `26_families_panel`, `27_family_split`
e `28_allies_enemies`.

**Revisão final (subagente opus):** nenhum problema crítico. Foram corrigidos, cada um com um teste que
falhava antes:
- a casa nova podia ficar com uma criança e separar a família (agora fica com o adulto com mais parentes sem
  casa, e as camas seguem a família);
- filhos ficavam na casa antiga quando o pai ou a mãe ia morar com o cônjuge;
- o painel de famílias podia sair da tela.
Também entraram testes de horas recuperadas de uma vez e de recarregar o jogo sem repetir notícias.
Ficaram para depois os pontos menores listados acima.

Suíte: 409 testes passando.

## Etapa 7 — Casas e ambições (2026-10-24)

**O que mudou**
- As famílias viraram Casas: tradição e valores, riqueza pelo trabalho, especialização no ofício, prestígio,
  parentesco completo (pais, filhos, irmãos, avós, tios, primos, cônjuges, adoção) que sobrevive à morte.
- Lotes 8×8 marcados por estacas; casa simples → casa de pedra → solar (modelos do Blender).
- Objetivos próprios por pontuação (terra, melhorar a casa, aliança, superar rival, vingança, riqueza, herdeiro,
  união), com prazo, sucesso e expectativa quebrada.
- Vocações contra a tradição e desligamentos (amigável/neutro/hostil, às claras/escondido); casamentos
  arranjados (aceitar, resistir, fugir com quem ama, casamento infeliz e separação); união de Casas; corrupção;
  espiões; vingança; romances secretos; guardas que patrulham.
- **Nada do reino aparece no HUD:** tudo vai para a crônica e para o log do ADM (`user://adm_log.txt`, F9/F10).
- **As decisões acontecem de verdade (feitos):** a pessoa anda até o lugar numa janela de horas e só então o
  efeito acontece. Segredos só vêm à tona por testemunhas de fora da Casa.

**Decisões do fim da etapa** (seções 6 e 7 do design)
- O motivo de território cansa: depois de um ataque o bando aceita o que viu; só construção nova o reacende.
- Bando faminto sem caça na região muda a toca para longe do reino depois de 2 ataques por fome seguidos.
- Feito vencido de quem estava na tela é descartado (nada acontece sem a caminhada).
- Quem sai de uma Casa deixa a casa dela e leva os filhos menores.

**Captura orgânica** (12 dias com o jogador longe + 3 dias assistindo, nada encenado): o reino sobreviveu
(14 moradores, 4 Casas). Ataques caíram de 13 para 5 em 12 dias. Feitos vistos acontecendo sozinhos:
estacas no lote (`29_deed_stake`), encontro secreto de madrugada (`30_deed_tryst`), a Casa trabalhando na
obra (`31_deed_build_home`) e a cerimônia de união na sede (`32_deed_union`). Também `40_land_and_homes`,
`41_player_hud_only`, `42_adm_log` e `43_adm_houses`.

**Revisão final (subagente):** nenhum problema crítico. Corrigidos, cada um com teste que falhava antes:
testemunhas da própria Casa (fuga e encontro), feitos vencidos cumpridos sem a caminhada, lote reservado que
travava a Casa para sempre, Casa nova herdando a casa da antiga e deixando os filhos, fuga com amante que já
tinha casado (ou criança escolhida como amante), e o texto "Casa ?" quando a Casa alvo some numa união.

**Pendências** (pontos menores da revisão)
- Constantes ainda soltas em `house_rules.gd`/`house_sim.gd` (pesos e chances) e em `PackSim._migrate`.
- Nova toca não evita água nem o alcance de outro reino; espião de Casa que sumiu fica plantado para sempre.
- `acquire_plot`/`upgrade` (sem uso) mudam o mundo na hora; `_is_work_day()` sempre verdadeiro; desejos
  pessoais (`desire`) ainda não são sorteados.
- `adm_log.txt` não é rotacionado; adoção não confere camas livres.
- O primeiro quadro depois de 12 dias longe carrega a área inteira de uma vez (pico de ~9,7 s só na captura).

Suíte: 525 testes passando.


## Etapa 8 — Governo (2026-10-24)

**O que mudou**
- **Quem governa:** cada reino tem um governante. O fundador governa enquanto está lá; fora por 2 dias de jogo,
  o chefe de Casa com mais apoio (prestígio, membros adultos e simpatia das outras Casas) vira regente numa
  **cerimônia de posse na sede** (feito de verdade). Governante que morre ou vai embora é seguido pelo herdeiro.
- **Jeito do governante** (pela opinião dele sobre o fundador, na posse): leal, culto ao fundador, neutro ou
  inimigo; e, à parte, corrupto (traço ganancioso ou Casa que preza riqueza).
- **Decretos do fundador** (painel **P**, setas escolhem e mudam): imposto (nenhum/baixo/alto), ração
  (curta/normal/farta), guarda (livre ou 0 a 4) e obra preferida. Cada um tem efeito real: as Casas **levam o
  imposto à sede**, a ração muda quantas vezes se come, a guarda cresce com **convocados que vão à sede**, e a
  obra pedida é a primeira a ser feita. Mudar um decreto mexe na opinião de quem é afetado.
- **Governante NPC:** o corrupto sobe o imposto e **vai de madrugada ao armazém** levar estoque para a própria
  Casa (pode ser visto); sob culto, os devotos **rezam ao entardecer junto à bandeira**; o inimigo faz a opinião
  sobre o fundador cair enquanto ele está longe.
- **Volta do fundador:** leal e culto (e neutro, se o povo gosta do fundador) **caminham até a sede e devolvem o
  governo**. O inimigo não devolve: o fundador vira estrangeiro (não constrói, não demole, não doa ali).
- **Deposição:** governante odiado pelos chefes das Casas é deposto numa **reunião de madrugada perto da sede**
  (segredo com testemunhas: se alguém vê, a trama falha e a Casa do líder cai em desonra).
- O HUD mostra só "Governo: você / Nome" (é público); todo o resto vai para o log do ADM. O F10 ganhou a linha
  do governo (jeito, corrupção, decretos, quanto foi desviado).

**Captura orgânica** (nada encenado): o fundador pôs imposto baixo e guarda de 2 pelo painel
(`44_gov_panel`); dois moradores foram convocados; ele saiu e, 2 dias depois, Guiomar da Ponte tomou posse
(neutra e corrupta), subiu o imposto e desviou 10 do estoque de madrugada; as Casas levaram o imposto à sede
todo dia (`29_deed_tax`); na volta do fundador ela foi à sede e devolveu o governo (`30_deed_handover`,
`45_gov_return`).

**Revisão final (subagente):** corrigidos, com teste que falhava antes: o painel não segurava o jogador no
jogo real; com o fundador presente, um governante deposto ou morto devolvia o reino a ele sem perguntar ao povo
e pulava o herdeiro; reino podia ficar sem governante para sempre; trama contra um governante derrubava o
seguinte; devolução com o fundador já longe; Casa do governante desatualizada depois de uniões; imposto e reza
perdidos pulavam o dia; Esc não fechava o painel; nome de governante sumido travava a recusa.

**Pendências**
- A dispensa de guarda é imediata (exceção registrada à regra 17).
- Guardas não enfrentam o fundador estrangeiro; prisão, julgamento e guerra civil ficam para a etapa 9.
- Um convocado para a guarda pode virar regente e continuar guarda.
- Escândalo de desvio do governante pesa nas relações com o chefe da Casa dele, não com ele, se ele não for o
  chefe (pode atrasar uma deposição).

Suíte: 566 testes passando.


## Etapa 9 — Mundo vivo (2026-10-25)

**O que mudou**
- **Reinos NPC desde o começo:** todo mundo novo (e os saves antigos, uma vez) ganha 2 reinos NPC longe de onde o
  jogador surge: sede, bandeira, fogueira, fazenda, duas casas e duas famílias. O primeiro governante toma posse
  sozinho na sede. Eles crescem, recebem viajantes, formam Casas e vivem como o reino do jogador, fora da tela.
- **O jogador funda outros reinos:** uma Cabana longe de todas as sedes (160 m) funda mais um reino dele; perto de
  outra sede é só uma cabana (e o jogador é avisado). Renasce na sede dele mais perto.
- **Visitante em reino alheio:** não constrói nem demole lá; pode doar; não vê estoque nem moradores (só quem governa).
- **Diplomacia:** cada par de reinos tem relação e estado (paz ou guerra) que mudam todo dia por fronteira, pelo
  temperamento dos governantes, pelo comércio e pelo que o governante acha do jogador. Tudo por **enviados que
  andam de uma sede à outra**: declaração de guerra, proposta de paz e presente valem quando o enviado chega.
- **Guerra de verdade:** governante em atrito com um vizinho se arma (convoca a guarda toda); quem não é mais fraco
  declara guerra; **bandos de guerra marcham até a sede inimiga** e a batalha acontece quando chegam. Quem vence
  saqueia e queima uma construção (nunca a sede); os mortos morrem de verdade (com sucessão se era o governante).
  O cansaço leva à paz por enviado.
- **Novos reinos por êxodo:** Casa que odeia o governante, ou num reino lotado, parte para fundar um reino; o chefe
  anda até um lugar livre e, ao chegar, funda (com cônjuges e filhos de outras Casas junto).
- **Painel P:** no reino que governa, o jogador vê os reinos que já visitou (paz/guerra e relação) e manda um
  enviado com presente ou proposta de paz (Enter). F10 mostra as relações do reino com todos.

**Captura orgânica:** o mundo nasceu com os reinos NPC Ravmia e Casaria; o jogador fundou Seruvel longe deles; em 12
dias uma Casa de Ravmia partiu e fundou Velderia; a visita a Ravmia (`46_npc_realm`) mostra a vila com governante
próprio (Bento do Souto, 16 moradores). Não houve guerra nesses 12 dias.

**Simulação longa (`tests/visual/long_world.gd`, 60 dias, 3 mundos, sem janela):** 24 guerras declaradas, 22
pazes, 44 batalhas (7 vencidas pelos atacantes, com saque e fazendas ou comércio queimados), a primeira guerra
por volta do dia 29. Foi ela que achou o defeito de a guerra nunca vir (todos do mesmo tamanho e convocação que
só chamava guerreiros) e o de os defensores vencerem sempre.

**Revisão final (subagente):** corrigidos, com teste que falhava antes: nomes trocados (pai com nome de mulher)
nos reinos NPC; êxodo separando casais e filhos de Casas diferentes; declaração de guerra não conferida na chegada
(trégua, fundador de volta); convocação de guerra presa quando o fundador reassume; lugar do êxodo não conferido
de novo; painel abrindo numa linha que não existe; baixas sempre começando pelo líder.

**Pendências**
- O jogador não luta contra pessoas e reinos NPC não declaram guerra a reino que o jogador governa; não há
  cerco, vassalagem, tributo nem conquista.
- O log do ADM grava a mesma linha nos dois reinos de um evento entre reinos (aparece duas vezes no arquivo).
- A crônica guarda só as últimas 200 entradas por reino (eventos antigos de um reino movimentado somem).
- Bando de criaturas que não acha toca longe de todos os reinos fica onde está.
- `test_world::test_streams_while_walking` falha às vezes nesta máquina (quadro de ~51–55 ms contra 50 ms); já
  falhava igual no `main` da etapa 8, é a velocidade do computador.

Suíte: 600 testes passando.
