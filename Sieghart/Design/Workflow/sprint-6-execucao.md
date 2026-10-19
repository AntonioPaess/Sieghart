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

## Vinte IDs de S6 e próximos lotes

| Lote / IDs | Estado |
| --- | --- |
| 1: `scrollInverter`, `scrollHorizontal` | Implementação e revisão de integração nesta parte; aceite Mac pendente |
| Entrada — `smoothScroll`, `linearScroll`, `mouseAcceleration` | Planejados; definir pipeline de suavização/linearidade e limites de configuração sem alterar preferências globais sem restauração |
| 3: `focusFollowsMouse` | Implementado, desligado por padrão; aceite Mac pendente |
| Entrada — `mouseNavigation`, `mouseButtonShortcuts` | Planejados; definir navegação e conflitos de botões |
| Entrada — `mouseClickDebounce`, `keyboardDebounce`, `textSnippets`, `superKey`, `quitWindowProtection` | Planejados; cada módulo exige escopo, permissões e aceite próprios |
| 2: `switcher`, `windowLayout` | Implementados; Fast/build e aceite detalhados abaixo |
| Windows/Dock — `dockPreview`, `dockClick`, `windowMaximizer`, `autoQuit`, `spacesOrder` | Cinco IDs planejados; não confundir ação de preencher a tela com interceptação do botão verde |

Total após a parte 3: cinco IDs com implementação, quinze ainda planejados. `middleClick` já era entrega S4 e não é recontado como módulo novo de S6. Os demais lotes não foram iniciados.


## Parte 2 — layouts, encaixe e seletor de apps/janelas

19 de outubro de 2026, na mesma branch `sprint-6`, após `2b9d5e8`. Implementação sequencial pela sessão principal; nenhum agente adicional iniciado. Este lote cobre os IDs `windowLayout` e `switcher`. `windowMaximizer` significa o botão verde e permanece planejado. As referências de voz/ditado/desenho e Aegis continuam fora deste lote, com os limites registrados na auditoria.

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

Aceite físico pendente: Refresh e ativação em apps nativos/terceiros, app sem janelas, limites de tamanho e janelas que recusam AX; monitores Retina e secundários acima/à esquerda; Dock em lados diferentes; encaixe real por título, resize/clique sem encaixe, Spaces/full-screen; Undo após mover manualmente/fechar janela; revogação, lock/wake e encerramento; CPU e responsividade de apps lentos. A revisão independente de fechamento da Sprint 6 continua pendente, além do aceite físico. Este commit não declara a sprint inteira concluída.

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
- Aceite físico de scroll/permissões/layout/encaixe e novo foco continua pendente. Foco exige avaliação real de responsividade, CPU, sobreposição de janelas, troca de apps, segundo monitor, uso de cliques/scroll e lock/sono. A revisão independente de fechamento da Sprint 6 permanece pendente. Quinze IDs da sprint ainda estão planejados.

Evidências: [Fast](../Validation/sprint-6-part3/verification.json), [contratos novos](../Validation/sprint-6-part3/contract-results.json), [fontes](../Validation/sprint-6-part3/source-manifest.json), [build](../Validation/sprint-6-part3/app-build.json). Logs/xcresult ficam nas pastas temporárias da execução. Sem push solicitado para esta parte.
