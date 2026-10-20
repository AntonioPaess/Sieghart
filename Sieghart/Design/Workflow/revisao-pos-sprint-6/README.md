# Revisão pós-Sprint 6 — fila reservada

19 de outubro de 2026. A pedido do usuário, registrar agora e executar as correções depois, em branch separada. **Não iniciar correções nem acionar agentes automaticamente.**

Destino: **Sieg — Revisão**, chat `01a1434b-ee07-7e70-92e1-d6fbc21138dc`. Branch futura sugerida: `revisao/pos-sprint-6`, criada a partir da entrega publicada de `sprint-6`. Não foi criada nesta etapa. Usar somente `gpt-6.1-sol`, um agente ativo por vez; nenhum Astra. Preservar alterações de outros chats e manter commits por parte, sem coassinatura.

A [revisão recebida](revisao-recebida.txt) foi preservada integralmente como material de referência. Suas afirmações e números não constituem validação independente. Reproduzir cada problema antes de alterar comportamento.

## Triagem da revisão recebida

| ID | Prioridade recebida | Encaminhamento para o revisor |
| --- | --- | --- |
| R1 | P1 | `ToolProcess.swift`: avaliar stdin herdado, timeout/cancelamento de processos e espera bloqueante; saída já usa arquivos, portanto não assumir deadlock de Pipe cheio. Testar processo sem resposta com fixture. |
| R2 | P1 | `MacDisplayPowerBackend.swift`: remover espera síncrona de `pmset` no MainActor, com término/cancelamento verificáveis sem colocar o monitor real para dormir. |
| R3 | P2 | **Não confirmado:** a alegação de que `CGEvent.timestamp` retorna ticks Mach contradiz o cabeçalho local `CGEventTypes.h`, que documenta nanossegundos desde startup. Comparar timestamps reais Carbon/CG/NSEvent antes de aplicar conversão; não introduzir `mach_timebase_info` cegamente. |
| R4 | P2 | `AgentRPCProcess.swift`: serializar escrita e fechamento de stdin; verificar comportamento de pipe quebrado/SIGPIPE e desligamento concorrente com fixture. |
| R5 | P2 | Separar o problema concreto de ciclo de vida de `cameraClickMonitor` das propostas arquiteturais. Verificar remoção/reconfiguração e custo de consultas WindowServer antes de refatorar `NotchWidgetViewModel`. |
| R6 | P2 | Medir alocação de Tasks por movimento e polling antes de otimizar. A segunda consulta AX protege contra troca de janela sob o ponteiro; preservar revalidação de identidade/alvo. |
| R7 | P3 | A UI de Mouse Buttons já fica em Workspace → Activation; ausência em Windows não é falha de integração. Avaliar separadamente limite de 256 janelas e compatibilidade de comandos de menu/localização. |
| R8 | P3 | Artefatos acadêmicos, pesquisa, ZIPs, duplicatas e avisos de finais de linha: sem exclusão automática; pertencem a outros trabalhos. Nenhum desses arquivos deve entrar no commit da Sprint 6. |

## Achados da revisão rápida desta entrega

| ID | Prioridade | Evidência e aceite necessário |
| --- | --- | --- |
| S6-R1 | P1 | `NativeDockAndZoomBackend.windowCount(for:)` transforma falha ao ler `AXWindows` em `0`. Com auto-quit habilitado, falhas repetidas podem solicitar encerramento de um app que ainda tem janelas. Tratar falha como estado desconhecido (`nil`) e testar que nunca agenda/encerra nesse estado. Manter auto-quit desligado até a correção/validação. |
| S6-R2 | P2 | `handleDockClick` não tem chamador de produção. Previews são cartões geométricos abertos pela UI; não há observação de hover/clique dos ícones do Dock. `observeSnapshot` só é chamado por `DesktopController.refresh()`, sem observador de fechamento. Concluir gatilhos nativos e testes ou manter esses três IDs como parciais no roadmap. |
| S6-R3 | P2 | `AntigravityPlanHistory` descobre tokens por argumentos de processos, tenta portas locais adjacentes e usa `URLSession.shared` com redirecionamentos padrão. Vincular endpoint ao processo correto, bloquear redirecionamentos e limitar resposta; cancelar requisição ao expirar o prazo. Nunca registrar token/argumentos completos. Testar com transporte injetado, sem consultar credenciais reais. |
| S6-R4 | P2 | A descoberta do language server usa `ps`, leitura até EOF e `waitUntilExit()` sem timeout próprio. Remover espera indefinida e verificar cancelamento. Revisar também expiração do último relatório de quota e inferências de família/janela, distinguindo valores observados de estimativas. |
| S6-R5 | P2 | A recuperação de interrupção do tap de `MouseButtonController` limpa botões capturados. Pode passar um release sem down correspondente após recuperação. Preservar/reconciliar captura com estado físico e testar down → interrupção → up, sem segunda ação. Achado da revisão independente Sol já executada; não iniciar nova revisão ampla. |
| S6-R6 | P2 | Botão verde consome apenas down; revisar pareamento de up/drag e recuperação de tap desabilitado. Preferências globais de Spaces/aceleração precisam de teste de restauração quando outro app/usuário altera o valor durante o uso. |
| S6-R7 | P2 | Conferir nomes, aliases, fonte e data dos preços adicionados. Não apresentar inferência de modelo/preço nem API equivalente como cobrança/quota oficial. A revisão rápida não verificou preços externos. |

## Limites da validação recebida

O Fast registrado aprovou 233 funções/935 invocações; o recorte Complete de IA aprovou 26/26. O manifesto recebido não cobre o estado final de oito arquivos de IA alterados depois: `AIActivity.swift`, `AIUsage.swift`, `ModelPricing.swift`, `AIUsageViewModel.swift`, `AIUsageDetailsView.swift`, `AIUsageView.swift`, `AIActivityReaderTests.swift` e `LocalTokenReaderTests.swift`. Os resultados permanecem como histórico e não devem ser atribuídos automaticamente às fontes finais. A lacuna foi resolvida nesta publicação: nova execução Fast 233/935, Complete IA 26/26 e build aprovados, com manifestos atuais sem divergências. [Evidências novas](../../Validation/sprint-6-publicacao/verification.json). Os achados de código acima continuam pendentes.

Aceite físico segue pendente: [roteiro do Mac](../sprint-6-teste-manual.md). Nenhum app foi iniciado ou permissão modificada nesta revisão. As correções acima estão adiadas por instrução do usuário.
