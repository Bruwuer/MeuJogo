# Design — Etapa 6: sociedade

Data: 2026-10-24 · Status: decisões tomadas por Claude (autor: "faz tudo", "me entrega todas as partes")
Base: `2026-10-23-jogo-reino-vivo-design.md` e o design da etapa 5 (`2026-10-24-etapa-5-pessoas-design.md`).

## 1. Intenção

Na etapa 5 cada morador tem nome, traços e opinião, mas vive sozinho: ninguém conhece ninguém. Nesta
etapa o povoado vira uma **sociedade**. Os moradores se encontram, viram amigos ou rivais, se casam, têm
filhos que crescem, formam **famílias com brasão** e, quando brigam com o chefe ou a família cresce demais,
**rompem e fundam a própria casa**. Cada pessoa e cada família tem uma opinião sobre o jogador, que muda
sozinha (com o contentamento, a família e os amigos), e daí surgem **aliados e inimigos dentro do
reino sem o jogador escolher**: um aliado dá presentes, um inimigo rouba.

Palavras do autor: "cada pessoa pode ter sua própria opinião e nomes, criar famílias (brasões) ou
desmanchar, se desvincilhar de uma família para criar sua própria"; "você pode ter aliados, sem escolher,
ou inimigos dentro do próprio reino".

Anti-objetivo central: relações que são só números escondidos. Tudo o que muda (casamento, nascimento,
ruptura, família que se desfaz, novo aliado ou inimigo) aparece no HUD com o motivo, e o cartão de cada
pessoa mostra família, brasão, cônjuge, filhos, amigo, rival e o que acha do jogador.

## 2. Escopo

**Dentro**
1. **Famílias (casas):** todo morador pertence a uma família, um registro próprio em `WorldState`
   (`{id, surname, crest, head_id, kingdom_id, founded_hour, parent_id, origin, stance}`).
   - Quem decide ficar no reino funda a sua casa ("Casa Ferreira"), a menos que já exista no reino uma
     família com o mesmo sobrenome: aí entra nela como parente ("Bento Ferreira juntou-se à Casa
     Ferreira").
   - Casamento: o cônjuge entra na família maior (empate: a mais antiga). A família que fica vazia
     **se desfaz** ("A Casa do Vale uniu-se à Casa Ferreira").
   - Filhos nascem na família dos pais.
   - **Ruptura:** um adulto que vira rival do chefe da família rompe e funda a própria casa com o
     cônjuge e os filhos menores ("Martim Ferreira rompeu com a Casa Ferreira e fundou a Casa Seixas").
     Uma família grande (mais de `FAMILY_BRANCH_SIZE` pessoas) também solta um **ramo** em paz: um
     casal com casa própria funda uma família nova, com brasão derivado do original.
   - Família sem ninguém (todos foram embora, morreram ou saíram) se desfaz com aviso. Se o chefe sai,
     o adulto mais velho assume.
2. **Brasões gerados por código:** cada família tem um brasão (`Crest`): divisão do escudo (pleno,
   partido, cortado, em banda, esquartelado, em asna), duas cores heráldicas seguindo a regra de metal
   sobre cor (ouro e prata sobre vermelho, azul, verde, preto e púrpura) e uma figura no centro
   (besante, cruz, losango, estrela, crescente ou nenhuma). Nunca dois brasões iguais no mesmo reino.
   Um ramo herda o escudo e muda só a figura (a "brisura"); quem rompe por rivalidade guarda só uma cor.
   - A imagem é desenhada pixel a pixel numa `Image` pequena (32 × 40) e vira textura (cache por
     brasão). Nada de asset externo.
   - No mundo: o **estandarte da família** (poste com pendão em forma de escudo, modelo novo do
     Blender `crest_banner`) fica ao lado da porta de cada casa com dono, com o brasão da família dele.
   - No HUD: o cartão da pessoa e o painel de famílias mostram o brasão.
   - Uma descrição curta em português acompanha ("azul e ouro, partido, com uma estrela de prata").
3. **Relações entre moradores:** um valor de −1 a 1 por par (simétrico), guardado em `WorldState`.
   A cada hora, alguns pares de moradores do mesmo reino se encontram (mais quem mora na mesma casa,
   é da mesma família ou tem a mesma profissão). Cada encontro muda a relação conforme a afinidade:
   traços iguais aproximam, traços opostos afastam (trabalhador × preguiçoso, generoso × ganancioso…),
   sociável aproxima, solitário afasta, mais um ruído. Acima de `FRIEND_AT` = amigos; abaixo de
   `RIVAL_AT` = rivais.
4. **Casais:** dois adultos solteiros, sem parentesco (pais, filhos, irmãos), com relação acima de
   `COUPLE_AT` e diferença de idade até `COUPLE_MAX_AGE_GAP`, se casam ("Ana Ferreira e Bento do Vale se
   casaram"). Mudam-se para a mesma casa assim que houver lugar.
5. **Filhos:** um casal que mora junto, contente, com comida para 2 dias e cama livre em casa pode ter
   um filho (só se uma das pessoas é mulher de 18 a 45 anos). Chance por dia, intervalo mínimo entre
   filhos e teto do reino. O filho herda um traço de cada pai, a pele de um e o cabelo de outro, o
   sobrenome da família e a opinião média dos pais ("Nasceu Inês, filha de Ana Ferreira e Bento do Vale").
   - **Crescer:** crianças envelhecem `CHILD_YEARS_PER_DAY` anos por dia de jogo; adultos,
     `ADULT_YEARS_PER_DAY`. Aos 16 a criança vira adulta e ganha a profissão que o reino mais precisa
     ("Inês Ferreira cresceu e agora é lenhadora"). Criança não trabalha: brinca perto de casa, dorme
     em casa, foge de lobos. O modelo é o humanoide em escala menor, crescendo com a idade.
   - **Velhice:** a partir de `OLD_AGE` há chance de morrer por dia ("Morreu Afonso Ferreira, aos 72
     anos"). O cônjuge fica viúvo; a família continua com quem restou.
6. **Opinião sobre o jogador (pessoa e família):** a opinião de cada pessoa (da etapa 5) agora também
   se move sozinha a cada hora:
   - **contentamento:** quem vive bem pensa melhor do fundador; quem vive mal o culpa;
   - **família:** puxa a opinião de cada membro para a média da família;
   - **amigos e rivais:** amigos puxam a opinião um do outro; um rival empurra para o lado contrário;
   - continuam valendo doações, proteção contra ataques e a deriva quando o jogador está longe.
   - **Conversar** (E) agrada uma vez por dia a pessoa sociável e desagrada a solitária.
   A opinião da família é a média dos adultos dela.
7. **Aliados e inimigos internos:** com opinião acima de `ALLY_AT` a pessoa (ou a família) vira
   **aliada**; abaixo de `ENEMY_AT`, **inimiga** (com histerese, para não piscar). O HUD avisa ("A Casa
   Ferreira agora é sua aliada", "Rui Couto agora é seu inimigo"). Efeitos nesta etapa:
   - uma família aliada dá um presente por dia ao jogador que está no reino (do estoque do reino, se
     sobrar): "A Casa Ferreira lhe deu 3 frutas";
   - um inimigo rouba uma vez por dia um pouco do recurso que o jogador tem mais, e leva ao estoque do
     reino: "Rui Couto roubou 2 de madeira de você".
   Os dados (posição de cada família, chefe, rivalidades entre casas) ficam prontos para a etapa 7
   (governo, sucessão, corrupção).
8. **Interface (só teclado):**
   - **E** (falar) mostra o cartão maior: nome, idade, reino, **Casa X com o brasão**, profissão e
     traços, cônjuge, pais ou filhos, melhor amigo, pior rival, o que está fazendo, do que precisa e o
     que acha de você (com "aliado"/"inimigo").
   - **C** abre e fecha o **painel de famílias** do reino onde o jogador está: brasão, nome, quantas
     pessoas, chefe, posição (aliada, neutra, inimiga) e rival de outra casa, se houver.
   - A linha do povoado ganha "Famílias: N".
9. **Mundo sem o jogador:** tudo isso é registro puro e roda no `VillageSim` horário para todos os
   reinos, carregados ou não; as mensagens de reino longe entram na fila da volta.
10. **Persistência:** famílias, relações, campos novos das pessoas (`family_id`, `spouse_id`,
    `parents`, `stance`, `last_birth_hour`, `talk_day`, `deed_day`) vão para o save. Saves da etapa 5
    abrem: moradores sem família ganham uma na primeira hora.
11. **Pendências da etapa 5 que tocam o mesmo código:** a fila de notícias ganha limite; a doação rende
    opinião proporcional ao que foi doado; aviso "Um viajante se aproxima do Reino de X".

**Fora (etapas futuras)**
- Governo, leis, impostos, sucessão do governante e governante NPC (etapa 7). Inimigos não se rebelam,
  não sabotam e não atacam o jogador nesta etapa.
- Famílias e casamentos entre reinos, diplomacia (etapa 8).
- Herança de bens, dote, dinheiro, nobreza e títulos.
- Animações próprias de criança, roupas por família, brasão na bandeira do reino.
- Morte por doença, fome ou ataque de criatura (as criaturas ainda não atacam pessoas).

**Anti-objetivos**
- Spam de mensagens: só eventos que mudam a história (casamento, nascimento, crescer, morte,
  ruptura, família que se desfaz, aliado/inimigo novo, presente, roubo).
- Família como rótulo vazio: a família pesa na opinião, no lar, no casamento e nos brasões nas casas.
- Escolher aliados no menu: o jogador só influencia indiretamente (doar, proteger, conversar, deixar o
  reino viver bem).

## 3. Decisões técnicas

| Tema | Decisão |
|---|---|
| Família | `Dictionary` em `WorldState._families` (id → família), com `kingdom_id` para a etapa 8. Membros não são guardados na família: são os moradores com `family_id` igual (derivado, sem duplicar estado) |
| Relações | `WorldState._relations: Dictionary[Vector2i, float]` com a chave `(menor id, maior id)`; salvas como lista `[a, b, valor]`. `remove_person` apaga as relações e desfaz o casamento |
| Pessoa | Campos novos com padrão em `WorldState.person_defaults` (usado em `add_person` e no carregamento). `age` vira número com fração (cresce por hora) |
| Brasão | `Crest` (estático): `generate`, `derive`, `image`, `texture`, `material`, `describe`. Imagem 32 × 40 desenhada por pixel, filtro "nearest"; cache por chave do brasão. Material com alpha scissor e sem culling (o pendão é um plano só) |
| Estandarte | `tools/blender/buildings.py crest_banner`: poste, travessa e pendão em forma de escudo com UV 0..1 e material `crest`. Carregado pelo `ModelLibrary` (único carregador) mantendo os próprios materiais. `Chunk.set_crest(building_id, crest)` cria, troca ou remove o estandarte; quem chama é o `PeopleManager` (o chunk não conhece famílias) |
| Regras puras | `SocietyRules` (estático): afinidade de um encontro, parentesco, pode casar, pode ter filho, deriva de opinião, posição com histerese, tipo de ruptura. `PersonGen.child` gera o filho |
| Simulação | `SocietySim` (RefCounted) chamado pelo `VillageSim` a cada hora para cada reino, depois das necessidades: famílias dos novos, idade/crescer/velhice, encontros, casamentos, lares dos casais, nascimentos, rupturas, famílias vazias, opinião, posição, presentes e roubos. Aleatoriedade semeada por (semente do mundo, reino, hora): recarregar não repete eventos |
| Sinais | `VillageSim` ganha `person_born`, `person_died` e `families_changed`; o `PeopleManager` cria o nó do bebê e atualiza os estandartes |
| Nó | Criança = mesmo `Person`, com escala `altura × lerp(CHILD_MIN_SCALE, 1, idade/16)` atualizada no "pensar". `choose_job` devolve `"child"`; o ponto de brincar é a porta de casa |
| Partida | Quem vai embora infeliz leva o cônjuge e os filhos menores |
| HUD | Cartão vira `HBox` (brasão + texto). Painel de famílias (`C`, ação `families`) com uma linha por família (brasão + texto), só dentro de um reino |
| Teclas | C é livre (E fala, G doa, B constrói, X demole, F flechas, H come, Q troca) |

## 4. Pronto quando

- **Testes headless** cobrindo:
  - brasão: determinismo, regra de metal sobre cor, sem repetição no reino, ramo muda só a figura,
    imagem com as cores certas no lugar certo e transparente fora do escudo, descrição em português;
  - estado: famílias e relações no save, relação simétrica, `remove_person` limpa relações e cônjuge,
    save da etapa 5 abre e ganha famílias;
  - regras: afinidade (iguais aproximam, opostos afastam), parentesco impede casamento, idade e
    relação para casar, condições do filho, posição com histerese, deriva de opinião (contentamento,
    família, amigos, rivais), ruptura por rivalidade e ramo;
  - simulação: quem fica funda família ou entra na de parentes; casal se forma e se muda junto;
    família vazia se desfaz; nasce filho com traços dos pais; criança cresce e ganha profissão; velho
    morre; rival do chefe rompe e funda casa com brasão novo; família grande solta ramo; aliado dá
    presente e inimigo rouba só com o jogador no reino; quem parte leva a família; mensagens de reino
    longe vão para a fila (com limite);
  - mundo: estandarte com o brasão aparece na casa do dono e troca quando ele muda de família; o cartão
    mostra família e relações; C abre o painel; criança aparece menor; conversar muda a opinião uma vez
    por dia; a suíte inteira passa.
- **Capturas com janela:** cartão de um morador casado com filhos e brasão, um casal com os filhos perto
  de casa, estandartes com brasões nas casas, o painel de famílias, uma ruptura (mensagem e casa com
  brasão novo) e as mensagens de aliado, presente e roubo.

### Números (todos em `GameConstants`; 1 hora de jogo = 20 s, 1 dia = 8 min)

| Item | Valor |
|---|---|
| Encontros | 6 pares por hora por reino (metade entre "próximos": casa, família ou profissão) |
| Afinidade por encontro | base +0,02; traço igual +0,04; traço oposto −0,06; sociável +0,02 cada; solitário −0,02 cada; mesma casa ou família +0,02; ruído ±0,03 |
| Limiares | amigo ≥ 0,35; rival ≤ −0,35; casar ≥ 0,6 |
| Casar | adultos (≥ 18), solteiros, sem parentesco, diferença de idade ≤ 15 |
| Filho | chance 0,35 por dia; contentamento dos dois ≥ 0,5; comida ≥ 2 dias; cama livre na casa; mãe de 18 a 45; 3 dias entre filhos |
| Idade | criança +2 anos por dia (adulta aos 16, em 8 dias ≈ 1 h de jogo); adulto +0,25 por dia |
| Velhice | a partir de 70 anos, 15 % de chance por dia |
| Casa | passa a ter 4 camas (um casal e dois filhos); teto do reino sobe para 16 pessoas |
| Ruptura | relação com o chefe ≤ −0,5; ramo com família > 5 pessoas, casal com casa própria, 25 % por dia |
| Opinião por hora | contentamento: (c − 0,5) × 0,01; família: 2 % da diferença para a média; amigo: 1 % da diferença; rival: −0,5 % da diferença |
| Conversar | sociável +0,03, solitário −0,02, outros +0,01; uma vez por dia por pessoa |
| Posição | aliado ≥ 0,5 (deixa de ser < 0,4); inimigo ≤ −0,4 (deixa de ser > −0,3) |
| Presente | às 10 h, cada família aliada dá 3 do recurso que o estoque tem mais (se o estoque tiver ao menos 10) |
| Roubo | às 10 h, cada inimigo adulto rouba 2 do recurso que o jogador tem mais |
| Notícias | a fila de mensagens de reinos longe guarda no máximo 40 |
| Doação | opinião +0,05 × (total doado / 10, até 1) |

## 5. Decisões após a revisão do design (Claude)

A revisão de "quem vai construir" levantou 25 pontos. Decisões, na mesma ordem:

1. **Sobrenome da ruptura:** um sobrenome de `SURNAMES` que nenhuma família nem morador do reino usa
   (sem sobra: "Seixas de Martim"). Quem rompe e os filhos menores dele passam a usar o sobrenome novo; o
   cônjuge fica com o dele. A regra "mesmo sobrenome entra na família" vale só para quem chega.
2. **Sobrenome da pessoa × da família:** quem chega é comparado com `family.surname`. O cartão mostra o
   nome da pessoa e a linha "Casa <sobrenome da família>".
3. **Casais:** quaisquer dois adultos podem se casar. Filhos só de um casal de mulher (18 a 45) e homem.
   Sem adoção nesta etapa.
4. **Traços do filho:** um traço sorteado de cada pai; se os dois caem no mesmo par (iguais ou opostos),
   o segundo vem de outro par ao acaso. Sexo 50 %, nome ao acaso sem repetir irmãos vivos, roupas ao
   acaso, altura = média dos pais ± 0,03.
5. **Profissão da criança:** `-1`. `profession_name` devolve "criança" para `-1`; crianças ficam fora de
   `snapshot.professions`. `choose_job` devolve `"child"` antes de tudo, e o trabalho resumido ignora.
6. **Crianças nos números:** contam como moradores (teto, comida, casas). Ficam fora da fama, das
   posições (aliado/inimigo), da média de opinião da família e da conta de partida: nunca vão embora
   sozinhas.
7. **Teto:** `KINGDOM_MAX_PEOPLE = 16` para todos. Nascimentos só enquanto o reino tem menos de
   `KINGDOM_BIRTH_CAP = 14` moradores (sobra lugar para viajantes, que trazem gente sem parentesco).
8. **Casas por família:** `_assign_homes` escolhe para cada sem-teto, nesta ordem: a casa do cônjuge, a
   de um dos pais (menor), a de alguém da família, uma casa vazia, qualquer casa com cama. Ninguém é
   despejado. O bebê nasce na casa dos pais (o nascimento exige cama livre nela). `_reunite`: casal
   separado vai para a casa de um dos dois que tenha lugar, ou para uma casa com 2 camas livres. O
   planejador conta casais separados como necessidade de casa (`homeless + apart > free_beds`).
9. **Dono da casa:** quem assina continua dono. Se o dono morre ou deixa o reino, a casa passa ao adulto
   mais velho que mora nela; sem ninguém, vira do reino (`OWNER_KINGDOM`) e perde o estandarte. Só
   casas (`HOUSE`) com dono pessoa têm estandarte; o jogador não constrói casas.
10. **Partida com a família:** o cônjuge e os filhos menores vão junto (mesmo contentes) e cada um passa
    pelo `_leave` (lar, sinal, remoção). Uma só mensagem ("… deixou o Reino de X com a família: …").
11. **Morte com nó:** o `SocietySim` emite `person_died` antes de remover o registro; o `PeopleManager`
    libera o nó e as reservas de trabalho. Quem está dentro de casa morre do mesmo jeito.
12. **Referências soltas:** `parents` nunca é apagado (o parentesco vale depois da morte). `remove_person`
    zera o `spouse_id` do cônjuge e marca `widowed = true`; viúvos podem casar de novo. O cartão só mostra
    nomes de quem ainda existe.
13. **Chefe:** se o chefe não é mais membro, assume o adulto mais velho; sem adultos, a criança mais
    velha. Quem casa e entra na família do outro sai sozinho da antiga (ela continua com quem ficou). Os
    filhos menores de um viúvo que casa de novo vão com ele.
14. **Ruptura:** cônjuges não rompem (sem divórcio nesta etapa). Um filho adulto do chefe pode romper.
    Limite `SPLIT_RIVAL_AT = −0,5` (mais forte que rival). A família nova fica nas casas onde já moram.
    "Casal com casa própria" = mora numa casa diferente da do chefe. O líder da família nova é quem
    rompeu. Uma família só solta ramo a cada `FAMILY_SPLIT_COOLDOWN_DAYS` (3 dias), e uma família nova
    também espera esse tempo.
15. **Chances por dia:** convertidas para chance por hora (`1 − (1 − p)^(1/24)`). Conversa: uma vez por
    dia de jogo (`talk_day = floor(hora/24)`). Presente e roubo: uma vez por dia, na primeira hora a partir
    das 10 h em que o jogador está no reino (`deed_day` na família e na pessoa).
16. **Determinismo:** `tick_hours(n)` passa a hora simulada de cada volta ao `SocietySim` (não a mesma
    hora n vezes). Os moradores são ordenados por id antes dos sorteios. O brasão é semeado por
    (semente, família).
17. **Saves antigos:** `person_defaults` no carregamento; cartão e HUD aceitam `family_id = −1`. Moradores
    antigos com o mesmo sobrenome viram parentes (aceito). Casas antigas ganham a 4ª cama. A idade vira
    número com fração e é mostrada sem a fração.
18. **Brasões:** o escudo pleno sempre tem figura (duas cores). A figura contrasta com o campo. Sem
    variação livre depois de `CREST_TRIES`, aceita-se repetir (raríssimo).
19. **Estandarte e `ModelLibrary`:** tipo novo de carga `"crest"` na mesma fila (o `is_ready` espera por
    ele), mantendo os materiais próprios; o pano usa `set_surface_override_material` na superfície
    `crest`. O estandarte não some na frente do jogador (é fino e fica de lado); aceito.
20. **Estandartes nos chunks:** `PeopleManager.refresh_crests()` é idempotente (`Chunk.set_crest` não faz
    nada se o brasão é o mesmo) e roda no `chunk_loaded`, no `site_finished`, no `families_changed` e no
    `_sync` de 1 s (pega qualquer outra troca de dono). Fica no canto da frente, fora da planta e ao lado
    da parede, sem colisão: não bloqueia a porta.
21. **Nó da criança:** só o modelo encolhe (a cápsula fica, só colide com chão e obstáculos). A criança
    brinca perto da porta de casa (o `seat_pos` do contexto vira a porta). O bebê nasce dentro de casa se
    a mãe está dentro. `person_born` chama `_fill()`.
22. **Forças da opinião:** as parcelas da hora (contentamento, família, amigos, rivais) são calculadas
    com as opiniões do começo da hora e aplicadas juntas; depois vem a deriva de "longe". A família usa a
    média dos adultos.
23. **Mensagens:** quem fica gera só "decidiu ficar" (fundar a casa é silencioso; entrar na de parentes
    avisa). Posição: só adultos e famílias. Roubos: no máximo `THEFT_MAX_PER_DAY = 2` por reino por dia
    (os de pior opinião). O limite de 40 vale para a fila do `VillageSim` e descarta as mais antigas,
    contando-as em "mais N coisas".
24. **Presente e roubo:** presente só de madeira ou pedra (nunca comida). Roubo só de madeira, pedra ou
    frutas do jogador (nunca flechas); empate na ordem do enum; sem nada, sem roubo e sem mensagem. É um
    evento resumido do dia: não precisa do nó do ladrão.
25. **Testes e custo:** o `SocietySim` recebe as funções (`say`, `is_player_in`) por `setup`, e os testes
    as trocam. A cada hora monta um cache família → membros. O painel C só se refaz ao abrir e a cada 1 s
    aberto; o cartão é montado uma vez ao falar.
