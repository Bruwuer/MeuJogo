# Design — Etapa 5: pessoas

Data: 2026-10-24 · Status: decisões tomadas por Claude (autor: "faz tudo", "me entrega todas as partes")
Base: `2026-10-23-jogo-reino-vivo-design.md` e designs das etapas 2 a 4.

## 1. Intenção

Quem faz o reino crescer são as pessoas, não o jogador. Nesta etapa surgem os primeiros moradores:
viajantes com nome, traços e opinião própria chegam ao reino, olham o que há (comida, abrigo,
segurança, trabalho) e decidem se ficam. Quem fica tem necessidades, trabalha na sua profissão e,
sem ninguém mandar, ergue casas, fazendas e comércios. Se o reino vai mal, eles vão embora e dizem
por quê. Tudo isso continua acontecendo com o jogador longe.

Anti-objetivo central: moradores que são só cenário. Cada ação de um morador tem um motivo que o
jogador consegue ler (no HUD ou conversando com ele).

## 2. Escopo

**Dentro**
1. **Gerador de pessoas** (`PersonGen`, determinístico por semente):
   - nome e sobrenome portugueses medievais (sobrenome por ofício ou origem: "Ferreira", "do Vale");
   - sexo (só para o nome e a aparência), idade de 16 a 60 anos;
   - **dois traços** de pares opostos: trabalhador/preguiçoso, corajoso/medroso, generoso/ganancioso,
     sociável/solitário, devoto/cético (este último só vale nas etapas 6 e 7, mas já é gerado);
   - **profissão**: lenhador, pedreiro, agricultor, coletor, construtor ou comerciante;
   - aparência: cor de pele, cabelo, túnica e calça, e altura de 0,92 a 1,06;
   - **opinião sobre o jogador** inicial (−1 a 1), puxada pelos traços e pela fama do jogador.
2. **Chegada de viajantes:** com um reino fundado, chega um viajante a cada `TRAVELER_INTERVAL_HOURS`
   (o primeiro, pouco depois da fundação). O intervalo encurta com um Comércio e para quando o reino
   está cheio (`KINGDOM_MAX_PEOPLE`). O viajante surge a 60–90 m do centro, anda até a sede, para um
   pouco ("olhando o reino") e decide.
3. **Decisão de ficar:** uma soma de fatores, cada um com o seu texto:
   abrigo (vaga em casa ou fogueira para dormir), comida guardada por morador, segurança (ataques nos
   últimos 2 dias, pesando em dobro para os medrosos), trabalho para a profissão, poço, reino pequeno
   precisando de gente, traços (sociável gosta de reino cheio) e a opinião sobre o jogador, mais um
   ruído pequeno. O HUD diz o motivo mais forte: "Ana Ferreira decidiu ficar: há comida guardada" ou
   "Bento do Vale seguiu viagem: não há onde morar".
4. **Necessidades:** fome (sobe ao longo do dia; come 2 de comida por dia do estoque do reino: Comida
   primeiro, Frutas depois), descanso (dorme à noite: em casa, ou junto à fogueira se não tem casa) e
   abrigo. A cada hora, o **contentamento** (0 a 1) sobe ou desce com fome, abrigo, ataques recentes,
   poço e comércio. Contentamento abaixo de `LEAVE_CONTENTMENT` por `LEAVE_AFTER_HOURS` seguidas → a
   pessoa vai embora com aviso ("Carla deixou o Reino de X: passava fome").
5. **Estoque do reino:** o reino tem o seu próprio estoque (madeira, pedra, frutas, comida), separado
   do inventário do jogador. Os moradores levam o que coletam para o Depósito mais próximo (ou para a
   sede) e constroem com esse estoque. O jogador pode **doar** com **G** dentro do reino (até 10 de
   cada recurso por vez), o que melhora a opinião de quem está perto.
6. **Trabalho por profissão** (só quando o estoque precisa, para não desmatar o mapa):
   | Profissão | Trabalho | Rende |
   |---|---|---|
   | Lenhador | corta árvores perto do reino | madeira |
   | Pedreiro | quebra rochas | pedra |
   | Coletor | colhe arbustos | frutas |
   | Agricultor | cuida de uma Fazenda | comida (por dia, por fazenda cuidada) |
   | Construtor | trabalha nos canteiros | progresso da obra |
   | Comerciante | cuida do Comércio | contentamento e viajantes mais frequentes |
   Sem trabalho da própria profissão (sem fazenda, sem comércio, estoque cheio), a pessoa ajuda na obra
   aberta ou coleta o que estiver faltando. Cortar, quebrar e colher **removem de verdade** o objeto do
   mundo (vai para a lista de removidos do save), como faz o jogador.
7. **Construção autônoma:** a cada hora o reino avalia, nesta ordem: **Casa** se há gente sem casa,
   **Fazenda** se a comida produzida não cobre o consumo, **Comércio** a partir de 4 moradores, **Poço** a
   partir de 3 e **Depósito** se não há nenhum. Só abre uma obra por vez e só se o estoque cobre o custo
   (que é reservado na hora). O lugar é escolhido perto do centro, com `BuildRules` (terreno plano, sem
   árvore no caminho, sem sobrepor) e um corredor livre de 1,5 m em volta. A obra aparece como
   **canteiro** (andaime e a construção subindo) e fica pronta com `BUILD_WORK_HOURS` horas de trabalho.
   A casa pronta é do primeiro sem-teto, que a "assina": "Ficou pronta a casa de Ana Ferreira".
8. **Novas construções** (só os moradores constroem nesta etapa; o jogador continua com as 5 dele):
   **Casa** (3 moradores), **Fazenda** (lavoura cercada) e **Comércio** (barraca coberta), mais o
   **andaime** do canteiro. Uma Cabana do jogador que não é a sede vale como casa para 2.
9. **Falar com um morador:** **E** perto de uma pessoa (tem prioridade sobre a coleta) mostra um cartão:
   nome, idade, profissão, traços, o que está fazendo, a necessidade mais urgente e a opinião sobre você
   ("Acha você generoso" / "Desconfia de você").
10. **Opinião sobre o jogador** muda com: doações (+), matar criaturas que atacam o reino (+, "nos
    protegeu"), demolir a casa ou obra de um morador (−− para o dono, − para os outros) e passar muito
    tempo longe do reino (lentamente na direção do neutro). Fica guardada para as etapas 6 e 7.
11. **Medo das criaturas:** pessoas fogem de carnívoros e de bandos hostis por perto, e durante um ataque
    vão para casa. Nesta etapa as criaturas não atacam pessoas (ver §3).
12. **HUD:** dentro do reino, uma linha "Moradores: 5 · Estoque: Madeira 12, Pedra 3, Comida 8, Frutas 4"
    e as mensagens de chegada, decisão, obra, casa pronta e partida.
13. **Mundo sem o jogador:** um `VillageSim` horário cuida de todos os reinos, carregados ou não:
    chegadas, decisões, comida, contentamento, partidas e obras. Com o reino descarregado, o trabalho é
    resumido (cada trabalhador rende por hora segundo a profissão, sem remover objetos do mapa) e as
    mensagens ficam para a volta do jogador, como os ataques resumidos da etapa 4.
14. **Persistência:** pessoas (todos os campos), estoque do reino, dono e progresso das construções e
    a fama do jogador vão para o save. Pessoas fora dos chunks carregados não têm nó.

**Fora (etapas futuras)**
- Famílias, brasões, relações entre pessoas, filhos e envelhecimento (etapa 6).
- Pessoas lutando, guardas e milícia; criaturas atacando pessoas (etapas 6 e 7).
- Comércio de verdade entre reinos e dinheiro (etapa 8); governo e ordens do jogador (etapa 7).
- Caminhos, estradas e navegação com NavMesh.

## 3. Decisões técnicas

| Tema | Decisão |
|---|---|
| Dados | Pessoa = `Dictionary` em `WorldState` (como as criaturas): `{id, name, surname, female, age, traits, profession, looks, kingdom_id, home_id, pos, hunger, energy, contentment, opinion, status (traveler/resident/leaving), unhappy_hours, arrived_hour, job, carrying}`. Índice por chunk derivado, não salvo |
| Reino | O dicionário do reino ganha `stock` (Res → int), `last_raid_hour`, `next_traveler_hour` e `site_id` (obra aberta) |
| Construções | Registro ganha `owner` (−1 = jogador/reino, ou id da pessoa) e, enquanto obra, `progress` (0..1) e `site: true`. Uma obra já ocupa o lugar e tem colisão só da base |
| Regras puras | `PersonGen` (gerar), `VillageRules` (decisão de ficar, contentamento, comida, partida, plano de obra e escolha de trabalho). Tudo estático e testável sem cena |
| Simulação | `VillageSim` (Node, horário), análogo ao `PackSim`. Com o reino carregado, as pessoas com nó fazem o trabalho de verdade; o `VillageSim` só cuida do que é por hora (comida, contentamento, chegadas, planejamento) |
| Nó | `Person` (CharacterBody3D, camada nova `LAYER_PEOPLE`, colide com terreno e obstáculos, não com criaturas nem pessoas; o jogador não colide com pessoas para ninguém ficar preso em portas). Usa o `humanoid.glb` com materiais recoloridos por pessoa e as animações `idle`, `walk`, `run` e `work`. `PersonBrain` puro decide o que fazer a cada `PERSON_BRAIN_TICK` |
| Movimento | Igual às criaturas: reto pelo terreno, desvio de obstáculos por raios. Pessoas entram em casa (o nó some) para dormir e no ataque |
| Gestão | `PeopleManager` (Node3D): cria e remove nós conforme os chunks (teto `PEOPLE_MAX_ACTIVE` = 30, no máximo 2 por frame), aplica o trabalho ao mundo (remove objeto, deposita no estoque, avança a obra), mostra os canteiros e termina as obras |
| Modelos | `tools/blender/buildings.py` ganha `house`, `farm`, `market` e `scaffold`. O humanoide não muda: os materiais `skin`, `hair`, `tunic`, `trousers` são trocados por cópias coloridas |
| Carregamento | O `humanoid.glb` para as pessoas entra na fila do `ModelLibrary` (único carregador) |
| Criaturas | Pessoas aparecem para as criaturas só como ameaça leve (herbívoros fogem delas); as criaturas não as atacam nesta etapa. Assim os bandos com motivo continuam mirando construções e o jogador |

## 4. Pronto quando

- **Testes headless** cobrindo:
  - gerador: nomes válidos, traços sem par contraditório, determinismo por semente, profissões e cores;
  - estado: pessoas e estoque no save, índice por chunk, dono e obra nas construções;
  - regras: ficar com comida e abrigo, ir embora sem abrigo, medroso e ataques recentes, motivo certo no
    texto, contentamento e partida, comida (Comida antes de Frutas), plano de obra na ordem e escolha
    de lugar válido;
  - simulação: chegada no intervalo, teto do reino, obra resumida com o reino longe, mensagens na volta;
  - pessoa: anda até o alvo sem atravessar obstáculo, corta uma árvore de verdade e leva a madeira ao
    estoque, trabalha no canteiro até a obra ficar pronta, dorme em casa à noite, foge de um lobo;
  - jogador: falar (cartão), doar (G), demolir casa de morador baixa a opinião;
  - orçamento de frame com 30 pessoas e 40 criaturas.
- **Capturas com janela:** viajante chegando, povoado com moradores trabalhando, um canteiro subindo,
  o cartão de um morador e o povoado à noite (com gente dormindo em casa e junto à fogueira).

## 5. Decisões após a revisão do design (Claude)

1. **Dono das construções:** só o reino/jogador (`owner = -1`) e os moradores (`owner = id`) são donos.
   O jogador **não pode demolir** casa ou obra de morador nesta etapa ("A casa é de Ana Ferreira").
   Toda remoção passa por `WorldState.remove_building`, que limpa o `home_id` dos moradores, ejeta quem
   estava dentro, fecha a obra do reino e devolve ao estoque o custo reservado de uma obra destruída.
   A demolição pelo jogador continua devolvendo 50 % ao inventário dele (só nas construções dele).
2. **`BuildRules`:** dividido em `check_site` (lugar: mapa, inclinação, objetos, sobreposição, quem está
   no caminho) e `check` (lugar + custo no inventário do jogador). O planejador usa `check_site` e confere
   o custo no estoque do reino. Pessoas também bloqueiam o lugar de uma obra.
3. **Começo:** fundar o reino dá um estoque inicial (`KINGDOM_START_STOCK`: 20 madeira, 24 frutas). A
   sede com uma fogueira (ou só a sede) serve de abrigo para dormir ao relento. As duas primeiras
   pessoas que chegam a um reino ficam sempre ("o reino é novo e precisa de gente"). A Fazenda passa na
   frente da Casa quando a comida dura menos de 2 dias. Metade dos viajantes vem com a profissão que o
   reino mais precisa.
4. **Carregado ou não, por pessoa:** quem tem nó trabalha de verdade; quem não tem é resumido naquela
   hora pelo `VillageSim`. Ao perder o nó, o que a pessoa carregava vai para o estoque. Um viajante sem
   nó chega à sede na hora seguinte (o registro "anda" até lá). `WorldState.move_person` reindexa o chunk.
5. **Saves antigos:** valores novos entram **no fim** dos enums (`Res.FOOD` depois de `ARROWS`; `HOUSE`,
   `FARM`, `MARKET` depois de `FLAG`) e ficam fora de `BUILDABLE`. `_from_dict` completa reinos sem
   `stock` etc. e construções sem `owner`. Um teste carrega um save no formato da etapa 4.
6. **Fama do jogador:** média da opinião dos moradores de todos os reinos, recalculada a cada hora e
   salva. Puxa a opinião inicial dos viajantes.
7. **Território das criaturas:** o planejador não abre obra dentro do território de uma toca
   (`TERRITORY_RADIUS`), para os moradores não provocarem os bandos. Obras não são alvo de ataque.
8. **Criaturas veem pessoas** como tipo `person`: herbívoros fogem delas, carnívoros as ignoram.
9. **Recursos:** moradores só coletam enquanto o estoque está abaixo da meta (`KINGDOM_STOCK_TARGET`).
   O trabalho resumido também remove objetos de verdade (o mais próximo do centro, pela semente), para o
   reino não render mais com o jogador longe. Árvores, rochas e arbustos não voltam nesta etapa; a comida
   duradoura vem das fazendas.
10. **Teto:** `KINGDOM_MAX_PEOPLE = 12` por reino, abaixo de `PEOPLE_MAX_ACTIVE = 30`.
11. **Fazenda sem colisão** (lavoura com estacas baixas, dá para atravessar). Casas têm um ponto de porta
    na frente; entrar em casa = andar até a porta e o nó sumir.
12. **Obra parada:** sem progresso por `SITE_STALL_HOURS` (48 h), a obra é abandonada e o custo volta.
13. **Escopo:** fica numa etapa só, mas o plano entrega primeiro a base (pessoas, chegada, decisão,
    necessidades, estoque, conversa, simulação, save) e depois o trabalho de verdade e as obras.
14. **Busca de lugar limitada:** no máximo `SITE_CANDIDATES` (24) lugares testados por hora, numa
    espiral determinística a partir do centro.
15. **Mensagens:** de reino carregado vão direto ao HUD; de reino descarregado ficam numa fila e são
    contadas na volta (juntas, como os ataques resumidos).
16. **Teclas:** E fala com uma pessoa a até `TALK_RANGE` (2,2 m) fora do modo construção, com prioridade
    sobre a coleta; G doa. O descanso não é uma barra: é o horário (dormem das 21h às 6h).
17. **Materiais das pessoas** ficam num cache por cor, não um por pessoa.

### Números (todos em `GameConstants`; 1 hora de jogo = 20 s)

| Item | Valor |
|---|---|
| Viajantes | 1º 1 h após a fundação; depois a cada 6 h (4 h com Comércio); surgem a 60–90 m |
| Comida | cada pessoa come 2 por dia (1 quando a fome passa de 0,5); Comida antes de Frutas |
| Fazenda | 0,75 de comida por hora de agricultor trabalhando nela (≈ 8 por dia) |
| Resumido por hora de trabalho | lenhador 2 madeira, pedreiro 1,2 pedra, coletor 1,5 frutas |
| Metas de estoque | madeira 60, pedra 30; frutas só se a comida dura menos de 3 dias |
| Horário | trabalho das 7h às 19h; sono das 21h às 6h |
| Casa | 40 madeira + 10 pedra, 8 h de obra, 3 moradores |
| Fazenda | 12 madeira, 4 h de obra, 6 × 6 m |
| Comércio | 25 madeira + 8 pedra, 6 h de obra, a partir de 4 moradores |
| Poço / Depósito (moradores) | custo da etapa 3; 5 h e 6 h de obra |
| Contentamento | começa em 0,6; por hora: com fome −0,04, sem abrigo nenhum −0,03, só fogueira −0,01, ataque nas últimas 48 h −0,02 (×2 medroso, ×0,5 corajoso), alimentado +0,02, com casa +0,01, poço +0,005, comércio +0,01 |
| Partida | contentamento < 0,25 por 24 h seguidas |
| Decisão de ficar | casa com vaga +0,25, só fogueira/sede +0,05, nada −0,3; comida ≥ 2 dias +0,25, sem comida −0,35; ataque recente −0,25 (×2 medroso, ×0,5 corajoso); trabalho na profissão +0,1; poço +0,05; reino com menos de 3 moradores +0,2; sociável +0,05 por morador acima de 3 (até 0,15); solitário −0,05 por morador acima de 6; opinião × 0,2; ruído ±0,1. Fica se > 0 |
| Opinião | inicial: traços (generoso +0,1, ganancioso −0,1, devoto +0,1, cético −0,05) + fama × 0,5 ± 0,2. Doação: +0,05 para quem está a até 25 m. Matar um atacante dentro do reino: +0,05 para todos os moradores. Longe do reino: −0,1 por dia na direção do neutro |
