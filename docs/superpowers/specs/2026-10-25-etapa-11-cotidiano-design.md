# Etapa 11 — Cotidiano (design)

Data: 2026-10-25 · Status: feito na noite de carta branca do autor (cada decisão vai como `Ruling:`)

## 1. Intenção

Continuação do pedido do autor para a etapa 10 ("novas possibilidades para o mundo vivo, novas estéticas, novas
animações, necessidades... tudo deve ocorrer"): a vida de todo dia também acontece de verdade, com animação.

## 2. Escopo

- **Refeições de verdade:** quem está na tela come nas horas de refeição (7h, 12h, 19h) **sentado em roda da
  fogueira** (`eat`); a comida sai do estoque quando a pessoa termina. Fora da tela, a refeição continua resumida.
- **Noite na fogueira:** às 19h, adulto que sente falta de companhia **senta à fogueira** (`sit`) e conversa; sai com
  a companhia em dia.
- **Crianças brincam** (`play`) perto de casa às 10h, 14h e 16h.
- **Chuva:** alguns dias chove (sorteio semeado por dia): as pessoas vão para baixo de um teto, o trabalho das
  fazendas resumido rende menos, o céu fica cinza, a luz cai e gotas caem em volta do jogador.
- **Fofoca:** ao conversar, cada um puxa um pouco a opinião do outro sobre o fundador e passa a não gostar de quem
  o outro odeia.

## 3. Decisões

- **Ruling:** a refeição na tela é um feito do `LifeSim` (`meal`); o `VillageSim` não alimenta mais quem tem nó, a
  não ser com fome de `HUNGER_STARVING` (ninguém morre esperando a ceia). Para o contentamento, quem está na tela
  conta como alimentado até essa fome.
- **Ruling:** chuva é o tempo do mundo (o jogador vê, não é evento de reino); `WeatherSim` decide às 6h; o estado
  (`rain_from`, `rain_until`) vai no save.
- **Ruling:** as gotas são um efeito feito por código (`GPUParticles3D` com um quad esticado), não um modelo; a regra
  dos modelos do Blender vale para objetos e personagens.
- **Ruling:** fogueira, refeição e brincadeira só vão para quem está livre e nunca substituem outro feito.

## 4. Revisão final: correções

- **Ruling (ceia e fogueira):** a fogueira é às 20h, depois da ceia das 19h (antes quase ninguém chegava à fogueira,
  porque a fome das 19h ganhava). A fome para ir comer baixou para 0,2 (a refeição do meio-dia também acontece).
- **Ruling (comida em dobro):** a refeição só alimenta quem ainda está com fome (uma refeição resumida antes conta).
- **Ruling (ração na tela):** a refeição segue o decreto de ração; "alimentado", na tela, é não passar da fome da ração
  e ter comida no estoque.
- **Ruling (guardas):** na chuva os guardas continuam de vigia.
- **Ruling (chuva):** ninguém brinca nem vai à fogueira debaixo de chuva; o trabalho resumido usa a hora simulada.
- **Ruling (fofoca):** nunca vira a pessoa contra o próprio cônjuge ou parente próximo.
