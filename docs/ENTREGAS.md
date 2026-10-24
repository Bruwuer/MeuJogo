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
