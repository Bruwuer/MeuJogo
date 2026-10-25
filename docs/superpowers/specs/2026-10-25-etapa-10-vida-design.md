# Etapa 10 — Vida (design)

Data: 2026-10-25 · Status: aprovado pelo fluxo (o autor deu carta branca até as 06h; cada decisão vai como `Ruling:`)

## 1. Intenção (nas palavras do autor)

"Novas possibilidades para o mundo vivo, novas estéticas, novas animações, novos itens, morte, recolher corpos,
enterrar, opiniões, sentimentos, vontades, mercadores, necessidades." "Tudo deve ocorrer: recolher corpos deve ser
uma animação, e por aí vai."

Valem as regras: nada do reino no HUD; tudo acontece de verdade, por uma pessoa que anda e faz, **com a animação do
que está fazendo**; só teclado; sorteios semeados; números em `GameConstants`; modelos e animações por scripts do
Blender.

## 2. Escopo (em ordem de prioridade)

### 2.1 Morte, corpo e enterro
- Quem morre (velhice, batalha) **não some**: vira um **corpo** deitado onde morreu (registro `status = "dead"`,
  nó com a animação `dead`). Criaturas continuam como hoje.
- O reino do território onde o corpo está (ou o reino do morto, se fora de qualquer território) cuida dele: um
  adulto livre — de preferência da família — recebe o feito **recolher**: anda até o corpo, se abaixa (`pickup`),
  pega o corpo nos braços e **anda carregando** (`carry`, com o corpo no colo) até o **cemitério** do reino.
- **Cemitério:** o primeiro enterro escolhe um lugar livre perto da borda do reino (`k.cemetery`); as covas ficam
  em fileiras ali. No lugar da cova a pessoa **cava** (`dig`, com uma pá) e, ao terminar, a cova vira uma
  **sepultura** (construção `GRAVE`: monte de terra e cruz de madeira, modelo do Blender) com o nome do morto.
- **Velório:** a família adulta que estiver livre vai à sepultura ao entardecer do dia do enterro e **reza**
  (`pray`, ajoelhada). Isso conta como luto vivido (o luto passa mais rápido).
- Corpo esquecido: quem passa perto de um corpo não enterrado sente medo e o reino perde contentamento a cada dia
  (`BODY_UNBURIED_*`).
- Fora da tela, tudo isso é resumido (o corpo vai para a cova na hora em que o feito começa), como os outros feitos.

### 2.2 Sentimentos
- Cada pessoa tem `mood = {joy, grief, fear, anger}` (0..1), que volta devagar ao zero.
- O que mexe: morte de parente ou amigo → luto; casamento, nascimento, presente → alegria; ataque, batalha, corpo
  por perto → medo; roubo, insulto, escândalo da Casa → raiva.
- O que muda: luto e medo baixam o contentamento; luto deixa o trabalho mais lento; raiva baixa a relação com quem
  causou; medo aumenta a vontade de ir embora. Parado, quem está de luto fica de cabeça baixa (`mourn`).
- O cartão (E) mostra o sentimento mais forte em palavras ("de luto por Ana", "com medo").

### 2.3 Vontades e necessidades
- Necessidades além de fome e sono: **companhia** (sobe com o tempo; satisfeita por uma **conversa de verdade**: duas
  pessoas que se gostam andam uma até a outra no tempo livre e conversam, `talk`) e **fé** (devotos rezam junto à
  bandeira ao entardecer, `pray`). Necessidade alta baixa o contentamento.
- **Vontades** (`desire`, que existia mas nunca era sorteada): cada adulto ganha uma vontade pelo jeito dele (casar
  com quem ama, ficar rico, proteger os irmãos, sair da Casa, superar o pai) e ela pesa nas decisões que já existem
  (casamento, trabalho, saída da Casa). Aparece no cartão.

### 2.4 Mercadores e itens
- **Mercador ambulante:** de tempos em tempos um mercador (pessoa com mochila, `status = "merchant"`) surge na borda
  do mapa e **anda de reino em reino**; em cada sede para, negocia com o estoque do reino (leva o que sobra, deixa o
  que falta) e segue. Fora da tela, a viagem é resumida.
- **Moedas** (recurso novo do jogador e dos reinos) e **itens** novos: **pão** (comer cura mais que fruta),
  **ervas** (curam aos poucos), **feixe de flechas**. O jogador fala com o mercador (E) e negocia por teclado: o
  cartão do mercador lista o que ele vende e compra; teclas **Z/X/C** compram pão/ervas/flechas e **V** vende madeira
  e pedra por moedas.

### 2.5 Animações e estética novas (Blender)
- Humanoide: `dead`, `pickup`, `carry` (andando com os braços à frente), `dig`, `pray` (ajoelhado), `mourn`
  (cabeça baixa), `talk` (gestos).
- Modelos novos: `grave` (sepultura), `shovel` (pá na mão de quem cava), `pack` (mochila do mercador).

## 3. Fora do escopo
- Doenças, ferimentos que matam devagar, herança de bens pessoais.
- Comércio do jogador com os reinos (só com o mercador).

## 4. Decisões técnicas
- **Ruling:** o corpo é o próprio registro da pessoa com `status = "dead"` (não conta como residente, não come, não
  trabalha); `WorldState.residents` já filtra por `status == "resident"`. Ele sai do mundo só quando enterrado (o
  registro vira uma sepultura com o nome e a data). O sinal `person_died` continua; o nó vivo vira um nó de corpo.
- **Ruling:** feitos ganham `anim` (o clipe tocado no lugar) e `carry_id` (o corpo no colo enquanto anda).
- **Ruling:** `LifeRules` (puro) e `LifeSim` (por hora, por reino, depois do `HouseSim`) cuidam de corpos, enterros,
  sentimentos, necessidades e vontades; `MerchantSim` cuida dos mercadores.
- **Ruling:** cemitério = ponto do reino + fileiras de covas de `GRAVE_SPACING`; nenhuma construção grande.

## 5. Pronto quando
- Testes cobrem cada regra (corpo, recolher, carregar, cavar, sepultura, velório, luto, medo de corpo, conversa,
  reza, vontades, mercador, compra e venda, itens).
- Modelos e animações gerados pelo Blender; capturas mostrando, sem encenar: alguém carregando um corpo, alguém
  cavando, a sepultura, a família rezando, duas pessoas conversando, o mercador chegando.
- Revisão final por subagente, correções, merge.
