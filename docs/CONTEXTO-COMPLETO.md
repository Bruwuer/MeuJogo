# MeuJogo — contexto completo (passagem para outro computador)

Escrito em 2026-10-24 para continuar o projeto em outra máquina, por outra pessoa ou por outra sessão
do Claude Code sem perder nada. Junto com este arquivo: `README.md` (como rodar), `CLAUDE.md` (regras
do projeto), `CONTINUAR.md` (onde parou), `docs/ENTREGAS.md` (o que cada etapa entregou),
`docs/superpowers/specs/` (designs) e `docs/superpowers/plans/` (planos).

---

## 1. A ideia do jogo (nas palavras do autor, resumidas)

- Jogo **2.5D isométrico, low-poly, medieval, mundo aberto**, feito no **Godot 4** (GDScript).
- O jogador é **só mais um no mundo, não o protagonista**. O mundo vive sem ele.
- Um **reino vivo**: pessoas chegam, avaliam o lugar e decidem ficar ou ir embora; têm opinião,
  traços, profissão; formam **famílias com brasões**, constroem as próprias casas, trabalham.
- O jogador pode fundar um reino (a primeira Cabana) e, **se ficar, terá de administrar** — e
  governantes podem **cultuar ou odiar** o jogador. Sair também tem consequências.
- **Pouco fantasioso.** Criaturas geradas **semi-aleatoriamente** por genoma de peças: animais reais
  (o lobo é a primeira criatura) e alguns inventados; elas **cruzam** e os filhotes herdam traços.
- **Ataques ao reino só com motivo** (fome, território, rancor, filhotes) — nunca "porque é noite".
- **Tudo por teclado.** Combate por botão, sem mouse para mirar e sem mira automática.
- Modelos e personagens feitos por **scripts Python do Blender** (com rig e animações), exportados
  em `.glb`. Nada de assets baixados.

## 2. Decisões e preferências do autor (valem sempre)

1. **Controles só no teclado**; combate por botão (Espaço ataca para onde olha), sem mira automática.
2. **Ataques de criaturas só por motivo** do bando.
3. **Costume medieval:** casamento e filhos **só entre homem e mulher**; adoção por casais ou viúvos.
   Relação entre pessoas do mesmo sexo **só em segredo**, malvista como na Idade Média: se for
   descoberta, vira **escândalo** (desonra para as Casas, pressão da família).
4. **O jogador não sabe de tudo.** Nada do que acontece no reino aparece no HUD (nem das etapas
   antigas: viajantes, nascimentos, casamentos, mortes, ataques, intrigas). O HUD mostra só o que é do
   jogador. Tudo vai para o **log do ADM** (arquivo + painel escondido do desenvolvedor).
5. **As coisas têm de acontecer de verdade.** Decisões das Casas não podem ser só números mudando:
   as pessoas **andam pelo mundo e fazem** (o filho foge de madrugada, o chefe finca as estacas do lote,
   a família trabalha na obra da casa, o casamento tem cerimônia, quem desvia vai ao armazém de noite e
   pode ser visto, o espião se muda e é pego por testemunhas, os amantes se encontram escondidos).
   As capturas de tela têm de mostrar isso **acontecendo sozinho**, não encenado.
6. **Fluxo completo, sem perguntas:** o autor autorizou qualquer decisão técnica; cada decisão vai
   como `Ruling:` no ledger e no design.
7. **Fazer as etapas na própria conversa** (não mandar um subagente fazer a etapa inteira) para
   economizar uso. Subagente só para a revisão final de cada etapa.
8. **Retomada automática DESLIGADA** (tarefa agendada "MeuJogo-Continuar" removida). Não religar sem
   pedido do autor.
9. Comunicação com o autor **em português**. Código e comentários em inglês; textos do jogo em português.
10. O autor não é programador profissional: explicar em linguagem simples, sem jargão.

## 3. Roadmap (10 etapas)

| # | Etapa | Estado |
|---|---|---|
| 1 | Fundação jogável: chunks, humanoide do Blender com WASD/Shift, câmera isométrica, testes | ✅ no `main` |
| 2 | Mundo com conteúdo: biomas, árvores/pedras/arbustos (MultiMesh), coleta, dia e noite, persistência delta | ✅ no `main` |
| 3 | Construção: inventário, construções com custo, fundação do reino | ✅ no `main` |
| 4 | Criaturas e combate: genoma de peças, comportamento, cruzamento, armas medievais, ataques com motivo | ✅ no `main` |
| 5 | Pessoas: gerador de pessoas, chegada e decisão de ficar, necessidades, construção autônoma | ✅ no `main` |
| 6 | Sociedade: famílias e brasões, relações, opinião sobre o jogador, aliados e inimigos internos | ✅ no `main` |
| 7 | **Casas e ambições** (ver §4) | 🔶 quase pronta, branch `etapa-7` |
| 8 | Governo: decisões com efeito, sucessão, governante NPC (corrupção, lealdade, culto ou inimizade) | a fazer |
| 9 | Mundo vivo: reinos NPC, simulação resumida fora da tela, diplomacia e guerras, novos reinos | a fazer |
| 10 | Acabamento: menu, salvar/carregar, som, balanceamento | a fazer |

## 4. Etapa 7 — Casas e ambições (o que o autor pediu e o que existe)

**Pedido:** famílias viram Casas com estilo de vida e preferências; crescimento de riqueza e de
terras; especialização; corrupção; infiltração; objetivos próprios gerados ao acaso mas coerentes;
melhoria de casa; união de Casas; casamento a serviço da família; quebra de expectativas. Filhos,
cônjuges, primos e tios com **vontade própria** — ex.: a Casa é referência em guerreiros, o filho não
quer ser guerreiro e se desliga (amigável ou não, neutro ou não, às claras ou escondido).

**Pronto (514 testes passando):**
- Parentesco completo (pais, filhos, irmãos, avós, tios, primos, cônjuges; adoção) que sobrevive à morte.
- Tradição e valores da Casa, riqueza por trabalho, especialização no ofício, prestígio.
- Lotes 8×8 marcados por estacas; casa simples → casa de pedra → solar (modelos do Blender).
- Objetivos por pontuação (terra, melhorar a casa, aliança, superar rival, vingança, riqueza, herdeiro,
  união), com prazo, sucesso e fracasso (expectativa quebrada).
- Vocações contra a tradição, conflito, e desligamento (amigável/neutro/hostil, às claras/escondido).
- Casamentos arranjados (aceitar / resistir / fugir com quem ama / casamento infeliz e separação),
  união de Casas, corrupção (desvio do estoque), espiões, vingança, romances secretos.
- Guardas (profissão nova) que patrulham com lança e enfrentam criaturas.
- **Log do ADM:** nenhum evento no HUD; tudo na crônica e em `user://adm_log.txt`; F9/F10 só para o ADM.
- **Feitos encarnados (`Deeds`):** cada decisão vira uma ida real a um lugar numa janela de horas;
  efeito só no fim; sem nó carregado, resumo na hora certa. Despedida de dia / fuga de madrugada até a
  borda; o chefe finca as estacas; a Casa trabalha na obra; cerimônia de casamento e de união na sede;
  desvio de madrugada no armazém; espião se muda de dia e vai relatar de noite; encontro secreto num
  ponto afastado; vingança de madrugada. **Segredos só vêm à tona por testemunhas** (adultos acordados
  de fora da Casa por perto; fora da tela, sorteio por quem está acordado).

**Falta na etapa 7:**
1. **Captura orgânica com feitos ao vivo.** Na última rodada (mundo sozinho, 12 dias com o jogador
   longe + 3 dias assistindo) **o reino da captura morreu**: lobos, javalis e rastejantes atacaram todo
   dia porque a vila nasceu perto das tocas (motivo de território que nunca acaba), as fazendas caíram,
   o povo passou fome e foi embora — sobrou ninguém para fazer feitos. Já corrigido: estacas não contam
   mais como construção para os bandos nem são atacadas. Próximo passo: rodar a captura com o jogador
   presente (reino carregado, tempo acelerado) e/ou rever o equilíbrio do motivo de território (uma vila
   perto de toca não pode ser atacada todo dia para sempre — o motivo deveria cansar ou ser defendido).
2. Revisão final da etapa por subagente (modelo mais capaz), correções Critical/Important com teste
   que falha antes, merge no `main`, atualizar `docs/ENTREGAS.md` e `CONTINUAR.md`.

## 5. Como o trabalho é feito (fluxo)

Skills *superpowers*: design curto (`docs/superpowers/specs/`) → plano (`docs/superpowers/plans/`) →
execução com TDD (teste que falha primeiro) e ledger em `.superpowers/sdd/<plano>/progress.md`
(pasta ignorada pelo git) → capturas com janela (`tools/capture.ps1`) inspecionadas → revisão final por
subagente → correções → merge fast-forward no `main` → apagar o branch → atualizar `CONTINUAR.md` e
`docs/ENTREGAS.md`.

Comandos (Windows, PowerShell):
- Testes: `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 [filtro]` → `RESULT: N passed, 0 failed`
- Jogo: `powershell -ExecutionPolicy Bypass -File tools/godot.ps1` (editor: `... tools/godot.ps1 -e`)
- Modelos: `powershell -ExecutionPolicy Bypass -File tools/build_models.ps1` (precisa do Blender)
- Capturas: `powershell -ExecutionPolicy Bypass -File tools/capture.ps1` (saem em `captures/`)

## 6. Arquitetura em uma página

- `GameConstants` (`scripts/core/game_constants.gd`): todos os números e textos. Enums só crescem no fim
  (compatibilidade de save).
- `WorldState`: tudo o que muda no mundo (save delta com MAGIC + MD5, `.bak`/`.tmp`), pessoas,
  criaturas, famílias, construções, crônica.
- Chunks carregados em threads (`WorkerThreadPool`); um único `ModelLibrary` sequencial.
- Simulação por hora: `VillageSim` → `SocietySim` → `HouseSim` (sorteios semeados por semente, reino e hora).
- Pessoas e criaturas são registros; só têm nó nos chunks carregados. `PersonBrain` decide (puro);
  `PeopleManager` dá contexto, alvos de trabalho e feitos; `Person` anda e age.
- `Deeds` (feitos), `HouseRules` (regras puras das Casas), `Kinship` (parentesco), `AdminLog` (arquivo do ADM).

## 7. Onde está cada coisa

- Código: `scripts/` (core, world, people, creatures, combat, ui), `scenes/`, `shaders/`.
- Testes: `tests/unit`, `tests/integration`, `tests/visual/capture.gd`.
- Modelos: `assets/models/*.glb` (gerados por `tools/blender/*.py`).
- Histórico git: `main` (etapas 1–6) e `etapa-7` (trabalho atual).

## 8. Como levar o projeto inteiro (código + histórico)

- **GitHub:** repositório privado `MeuJogo` (branches `main` e `etapa-7`). No outro computador:
  `git clone <url>`, `cd MeuJogo`, `git checkout etapa-7` e siga o `README.md`.
- **Google Drive:** pasta `MeuJogo` com os documentos (contexto, README, CLAUDE, CONTINUAR, ENTREGAS, designs).
- **OneDrive** da máquina original, pasta `MeuJogo`: `MeuJogo-projeto-completo.zip` e `MeuJogo.bundle`
  (histórico do git: `git clone MeuJogo.bundle MeuJogo`).
