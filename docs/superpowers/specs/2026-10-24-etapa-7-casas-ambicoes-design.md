# Design — Etapa 7: Casas e ambições

Data: 2026-10-24 · Status: pedido do autor ampliando a sociedade; decisões de Claude (autor: "faz tudo")
Base: designs das etapas 5 (pessoas) e 6 (sociedade). O roadmap passa a ser: 7 Casas e ambições,
8 Governo, 9 Mundo vivo, 10 Acabamento.

## 1. Intenção (nas palavras do autor)

"Famílias, estilo de vida, preferências, crescimento de riqueza, crescimento de terras,
especialização, corrupção, infiltrações, objetivos próprios gerados aleatoriamente mas que fazem
sentido com as demais necessidades, melhoria de casa, união de casas, casamento com objetivo da
família, quebra de expectativas…" e "filhos, pessoas, marido e mulher, só marido, só mulher, primos,
tios podem ter vontades próprias: a casa é referência em guerreiros, mas o filho não quer ser
guerreiro, ele se desvincula da família (amigavelmente ou não, neutro ou não, escondido ou não)".

Cada Casa vira um ator com tradição, riqueza, terra, ofício e planos; cada pessoa tem vocação e
desejos próprios que podem bater de frente com os da Casa. O reino passa a gerar histórias sozinho.

## 2. Escopo

**Dentro**
1. **Parentesco completo:** pais, filhos, irmãos, avós, netos, tios, sobrinhos e primos calculados
   pela árvore (`parents`). **Costume medieval (pedido do autor):** casamento e filhos só entre homem e
   mulher. Casais sem filhos, viúvos e viúvas de boa situação podem **adotar** órfãos (crianças sem pai nem mãe no reino). O cartão mostra o parentesco entre
   moradores ("primo de Ana", "tio de Bento").
2. **Tradição da Casa (estilo de vida):** cada Casa nasce com uma tradição — **Guerreiros, Lavradores,
   Mercadores, Construtores, Gente da mata** (lenha e coleta) — e **valores** (pesos de riqueza,
   terra, prestígio, fé, honra). A tradição define o ofício esperado dos filhos, o que a Casa compra
   e do que se orgulha. Uma Casa que muda de chefe pode mudar de tradição aos poucos.
3. **Guerreiros de verdade:** nova profissão **Guarda**. Guardas patrulham o reino (mais à noite) e
   atacam criaturas que entram no território, com o mesmo combate do jogador (lança). Reduzem a força
   de ataques resumidos.
4. **Riqueza (moedas da Casa):** cada Casa acumula riqueza com o trabalho dos membros (valor do que
   produzem, com bônus de especialização), o comércio (se há Comércio) e dotes. Gasta em melhoria de
   casa, terra, dotes, subornos e ajuda a parentes. Riqueza é abstrata (não sai do estoque do reino).
5. **Terras:** a Casa reivindica **lotes** (8×8 m) perto da sua casa, marcados no chão com estacas na
   cor da Casa. Ganha lotes livres no território pagando por eles, ou compra de uma Casa que precisa de
   dinheiro. Lavradores fazem fazendas nos próprios lotes. Terra rende prestígio e riqueza.
6. **Especialização:** cada Casa tem perícia por ofício, que cresce com as horas trabalhadas e passa de
   pais para filhos que seguem o ofício. Perícia alta dá até +50 % de produção e o título "referência
   em …" (a maior perícia do reino naquele ofício).
7. **Melhoria de casa:** casa simples → **casa de pedra** → **solar**. Custa riqueza (e pedra/madeira do
   estoque do reino, pagos com riqueza); aumenta camas, conforto e prestígio. Modelos novos do Blender.
8. **Prestígio:** soma de riqueza, terras, nível da casa, perícia, alianças e honra (escândalos
   derrubam). Ordena o painel de famílias.
9. **Objetivos das Casas** (gerados do que falta, sempre coerentes): *conseguir terra* (muita gente,
   pouca terra), *melhorar a casa* (riqueza sobrando), *aliança por casamento* (com uma Casa útil),
   *superar a rival*, *vingar uma afronta*, *juntar riqueza* (pobre), *formar um herdeiro no ofício*,
   *unir-se a outra Casa* (pequena, sem herdeiro, aliada). Cada objetivo tem progresso, prazo e
   resultado; cumprir dá prestígio e contentamento; falhar frustra (quebra de expectativa).
10. **Vontades pessoais:** cada pessoa tem **vocação** (ofício desejado; ao crescer, sai pela
    tradição da Casa, pelo traço ou ao acaso) e **desejos** (casar por amor com alguém, ficar rico,
    proteger os irmãos, sair da Casa, superar o pai…). Quando a vocação bate com a tradição, tudo bem;
    quando não, nasce um **conflito** que se resolve com o tempo:
    - **conformar-se** (segue o ofício da Casa e acumula ressentimento),
    - **negociar** (a Casa aceita; ela perde um pouco de prestígio),
    - **desligar-se**, que tem **tom** (amigável, neutro, hostil) e **forma** (às claras ou escondido):
      amigável leva a bênção e uma ajuda em riqueza; hostil vira rivalidade entre as Casas; escondido
      é sair à noite — a família só descobre no dia seguinte (aviso e reação).
11. **Casamentos com objetivo:** além dos de amor (etapa 6), Casas **arranjam** casamentos para
    aliança, terra, riqueza ou para apagar uma rivalidade (com dote). O noivo arranjado pode **aceitar,
    resistir ou fugir** (com quem ama, às vezes em segredo). Casamento arranjado com relação ruim vira
    **casamento infeliz**: brigas, separação ou fuga. Casamento secreto pode ser descoberto.
12. **União de Casas:** duas Casas aliadas, uma pequena e sem herdeiro adulto, se fundem (a maior
    absorve a menor; brasão da maior, terras somadas).
13. **Corrupção:** Casas gananciosas (chefe ganancioso, objetivo de riqueza) **desviam** do estoque do
    reino quando trabalham, ou **subornam** para vencer disputas de terra. Há chance de serem pegas
    (Casas honestas vigiam): **escândalo** — prestígio cai, relações azedam, aviso no HUD.
14. **Infiltração:** uma Casa com rival forte pode **plantar** alguém na rival (casamento arranjado ou
    agregado). O infiltrado **espia** (a Casa dele adianta os próprios objetivos contra a rival) e
    **sabota** (atrasa um objetivo, desvia riqueza). Pode ser **descoberto**: escândalo grande, rixa
    aberta, o infiltrado é expulso. O jogador só vê o que já veio a público.
14b. **Amores malvistos (pedido do autor):** dois homens ou duas mulheres podem se apaixonar, mas só em
    **segredo** — é malvisto como na Idade Média. Se descoberto, vira **escândalo** para a Casa (honra e
    prestígio caem, relações com a família azedam) e a pessoa sofre pressão: conforma-se e separa-se,
    ou se afasta da Casa (às claras ou fugindo). O tratamento é sóbrio, sem caricatura.
15. **Quebra de expectativas** como evento explícito: herdeiro que recusa o ofício, noiva que foge,
    aliança que trai, casa que não sai, filho escondido que aparece. Cada uma gera mensagem, mexe em
    relações, opiniões e objetivos.
16. **Interface (só teclado):** o cartão do **E** ganha parentesco, vocação, desejo, segredo (só se
    público) e o objetivo da Casa; o painel **C** ganha tradição, riqueza, terras, nível da casa,
    especialidade, prestígio e objetivo atual; uma **crônica** (tecla **K**) lista os últimos
    acontecimentos das Casas.
17. **Persistência** de tudo; saves da etapa 6 continuam abrindo (valores padrão coerentes).

**Fora (vai para o Governo, etapa 8)**
- Leis, impostos, regente, decisões do jogador sobre disputas. A corrupção aqui é entre Casas e
  contra o estoque; a corrupção do governante fica para a etapa 8.
- Infiltração vinda de outros reinos (etapa 9).

**Anti-objetivos**
- Objetivos sem sentido (Casa rica querendo "juntar riqueza", Casa sem filhos arranjando casamento).
- Spam de mensagens: a crônica guarda tudo; o HUD só mostra o que importa ao jogador.
- Reino travado: tudo é regra horária/diária barata, sem custo por frame.

## 3. Decisões técnicas

| Tema | Decisão |
|---|---|
| Onde roda | Nova `HouseSim` (Node) chamada pela `VillageSim` a cada hora, depois da `SocietySim`; regras puras em `HouseRules` e `Kinship` (static), testáveis sem nós |
| Dados da Casa | `family` ganha: `tradition`, `values {wealth, land, prestige, faith, honor}`, `wealth`, `plots: Array[Rect2]`, `skill {profession: horas}`, `house_level`, `prestige`, `goal {kind, target_id, progress, deadline_hour}`, `rival_id`, `secrets: Array` |
| Dados da pessoa | `vocation`, `desire {kind, target_id}`, `resentment`, `secret` (fugitivo, infiltrado de X, casado em segredo com Y), `adopted_by` |
| Riqueza | Moedas abstratas por Casa; preços em `GameConstants` (lote, melhorias, dote, suborno) |
| Lotes | Retângulos 8×8 alinhados à grade, dentro do território, sem construções nem árvores grandes; estacas (`Building.STAKE`, modelo do Blender) nos cantos, recoloridas |
| Melhorias | `Building.HOUSE` ganha nível (`house_level` no registro): modelos `house_stone.glb`, `manor.glb`; camas 4 → 6 → 8 |
| Guarda | Nova profissão `GUARD`; estado de patrulha no `PersonBrain`; ataque com `Combat.melee_targets` contra criaturas no território; no resumo, cada guarda reduz o dano de ataques |
| Objetivos | Gerador por pontuação (necessidade × valores da Casa); um objetivo ativo por Casa; reavaliado diariamente; prazo; resultado com eventos |
| Segredos | Flags privadas; descoberta por chance diária (vigilância das Casas honestas/curiosas); só segredos públicos aparecem na interface |
| Determinismo | RNG semeado por (semente do mundo, reino, hora) como nas etapas 5 e 6 |

## 4. Pronto quando

Testes headless para parentesco, adoção, tradição/vocação/conflito e as 6 formas de desligamento,
riqueza e preços, lotes (validade e compra), especialização, melhoria de casa, objetivos coerentes
(gerador e resolução), casamentos arranjados (aceitar/resistir/fugir/infeliz), união de Casas,
corrupção e escândalo, infiltração e descoberta, guarda patrulhando e atacando, persistência e
compatibilidade com saves da etapa 6; capturas da crônica, do painel com riqueza e terras, de lotes
marcados, de uma casa de pedra e um solar, de guardas enfrentando lobos e do cartão com parentesco.
