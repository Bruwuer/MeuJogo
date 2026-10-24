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
