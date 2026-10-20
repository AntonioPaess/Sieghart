# Sprint 6 — execução por partes

## Parte 1 — scroll e infraestrutura de entrada

18 de outubro de 2026, branch `sprint-6`, baseline `04723e7`. Início autorizado pelo usuário após o gate pré-S6 executado e revisto. Este lote implementa somente `scrollInverter` e `scrollHorizontal`; não fecha a Sprint 6 nem o aceite físico do Mac. Um commit próprio registra esta parte; nenhum push foi solicitado para a Sprint 6.

As duas opções ficam desligadas por padrão e persistem em `input.scroll.*` no domínio fornecido pelas preferências do app. Workspace → Activation inclui os controles, modificador Shift/Option/Control, inclusão explícita de eventos contínuos, estado, Retry e botão de Accessibility. A ativação acompanha `startUtilities`/`stopUtilities`; fixtures `managesWindows: false` não iniciam o recurso.

Um pipeline recebe somente `scrollWheel`, no main run loop, usando `.defaultTap`; não lê teclas ou texto. A transformação pura inverte os dois eixos em linhas, pixels e valores fixos 16.16; depois soma o vertical no horizontal e zera o vertical quando o modificador está presente. Remove somente o modificador usado. Outros flags, phase, momentum, precisão, posição e timestamp são preservados. Soma/negação inválida ou representação fora do intervalo de 32 bits preservam o evento inteiro. Um evento sem componente vertical não é redirecionado novamente.

Eventos contínuos ficam intactos por padrão. A opção para incluí-los afeta mouse e trackpad conforme os eventos recebidos: a API pública não distingue confiavelmente o dispositivo. Não prometemos identificação por hardware. O conflito com qualquer atalho só de modificadores que inclua o modificador escolhido impede a instalação; também é reavaliado em cada amostra e na checagem de saúde, cobrindo alterações tardias de companion/voice/clipboard/audio. Nenhum modificador conflitante é consumido pelo scroll. MiddleClick mantém sua implementação anterior.

Sem opção ligada ou sem Accessibility disponível, nenhum tap é criado. O prompt de permissão existe somente no botão explícito. Desligar, parar, revogar permissão, dormir ou bloquear a tela ou perder sessão ativa liberam o backend. Sono, bloqueio da tela e sessão ativa são três gates independentes; wake só retoma opt-in ainda válido. A saúde verifica revogação/conflito a cada segundo enquanto ativo e cada evento verifica novamente antes da transformação. Timeout/disable agenda reavaliação no main loop, com geração para invalidar callbacks antigos e evitar taps duplicados. Falha de instalação limpa o backend e permite Retry explícito.

## Evidências e aceite

- Testes Python da infraestrutura: `test-swift-test-index.py` e `test-project-sources.py`, 4 + 3 casos aprovados.
- Primeira execução isolada: `/private/tmp/sieghart-s6-input-part1`, 10/10 funções, 16/16 invocações, 125/125 fontes de produção; sem fontes alteradas, casos ausentes ou inesperados.
- Execução final focada: `/private/tmp/sieghart-s6-input-part1-verified`, **11/11 funções e 17/17 invocações aprovadas**, 125/125 fontes na cobertura, sem fontes alteradas, casos ausentes ou inesperados. Após finalizar screen lock e a invalidação de callback de start falho, somente o grupo `input` foi reexecutado. Contratos G19.01–G19.11, grupo/tag próprio `input`, roots LogicTests e MacContractsTests serializado. Fixtures usam defaults isolados e backend injetado. O teste da ponte CGEvent cria apenas uma amostra em memória; não instala taps ou publica eventos.
- Projeto sincronizado pelo gerador: 127 fontes app / 125 produção no target de testes. O runner deriva os grupos diretamente de GROUP_TAGS. O plano Fast foi atualizado pela descoberta final: 182 funções elegíveis; Complete descobre 246. A revisão de integração separou os gates de bloqueio/sessão e executou Fast: **182/182 funções e 867/867 invocações aprovadas**, em `/private/tmp/sieghart-s6-part1-fast-final`, sem alterações das fontes durante a execução. O Complete foi apenas descoberto nesta parte.
- Nenhum Sieg ou Xcode UI foi aberto; não houve acesso a hardware, event tap real, pedido de permissão, modelo ou conta. Build/testes CLI não demonstram comportamento físico ou desempenho.

Aceite Mac pendente: ligar cada opção em app autorizado, conferir roda mouse e trackpad/contínuos, signs/precision e inércia em apps diferentes, Shift sem dupla conversão, coexistência dos três modificadores com atalhos, revogação no painel do sistema, screen lock/sono/wake, encerramento e ausência de duplicação/CPU indevida. A revisão de integração corrigiu a independência dos gates e validou as regressões de atalhos/voz no Fast. A revisão independente de fechamento da Sprint 6 permanece para o conjunto final.

A pesquisa HeyClicky/voz recebida de outra worktree serve de referência e permanece não integrada; não houve cherry-pick nem alegação de merge. Aegis e migração Toni/Gantt/hellman não pertencem a este lote.

A [auditoria de aderência ao roadmap](sprint-roadmap-audit-2026-10-18.md) conferiu 77 IDs únicos e os compromissos S1–S5. As seis pendências antigas da ilha foram explicitadas como backlog para replanejar após S6; histórico GitHub/macOS e extensões vagas foram esclarecidos. A seção Aegis local de outro chat foi preservada e não incluída neste commit.

Evidências duráveis resumidas: [Fast revisado](../Validation/sprint-6-part1/fast-verification.json), [verificação](../Validation/sprint-6-part1/verification.json), [contratos](../Validation/sprint-6-part1/contract-results.json), [hashes das fontes](../Validation/sprint-6-part1/source-manifest.json). Logs, índice completo, descoberta e xcresult permanecem na pasta temporária da execução.

## Vinte IDs de S6 e lotes entregues

| Lote / IDs | Estado |
| --- | --- |
| 1: `scrollInverter`, `scrollHorizontal` | Implementados (`G19.01`–`G19.13`); aceite Mac pendente |
| 2: `switcher`, `windowLayout` | Implementados (`G20.01`–`G20.13`); aceite Mac pendente |
| 3: `focusFollowsMouse` | Implementado (`G21.01`–`G21.07`), desligado por padrão; aceite Mac pendente |
| 4: `mouseNavigation`, `mouseButtonShortcuts` | Implementados (`G22.01`–`G22.14`), botões 3..7, fila limitada e guarda de alvo; aceite Mac pendente |
| 5: `smoothScroll`, `linearScroll`, `mouseAcceleration` | Implementados (`G23.01`–`G23.04`), curvas de roda e backup/restauração reversível de `com.apple.mouse.scaling`; aceite Mac pendente |
| 6: `mouseClickDebounce`, `keyboardDebounce`, `textSnippets`, `superKey`, `quitWindowProtection` | Implementados (`G24.01`–`G24.06`), desligados por padrão, pausa em Secure Input e detecção de conflitos; aceite Mac pendente |
| 7: `dockPreview`, `dockClick`, `windowMaximizer`, `autoQuit`, `spacesOrder` | Implementados (`G25.01`–`G25.05`), opt-in explícito, lista de exclusão e backup/restauração de `mru-spaces`; aceite Mac pendente |

Após a revisão rápida: os 20 IDs têm código correspondente, mas `dockPreview`, `dockClick` e `autoQuit` permanecem **parciais** por falta dos gatilhos nativos/observação contínua. Contratos com backends injetados não comprovam essa integração. `middleClick` já era entrega S4 e permanece separado. O aceite físico no Mac continua pendente de execução pelo usuário.


## Parte 2 — layouts, encaixe e seletor de apps/janelas

19 de outubro de 2026, na mesma branch `sprint-6`, após `2b9d5e8`. Implementação sequencial pela sessão principal; nenhum agente adicional iniciado. Este lote cobre os IDs `windowLayout` e `switcher`. `windowMaximizer` significa o botão verde e foi entregue na Parte 7. As referências de voz/ditado/desenho e Aegis continuam fora deste lote, com os limites registrados na auditoria.

Workspace → Windows e menu → More tools → Windows compartilham o mesmo controller. A lista só consulta o sistema após Refresh, tem busca local, seleção explícita para layouts, botões próprios para solicitar ativação do app ou elevar uma janela e feedback de falha. Não substitui Cmd-Tab. As mensagens de ativação descrevem a solicitação enviada à API, não confirmação visual de foco. A lista exclui o próprio app, apps sem interface regular, janelas minimizadas/full-screen e janelas sem geometria legível. Apps com data de lançamento não verificável não são ativados pelo backend.

O backend nativo usa Accessibility pública e revalida permissão, PID/data de lançamento e elemento AX antes da operação. IDs de janela são UUIDs associados à igualdade do elemento AX e à instância do processo, nunca à posição na lista. A descoberta consulta até 64 apps, 32 janelas por app e 128 janelas no total, com orçamento de um segundo verificado entre consultas e timeout AX de 80 ms por mensagem; a última sequência de atributos pode ultrapassar o orçamento. Uma lista interrompida é marcada Partial e pode ser atualizada explicitamente. Mantém no máximo 256 handles AX. Não lê imagens, conteúdo das janelas ou teclas.

Os oito layouts são metades esquerda/direita, quatro cantos, preencher a área útil e centralizar. Usam visibleFrame convertido para coordenadas AX a partir da tela primária; telas acima/à esquerda e origens negativas são suportadas. A tela de destino do botão é a de maior interseção com a janela atual; se desconectada, usa a mais próxima. O Dock/menu ficam fora da área útil. Centralizar limita o tamanho à área útil. Escrita verifica se posição e tamanho são alteráveis, lê o resultado efetivo e informa restrições do app. Falha parcial tenta restaurar ambos os atributos e distingue restauração confirmada de falha de restauração.

Undo guarda até 32 mudanças efetivas e só restaura a mesma janela se sua geometria atual ainda corresponder à última escrita (tolerância de dois pontos). Não sobrescreve reposicionamento manual posterior nem janela fechada. Se a restauração for recusada e a geometria continuar inalterada, conserva a entrada para Retry. Não altera preferências globais nem restaura automaticamente no encerramento.

Edge snapping fica desligado por padrão, persistido em `desktop.edgeSnapping`. O monitor global só é instalado após opt-in e Accessibility; observa down/dragged/up do botão esquerdo, sem consumir nem publicar eventos e sem polling. Guarda a janela sob o ponto de down; exige arrasto do ponteiro superior a quatro pontos, mesma janela/processo, deslocamento real de origem e tamanho sem mudança relevante. Clique simples, movimento do app sem arrasto, resize e janela fechada são ignorados. No release, proximidade de 20 pontos da borda física escolhe metade/canto; topo preenche área útil e base isolada não age. Undo restaura a posição onde o usuário soltou, preservando seu próprio arrasto.

Sono, lock e sessão inativa são gates independentes. Disable, stop e suspensão removem o monitor e invalidam candidatos/callbacks por geração; retomar requer o opt-in ainda ativo. Revogação é reavaliada em cada evento e ação; não existe tarefa periódica de saúde neste controller. Retry é explícito após permissão ou falha de instalação. Inicialização, previews e fixtures `managesWindows: false` não instalam monitor nem consultam janelas.

### Validação da parte 2

- Infraestrutura Python: 3 testes do gerador e 4 do índice aprovados. Projeto: 131 fontes no app, 129 de produção e 77 de testes/support no target de testes.
- Primeira execução focada `/private/tmp/sieghart-s6-desktop-part2`: 13 funções / 20 invocações aprovadas. Depois dessa execução, a revisão adicionou a exigência de evento dragged, posição obtida do próprio CGEvent, validação de data de lançamento e Retry seguro do Undo.
- Fast final `/private/tmp/sieghart-s6-part2-fast-reviewed`: **195/195 funções e 887/887 invocações aprovadas**, 129/129 fontes de produção, nenhuma fonte alterada, nenhum caso ausente ou inesperado. Todos os contratos G20.01–G20.13 foram incluídos. Complete descobriu 259 funções; não foi reexecutado integralmente nesta parte.
- Build Debug do aplicativo completo: **BUILD SUCCEEDED**, arm64 + x86_64, sem assinatura e sem executar o app. A tentativa inicial no workspace exclusivo dos testes não tinha o Info.plist da raiz; a execução final usou o projeto original. Nenhuma fonte diverge do manifesto Fast aprovado.
- Geometria, múltiplas telas, falha parcial/rollback, limite de Undo, handles antigos, constraints, opt-in/permissão, clique/resize/arrasto, callbacks obsoletos, lock/sono/sessão e ativação explícita foram exercitados com fixtures. Nenhum teste instalou monitor global, chamou AX nativo ou ativou apps/janelas reais.

Evidências da parte 2: [Fast](../Validation/sprint-6-part2/verification.json), [contratos G20](../Validation/sprint-6-part2/contract-results.json), [manifesto](../Validation/sprint-6-part2/source-manifest.json) e [build do app](../Validation/sprint-6-part2/app-build.json). Logs e xcresult ficam nas pastas temporárias acima.


## Parte 3 — foco por ponteiro e recuperação do teste manual

19 de outubro de 2026, após `b6f4b94`, mesma branch `sprint-6`. A pedido do usuário, o aceite físico das partes anteriores foi deixado pendente e o próximo módulo avançou sem outros agentes. Esta parte acrescenta somente o ID `focusFollowsMouse`, usando também o trackpad; não exige mouse externo. Corrige explicações/recuperação das partes anteriores sem recontá-las como novos módulos.

**Foco:** Workspace e menu → Windows incluem **Focus window under pointer**, desligado por padrão, com persistência em `desktop.focusFollowsPointer`. Após o ponteiro parar por 300 ms sobre uma janela externa elegível e visível, solicita ativação e AXRaise usando o backend existente. AppKit observa movimento e cancelamento por clique/scroll, global e localmente, sempre retornando o evento original; não lê teclas/texto nem publica eventos. O dwell é cancelável e não existe consulta periódica de janelas em repouso.

Antes de ativar, revalida opção, geração/ticket, permissão, sessão/lock/sono, botões pressionados, posição atual do ponteiro e identidade/frame da janela. Um segundo hit-test antes da ativação evita usar o alvo antigo quando a janela sob o ponteiro mudou. Ignora o próprio app, full-screen/minimizadas e janela já focada. A seleção manual dos layouts permanece intacta. Clique, scroll, nova movimentação, disable, stop, revogação e suspensão invalidam trabalho pendente; callbacks de monitores falhos/antigos não têm efeito. Falha de instalação do encaixe não invalida foco por ponteiro; desligar foco não desliga encaixe.

**Relato de teste:** o usuário informou que o pedido de Accessibility não apareceu e o scroll não funcionou mesmo após autorizar no macOS; confirmou estar usando trackpad do MacBook. O pipeline já excluía eventos contínuos por padrão, mas **Include smooth scrolling** não explicava esse caso de forma suficiente. A opção agora se chama **Include trackpad and smooth-scroll mice** e explica sua aplicação ao trackpad. Ao receber evento contínuo ignorado, o controller mostra um aviso sem mudar o comportamento/persistência de opt-in; o aviso só publica alterações de texto, não cada amostra. Isso é uma causa possível reproduzida em teste, não comprovação de causa física única ou de aceite concluído.

O botão **Open Accessibility settings** usa uma ação compartilhada: pede consentimento se não autorizado e abre explicitamente o painel, pois o pedido assíncrono não garante novo alerta ou autorização imediata. **Locate this copy of Sieghart** revela o bundle da instância atual no Finder para distinguir cópias. A permissão continua sendo concedida pelo usuário. Nenhuma aprovação foi alterada, nenhuma entrada TCC foi apagada e nenhuma permissão real foi pedida durante a validação. A inspeção somente de leitura confirmou que o build Xcode em execução vinha do projeto esperado; isso não confirma confiança AX daquele processo.

**Clareza da tela Windows:** janelas aparecem antes dos apps, com rótulos próprios, três passos curtos e nome do alvo selecionado acima dos layouts. Filtrar uma janela para fora da lista limpa sua seleção. O menu usa área rolável de altura limitada para acomodar os controles. O [roteiro manual](sprint-6-teste-manual.md) usa duas janelas concretas do Finder e distingue selecionar, Show e Open.

### Validação da parte 3

- Infraestrutura Python: 3 testes do gerador e 4 do índice aprovados. Projeto com 133 fontes no app, 131 de produção e 77 de testes/support no target de testes.
- Contratos novos G19.12–G19.13 e G21.01–G21.07. A primeira tentativa teve somente erro de expressão opcional em teste novo; foi corrigida antes da execução. Focada `input|desktop`, `/private/tmp/sieghart-s6-part3-input-desktop-verified`: **33 funções / 46 invocações aprovadas**, sem fonte alterada ou casos divergentes.
- Após a revisão da independência de falhas dos monitores, Fast final `/private/tmp/sieghart-s6-part3-fast-final`: **204/204 funções e 896/896 invocações aprovadas**, 131/131 fontes, nenhum caso ausente/inesperado, nenhuma fonte alterada. Complete descobriu 268 funções; não foi executado integralmente nesta parte.
- Build do aplicativo: **BUILD SUCCEEDED**, Debug arm64, sem assinatura, sem abrir/reiniciar o Sieg ou interferir no app usado pelo usuário. Hashes das fontes coincidem com o Fast final. Os testes usam monitores, scheduler, janelas e efeitos de permissão injetados; não instalam monitores reais nem ativam apps/janelas.

Evidências: [Fast](../Validation/sprint-6-part3/verification.json), [contratos novos](../Validation/sprint-6-part3/contract-results.json), [fontes](../Validation/sprint-6-part3/source-manifest.json), [build](../Validation/sprint-6-part3/app-build.json).


## Parte 4 — navegação lateral e atalhos para botões extras do mouse

19 de outubro de 2026, após `12ba043`, mesma branch `sprint-6`. Implementa os IDs `mouseNavigation` e `mouseButtonShortcuts`.

- **Escopo e opt-in:** desligado por padrão em `input.mouseButtons.*`. Atende somente botões extras (`3...7`, como Side 4 / Side 5 e botões auxiliares) sem tocar em cliques primário (0), secundário (1) ou middle click (2), nem em cliques modificados por teclado.
- **Regras de captura e fila:** `MouseButtonBindings` e `MouseButtonPressState` exigem clique estacionário no mesmo botão (rejeitando arrastos > 4 pt ou mais de 600 ms), consomem o par down/drag/up do botão configurado e despacham a ação no release. Uma fila assíncrona limitada (máximo 8 ações) revalida que o app/janela alvo sob o clique não mudou antes de sintetizar atalhos (`⌘[`, `⌘]`, trocar abas, Mission Control/App Exposé, copiar/colar) ou acionar rotas internas do Sieghart (ilha, voz, área de transferência, janelas).
- **Validação da parte 4:** contratos `G22.01`–`G22.14` em `MouseButtonsTests.swift` (`mouse-buttons`). Na validação revisada (`/private/tmp/sieghart-s6-part4-fast-reviewed`), **218/218 funções e 918/918 invocações aprovadas**, com build Debug do app concluído (`74c5b43306b23dc6b927299eb5fb711ddb8a707d7ddd2dafde5beb02c263bb46`). Evidências arquivadas em [sprint-6-part4](../Validation/sprint-6-part4/verification.json).


## Parte 5 — curvas de rolagem (linear e suave) e aceleração do ponteiro

19 de outubro de 2026, mesma branch `sprint-6`. Implementa os IDs `linearScroll`, `smoothScroll` e `mouseAcceleration` em `ScrollInput.swift` e `WorkspaceView.swift`.

- **Curvas de roda (`linearScroll`, `smoothScroll`):** desligadas por padrão (`input.scroll.linear`, `input.scroll.smooth`, `input.scroll.stepPixels` em `8...96`, padrão `24`). Atuam sobre eventos discretos de roda (`!continuous`), normalizando picos de aceleração para passo fixo por notch (linear) e sintetizando deltas sub-linha em pontos e fixed-point 16.16 (smooth), compondo na mesma passagem com `scrollInverter` e `scrollHorizontal` e preservando trackpad contínuo intacto salvo opt-in explícito.
- **Aceleração do ponteiro (`mouseAcceleration`):** desligada por padrão (`input.pointer.acceleration.*`), com velocidade `0.25...3.0` e curva plana (`-1.0`). O `ScrollInputController` lê e faz backup persistente do valor original de `com.apple.mouse.scaling` antes da primeira escrita, recusa aplicar se a leitura inicial não for verificável e restaura automaticamente o valor original ao desligar, dormir, bloquear a tela, perder sessão, parar ou acionar **Restore macOS default**.
- **Validação:** contratos `G23.01`–`G23.04` em `ScrollInputTests.swift`.


## Parte 6 — debounce de clique e teclado, Hyper Key, proteção Cmd+Q/Cmd+W e snippets

19 de outubro de 2026, mesma branch `sprint-6`. Implementa os IDs `mouseClickDebounce`, `keyboardDebounce`, `superKey`, `quitWindowProtection` e `textSnippets` em `InputGuards.swift`, `InputGuardsController.swift` e `InputGuardsSettingsView.swift`.

- **Debounce de clique (`mouseClickDebounce`, `15...100 ms`) e teclado (`keyboardDebounce`, `15...80 ms`):** suprimem bounce mecânico no mesmo botão/tecla logo após a liberação, pareando o `up`/`dragged` correspondente para nunca deixar botão ou tecla presa. Cliques distantes (> 2 pt), autorepeat do macOS (`keyboardEventAutorepeat != 0`) e teclas modificadoras nunca são suprimidos.
- **Hyper Key (`superKey`):** transforma F18, Right Option ou Caps Lock em `⌃⌥⌘⇧` enquanto mantida pressionada, e bloqueia ativação caso o gatilho conflite com atalho global registrado.
- **Proteção contra encerramento/fechamento acidental (`quitWindowProtection`):** intercepta o primeiro `⌘Q` (e opcionalmente `⌘W`) em apps externos e exige segundo pressionamento entre `80 ms` e `1,5 s` no mesmo PID, ignorando autorepeat contínuo do primeiro aperto.
- **Snippets de texto (`textSnippets`):** validação anti-recursão/duplicidade (`2...32` caracteres sem espaço para o gatilho; `1...500` para o texto), buffer com suporte a Backspace e limpeza em clique/setas/Enter/Tab/Escape, expandindo via eventos Unicode anotados. Pausa automaticamente todo o processamento de teclado durante `IsSecureEventInputEnabled()`.
- **Validação:** contratos `G24.01`–`G24.06` em `InputGuardsTests.swift`.


## Parte 7 — previews e clique do Dock, botão verde, auto-quit e ordem fixa dos Spaces

19 de outubro de 2026, mesma branch `sprint-6`. Implementa os IDs `dockPreview`, `dockClick`, `windowMaximizer`, `autoQuit` e `spacesOrder` em `DockSpacesController.swift`, integrado ao `DesktopController` e `DesktopToolsView.swift`.

- **Previews e clique do Dock (`dockPreview`, `dockClick`):** inspeção opt-in de janelas por app do Dock (incluindo minimizadas, proporção geométrica, elevar e minimizar/restaurar) e ação configurável ao clicar em app já ativo (`minimizeOrRestore`, `hideActiveApp`, `bringAllForward`).
- **Botão verde (`windowMaximizer`):** intercepta opt-in cliques sobre o elemento AX `kAXZoomButtonAttribute`, preenchendo a área útil da tela (`visibleFrame`) sem entrar em full-screen nativo e restaurando o frame anterior da janela no segundo clique.
- **Auto-quit ao fechar última janela (`autoQuit`):** encerra após janela de graça (`1...15 s`) apenas apps regulares previamente observados com `>= 1` janela aberta cujo total permaneceu em `0`, protegendo `com.apple.finder`, `com.apple.systempreferences` e `com.sieghart.app`.
- **Ordem fixa dos Spaces (`spacesOrder`):** faz backup persistente de `com.apple.dock` → `mru-spaces` antes de gravar `false` e restaura o valor original ao desligar, dormir, bloquear a tela, perder sessão ou parar.
- **Validação:** contratos `G25.01`–`G25.05` em `DockSpacesTests.swift`.


## Extensão de IA na Sprint 6 — Integração local do Antigravity (`~/.gemini/antigravity`)

19 de outubro de 2026, a pedido do usuário, mesma branch `sprint-6`. Adiciona o provedor `.antigravity` ao monitoramento local de uso, atividade, preços e onboarding de IA do Sieghart, ao lado de Codex (OpenAI) e Claude Code (Anthropic).

- **Descoberta e contadores locais (`AIUsage.swift`, `AIActivity.swift`):** lê sessões locais em `~/.gemini/antigravity/brain/<conversation-id>/.system_generated/logs/transcript.jsonl` (ignorando `transcript_full.jsonl` para evitar contagem dupla), deduplicando `PLANNER_RESPONSE` por `step_index`, somando `input_tokens` (novos) + `cache_read_tokens` (cache lido) e `output_tokens`, e detectando trabalho ativo (`status == "RUNNING"` ou turno em aberto nos últimos 5 minutos) e nome de projeto via `cwd` / `tool_calls[].arguments.Cwd` sem reter textos de prompt.
- **Preços e UI (`ModelPricing.swift`, `ModelTokenPrices.json`, `ProviderMark.swift`, `AIUsageView.swift`, `AIUsageDetailsView.swift`, `OnboardingViewModel.swift`):** adiciona marca vetorial `AntigravityMark`, preços embutidos e parser oficial para modelos Gemini/Antigravity (`gemini-antigravity`, `gemini-4-argon`, `gemini-3-8-flash`, `gemini-2-5-pro`, `gemini-2-5-flash`), detecção no Onboarding (`InstalledAIProviders.detect`) e cartões de conexão/tokens na visão de IA.
- **Contratos novos:** `G07.03` em `LocalTokenReaderTests.swift` e `G08.07` em `AIActivityReaderTests.swift` (**26/26 funções aprovadas** no plano `Sieghart-Complete` filtrado por `spending|activity|pricing|usage`).


## Validação consolidada de fechamento da Sprint 6 (Partes 1–7 + Antigravity)

- **Infraestrutura Python:** `update-project-sources.py` (`App: 141 sources; tests: 139 production + 80 tests/support. Project valid.`), `test-project-sources.py` (3/3 OK) e `test-swift-test-index.py` (4/4 OK).
- **Execução focada de utilitários (`input|desktop|mouse-buttons`):** `/private/tmp/sieghart-s6-final-focused` — **62/62 funções e 85/85 invocações aprovadas**, 139/139 fontes de produção cobertas.
- **Execução completa de IA (`Sieghart-Complete`, `spending|activity|pricing|usage`):** `/private/tmp/sieghart-s6-antigravity-complete` — **26/26 funções e 26/26 invocações aprovadas** (incluindo `G07.03` e `G08.07` para Antigravity).
- **Suíte completa `Sieghart-Fast`:** `/private/tmp/sieghart-s6-final-fast` — **233/233 funções e 935/935 invocações aprovadas**, `missingTests: []`, `unexpectedTests: []`, `sourceChangedDuringRun: []`, `productionCoverageFiles: 139/139`, `xcodeExitCode: 0`.
- **Build CLI Debug do app (`Sieghart`):** **BUILD SUCCEEDED** em `/tmp/sieghart-s6-app-build/Build/Products/Debug/Sieghart.app/Contents/MacOS/Sieghart` (`SHA-256: e4dff51d8bcfa63c7e64da6e8be551698cb6c2aaa211c463388c5f2b779c5d57`), sem abrir `Sieghart.app` ou `Xcode.app`.
- **Evidências duráveis finais:** [verificação Fast](../Validation/sprint-6-final/verification.json), [contratos Fast](../Validation/sprint-6-final/contract-results.json), [verificação Complete IA](../Validation/sprint-6-final/ai-usage-complete-verification.json), [contratos Complete IA](../Validation/sprint-6-final/ai-usage-complete-contracts.json), [manifesto de fontes](../Validation/sprint-6-final/source-manifest.json) e [build do app](../Validation/sprint-6-final/app-build.json).
- **Pendências externas ao CLI:** aceite físico no Mac pelo usuário conforme [roteiro manual](sprint-6-teste-manual.md). Nenhum commit ou push foi executado sem solicitação explícita.



## Revisão rápida e fila posterior — 19 de outubro de 2026

O pedido atual autoriza commit/push da entrega e adia correções para branch separada. A [fila do chat Sieg — Revisão](revisao-pos-sprint-6/README.md) preserva a revisão recebida, a triagem e os achados novos; o chat não foi acionado. A revisão rápida não equivale à aprovação completa da Sprint 6.

Correções de escopo na documentação: os cartões de janelas são abertos pela UI, sem hover no Dock; a ação de clique do Dock não tem chamador de produção; auto-quit depende de Refresh e pode confundir falha AX com zero janelas. Esses IDs permanecem parciais. Manter auto-quit desligado até corrigir o tratamento de leitura desconhecida. Mouse Buttons executa comandos AX de menu e captura a ação no down; não oferece rotas arbitrárias/atalhos sintéticos nem rejeição de hold após a ação já executada.

A validação histórica acima antecede oito alterações de IA detectadas pelo manifesto. Não representa o estado final desses arquivos. A atualização de validação desta revisão será registrada abaixo com o resultado efetivo, sem substituir os artefatos recebidos.

### Validação das fontes finais para publicação

A lacuna dos oito arquivos de IA foi resolvida por nova execução: **Fast 233/233 funções e 935/935 invocações; Complete IA 26/26 funções e invocações; 139/139 fontes de produção, nenhum teste ausente/inesperado e nenhuma fonte alterada durante as execuções**. Os dois manifestos foram comparados novamente com as fontes atuais, sem divergências. Infraestrutura Python: 3 + 4 testes aprovados. App Debug arm64: **BUILD SUCCEEDED**, assinatura desabilitada, sem abrir o app/Xcode.

[Evidência Fast](../Validation/sprint-6-publicacao/verification.json) · [Complete IA](../Validation/sprint-6-publicacao/ai-verification.json) · [Manifesto final](../Validation/sprint-6-publicacao/source-manifest.json) · [Build](../Validation/sprint-6-publicacao/app-build.json). Logs temporários em `/private/tmp/sieghart-s6-publish-fast`, `/private/tmp/sieghart-s6-publish-ai` e `/private/tmp/sieghart-s6-publish-app-build.log`.

Há apenas dois avisos de linha em branco extra no fim de `DesktopToolsView.swift` e `WorkspaceView.swift`, preservados para não alterar fontes após a validação. Testes aprovados não fecham os achados da revisão nem o aceite físico. Publicação separada em commits das partes 4, 5, 6, 7, integração de IA e documentação; sem referências a assistente ou coassinatura. A seção Aegis de outro chat e os arquivos de pesquisa/estudo permanecem fora desses commits.
