# Design — Jogo de reino vivo (nome provisório: MeuJogo)

Data: 2026-10-23 · Status: aprovado (com pipeline Blender adicionado pelo autor)

## 1. Intenção

Um jogo 2.5D de mundo aberto, medieval e com pé no chão, em que **o reino ganha vida própria**.
O jogador funda um pequeno reino, mas quem faz o reino crescer são as pessoas que chegam. Cada uma
tem nome, opinião, família e vontade própria. O jogador **não é o protagonista**, é só mais um
habitante do mundo. O mundo continua girando com ele ou sem ele.

Para o jogo dar certo, o jogador precisa voltar a um lugar que deixou e encontrar uma história
que ele não escreveu: um governante corrupto, um culto em sua homenagem, ruínas deixadas por
criaturas, uma família que virou inimiga.

## 2. O que o jogo é (definido pelo autor)

- **Começo:** o jogador surge num ponto aleatório do mapa.
- **Fundação:** constrói as primeiras estruturas a partir de modelos prontos. O custo em recursos é
  realista (madeira, pedra etc.). No começo o papel dele é fundar e proteger.
- **Pessoas:** viajantes chegam e decidem se querem ficar. Cada um tem nome e opinião própria.
  Formam famílias com brasão, podem sair de uma família e fundar outra. Os moradores constroem
  **sozinhos** casas, fazendas e comércios.
- **Ficar = governar:** se o jogador permanece, ele administra. As decisões dele impactam o reino
  para o bem ou para o mal. Aliados e inimigos surgem dentro do reino sem o jogador escolher.
- **Sair tem consequências:** se o jogador vai explorar, fundar outro reino ou visitar reinos que já
  existem, o reino anterior continua. Um morador pode assumir o governo e ser favorável ou contrário
  ao jogador, chegando a adorá-lo como deus ou a tratá-lo como inimigo mortal. O governante pode ser
  corrupto, enriquecendo enquanto o reino definha. O reino pode crescer ou ser destruído.
- **Mundo vivo:** reinos guerreiam entre si por conta própria.
- **Tom:** medieval com fantasia contida. Armas medievais (espada, arco, lança, escudo). Humanos são
  só humanos: sem magia, sem raças fantásticas jogáveis.
- **Criaturas:** o fantástico está nelas. O mundo já começa com animais reais (o lobo é o primeiro
  encontro) e criaturas que não existem. Elas são geradas de forma semi-aleatória, cruzam entre si e
  geram filhotes com características misturadas, além de brigar umas com as outras.

## 3. Objetivos, não-objetivos e anti-objetivos

**Objetivos**
- Simulação social com consequências reais e persistentes.
- Mundo aberto carregado em chunks, sem travadas.
- Tudo feito por código: personagens, criaturas e construções por scripts do Blender, terreno
  low-poly gerado na Godot. Sem assets externos.
- Desenvolvimento em etapas jogáveis, cada uma testada automaticamente.

**Não-objetivos (por agora)**
- Multiplayer.
- Magia, raças fantásticas humanoides.
- Modelos/texturas artísticos importados.
- Mundo realmente infinito (o mapa é grande, mas tem limite).

**Anti-objetivos (seria um fracasso mesmo funcionando)**
- O jogador virar o "escolhido" e o mundo girar em torno dele.
- Moradores que são só cenário, sem vontade própria.
- Travadas ao andar pelo mapa (carregamento síncrono).
- Mundo grande e vazio. Densidade importa mais que tamanho.

## 4. Stack e decisões técnicas

| Item | Decisão | Quem decidiu |
|---|---|---|
| Engine | Godot 4 (versão estável mais recente via winget), GDScript | autor |
| Visão | 2.5D isométrica: mundo 3D com câmera **ortográfica** fixa (yaw 45°, pitch -30°) | autor (iso) / Claude (ortográfica, ângulos) |
| Estilo | Low-poly flat-shaded, cores sólidas por material, sem texturas | autor |
| Personagens e objetos | **Modelados por scripts Python do Blender** em `tools/blender/`, low-poly, com rig e animações básicas (parado, andar, correr), exportados em `.glb` para `assets/models/`. Os `.glb` são gerados, nunca editados à mão: o script é a fonte | autor |
| Pipeline Blender | Scripts rodam sem interface (`blender -b --python tools/blender/<x>.py`), reproduzíveis por linha de comando. O Blender MCP fica configurado para inspeção e iteração interativa | autor (MCP) / Claude (modo sem interface como caminho oficial) |
| Criaturas | Peças separadas (corpo, cabeça, patas, cauda...) modeladas no Blender e combinadas na Godot por um "genoma", para permitir herança visual nos cruzamentos | autor (Blender) / Claude (peças + genoma) |
| Terreno | Continua gerado na Godot por código (é procedural e por chunk, não cabe num `.glb`) | Claude |
| Malha do terreno | Por chunk, gerada a partir de `FastNoiseLite`, faces planas | Claude |
| Streaming | Streamer próprio seguindo a skill `godot-genre-open-world`: geração em `WorkerThreadPool`, inserção na árvore via `call_deferred`, descarregamento com `queue_free` | Claude |
| Persistência (etapas futuras) | Delta por chunk em binário (`store_var`) | Claude (padrão da skill) |
| Testes | Runner próprio mínimo em GDScript (`godot --headless -s tests/run_tests.gd`), sem dependências | Claude |
| Controle de versão | git na raiz `D:\MeuJogo` | autor |

### Avaliação dos addons

| Addon | Avaliação | Decisão |
|---|---|---|
| **Chunk-Loader** (LittleFernStudio) | Feito para 2D (TileMapLayer), conteúdo autorado, 7 estrelas, sem releases, sem carregamento em thread | **Não instalar** |
| **Godot-Open-World-Database** (DigitallyTailored) | Maduro (≈400 estrelas, MIT, ativo). Pensado para objetos **posicionados no editor**, salvos num `.owdb`. Nosso mundo é procedural. O próprio README avisa sobre deleção inesperada de nós | **Não instalar agora.** Reavaliar se surgirem regiões feitas à mão (ex.: ruínas fixas) |
| **Terrain3D** (TokisanGames) | Excelente (≈4,4k estrelas, C++/GDExtension). Feito para terreno suave esculpido em heightmap, que é o oposto do visual low-poly facetado. Adiciona um binário nativo ao projeto | **Não instalar agora.** Reavaliar se o mapa crescer a ponto de a malha própria pesar |

Conclusão: na etapa 1 nenhum addon entra. O streaming próprio é pequeno, testável e segue a skill.

## 5. Regras do projeto (vão para o CLAUDE.md)

1. **Mundo carregado por chunks.** Nada de cena única gigante.
2. **Nada de carregamento síncrono** durante o jogo: geração/carga em thread (`WorkerThreadPool` ou
   `ResourceLoader.load_threaded_request`), aplicação na árvore no thread principal.
3. **Constantes num arquivo único:** `scripts/core/game_constants.gd` (`class_name GameConstants`).
   Nenhum número mágico de gameplay espalhado.
4. **Testes automáticos em modo headless antes de declarar algo pronto.** Todos devem passar e a
   saída deve ser conferida.
5. Tudo gerado por código, sem assets externos. Personagens e objetos vêm de scripts Python do
   Blender em `tools/blender/` (low-poly, com rig e animações parado/andar/correr), exportados em
   `.glb`. Para mudar um modelo, edite o script e regenere, nunca o `.glb`.
6. Código e comentários em inglês. Documentação e textos do jogo em português.
7. Commits pequenos por funcionalidade.

## 6. Estrutura de pastas

```
D:\MeuJogo\
  project.godot
  CLAUDE.md
  docs/superpowers/specs/      # documentos de design
  scenes/                      # main.tscn e cenas mínimas
  assets/models/               # .glb gerados pelo Blender (não editar à mão)
  scripts/
    core/                      # game_constants.gd, utilitários
    world/                     # chunk_streamer.gd, terrain_generator.gd, world.gd
    actors/                    # player.gd (usa o .glb e o AnimationPlayer dele)
    camera/                    # iso_camera.gd
  tests/
    run_tests.gd               # runner headless
    unit/                      # test_*.gd
    integration/               # test_*.gd (carregam a cena principal)
  tools/
    blender/                   # scripts Python do Blender (um por modelo + utilitários comuns)
    *.ps1                      # rodar testes, gerar modelos, captura de tela
  .claude/skills, .agents/     # skills do projeto
```

## 7. Etapa 1: primeira versão jogável (escopo exato)

- **Mapa pequeno:** 8×8 chunks de 32×32 m (256×256 m), terreno low-poly com morros suaves, gerado
  por semente. Mesmo pequeno, ele já é carregado por chunks num raio ao redor do jogador, em thread,
  para provar a regra desde o primeiro dia. Bordas com limite invisível.
- **Personagem:** humanoide low-poly modelado por script do Blender (`tools/blender/humanoid.py`),
  com armature e as animações `idle`, `walk` e `run`, exportado em `assets/models/humanoid.glb`.
  Anda com **WASD relativo à tela** (W = para cima na tela), corre segurando **Shift**, gira para a
  direção do movimento, troca de animação conforme a velocidade, tem gravidade e acompanha o relevo.
- **Spawn aleatório** em ponto válido do mapa (semente configurável).
- **Câmera isométrica** ortográfica seguindo o jogador com suavização.
- Luz direcional com sombra e céu simples.

**Testes da etapa 1**
- Pipeline: o script do Blender roda sem interface e gera o `.glb`; a Godot importa o arquivo, e o
  teste confere que existem `Skeleton3D` e as três animações.
- Unitários: sanidade das constantes; conversão mundo↔chunk; determinismo do terreno (mesma semente
  = mesma altura); mapeamento WASD→direção no mundo de acordo com o ângulo da câmera; spawn
  sempre dentro do mapa.
- Integração (headless): cena principal carrega; chunks ao redor do jogador aparecem de forma
  assíncrona e os distantes são descarregados; simular W por N frames move o jogador na direção
  esperada sem atravessar o terreno; câmera acompanha; nenhum frame bloqueado acima do limite
  definido nas constantes durante o streaming.
- **Visual:** execução com janela gerando capturas de tela (andando em direções diferentes), que
  serão mostradas ao autor.

**Pronto =** todos os testes passam em headless, as capturas mostram o personagem no terreno com a
câmera isométrica, e o resultado está commitado.

## 8. Roadmap

1. **Fundação jogável:** mapa, personagem, câmera, chunks, testes (seção 7).
2. **Mundo com conteúdo:** biomas, árvores/pedras/arbustos com MultiMesh, recursos coletáveis,
   ciclo dia/noite, mapa maior, persistência delta por chunk.
3. **Construção:** inventário, coleta de recursos, construções pré-feitas com custo realista,
   posicionamento em grade, fundação do reino.
4. **Criaturas e combate:** gerador de criaturas por genoma de peças (animais reais + inventadas),
   comportamento (caçar, fugir, território), cruzamento com herança, brigas entre espécies, armas
   medievais e combate do jogador, criaturas atacando o reino.
5. **Pessoas:** gerador de pessoas (nome, traços, opinião), chegada de viajantes e decisão de ficar,
   necessidades, construção autônoma de casas, fazendas e comércios.
6. **Sociedade:** famílias e brasões gerados, relações, opinião sobre o jogador, aliados e inimigos
   internos, rompimentos e novas famílias.
7. **Governo:** decisões do jogador com efeitos no reino, sucessão quando o jogador sai, governante
   NPC com personalidade (corrupção, lealdade), culto ao jogador ou inimizade.
8. **Mundo vivo:** reinos de NPC já existentes, simulação resumida de reinos fora da tela,
   diplomacia e guerras entre reinos, fundar novos reinos.
9. **Polimento:** menu, salvar/carregar, som gerado, balanceamento.

Cada etapa recebe seu próprio documento curto de design antes de ser construída.

**Decisões da etapa 1 tomadas por Claude (após revisão)**
- **Borda do mapa:** um anel de 1 chunk só visual (sem colisão de gameplay) em volta das 8×8 jogáveis,
  para o horizonte não terminar num corte seco. O limite invisível fica na borda jogável.
- **Spawn válido:** dentro do mapa jogável, a uma distância mínima da borda e num terreno com
  inclinação máxima definida. Todos os limites ficam em `GameConstants`.
- **Teste de "frame travado":** mede o tempo de cada frame no teste headless contra um limite em
  `GameConstants`. A rodada com janela (capturas) também registra o pior frame.

## 9. Deixado para quem construir

- Detalhes de implementação do streamer, formato da malha, nomes de classes.
- Paleta de cores exata e proporções do humanoide.
- Valores numéricos (velocidade, raio de carregamento, suavização da câmera), desde que estejam em
  `GameConstants`.
