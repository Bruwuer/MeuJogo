# Design — Etapa 2: mundo com conteúdo

Data: 2026-10-23 · Status: decisões tomadas por Claude (o autor pediu "fluxo completo, faz tudo")
Base: `docs/superpowers/specs/2026-10-23-jogo-reino-vivo-design.md` (regras e visão continuam valendo).

## 1. Intenção

Na etapa 1 o mundo é um gramado vazio. A etapa 2 o deixa com cara de lugar: regiões diferentes,
árvores, pedras e arbustos, um sol que nasce e se põe, e as primeiras ações do jogador que mudam o
mundo de forma **permanente** (cortar uma árvore e ela continuar cortada quando ele volta). É a base
para a etapa 3 (construção), que vai gastar os recursos coletados aqui.

## 2. Escopo

**Dentro**
1. **Mapa maior:** de 8×8 para **24×24 chunks** (768×768 m), mais o anel visual.
2. **Biomas:** três regiões contínuas geradas por ruído: **Planície** (grama, árvores esparsas,
   arbustos), **Floresta** (densa, carvalhos e pinheiros) e **Pedregoso** (relevo mais alto, rochas,
   poucos pinheiros). As transições de cor e altura são suaves, sem degraus entre biomas.
3. **Vegetação e rochas:** quatro modelos low-poly feitos por script do Blender (`carvalho`,
   `pinheiro`, `rocha`, `arbusto` com frutinhas), espalhados por chunk de forma determinística (mesma
   semente = mesmo mundo), desenhados com **MultiMesh** (um draw por tipo por chunk). Árvores e rochas
   têm colisão; arbustos não.
4. **Coleta:** a tecla **E** perto de um objeto golpeia. Árvore: 4 golpes, dá 3 de madeira. Rocha:
   5 golpes, dá 2 de pedra. Arbusto: 1 golpe, dá 2 frutas. No último golpe o objeto some. O
   personagem vira para o alvo e toca a nova animação `work`, gerada no Blender.
5. **HUD simples (português):** contadores de Madeira, Pedra e Frutas; dica contextual
   ("[E] Cortar árvore", "[E] Quebrar rocha", "[E] Colher frutas"); relógio do dia ("Dia 2 · 14:30").
6. **Dia e noite:** ciclo completo de 8 minutos. O sol gira, e a cor e a intensidade da luz e do céu
   mudam. A noite fica azulada e escura, mas o jogador continua visível.
7. **Persistência delta:** só o que mudou é salvo (objetos removidos por chunk, recursos, posição do
   jogador, hora do dia), em binário (`store_var`) em `user://save.bin`. Salva a cada 60 s e ao fechar
   o jogo. Se existe save, o jogo continua de onde parou. `tools/new_world.ps1` apaga o save.

**Fora (vai para etapas futuras)**
- Inventário com slots e uso de itens (etapa 3).
- Água, rios, cavernas, estradas.
- Árvores crescendo de novo (regeneração).
- Menu de salvar/carregar e múltiplos saves (etapa 9).

**Anti-objetivos**
- Travadas ao andar por floresta densa (os objetos são gerados na mesma thread do terreno).
- Árvore cortada que reaparece ao voltar ao chunk.
- Jogador nascendo dentro de uma árvore ou rocha.
- Noite tão escura que não dá para jogar.

## 3. Decisões técnicas

| Tema | Decisão |
|---|---|
| Biomas | Segundo ruído de baixa frequência (`BIOME_NOISE_FREQ`) dá `b ∈ [-1,1]`: `b > 0.2` = Floresta, `b < -0.3` = Pedregoso, senão Planície. Altura multiplicada por `1 + ROCKY_HEIGHT_BOOST·rockiness` (rockiness = smoothstep sobre `b`) e cor do terreno misturada pelos mesmos pesos, o que garante continuidade |
| Enums | `GameConstants.Biome {PLAINS, FOREST, ROCKY}`, `GameConstants.Prop {OAK, PINE, ROCK, BUSH}`, `GameConstants.Res {WOOD, STONE, BERRIES}`. Tabelas de densidade, golpes e rendimento ficam em `GameConstants` |
| Espalhamento | `PropScatter` (thread-safe): grade de `PROP_CELL` m por chunk, uma tentativa por célula com posição aleatória dentro dela, RNG semeado por `hash([WORLD_SEED, c.x, c.y])`. Rola o tipo pela densidade do bioma; descarta onde a inclinação passa de `PROP_MAX_SLOPE_DEG` ou fora do chunk. Cada objeto ganha `id` = índice na lista (estável) |
| Modelos | `tools/blender/props.py <tipo> <saida>` gera `assets/models/{oak,pine,rock,bush}.glb`, cada um uma malha única (várias superfícies de material), origem na base, facetado |
| Carregamento | `PropLibrary` pede os 4 `.glb` com `ResourceLoader.load_threaded_request` no início. O mundo só começa a aplicar chunks quando as malhas estão prontas |
| Chunk | Passa a ser a classe `Chunk` (`scripts/world/chunk.gd`): terreno + um `MultiMeshInstance3D` por tipo + um `StaticBody3D` com uma `CollisionShape3D` por árvore/rocha. `remove_prop(id)` reconstrói o MultiMesh daquele tipo e remove a colisão |
| Estado do mundo | `WorldState` (RefCounted): `seed`, `removed: Dictionary[Vector2i, PackedInt32Array]`, `resources`, `player_position`, `time_of_day`, `day`. `save_to(path)` / `load_from(path)` binário com versão. O streamer filtra objetos removidos ao aplicar o chunk |
| Coleta | `HarvestSystem` (Node): acha o objeto colhível mais próximo dentro de `HARVEST_RANGE` nos chunks carregados, conta golpes por `(chunk,id)`, ao completar chama `chunk.remove_prop`, registra em `WorldState` e soma recursos. Golpe com cooldown `HARVEST_HIT_TIME`, durante o qual o jogador não anda |
| Dia/noite | `DayNight` (Node) com `time_of_day ∈ [0,1)` (0 = meia-noite, 0,5 = meio-dia), avança `delta / DAY_LENGTH_SEC`. Elevação do sol = `sin((t-0,25)·TAU)`; energia, cor do sol, cores do céu e luz ambiente interpoladas entre tabelas de dia, crepúsculo e noite em `GameConstants`. Piso de luz ambiente noturna `NIGHT_MIN_AMBIENT` |
| Spawn | `SpawnPicker.pick(gen, scatter, rng)` também rejeita pontos com árvore ou rocha a menos de `SPAWN_PROP_CLEARANCE` m |
| Save em testes | `World.save_path` (export). Testes e capturas usam caminho temporário ou vazio (= não salva) |

Carregar `save.bin` (poucos KB) no início, antes de o mundo ficar pronto, não fere a regra de
"nada síncrono durante o jogo": acontece antes de haver jogo.

## 4. Pronto quando

- Todos os testes headless passam: os anteriores ajustados ao mapa novo e os novos de biomas,
  espalhamento, chunk com objetos, coleta, persistência, dia/noite, HUD e spawn livre.
- As capturas com janela mostram floresta, planície e região pedregosa, coleta acontecendo, HUD
  legível, e a mesma cena de dia e de noite.
- O pior frame andando por floresta densa fica abaixo de `MAX_FRAME_MS`.
- CLAUDE.md atualizado (comandos novos e etapa 2 marcada como concluída).

## 5. Decisões após a revisão do design (Claude)

- **Semente por mundo:** cada mundo novo sorteia a própria semente, que fica salva em `WorldState.seed`.
  `World` lê o save **antes** de criar `TerrainGenerator`/`PropScatter`. `World.world_seed` (export,
  -1 = sorteia) permite fixar a semente em testes e capturas. `GameConstants.WORLD_SEED` passa a ser
  só a semente padrão dos testes.
- **Identidade dos objetos:** `id = j * cells + i`, o índice da célula da grade dentro do chunk. Fica
  estável quando as densidades mudam.
- **Versão da geração:** `GameConstants.WORLDGEN_VERSION` vai no save. Se o save tiver outra versão,
  os objetos removidos são descartados (com aviso no log), e recursos, posição, hora e semente são
  mantidos. Mexeu na geração? Suba a versão (regra registrada no CLAUDE.md).
