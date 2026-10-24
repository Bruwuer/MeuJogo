# Design — Etapa 4: criaturas e combate

Data: 2026-10-24 · Status: decisões tomadas por Claude (autor: "faz tudo", "me entrega todas as partes")
Base: `2026-10-23-jogo-reino-vivo-design.md` e designs das etapas 2 e 3.

## 1. Intenção

O autor descreveu as criaturas como o lado fantástico do mundo: o mundo já começa com animais
reais (o lobo é o primeiro encontro) e com criaturas inventadas. Elas são geradas de forma
semi-aleatória, cruzam e têm filhotes com características misturadas, além de brigar entre si.
Nesta etapa o jogador também ganha como se defender (armas medievais), e as criaturas passam a
ser uma ameaça ao reino.

## 2. Escopo

**Dentro**
1. **Genoma:** cada criatura carrega genes que definem:
   - **corpo:** tamanho, tipo de corpo, cabeça, patas, cauda, extra (chifres, espinhos, juba) e duas cores;
   - **comportamento:** dieta (herbívora/carnívora), agressividade, tamanho de bando, velocidade, vida,
     dano, alcance de percepção e se é noturna.
2. **Espécies iniciais (8):**
   - **Animais reais:** Lobo, Urso, Javali e Cervo.
   - **Inventadas:** Espinhudo (lagarto robusto com espinhos), Chifrudo (herbívoro grande com chifres
     enormes), Rastejante (réptil comprido e noturno) e Uivante (lobo pálido de juba, noturno, em bando).
   Cada espécie é um modelo de genoma com faixas de variação, e dois lobos nunca saem idênticos.
3. **Corpo por peças:** o Blender gera uma **biblioteca de peças** (corpos, cabeças, patas, caudas e
   extras), cada uma com o ponto de encaixe na origem. A Godot monta a criatura a partir do genoma
   e a anima por código: parado, andar e correr, com as patas balançando, o corpo subindo e descendo
   e a cauda e a cabeça mexendo. É isso que permite um filhote herdar a cabeça de um pai e o corpo
   do outro.
4. **Cruzamento:** dois adultos compatíveis (mesma espécie, ou espécies próximas com chance menor)
   que se encontram calmos e saciados podem ter um filhote:
   - cada gene vem de um dos pais, e há pequena chance de mutação;
   - o filhote nasce pequeno e cresce com o tempo;
   - um híbrido recebe nome composto ("Lobo-javali").
   Há limite de população perto do jogador.
5. **Ecossistema e comportamento** (máquina de estados): vagar, pastar ou caçar, fugir, atacar, seguir o
   bando, dormir (de dia para as noturnas, à noite para as outras) e cruzar.
   - **Carnívoros:** caçam herbívoros e brigam por território com outros carnívoros quando a
     agressividade é alta.
   - **Herbívoros:** fogem.
6. **Combate do jogador** com três armas medievais, que ele já carrega:
   | Arma | Uso |
   |---|---|
   | Espada | golpe em arco curto na frente, rápido |
   | Lança | alcance maior, mais lenta |
   | Arco | flechas com gravidade; **F** fabrica 5 flechas com 1 madeira |
   - **Controles (só teclado, pedido do autor):** fora do modo construção, **1/2/3** escolhem a arma e
     **Q** troca para a próxima; **Espaço** ataca na direção em que o personagem está virado. Sem mira
     automática e sem mouse: quem mira é o jogador, virando o personagem com WASD.
   - **Vida:** o jogador tem 100 de vida, que regenera devagar; **H** come 1 fruta e recupera 15.
   - **Morte:** ele renasce na cabana-sede (ou no ponto inicial) sem perder recursos e com aviso no HUD.
7. **Ameaça ao reino:**
   - **Ataque noturno:** à noite, carnívoros agressivos perto do território podem formar um ataque e
     ir em direção às construções.
   - **Dano às construções:** cada construção tem vida e é destruída ao chegar a zero, sem reembolso.
   - **Aviso:** o HUD avisa ("Lobos atacam o Reino de X!", "Uma Cerca foi destruída").
   - **Sede:** a cabana-sede não é destruída; fica com vida 1, para não acabar com o reino nesta etapa.
8. **Persistência:** criaturas vivas (genoma, posição, vida, idade) e a vida das construções vão para o
   `WorldState`. Criaturas longe do jogador (fora dos chunks carregados) ficam congeladas e escondidas,
   e voltam ao ser carregadas. A população inicial de cada chunk nasce uma única vez, de forma
   determinística por semente e bioma, quando o chunk é visitado pela primeira vez.

**Fora (etapas futuras)**
- Pessoas lutando ou caçando (etapa 5), domesticação e montaria.
- Simulação de criaturas fora da tela (etapa 8, mundo vivo).
- Criaturas que voam ou nadam.

**Anti-objetivos**
- Criaturas idênticas, ou que parecem quebradas (peças soltas, patas atravessando o chão).
- Travadas com muitas criaturas: só as que estão perto pensam e se movem.
- Morte frustrante: o jogador nunca perde a construção nem os recursos ao morrer.

## 3. Decisões técnicas

| Tema | Decisão |
|---|---|
| Regra do rig | As criaturas são montadas em runtime a partir de peças do Blender, e o "rig" é a hierarquia de nós: as patas giram no quadril. As animações parado/andar/correr são procedurais. Exceção registrada no CLAUDE.md: o genoma exige montar e misturar peças em runtime, o que não cabe numa animação exportada |
| Genoma | `Genome` (RefCounted) ↔ `Dictionary` (persistível). `Genome.random(species, rng)`, `Genome.cross(a, b, rng)` e `Genome.compatibility(a, b)`. Os dados das espécies ficam em `GameConstants.SPECIES` |
| Peças | `tools/blender/creature_parts.py -- <part> <out>`, com `assets/models/parts/<part>.glb`. Encaixes por convenção: corpo com origem no centro do tronco, cabeça/cauda/patas com origem no ponto de encaixe. Os pontos de encaixe de cada corpo ficam numa tabela em `GameConstants.BODY_SOCKETS` |
| Criatura | `Creature` (CharacterBody3D, camada `LAYER_CREATURES`): `CreatureBody` monta as peças e anima, `CreatureBrain` cuida dos estados. A navegação é direta no terreno, com desvio simples de obstáculos por raios, sem NavMesh, para não travar |
| Gestão | `CreatureManager` (Node): cria e remove criaturas conforme os chunks carregam e descarregam, cuida do ciclo do mundo, do cruzamento, do teto de população e dos ataques noturnos, e repassa o estado ao `WorldState` |
| Combate | `Combat` estático: dano, empurrão, arcos e alcances. `Weapon` com dados em `GameConstants.WEAPONS`, `Arrow` como projétil com gravidade. A vida do jogador e dos bichos fica num componente `Health` |
| Carregamento | As peças entram na fila do `ModelLibrary`, que continua sendo o único carregador |
| Desempenho | Criaturas só pensam e se movem dentro dos chunks carregados. Teto `CREATURE_MAX_ACTIVE` (40). O cérebro de cada uma roda a cada `BRAIN_TICK` (0,2 s), e o movimento a cada frame de física |

## 4. Pronto quando

- **Testes headless** cobrindo:
  - genoma: geração com faixas, cruzamento com herança de peças, mutação, compatibilidade e nome de híbrido;
  - montagem do corpo (peças encaixadas, patas no chão);
  - estados do cérebro (fuga, caça, ataque, sono, cruzamento);
  - armas (alcance, dano, flecha com gravidade, fabricação de flechas);
  - vida, regeneração, comer, morte e renascer;
  - ataque noturno e destruição de construções (sede protegida);
  - persistência e congelamento fora dos chunks;
  - teto de população e orçamento de frame com 40 criaturas.
- **Capturas com janela:** um lobo, a galeria das 8 espécies, um híbrido com o pai e a mãe, o jogador
  lutando de espada e de arco, e um ataque noturno ao povoado.

## 5. Decisões após pedido do autor (2026-10-24)

- **Combate só por tecla:** Espaço ataca, 1/2/3 ou Q trocam a arma, F faz flechas, H come. O ataque
  vai sempre na direção para onde o personagem olha (a última direção de movimento). Não há mira
  automática nem uso do mouse no combate.
- **Construção também funciona só com teclado:** o fantasma fica à frente do personagem; o mouse
  passa a ser opcional (só segue o cursor se ele se mexer sobre a janela) — ajuste em `BuildSystem`.

## 6. Ameaça ao reino com motivos (pedido do autor, 2026-10-24)

"À noite não atacam o reino assim simples, deve ter motivos." Substitui o item 7 da seção 2:

- Cada **bando** (grupo da mesma espécie com um líder) tem uma **toca** (centro de território,
  raio `TERRITORY_RADIUS`) e quatro **motivos** de 0 a 1, guardados no save:
  - **Fome:** sobe com o tempo e desce ao comer. Desce devagar se a região tem pouca caça (poucos
    herbívoros vivos num raio). Bando faminto se arrisca perto de pessoas e é atraído por comida
    guardada (frutas do jogador, depósitos do reino).
  - **Território:** o quanto o reino invade a área da toca (construções dentro do raio).
  - **Rancor:** sobe quando o jogador mata ou fere membros do bando (mais com filhotes); cai devagar
    com os dias.
  - **Defesa dos filhotes:** dispara forte quando o jogador chega perto da toca com filhotes.
- **Decisão de atacar:** combinação ponderada dos motivos × agressividade da espécie, só para
  carnívoros ou espécies territoriais. A noite e o sono só mudam *quando* agem (predadores noturnos
  e a maioria dos carnívoros saem à noite). Sem motivo acima do limiar, não há ataque.
- O HUD anuncia o **motivo dominante**: "Lobos famintos rondam o Reino de X: a caça acabou na
  região", "Os ursos defendem seu território: o reino foi erguido perto da toca", "A alcateia quer
  vingança pelos lobos mortos", "Javalis furiosos protegem os filhotes".
- O jogador pode **evitar** ataques: preservar a caça, não construir perto de tocas, não provocar
  bandos, alimentar a fome deles longe do reino (caçando para eles não é necessário nesta etapa).
- Construções têm vida; a cabana-sede não cai abaixo de 1 nesta etapa. Bandos que satisfazem o
  motivo (comeram, afastaram o invasor, mataram o alvo do rancor) voltam para a toca.
