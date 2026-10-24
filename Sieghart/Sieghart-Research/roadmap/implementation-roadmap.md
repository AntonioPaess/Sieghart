# Roteiro de pesquisa e implementação proposta

O roteiro é incremental, com pausa após cada aplicação prioritária. Boring Notch foi aprofundado no código público; o usuário instalou a versão 2.7.3 (271), cujo pacote e configurações abertas foram inspecionados. O painel flutuante e o consumo não puderam ser validados diretamente nesta etapa. OpenJarvis e **os dois projetos Open Finance** foram analisados estaticamente no código oficial, sem instalação ou medição local. Raycast foi analisado por documentação oficial e exemplo público; o usuário preferiu não instalar, portanto não houve inspeção de pacote nem medição. Os custos abaixo são estimativas qualitativas e devem ser revistos após protótipos e medições. Nenhuma etapa de implementação foi executada por esta pesquisa.

| Ordem | Entrega de pesquisa | Evidência necessária | Resultado esperado |
| --- | --- | --- | --- |
| 1 | Boring Notch | Código público, APIs Apple, pacote instalado e leitura das configurações; testes de painel/monitores/desempenho pendentes | [Dossiê](../applications/boring-notch.md) e [proposta de UI](../architecture/sieghart-ui-architecture.md) |
| 2 | OpenJarvis — **pesquisa estática concluída; validação empírica pendente** | Código público e licença no commit fixado; componentes, execução local, persistência, agenda, ferramentas, memória, modelos e observabilidade | [Dossiê](../applications/openjarvis.md), [runtime](../architecture/openjarvis-agent-runtime-analysis.md), [comparação](../comparisons/openjarvis-vs-sieghart-architecture.md) e [integração](../integrations/openjarvis-integration-feasibility.md) |
| 3 | Open Finance: DeseretSaint — **pesquisa estática concluída; validação empírica pendente** | Código público, identidade, licença, modelo de dados, MCP, controle de acesso e manutenção | [Dossiê independente](../applications/open-finance-deseretsaint.md), com lacunas de segurança e multi-moeda documentadas |
| 4 | Open Finance: openfinance-app — **pesquisa estática concluída; validação empírica pendente** | Código público, identidade, licença ELv2, modelo financeiro, importação, IA, segurança e manutenção | [Dossiê](../applications/open-finance-openfinance-app.md), [comparação](../applications/open-finance-comparison.md) e documentos de arquitetura/integração financeira |
| 5 | Raycast — **pesquisa pública concluída; validação empírica não solicitada** | API oficial, modelo de segurança, exemplo Todo List no commit fixado; sem app instalado | [Dossiê](../applications/raycast.md), [automação](../architecture/sieghart-automation-architecture.md), [agentes](../architecture/sieghart-agent-architecture.md), [comparações](../comparisons/automation-comparison.md) de automação e [IA](../comparisons/ai-comparison.md) |
| 6 | VoiceInk — **pesquisa de código entregue; teste macOS pausado pelo usuário** | Código público, documentação Apple; app local identificada era a versão iOS no Mac | [Dossiê](../applications/voiceink.md), [comparação](../comparisons/voice-comparison.md) e [arquitetura de voz](../architecture/sieghart-voice-architecture.md) |
| 6A | HeyClicky — **dossiê do app completo entregue; métricas pendentes** | Release oficial 1.0.53, REA estático anterior, pacote, tour/Home/capturas, relatos de ditado, interrupção e troca de entrada; sem conectores ligados | [Dossiê](../applications/heyclicky.md): UI, voz, visão, agentes, arquivos, integrações, rotinas, dados e viabilidade Apple Foundation Models. Algoritmo interno e benchmark continuam desconhecidos |
| 7 | Dayflow e Screenpipe | Repositórios/documentação, permissões e retenção | Política de captura e memória local; pausa entre aplicativos |
| 8 | Alcove, Droppy, BetterTouchTool | Documentação oficial; pacote/runtime só se houver pergunta que exija | Refinar UI, arquivos e automação; pausa entre aplicativos |

## Fila do adendo V3

O adendo acrescenta investigação de código-fonte, sem modificar o aplicativo. Cada etapa distingue fatos verificados, inferências, propostas e lacunas, citando arquivos de implementação. OpenJarvis foi avaliado como referência arquitetural, runtime reutilizável, serviço local, base de implementação Swift ou combinação; a recomendação atual é usá-lo como referência e avançar com contratos nativos seletivos, sem dependência obrigatória. Os dois projetos Open Finance foram avaliados como projetos distintos antes da recomendação.

| Depois da investigação correspondente | Documento solicitado |
| --- | --- |
| OpenJarvis — **entregue** | [Dossiê](../applications/openjarvis.md); [runtime](../architecture/openjarvis-agent-runtime-analysis.md); [opções](../architecture/agent-runtime-comparison.md); [integração](../integrations/openjarvis-integration-feasibility.md); [Sieghart × OpenJarvis](../comparisons/openjarvis-vs-sieghart-architecture.md) |
| Ambos os repositórios Open Finance — **entregue** | [Comparação](../applications/open-finance-comparison.md); [Elinor](../architecture/financial-agent-architecture.md); [segurança](../architecture/financial-data-security.md); [MCP](../integrations/finance-mcp-integration.md) |
| Fontes oficiais brasileiras e alternativas de importação — **entregue** | [Open Finance Brasil](../integrations/brazilian-open-finance.md) |

Os documentos de OpenJarvis e os dois dossiês independentes de Open Finance estão entregues. A recomendação financeira preserva **Elinor**, já definida, usa conceitos dos dois projetos sem os integrar como dependência e começa por importação local CSV/OFX. Permissões de leitura por conta/fonte são verificadas em cada consulta; mudanças de orçamento requerem aprovação específica. Transferências de dinheiro e operações de investimento ficam fora do escopo padrão. Respostas sobre BRL/EUR/USD devem derivar de fatos reais autorizados e distinguir estimativas. A viabilidade brasileira foi avaliada com normas/fontes oficiais e exemplos de agregadores; acesso bancário direto por app pessoal não foi presumido. O lote Raycast acrescenta paleta de comandos, ferramenta tipada e autorização do host como direção técnica, com limites do núcleo fechado documentados. Na etapa de voz, o código VoiceInk para Mac e o pacote HeyClicky foram pesquisados; o usuário relatou três testes neutros bem-sucedidos no HeyClicky, separados das fontes estáticas. O dossiê HeyClicky cobre também os demais módulos do produto.

## Sequência de produto sugerida após validar a pesquisa

| Etapa | Complexidade | Dependências e permissões | Impacto e manutenção | Valor |
| --- | --- | --- | --- | --- |
| Estabilizar geometria, foco e estados da ilha | Média | AppKit/SwiftUI; sem nova permissão para a UI básica | Impacto baixo se eventos ociosos forem reduzidos; manutenção média por versões do macOS | Alto |
| Registro de comandos tipados com autorização por ação | Alta | APIs de apps, App Intents/Shortcuts conforme integração; Accessibility/Apple Events apenas por recurso | Logs e compatibilidade exigem manutenção alta | Alto |
| Ditado local com interrupção | Alta | Microfone; Speech/AVFoundation ou motor local avaliado | CPU/energia potencialmente altos em captura; manutenção média | Alto |
| Memória de sessão local e busca textual | Média | SQLite/FTS, consentimento e exclusões | Armazenamento e política de retenção; manutenção média | Alto |
| Captura contextual contínua | Muito alta | Screen Recording/Accessibility conforme fonte; filtros e deleção | CPU, armazenamento, privacidade e manutenção altos | Condicional à validação com usuários |

## Portões de decisão

Antes de adicionar permissões, demonstrar em protótipo que o caso de uso depende delas. Antes de escolher um motor ou framework externo, medir latência e recursos frente à solução nativa. Antes de automatizar uma ação mutável, definir esquema, prévia, autorização, cancelamento, resultado verificável e histórico. Priorizar um agente orquestrador com ferramentas; introduzir agentes especializados somente quando tarefas independentes e métricas justificarem a complexidade.

## Implementação por estágios após concluir as aplicações prioritárias

| Estágio | Entrega sugerida | Complexidade / dependência | Permissão / desempenho / manutenção | Validação necessária |
| --- | --- | --- | --- | --- |
| MVP | Paleta de apps e comandos locais; entrada por hotkey e voz atual; abrir app, URL e timer | Média; integrar `ActivationController`/`LocalAppLauncher` | Sem permissão nova para busca local e abertura; índice leve e sem polling agressivo | Busca por alias, conflito de hotkey, app ausente, tempo até primeiro resultado |
| V1 | `ActionRegistry`, prévia, autorização, recibo e verificação; workflow curto de ambiente | Alta; Swift concurrency e persistência mínima | Accessibility somente para mover janelas; Atalho do usuário para Focus; manutenção por app alvo | Negação, cancelamento, idempotência, janela incompatível, dois monitores |
| V2 | Contexto e memória local opt-in; modelo local/remoto por capacidade e rota explícita | Alta; `ModelRuntime`, store local e redaction | Custo/energia de inferência medidos; política de retenção e exclusão | Prompt injection, falta de rede, fallback consentido, fatos com origem |
| V3 | Agenda persistente e conectores adicionais com escopo por tarefa | Muito alta; ciclo de vida fora do app e possíveis helpers | Aprovação para Login Item/LaunchAgent; suporte/observabilidade elevados | Reinício, tarefa vencida, aprovação pendente, crash e retomada |

Esta sequência é **proposta**, não compromisso de prazo. Medir baseline no Mac alvo antes de fixar metas de latência/energia. Qualquer edição do app ou ensaio de implementação deve começar em worktree separado e terminar com instruções de teste reproduzíveis para o usuário.
