# MeuJogo — reino vivo (nome provisório)

## Visão do jogo

Jogo 2.5D de mundo aberto, medieval com fantasia contida, em vista isométrica e estilo low-poly.
O jogador surge num ponto aleatório do mapa e funda um pequeno reino com construções pré-feitas,
que custam recursos de forma realista. Quem faz o reino crescer são as **pessoas**: viajantes
com nome e opinião próprios chegam e decidem se ficam, constroem sozinhos casas, fazendas e
comércios, formam famílias com brasões e rompem com elas.

O jogador **não é protagonista**, é só mais um no mundo. Se fica, governa: as decisões dele
têm consequências, e aliados e inimigos surgem dentro do reino sem que ele escolha. Se sai para
explorar ou fundar outro reino, um morador pode assumir o governo, adorar o jogador como deus ou
tratá-lo como inimigo mortal, ser corrupto e por aí vai. Reinos guerreiam entre si sozinhos, e
o mundo gira com ou sem o jogador.

Humanos são só humanos: sem magia, com armas medievais. O fantástico fica nas **criaturas**:
animais reais (o lobo é o primeiro encontro) e criaturas inventadas, geradas de forma
semi-aleatória, que cruzam, geram filhotes com características misturadas e brigam entre si.

Design completo: `docs/superpowers/specs/2026-10-23-jogo-reino-vivo-design.md`.

## Stack

- **Godot 4.7** (GDScript), renderer Forward+, câmera **ortográfica** isométrica (yaw 45°, pitch -30°).
- **Blender 5.2** + Python (`bpy`) para modelar personagens e objetos por script.
- Blender MCP configurado no projeto (`claude mcp add blender uvx blender-mcp`) para inspeção
  interativa. O servidor sobe quando o Blender é aberto com interface.
- Skills: `godot` (plugin awesome-gamedev-agent-skills) e `godot-genre-open-world` (em `.agents/skills`).
- Addons avaliados e **não instalados** (Chunk-Loader, Open-World-Database, Terrain3D). Os motivos
  estão no design, §4.

## Estrutura de pastas

```
project.godot
assets/models/        .glb gerados pelo Blender (NUNCA editar à mão)
scripts/core/         game_constants.gd (todas as constantes)
scripts/world/        chunks, terreno, spawn, cena do mundo
scripts/actors/       jogador e entrada
scripts/camera/       câmera isométrica
scripts/ui/           HUD
shaders/              prop_occlusion.gdshader (árvores/rochas somem na frente do jogador)
scenes/               main.tscn, player.tscn
tests/                run_tests.gd, game_test.gd, unit/, integration/, visual/
tools/                godot.ps1, run_tests.ps1, build_models.ps1, capture.ps1, new_world.ps1
tools/blender/        scripts Python do Blender (um por modelo + common.py)
docs/superpowers/     specs/ e plans/
```

## Regras

1. **O mundo é carregado por chunks.** Nada de cena única gigante.
2. **Nada de carregamento síncrono** durante o jogo. Geração e carga rodam em thread
   (`WorkerThreadPool` ou `ResourceLoader.load_threaded_request`), e só o thread principal mexe
   na SceneTree (`call_deferred`).
3. **Constantes num arquivo único:** `scripts/core/game_constants.gd` (`GameConstants`).
   Nenhum número de gameplay solto no código.
4. **Testes automáticos em headless antes de dar algo como pronto.** Rode
   `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`, leia a saída e confira `RESULT: N passed, 0 failed` com exit 0.
   TDD: teste falhando primeiro.
5. **Personagens e objetos são modelados por scripts Python do Blender** em `tools/blender/`:
   low-poly, com rig e animações básicas (`idle`, `walk`, `run`), exportados em `.glb` para
   `assets/models/`. Para mudar um modelo, edite o script e rode `powershell -ExecutionPolicy Bypass -File tools/build_models.ps1`.
   Nunca edite o `.glb`. O terreno é gerado na Godot por código.
6. Sem assets externos. As integrações de assets do Blender MCP (PolyHaven, Sketchfab etc.) ficam desligadas.
7. Código e comentários em inglês. Documentação e textos do jogo em português.
8. Commits pequenos, um por funcionalidade. Cada etapa do roadmap ganha um design curto antes.
9. **Mexeu na geração do mundo** (terreno, biomas, densidades, `PROP_CELL`, inclinação)? Suba
   `GameConstants.WORLDGEN_VERSION`. Isso invalida só a lista de objetos removidos dos saves antigos.
10. Testes e capturas nunca usam o save real: `World.save_path = ""` e `world_seed` fixo.
11. Camadas de física: `LAYER_TERRAIN` (chão) e `LAYER_OBSTACLES` (árvores, rochas, construções). Raios de
    posicionamento usam só o chão; o jogador colide com as duas.
12. Só existe UM carregador de modelos (`ModelLibrary`, sequencial): cargas paralelas causam corrida no renderizador.

## Comandos

- Testes: `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 [filtro]`
- Gerar modelos: `powershell -ExecutionPolicy Bypass -File tools/build_models.ps1`
- Capturas de tela: `powershell -ExecutionPolicy Bypass -File tools/capture.ps1` (saem em `captures/`)
- Abrir o editor: `powershell -ExecutionPolicy Bypass -File tools/godot.ps1 -e`
- Começar um mundo novo (apaga o save): `powershell -ExecutionPolicy Bypass -File tools/new_world.ps1`
- Controles: WASD anda, Shift corre, E coleta (árvore 4 golpes = 3 madeira, rocha 5 = 2 pedra, arbusto 1 = 2 frutas)
- Construção: B liga/desliga, 1–5 escolhe (Cabana, Fogueira, Depósito, Cerca, Poço), R gira, clique ou E constrói,
  Esc ou clique direito sai; X demole (devolve 50 %). A primeira Cabana funda o reino.

## Roadmap

1. ✅ **Fundação jogável:** mapa pequeno em chunks, humanoide do Blender com WASD e Shift para
   correr, câmera isométrica seguindo, testes.
2. ✅ **Mundo com conteúdo:** biomas, árvores, pedras e arbustos (MultiMesh), recursos coletáveis,
   dia e noite, mapa maior, persistência delta por chunk.
3. ✅ **Construção:** inventário, coleta, construções pré-feitas com custo realista, fundação do reino.
4. **Criaturas e combate:** genoma de peças (animais reais + inventadas), comportamento, cruzamento
   com herança, brigas entre espécies, armas medievais, ataques ao reino.
5. **Pessoas:** gerador de pessoas (nome, traços, opinião), chegada e decisão de ficar,
   necessidades, construção autônoma.
6. **Sociedade:** famílias e brasões, relações, opinião sobre o jogador, aliados e inimigos internos.
7. **Governo:** decisões com efeito, sucessão, governante NPC (corrupção, lealdade, culto ou inimizade).
8. **Mundo vivo:** reinos NPC, simulação resumida fora da tela, diplomacia e guerras, novos reinos.
9. **Polimento:** menu, salvar/carregar, som, balanceamento.
