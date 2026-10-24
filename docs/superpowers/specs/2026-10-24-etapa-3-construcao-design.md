# Design — Etapa 3: construção e fundação do reino

Data: 2026-10-24 · Status: decisões tomadas por Claude (autor: "faz tudo", "me entrega todas as partes")
Base: `2026-10-23-jogo-reino-vivo-design.md` e `2026-10-23-etapa-2-mundo-com-conteudo-design.md`.

## 1. Intenção

A madeira e a pedra coletadas na etapa 2 passam a ter uso. O jogador escolhe um lugar, gasta
recursos em construções prontas e, com a primeira cabana, **funda um reino** com nome e bandeira.
É o palco em que as pessoas (etapa 5) vão chegar e morar. O tom continua realista: as
construções custam o que custariam (uma cabana são umas dez árvores), não aparecem do nada, e o
terreno e a mata precisam permitir.

## 2. Escopo

**Dentro**
1. **Catálogo de construções** (modelos por script do Blender, low-poly):
   | Construção | Custo | Pegada | Observação |
   |---|---|---|---|
   | Cabana | 30 madeira, 10 pedra | 4×5 m | a **primeira** funda o reino |
   | Fogueira | 5 madeira, 3 pedra | 1,6×1,6 m | luz quente e tremeluzente à noite |
   | Depósito | 25 madeira, 5 pedra | 4×3 m | — |
   | Cerca | 4 madeira | 3×0,4 m | segmento; gira para fechar áreas |
   | Poço | 5 madeira, 20 pedra | 2×2 m | — |
2. **Modo construção:** **B** liga e desliga. **1–5** escolhem a construção e **R** gira 90°. Um
   fantasma translúcido segue o **mouse** (raio da câmera até o terreno); sem mouse sobre a
   janela, ele fica 3 m à frente do jogador. Verde = pode construir; vermelho = não pode, com o
   motivo no HUD ("Falta madeira (12/30)", "Terreno muito inclinado", "Há uma árvore no caminho",
   "Ocupado por outra construção", "Fora do mapa"). **Clique esquerdo** (ou **E**) constrói;
   **Esc** ou clique direito sai.
3. **Regras de colocação:** dentro do mapa jogável; desnível sob a pegada ≤ `BUILD_MAX_HEIGHT_DIFF`
   (1,2 m); nenhuma árvore ou rocha sob a pegada (arbustos são limpos automaticamente e contam
   como colhidos sem dar frutas); nenhuma outra construção sobrepondo; recursos suficientes. A
   construção assenta na altura **máxima** sob a pegada, sobre uma base de pedra que desce até o
   chão para não flutuar.
4. **Demolir:** **X** perto de uma construção (no modo normal) a remove e devolve **50 %** do custo.
   Uma Cabana-sede do reino não pode ser demolida enquanto o reino existir.
5. **Fundação do reino:** a primeira Cabana cria o **Reino**: nome gerado (português medieval
   inventado, determinístico pela semente do mundo e pelo número do reino), cor de bandeira
   sorteada, centro na cabana, raio `KINGDOM_RADIUS` (40 m). Um mastro com bandeira é erguido ao
   lado. O HUD mostra "Reino de <Nome>" quando o jogador está dentro do território, e um aviso
   aparece no momento da fundação.
6. **Persistência:** construções e reino ficam no `WorldState` (delta), por chunk; são recriadas
   quando o chunk carrega. Bump de `WORLDGEN_VERSION` não é necessário, porque construções não
   dependem dos ids de objetos.
7. **Colisão:** cada construção tem caixas de colisão (paredes da cabana, círculo de pedras etc.)
   e bloqueia o jogador.

**Fora (etapas futuras)**
- Pessoas usando as construções (etapa 5), produção do depósito e do poço.
- Construção em etapas, com trabalhadores, e terraplanagem.
- Mais reinos do jogador (etapa 8). O modelo já suporta uma lista de reinos.

**Anti-objetivos**
- Construir dentro de árvores ou rochas, ou com metade da casa flutuando.
- Perder construções ao salvar, sair ou voltar ao chunk.
- Gastar recursos sem a construção ter sido colocada (ou o contrário).

## 3. Decisões técnicas

| Tema | Decisão |
|---|---|
| Dados | `GameConstants.Building {CABIN, CAMPFIRE, STORAGE, FENCE, WELL}` + tabelas `BUILD_COST`, `BUILD_FOOTPRINT` (Vector2 m), `BUILD_NAMES`, `BUILD_SCENES`, `BUILD_COLLIDERS` (lista de caixas locais por tipo) |
| Placement | `BuildRules` (RefCounted, puro): `check(type, pos, rot_quarter, gen, scatter, state) -> Dictionary {ok, reason, y, cleared_bushes}`; usa a pegada girada (AABB), amostras de altura numa grade de 0,5 m, `scatter.props_near` + `state.removed_in` para os objetos, e as construções do estado |
| Estado | `WorldState`: `buildings: Array[Dictionary]` `{id, type, pos: Vector3, rot: int}` indexado por chunk; `kingdoms: Array[Dictionary]` `{id, name, color, center, radius, seat_building}`; `next_building_id`. Salvos no mesmo payload |
| Nomes | `KingdomNames.generate(seed: int, index: int) -> String` combinando sílabas (ex.: "Valdemar", "Torvela", "Aurímia") |
| Modelos | `tools/blender/buildings.py -- <cabin|campfire|storage|fence|well|flag> <out>`; origem no centro da pegada, no chão; a bandeira tem material "banner" recolorido em runtime |
| Streaming | `Chunk` recebe também a lista de construções do chunk e instancia as cenas (`BuildingLibrary`, carregamento em thread e sequencial como o `PropLibrary`) |
| Interação | `BuildSystem` (Node): modo, tipo, rotação, fantasma (`MeshInstance3D`s com material translúcido verde/vermelho), `try_place()`, `try_demolish(pos)`; sinais `built`, `demolished`, `kingdom_founded` |
| Fogueira | `OmniLight3D` laranja com cintilação por ruído, só visível à noite (energia ligada ao `DayNight`) |
| HUD | linha do modo construção ("Construindo: Cabana — 30 madeira, 10 pedra · R gira · Clique constrói · Esc sai"), motivo de bloqueio, nome do reino e aviso de fundação (5 s) |

## 4. Pronto quando

Testes headless cobrindo regras de colocação (cada motivo), custo e reembolso, persistência
(salvar/recarregar e recarregar o chunk), fundação do reino (nome determinístico e só na primeira
cabana), colisão e modo de construção dirigido por entrada; capturas mostrando o fantasma
verde e o vermelho, a cabana com a bandeira, um pequeno povoado e a fogueira acesa à noite.

## 5. Decisões após a revisão do design (Claude)

1. **Blocos sólidos:** nesta etapa não dá para entrar nas construções. A colisão de cada uma é uma
   caixa do tamanho da pegada (mais fina na cerca, um círculo de pedras na fogueira). Interiores
   ficam para quando as pessoas forem usá-los.
2. **Grade e encostar:** posição em grade de 0,5 m. Retângulos que só se encostam não contam como
   sobreposição (tolerância de 0,1 m). Cerca nunca bloqueia outra cerca, então dá para fazer cantos
   e fechar áreas.
3. **Bandeira:** é um registro próprio (`Building.FLAG`), salvo à parte, colocado dentro da pegada
   da cabana-sede (canto da frente). Não passa pelas regras, não entra na checagem de sobreposição
   e não pode ser demolida.
4. **Território:** não limita onde se constrói nesta etapa. Uma segunda cabana, dentro ou fora do
   raio, é só uma cabana (novos reinos ficam para a etapa 8).
5. **Inventário:** sem tela própria; os contadores do HUD bastam nesta etapa.
6. **Oclusão:** as construções usam o mesmo shader de oclusão das árvores, então também ficam
   pontilhadas quando escondem o jogador.
