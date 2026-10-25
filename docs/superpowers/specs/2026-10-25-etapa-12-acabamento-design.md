# Etapa 12 — Acabamento (design)

Data: 2026-10-25 · Status: aprovado pelo fluxo (o autor autorizou as decisões; cada uma vai como `Ruling:`)

## 1. Intenção

Roadmap: "menu, salvar/carregar, som, balanceamento". O jogo hoje abre direto no mundo, salva sozinho num arquivo
único e não tem som.

## 2. Escopo

**Menu inicial** (cena nova, a cena principal do projeto), só teclado (setas e Enter, Esc volta):
- **Continuar** (o último jogo salvo), **Novo jogo** (escolhe um de 3 espaços; se o espaço tiver um jogo, pede
  confirmação), **Carregar** (lista os 3 espaços: reino, dia, quando foi salvo), **Opções** (volume da música e dos
  efeitos, música ligada/desligada), **Sair**.
- Fundo: o título "MeuJogo — reino vivo" sobre uma vista do mundo (cor sólida se não houver).

**Menu de pausa** (Esc com nada aberto no jogo): **Continuar**, **Salvar**, **Opções**, **Voltar ao menu** (salva
antes), **Sair** (salva antes). O jogo para (árvore pausada) enquanto o menu está aberto.

**Salvar e carregar:** 3 espaços (`user://save_1.bin`..`save_3.bin`) com um resumo ao lado (`save_N.meta`: reino,
dia, data e hora do save). O salvamento automático a cada minuto continua, no espaço do jogo aberto. O save antigo
(`user://save.bin`) vira o espaço 1 na primeira vez que o menu abre.

**Som**, todo gerado por script (como os modelos), sem arquivos de fora:
- `tools/sounds/make_sounds.py` (Python + numpy) gera os `.wav` em `assets/sounds/`: passos, golpe de espada, acerto,
  arco, machado na árvore, picareta na pedra, pá, fogueira (laço), chuva (laço), vento do dia (laço), grilos da noite
  (laço), pássaros, cliques do menu e duas músicas em laço (dia e noite) com um "alaúde" sintetizado.
- No jogo: passos do jogador ao andar, golpes, coleta; trabalho e cavar das pessoas próximas (3D, com teto de vozes);
  fogueiras acesas (3D); ambiente dia/noite e chuva (2D, com transição); música dia/noite com transição; cliques nos
  menus.

**Balanceamento:** rodar a simulação longa e a captura; ajustar o que estiver fora (população, mortes, guerras,
fome, mercadores), sempre por constantes.

## 3. Decisões

- **Ruling:** sons são gerados por `tools/sounds/make_sounds.py` e versionados como os `.glb`; nunca se edita um `.wav`
  à mão (mesma regra dos modelos).
- **Ruling:** o menu é uma cena própria (`scenes/menu.tscn`) que instancia `main.tscn` com o espaço escolhido; os testes
  continuam usando `main.tscn` direto (sem save).
- **Ruling:** opções de som ficam em `user://settings.cfg` (`ConfigFile`), fora do save do mundo.
- **Ruling:** Esc abre a pausa só quando nada mais usa o Esc (construção, painel P, cartão).

## 4. Adendo após a revisão do design

- **Ruling (Esc):** a construção marca o Esc como usado; a pausa ouve `ui_cancel` (não `build_cancel`, que também é o
  clique direito) e só abre com nada aberto (construção, painel P, painéis do ADM).
- **Ruling (pausa):** a árvore pausa; o menu de pausa e o som rodam sempre (`PROCESS_MODE_ALWAYS`); testes que pausam
  despausam no fim.
- **Ruling (espaços):** `SaveSlots` cuida de caminhos, resumo e migração. "Novo jogo" apaga `.bin`, `.bak`, `.tmp`,
  `.corrupt` e o resumo. O resumo (reino, dia, quando) é um arquivo à parte escrito depois do save dar certo (por
  `.tmp` e troca); se faltar, a linha diz só "jogo salvo". A migração do `save.bin` antigo leva junto `.bak`/`.tmp` e
  só acontece com o espaço 1 vazio. O `World` sem menu usa o espaço 1. `tools/new_world.ps1` apaga os 3 espaços.
- **Ruling (sair):** "Sair" e "Voltar ao menu" chamam `save_now()` e só seguem se der certo (senão avisam).
- **Ruling (cena):** um autoload `Session` leva o espaço escolhido do menu para o `World` (`change_scene_to_file`).
- **Ruling (som):** autoload `Sound` (`PROCESS_MODE_ALWAYS`) cria os canais Música, Efeitos e Ambiente; laços
  marcados em tempo de execução; vozes 3D num conjunto de 8 que vão até o lugar do som (nada além de 25 m do ouvinte);
  o ouvinte (`AudioListener3D`) fica no jogador; fogueiras têm seu próprio laço 3D; passos pela distância andada
  (passo mais longo correndo); opções em `user://settings.cfg` (caminho trocável nos testes); sons carregados só se
  existirem (nenhum erro de motor nos testes).
