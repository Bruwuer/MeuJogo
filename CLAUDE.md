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
scripts/combat/       vida, armas (Combat), flechas
scripts/creatures/    genoma, corpo por peças, cérebro, criatura, bandos (motivos, PackSim), gerenciador
scripts/people/       PersonGen, VillageRules, VillageSim (horário), Person + PersonBrain, PeopleManager,
                      Crest (brasões), SocietyRules + SocietySim (famílias, relações, opinião)
scripts/camera/       câmera isométrica
scripts/ui/           HUD
shaders/              prop_occlusion.gdshader (árvores/rochas somem na frente do jogador)
scenes/               main.tscn, player.tscn
tests/                run_tests.gd, game_test.gd, unit/, integration/, visual/
tools/                godot.ps1, run_tests.ps1, build_models.ps1, capture.ps1, new_world.ps1
tools/blender/        scripts Python do Blender (um por modelo + common.py; creature_parts.py e weapons.py)
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
   **Exceção registrada (etapa 4):** criaturas são montadas em runtime a partir de peças do Blender
   (`assets/models/parts/`) escolhidas pelo genoma, e o "rig" é a hierarquia de nós; parado, andar e
   correr são animados por código (`CreatureBody`). O genoma exige misturar peças de pais diferentes.
6. Sem assets externos. As integrações de assets do Blender MCP (PolyHaven, Sketchfab etc.) ficam desligadas.
7. Código e comentários em inglês. Documentação e textos do jogo em português.
8. Commits pequenos, um por funcionalidade. Cada etapa do roadmap ganha um design curto antes.
9. **Mexeu na geração do mundo** (terreno, biomas, densidades, `PROP_CELL`, inclinação)? Suba
   `GameConstants.WORLDGEN_VERSION`. Isso invalida só a lista de objetos removidos dos saves antigos.
10. Testes e capturas nunca usam o save real: `World.save_path = ""` e `world_seed` fixo.
11. Camadas de física: `LAYER_TERRAIN` (chão) e `LAYER_OBSTACLES` (árvores, rochas, construções). Raios de
    posicionamento usam só o chão; o jogador colide com as duas.
12. Só existe UM carregador de modelos (`ModelLibrary`, sequencial): cargas paralelas causam corrida no renderizador.
13. Criaturas: registros em `WorldState`; só têm nó dentro dos chunks carregados (teto `CREATURE_MAX_ACTIVE`).
    Ataques ao reino só por motivo do bando (fome, território, rancor, filhotes), nunca "porque é noite".
14. Pessoas: registros em `WorldState` (como as criaturas); só têm nó nos chunks carregados (teto `PEOPLE_MAX_ACTIVE`).
    Quem tem nó trabalha de verdade; quem não tem é resumido pelo `VillageSim` (sem trabalho em dobro).
    O reino tem estoque próprio. Construções dos moradores (dono >= 0 ou `OWNER_KINGDOM`) não são demolidas pelo jogador.
15. Sociedade: famílias (`WorldState` famílias + relações simétricas por par) são só registros e rodam no
    `SocietySim`, chamado pelo `VillageSim` a cada hora para todos os reinos (sorteios semeados por semente,
    reino e hora). Brasões são desenhados por código (`Crest`, imagem 32 × 40); o estandarte do Blender
    (`crest_banner`) recebe a textura e fica no canto da casa que a câmera vê. Crianças não trabalham, não
    casam e nunca vão embora sozinhas.
16. **O jogador não sabe de tudo.** Nenhum evento do reino vai para o HUD (viajantes, nascimentos, casamentos,
    mortes, ataques, intrigas). Tudo vai para a crônica (`WorldState.chronicle_add`, segredos com
    `public = false`) e para o log do ADM (`AdminLog`, `user://adm_log.txt`). O HUD só mostra o que é do
    jogador. Painéis do ADM: F9 (crônica com segredos) e F10 (Casas), fora da dica de teclas.
17. **Decisões das Casas acontecem de verdade.** Viram um feito (`person.deed`, ver `Deeds`): a pessoa anda até
    o lugar numa janela de horas e trabalha ali; só então o efeito acontece (`HouseSim.complete_deed`). Sem nó,
    o feito é resumido na hora em que começa. Segredos só vêm à tona por testemunhas (adultos acordados de fora
    da Casa, perto do feito; fora da tela, sorteio por quem está acordado). Casamento e filhos só entre homem e
    mulher; romance do mesmo sexo é segredo malvisto (escândalo se descoberto).

18. **Governo:** cada reino tem `ruler_id` (`GOV_PLAYER` = o fundador, `GOV_NOBODY` = sucessão em curso, ou um
    morador). `GovRules` (puro) e `GovSim` (por hora, depois do `HouseSim`) cuidam de posse, decretos, volta do
    fundador e deposição; tudo que muda o reino é feito de uma pessoa (posse, devolução, imposto, convocação, reza,
    deposição, desvio do governante). O HUD só mostra quem governa e o painel P do próprio fundador.

19. **Vários reinos:** reino tem `founder` ("player" ou "npc"). O jogador só constrói, decreta e reassume nos
    reinos dele. Relações entre reinos ficam em `WorldState.realm(a, b)` e mudam uma vez por dia no `RealmSim`
    (depois de todos os reinos, por hora); guerra, paz, presente, bando de guerra e êxodo são feitos de pessoas que
    andam de uma sede à outra. Nada disso vai para o HUD. Balanceamento: `tests/visual/long_world.gd` (60 dias sem janela).

20. **Vida:** quem morre vira corpo (`status = "dead"`) até ser enterrado; tudo que o `LifeSim` e o `MerchantSim` fazem
    é feito de uma pessoa com a animação do ato (`deed.anim`). Clipes novos vêm do `tools/blender/humanoid.py`;
    `tools/build_models.ps1 -Only nome` gera só os modelos pedidos. Verificação visual: `tests/visual/poses.gd` e
    `tests/visual/life_watch.gd`.

## Comandos

- Testes: `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 [filtro]`
- Gerar modelos: `powershell -ExecutionPolicy Bypass -File tools/build_models.ps1`
- Capturas de tela: `powershell -ExecutionPolicy Bypass -File tools/capture.ps1` (saem em `captures/`, inclui a galeria de criaturas)
- Abrir o editor: `powershell -ExecutionPolicy Bypass -File tools/godot.ps1 -e`
- Começar um mundo novo (apaga o save): `powershell -ExecutionPolicy Bypass -File tools/new_world.ps1`
- Controles: WASD anda, Shift corre, E fala com quem está perto (cartão com família, brasão e relações) ou coleta (árvore 4 golpes = 3 madeira,
  rocha 5 = 2 pedra, arbusto 1 = 2 frutas), G doa ao reino (até 10 de madeira, pedra e frutas).
  P abre o governo (setas escolhem e mudam os decretos: imposto, ração, guarda, obra; nos reinos já visitados
  escolhem presente ou proposta de paz e Enter manda o enviado; P ou Esc fecha).
  Perto de um mercador: Z compra pão, C compra flechas, V vende madeira (H come pão antes de fruta).
  Só para o ADM (desenvolvimento): F9 crônica do reino com segredos, F10 Casas do reino (e a linha do governo)
- Construção: B liga/desliga, 1–5 escolhe (Cabana, Fogueira, Depósito, Cerca, Poço), R gira, clique ou E constrói,
  Esc ou clique direito sai; X demole (devolve 50 %). A primeira Cabana funda o reino.
- Combate (só teclado): Espaço ataca para onde o personagem olha, 1/2/3 escolhem Espada/Lança/Arco, Q troca,
  F faz 5 flechas com 1 madeira, H come 1 fruta (+15 de vida). Morrer leva de volta à sede sem perder nada.

## Roadmap

1. ✅ **Fundação jogável:** mapa pequeno em chunks, humanoide do Blender com WASD e Shift para
   correr, câmera isométrica seguindo, testes.
2. ✅ **Mundo com conteúdo:** biomas, árvores, pedras e arbustos (MultiMesh), recursos coletáveis,
   dia e noite, mapa maior, persistência delta por chunk.
3. ✅ **Construção:** inventário, coleta, construções pré-feitas com custo realista, fundação do reino.
4. ✅ **Criaturas e combate:** genoma de peças (animais reais + inventadas), comportamento, cruzamento
   com herança, brigas entre espécies, armas medievais, ataques ao reino.
5. ✅ **Pessoas:** gerador de pessoas (nome, traços, opinião), chegada e decisão de ficar,
   necessidades, construção autônoma.
6. ✅ **Sociedade:** famílias e brasões, relações, opinião sobre o jogador, aliados e inimigos internos.
7. ✅ **Casas e ambições:** tradição e valores das Casas, riqueza, terras, especialização, melhoria de casa,
   objetivos próprios, vocações e desejos pessoais, parentesco completo e adoção, casamentos arranjados,
   união de Casas, corrupção, infiltração, desligamentos (amigável/neutro/hostil, às claras/escondido), guardas.
8. ✅ **Governo:** decisões com efeito, sucessão, governante NPC (corrupção, lealdade, culto ou inimizade).
9. ✅ **Mundo vivo:** reinos NPC, simulação resumida fora da tela, diplomacia e guerras, novos reinos.
10. ✅ **Vida:** morte com corpo, recolher, carregar, cavar e enterrar (com animação), velório, sentimentos,
    necessidades (companhia, fé), vontades, mercadores ambulantes, moedas e pão.
11. **Cotidiano:** mais da vida de todo dia (a definir no design da etapa).
12. **Polimento:** menu, salvar/carregar, som, balanceamento.
