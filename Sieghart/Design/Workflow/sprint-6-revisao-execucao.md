# Revisão e pendências da Sprint 6

Pedido atual do usuário: resolver as revisões e pendências da Sprint 6, finalizar, testar, commitar e aguardar integração antes de iniciar Sprint 7. Branch `revisao/pos-sprint-6`, baseline `e229194`.

## Lotes de correção

| Lote | Achados | Critério de fechamento | Estado |
| --- | --- | --- | --- |
| 1 — Processos e concorrência | R1, R2, R4 | stdin fechado, timeout/cancelamento e término assíncrono; display sem espera no MainActor; stdin RPC serializado e protegido contra SIGPIPE | Implementado; focado 71/88; Fast final aprovado |
| 2 — Entrada e ciclo de vida | R3, R5, R6, R7, S6-R5 | Triagem documentada de timestamps; teardown de monitor/caching; dwell sem Task por movimento; pares de botões preservados após interrupção; busca e comandos de menu compatíveis | Implementado; focado 92/428; Fast final aprovado |
| 3 — Dock e preferências | S6-R1, S6-R2, S6-R6 | AX desconhecido nunca encerra apps; observar fechamento real; gatilhos nativos do Dock; pareamento/recuperação do botão verde; restaurar preferências somente quando ainda pertencem ao recurso | Implementado; Dock corrigido 35/54; Fast final aprovado; Mac pendente |
| 4 — Antigravity e preços | S6-R3, S6-R4, S6-R7 | Endpoint vinculado ao processo, transporte limitado sem redirects, deadlines/cancelamento, expiração e inferências explícitas, preços e fontes verificáveis | Implementado; focado 19/19; Complete IA final aprovado |

R8: preservar os arquivos de outros trabalhos; nenhuma limpeza incidental. Não assumir que cada afirmação recebida seja um bug confirmado. O cabeçalho público documenta CGEventTimestamp em nanossegundos; validar a alegação R3 antes de mudar conversões. UI de Mouse Buttons já fica em Activation.

## Execução e gates

Somente GPT-6.1 Sol, um agente por vez; implementação atribuída ao chat Sieg — Revisão conforme pedido anterior do usuário, seguida de conferência independente da coordenação. Não iniciar Sprint 7 neste lote. Reaproveitar evidências e fixtures; adicionar testes de regressão apenas para comportamentos relevantes. Não acionar apps, hardware, contas ou permissões reais durante testes automatizados.

Um commit por lote, sem referência ao assistente ou coassinatura; documentação e aceite anteriores podem ser integrados ao fechamento. Preparar e rever tudo antes da publicação/merge. O aceite físico anterior continua válido no seu escopo e não é prova automática das correções novas. Registrar resultados, limitações e o que o usuário precisará retestar.

ROADMAP.md contém uma seção Aegis de outro chat, ainda fora dos commits. Preservar essa seção e os demais arquivos acadêmicos/pesquisas. Nenhuma alteração deles integra esta revisão.

## Registro de execução — 19/out

### Lote 1 — implementado

R1/R2/R4 confirmados. `ToolProcess.swift`: stdin EOF, prazo configurável (60 s padrão), conclusão por terminationHandler, cancelamento e SIGKILL após 1 s se necessário. `MacDisplayPowerBackend.swift` + `DisplayPowerViewModel.swift`: pmset assíncrono, prazo 5 s, Task possuída/cancelada no shutdown. `AgentRPCProcess.swift`: escrita e close na mesma fila, descritor nonblocking e F_SETNOSIGPIPE, espera de escrita limitada (2 s), stop interrompe pipe cheio.

Hunks/testes: `Tests/SwiftTesting/Integration/FileReceptionTests.swift` (EOF, timeout/SIGTERM ignorado, cancelamento existente), `AgentProtocolTests.swift` (stdin fechado/cheio, stop/restart), `Core/DisplayPowerTests.swift` e `Tests/UtilityChecks.swift` (aguardar conclusão assíncrona). Evidência `/private/tmp/sieg-pos-s6/lote1-native-tests`: **71 funções / 88 invocações aprovadas**, manifesto estável, cobertura inclui 139/139 fontes. A tentativa na sandbox falhou no servidor de macros; execução CLI fora dela passou. Não abriu Sieg/Xcode nem contas. Cópias anteriores/hunks por lote em `/private/tmp/sieg-pos-s6/lote1`.

### Lote 2 — implementado

R3 não confirmado: SDK macOS 27 `CoreGraphics/CGEventTypes.h:134–135` declara CGEventTimestamp como nanossegundos desde startup. Conversão atual preservada; comparação de eventos físicos Carbon/CG/NSEvent não executada. R7: UI já está em Activation e foi preservada. R8: nenhum artefato alheio foi excluído. Revalidação final AX do foco mantida, inclusive sob o mesmo ponto (a janela pode mudar sob o ponteiro).

`PointerFocus.swift` mantém um worker de dwell e atualiza deadline/closure; `DesktopController.swift` não cancela esse worker a cada movimento. As duas consultas AX são intencionais e permanecem: a identidade da janela pode mudar sob a mesma coordenada. `NotchWidgetViewModel.swift`: remove monitor antes de reconfigurar/no stop, cancela observações, calcula o nível de overlay uma vez por reveal/atualização de workspace. `MouseButtonController.swift`: recupera captura dos botões ainda fisicamente pressionados. `MouseButtonActions.swift`: busca janela do PID sem truncar antes do filtro; CmdVirtualKey usado só quando CmdChar falta, preservando modifiers exatos. Testes em `Core/{DesktopTests,MouseButtonTests,DisplayPowerTests}.swift`. Recorte Complete desktop/mouse-buttons/utilities/interactions: **92 funções / 428 invocações**, manifesto estável, 139/139 fontes. Evidência `/private/tmp/sieg-pos-s6/lote2-tests`. Inclui teste injetado extra do display: MainActor progride e cancelamento é propagado sem pmset real.

### Lote 3 — implementado, contratos focados aprovados

`DockSpacesController.swift`: AXWindows inválido retorna nil; auto-quit exige app conhecido/bundle/contagem válida, revalida ao expirar e não reinicia grace a cada notificação. NativeDockActivityMonitor liga hover a ícones AX reais do Dock, mostra painel de cartões com foco/minimize/restore e liga clique simples do app ativo à ação escolhida. Observa criação/destruição de janelas via AXObserver, além de launch/terminate, sem depender de Refresh list. Destruição usa a identidade do observer, não GetPid do elemento já destruído; eventos são consolidados por 100 ms. Sono/lock/stop removem observações e cancelam grace. NativePairedLeftClickMonitor captura down/drag/up apenas no botão verde, drena release após disable e reabilita taps interrompidos sem repetir ação. O Dock usa observação passiva: confirma clique curto no up e preserva arrasto, hold, modificadores e menus nativos, conforme a correção da conferência independente abaixo.

`ScrollInput.swift` e o controle de Spaces persistem o último valor aplicado. Restore lê o valor atual e escreve o backup só se ainda corresponder ao valor próprio; mudança externa é preservada, leitura desconhecida não escreve. Pausa libera backup após restore e retomada captura a referência atual. Testes em `Core/{DockSpacesTests,ScrollInputTests}.swift`: roteamento nativo injetado, última janela sem refresh, AX desconhecido antes/durante grace, pares/recovery e preferências externas. Evidência `/private/tmp/sieg-pos-s6/lote3-contract-tests`; **54 funções / 69 invocações** aprovadas. Duas tentativas anteriores apontaram erros de isolamento Swift 6 nos novos callbacks; corrigidos antes dos testes. Hover/AX/tap reais continuam sujeitos ao roteiro manual; não foram executados nesta sessão.


### Lote 4 — implementado; recorte focado aprovado

`AIUsage.swift`: descoberta assíncrona usa runner com deadline e stdin fechado; valida UID/path real do language server e identidade de lançamento no kernel, descobre listeners do PID exato via lsof e revalida propriedade antes/depois do pedido. Não sonda portas adjacentes. Transporte próprio ephemeral, sem cache/cookies/credenciais/proxy, rejeita redirects, limita corpo pelo Content-Length e durante o stream a 256 KiB, deadline absoluto de 2 s por pedido e cancelamento invalidateAndCancel; prazo global de leitura de 8 s, mais até 1 s de término de subprocesso. Tokens não são incluídos em erros/descrições ou logs. Testes usam somente tokens inventados, discovery e URLProtocol injetados.

Relatórios locais têm proveniência v2 e expiram em 5 min ou no reset. Rótulos vêm da resposta e duração desconhecida é mostrada como desconhecida; removidas inferências de 5h/semanal e família Claude. `AIUsageViewModel.swift` propaga cancelamento ao worker e substitui preços Antigravity antigos do cache. Views exibem quotas genéricas quando a duração não vem da fonte e separam equivalentes de API de cobrança/quota do produto. `ModelPricing.swift` não atribui preço a aliases reasoning/trial, suporta validade promocional e limiar documentado de contexto longo. `ModelTokenPrices.json`: seis modelos conferidos; dois aliases sem preço verificável removidos; fonte/data e prazos em [auditoria de preços](../Validation/revisao-pos-sprint-6/price-source-audit.md).

Recorte focado spending/pricing: **19 funções / 19 invocações**, manifesto estável, 139/139 fontes; `/private/tmp/sieg-pos-s6/lote4-contract-tests`. Uma fixture tentava mudar campo let; sua construção foi corrigida antes de executar. Depois desse recorte, a checagem final acrescentou o caso de PID reutilizado/troca de dono após resposta e retenção temporária do tap até drenar release; serão abrangidos pelo Fast/Complete finais abaixo. O lote 3 recebeu essa proteção de lifetime e o teste de relaunch de preferência sem nova intervenção física.

Roteiro manual atualizado com nomes reais de controles, hover/clique nativos, fechamento sem Refresh list, AX desconhecido, interrupções, mudanças externas de preferências, quotas expiradas e preços. Referência histórica de aceite não foi transformada em aprovação do código novo.

## Estado da conferência final

Fast completo, recorte Complete de IA e build CLI finalizados e aprovados. Nenhum commit, push ou merge realizado. HEAD/ref foram confirmados por leitura como `revisao/pos-sprint-6` em `e22919403134600e339459f665915c4c0b3f30f1`; não foi executado Git status/diff. FileProvider bloqueou leitura de fonte e de evidência histórica: comandos desta revisão foram interrompidos e apenas AIUsageView.swift foi reconstituído com os bytes pré-lote 4 e suas alterações registradas. Não houve substituição por HEAD, limpeza incidental ou mudança da estrutura do repositório. ROADMAP.md/Aegis e pesquisas/arquivos acadêmicos permaneceram fora das alterações.


## Fechamento da implementação — pronto para conferência independente

- **Fast final:** 254/254 funções e 968/968 invocações aprovadas após correções do Dock. [Verificação](../Validation/revisao-pos-sprint-6/fast-verification.json) e [contratos](../Validation/revisao-pos-sprint-6/fast-contracts.json).
- **Complete IA final** (`usage|spending|activity|pricing|agent-room`): 75/75 funções e 77/77 invocações aprovadas. [Verificação](../Validation/revisao-pos-sprint-6/ai-verification.json) e [contratos](../Validation/revisao-pos-sprint-6/ai-contracts.json). Inclui regressões novas de identidade/PID, redirects, limite de corpo, deadlines/cancelamento, quotas/preços e RPC com runtimes de fixture.
- Os dois manifestos Swift são idênticos: **221 entradas**, sem mudança durante as execuções ou depois delas. A cobertura de produção inclui **139/139 arquivos esperados**. [Manifesto Swift](../Validation/revisao-pos-sprint-6/source-manifest.json); [seis inputs adicionais](../Validation/revisao-pos-sprint-6/additional-input-manifest.json), incluindo preços JSON, projeto, runner/index, plano Complete e Info.plist. A fonte recuperada mantém as verificações de expiração, a view de allowance e o modelo desconhecido sem alias inventado.
- **Build CLI Debug universal (arm64 e x86_64): BUILD SUCCEEDED**, `CODE_SIGNING_ALLOWED=NO`, sem abrir o aplicativo ou Xcode. Executável em `/private/tmp/sieg-pos-s6/AppBuild/Build/Products/Debug/Sieghart.app/Contents/MacOS/Sieghart`. [Relatório/hash do build](../Validation/revisao-pos-sprint-6/app-build.json). O único aviso é extração de metadata AppIntents ignorada porque o app não depende desse framework; não é falha de compilação.
- Procedência: as fontes de runtime/testes continuaram no ROOT original, por symlinks da pasta temporária de projeto do runner. Não foi usado runtime alternativo nem espelho de fontes. O wrapper run-checks.sh ficou aguardando FileProvider; o mesmo runner Python foi chamado diretamente, sem modificá-lo. O primeiro build do app nessa pasta temporária falhou por Info.plist ausente; copiou-se o arquivo original byte a byte, conferiu-se o hash e repetiu-se **somente o build**. Projeto, Info.plist e catálogo de preços empacotado conferem com o original. Falha de infraestrutura preservada em `/private/tmp/sieg-pos-s6/app-build-missing-input.log`.
- Logs/xcresult finais em `/private/tmp/sieg-pos-s6/dock-followup/final-fast`, `final-complete-ai` e `final-app-build.log`. As pastas anteriores são histórico da primeira entrega. [Resumo durável](../Validation/revisao-pos-sprint-6/verification.json).

### Separação de arquivos e hunks

Os snapshots cumulativos ficam em `/private/tmp/s6-review-lotes/lote-{1,2,3,4}/`, cada qual com manifest.json. O índice `/private/tmp/s6-review-lotes/commit-lotes.json` lista arquivos e patches; `changes.patch` de cada lote contém os hunks dos arquivos existentes. O snapshot do lote 2 foi reconstruído com as cópias anteriores ao lote 3 para preservar sua fronteira. Não contém repositório completo, credenciais, pesquisas ou trabalhos acadêmicos.

| Lote | Arquivos de implementação/teste alterados (relativos a Sieghart/) |
| --- | --- |
| 1 | `Sieghart/Core/Services/Files/ToolProcess.swift`; `Sieghart/Core/Services/Display/MacDisplayPowerBackend.swift`; `Sieghart/Core/Services/AI/AgentRPCProcess.swift`; `Sieghart/Features/DisplayPower/ViewModels/DisplayPowerViewModel.swift`; `Tests/SwiftTesting/Core/DisplayPowerTests.swift`; `Tests/SwiftTesting/Integration/{FileReceptionTests,AgentProtocolTests}.swift`; `Tests/UtilityChecks.swift`. |
| 2 | `Sieghart/Shared/Services/Desktop/{PointerFocus,DesktopController}.swift`; `Sieghart/Shared/Services/Input/{MouseButtonController,MouseButtonActions}.swift`; `Sieghart/Features/DynamicIsland/ViewModels/NotchWidgetViewModel.swift`; `Tests/SwiftTesting/Core/{DesktopTests,MouseButtonTests}.swift`. |
| 3 | `Sieghart/Shared/Services/Desktop/DockSpacesController.swift`; `Sieghart/Shared/Services/Input/ScrollInput.swift`; `Tests/SwiftTesting/Core/{DockSpacesTests,ScrollInputTests}.swift`. |
| 4 | `Sieghart/Core/Services/AI/{AIUsage,ModelPricing}.swift`; `Sieghart/Features/AIUsage/ViewModels/AIUsageViewModel.swift`; `Sieghart/Features/AIUsage/Views/{AIUsageView,AIUsageDetailsView}.swift`; `Sieghart/Shared/Resources/ModelTokenPrices.json`; `Tests/SwiftTesting/Core/{LocalTokenReaderTests,UsagePricingTests}.swift`. |

Documentação/novas evidências ficam com o fechamento do lote 4: este registro, `sprint-6-teste-manual.md`, auditoria de preços e arquivos em `Design/Validation/revisao-pos-sprint-6/`. Os snapshots anteriores contêm registros de progresso, que não exigem commits separados de documentação.

### Limites e próximo passo

Os quatro lotes estão implementados e validados nos contratos disponíveis. A coordenação ainda deve revisar o diff e autorizar a integração. Não houve commit, push, merge, início da Sprint 7, subagentes ou mensagens de retorno para outros chats.

O aceite físico anterior é preservado apenas no escopo em que foi dado. Hover/clique reais do Dock, notificações AX de cada app, recuperação de event taps, lock/sono, permissões, CPU/RAM do processo completo e compatibilidade do serviço Antigravity real exigem reteste do [roteiro atualizado](sprint-6-teste-manual.md). Gate de Foundation Models/PCC, contas/Chaves e qualidade dos modelos reais não foi executado. O lote 1 reutilizou OCR/QR com imagens fictícias; não houve inferência de modelo de chat, acesso de conta ou captura de tela real.


## Correção após conferência independente — Dock

A coordenação identificou dois casos concretos no lote 3; a correção se limita a `Sieghart/Shared/Services/Desktop/DockSpacesController.swift`, `Tests/SwiftTesting/Core/DockSpacesTests.swift` e documentação/evidências correspondentes.

1. **Arrasto/ação no down:** removido o event tap de clique do Dock. NSEvent apenas observa down/drag/up/flags/contexto; não consome nem sintetiza eventos. DockClickObservation prepara a intenção no down, descarta drag, hold (>350 ms), deslocamento >4 pt, modificadores, clickCount diferente de 1, mudança de PID/launch/ícone e contexto; uma liberação válida executa no máximo uma vez. O estado desejado de minimize/restore e IDs de janelas são capturados antes da ação nativa. A aplicação no up é idempotente: não inverte uma restauração já feita pelo Dock e não atua sobre janelas novas. O interceptor pareado continua exclusivo do botão verde.
2. **Hover antigo:** DockHoverTracking recebe localização/hit-test/dwell injetáveis. Ao expirar a espera, lê a posição atual e revalida a identidade do ícone; só então apresenta com a geometria atual. Saída também cancela/esconde por teste geométrico barato antes da janela de 100 ms, sem nova consulta AX. Callbacks antigos são invalidados por geração.

Regressões determinísticas cobrem clique único, arrasto, hold, modificadores, contexto, movimento, troca de app/relaunch, ícone ausente, intenção anterior ao restore nativo e ausência de ação em janelas novas; saída na janela ignorada e saída sem evento entregue, além da troca de identidade/geometria ao expirar dwell. Não acessam Dock real. O limite HTTP é de **corpo**, via expectedContentLength e chunks (256 KiB); não há alegação de limite de headers.

Validação anterior (249/951 Fast, 75/77 Complete IA e build universal) permanece histórica para o estado anterior a esta correção. Recorte Desktop/Dock, manifestos e conferência final serão atualizados abaixo; não transferir aprovação de fonte antiga para a atual.


Recorte Desktop/Dock após a correção: **35/35 funções e 54/54 invocações**, manifesto estável, 139/139 arquivos de produção na cobertura. Evidência em `/private/tmp/sieg-pos-s6/dock-followup/focused`. Fast completo, Complete IA e build do mesmo estado serão registrados no fechamento atualizado, sem repetir os demais recortes históricos.


Fast completo após as correções do Dock: **254/254 funções e 968/968 invocações aprovadas**, sem mudanças nas fontes durante a execução; `/private/tmp/sieg-pos-s6/dock-followup/final-fast`. Diff incremental dos dois arquivos de código/teste em `/private/tmp/sieg-pos-s6/dock-followup/dock-corrections.patch` (índice/hunks em diff-index.json). As cópias cumulativas dos lotes 3/4 serão atualizadas mantendo os limites dos lotes 1/2.


### Fechamento atualizado da conferência do Dock

- Recorte Dock: **35 funções / 54 invocações**; Fast completo: **254 / 968**; Complete IA: **75 / 77**. Todas aprovadas. Os dois manifestos finais são idênticos (221 inputs Swift), sem mudança durante/depois das execuções e com cobertura incluindo 139/139 fontes de produção esperadas.
- Build CLI Debug universal **arm64/x86_64 aprovado**, CODE_SIGNING_ALLOWED=NO, sem abrir o app/Xcode. Preços empacotados, projeto e Info.plist continuam idênticos ao ROOT. Nenhuma mudança em HTTP, preços ou outros lotes foi necessária.
- Apenas **dois arquivos Swift** diferem da entrega anterior: DockSpacesController.swift e DockSpacesTests.swift. A localização/AX usados nas novas regressões são injetados; nenhum Dock real, gesto físico, permissão, conta ou modelo real foi acionado.
- [Evidência Dock](../Validation/revisao-pos-sprint-6/dock-verification.json), [Fast atual](../Validation/revisao-pos-sprint-6/fast-verification.json), [Complete IA atual](../Validation/revisao-pos-sprint-6/ai-verification.json), [build/hash atual](../Validation/revisao-pos-sprint-6/app-build.json) e [manifesto atual](../Validation/revisao-pos-sprint-6/source-manifest.json). Logs atuais em `/private/tmp/sieg-pos-s6/dock-followup/`. Snapshots cumulativos e patches dos lotes 3/4 atualizados em `/private/tmp/s6-review-lotes/`; lotes 1/2 preservados.
- Código pronto para nova conferência da coordenação; arrasto/contexto/hold e hover físicos continuam no roteiro manual. Sem commit, push, merge, Sprint 7, agentes paralelos ou mensagens de retorno.
