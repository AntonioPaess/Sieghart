# Comparação de runtimes de agentes para Sieghart macOS

**Data:** 13/10/2026. **OpenJarvis fixado:** [commit `108d257188cbad85f2e50209d9a61669ea4dec33`](https://github.com/open-jarvis/OpenJarvis/commit/108d257188cbad85f2e50209d9a61669ea4dec33). Este documento compara o runtime do código publicado com uma arquitetura Swift **proposta**. Não houve instalação, execução ou benchmark de OpenJarvis neste Mac; nenhuma capacidade abaixo é descrita como já implementada em Sieghart.

## O que o OpenJarvis realmente executa

**Verificado no código:** `SystemBuilder` resolve um engine e um modelo, monta segurança, telemetria, memória, ferramentas, skills, agendador, sessões e componentes de agentes em um `JarvisSystem`. A composição está em [`system/builder.py`](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/system/builder.py#L142-L369), não em `system.py`, caminho ainda citado por parte da documentação. Uma consulta passa por [`QueryOrchestrator.ask`](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/system/orchestrator.py#L21-L96): injeta contexto da memória quando configurado, escolhe um tipo de agente e chama o engine diretamente ou o agente. O loop de ferramentas do agente orquestrador está em [`agents/orchestrator.py`](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/agents/orchestrator.py).

**Limite importante de roteamento:** o caminho padrão de `SystemBuilder` escolhe engine/modelo na construção, e `QueryOrchestrator.ask` usa essa escolha. Políticas de roteamento existem, mas não devem ser tratadas como seleção automática por consulta neste caminho. A CLI só entra nesse fluxo com `--router-policy` ou aprendizagem habilitada; ticks de agentes gerenciados exigem `router_policy` na configuração do agente. [Builder](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/system/builder.py#L374-L428), [consulta](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/system/orchestrator.py#L21-L96), [CLI](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/cli/ask.py#L989-L1067), [tick](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/agents/executor.py#L393-L409).

**Persistência e agendamento:** `AgentManager` guarda agentes, tarefas, mensagens e checkpoints em SQLite WAL. O bloqueio de tick usa atualização condicional e considera obsoleto um tick sem atualização por 600 segundos; isso demonstra uma estratégia de recuperação, sem provar retomada exata de uma chamada externa interrompida. [`manager.py`](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/agents/manager.py#L111-L163), [`start_tick` e checkpoints](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/agents/manager.py#L307-L455). `AgentScheduler` mantém uma thread de polling e chama `execute_tick` para agentes vencidos na sequência do loop; concorrência entre ticks de agentes gerenciados **não está demonstrada nesse caminho**. [`scheduler.py`](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/agents/scheduler.py#L45-L230).

**Compressão:** existem estratégias registradas, inclusive `model_summarization`; no commit fixado, essa classe chama a consolidação simples e não invoca um modelo. Portanto, a presença do nome não comprova resumo por LLM nesse fluxo. [`sessions/compression.py`](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/sessions/compression.py#L1-L91).

## Comparação para o alvo nativo

| Aspecto | OpenJarvis verificado | Sieghart hoje | Direção Swift proposta |
| --- | --- | --- | --- |
| Composição | `SystemBuilder` configura componentes Python por TOML/registries | App, view models e serviços nativos; nenhum runtime geral de agentes demonstrado | Composition root Swift com protocolos pequenos para modelo, ferramenta, memória e tarefa |
| Agente e ferramentas | Tipos de agente e loops de ferramentas; `ToolExecutor` possui gates de execução | Sig/Ada/Toni/Gantt/Rita/Elinor têm identidade de produto; comandos de voz atuais são determinísticos | Um orquestrador por tarefa com papéis e ferramentas autorizadas, sem manter um modelo por personagem |
| Continuidade | SQLite, mensagens, checkpoints e agendadores no processo | Persistência específica de timer, calendário e arquivos | Store local de tarefas com estado, idempotência, retomada e cancelamento explícitos |
| Modelos | Engines locais/remotos opcionais; engine padrão fixado na construção | Medidores de uso de Codex/Claude, não inferência geral | `ModelRuntime` assíncrono; disponibilidade verificada em cada provedor, com fallback explícito |
| Observabilidade | Eventos, traces e telemetria local, além de analytics externo separado | Métricas de uso de serviços existentes; sem traces de tarefas de agentes | Eventos de ciclo de vida, duração e resultado sem conteúdo sensível por padrão |
| Integração macOS | Python, opção Tauri e servidor HTTP; não é a UI Swift de Sieghart | AppKit/SwiftUI e serviços macOS | UI e autorização no host Swift; serviço separado apenas após demonstrar valor |

O código local que sustenta a coluna “Sieghart hoje” está mapeado na [comparação de arquitetura](../comparisons/openjarvis-vs-sieghart-architecture.md). `SystemLanguageModel` da Apple deve ser consultado quanto à [disponibilidade real](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum?changes=_3) em cada Mac; não é substituto universal para outros engines. Tarefas que precisem continuar após o app principal terminar requerem um desenho explícito de ciclo de vida e consentimento. O macOS oferece [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice) para registrar Login Items e LaunchAgents, sujeito à aprovação do usuário; não se deve pressupor que um timer em processo sobreviva ao encerramento do app.

## Decisão de integração

| Opção do adendo | Avaliação para esta fase | Motivo |
| --- | --- | --- |
| **A. Referência arquitetural** | Recomendada agora | Permite aproveitar contratos de execução, checkpoint, telemetria e gates sem incluir Python no produto |
| **B. Runtime Python embutido** | Não recomendada sem protótipo | Empacotamento, atualizações, footprint, APIs macOS e fronteira de permissões exigem comprovação; não há benchmark local |
| **C. Serviço local separado** | Condicional | Pode isolar workloads longos, mas introduz IPC/HTTP, autenticação, supervisão, armazenamento duplicado e política de desligamento |
| **D. Implementação nativa Swift inspirada nos padrões** | Direção principal | Preserva UX, permissões e ciclo de vida nativos; exige implementar apenas as abstrações que casos reais justificarem |
| **E. Híbrido** | Possível evolução | Host Swift controla tarefas e autorização; serviço opcional fornece capacidade específica quando um teste demonstrar vantagem clara |

**Proposta:** começar com um orquestrador Swift de tarefas curtas e ferramentas tipadas, papéis existentes e persistência mínima de resultados. Acrescentar agenda e retomada só para fluxos que o usuário habilitar. Se um serviço OpenJarvis vier a ser comparado, ele deve receber um conjunto mínimo de ferramentas, escopo de dados por tarefa e uma autorização verificável do host antes de qualquer ação mutável. Um servidor em loopback sem chave, permitido pelo [middleware de autenticação atual](https://github.com/open-jarvis/OpenJarvis/blob/108d257188cbad85f2e50209d9a61669ea4dec33/src/openjarvis/server/auth_middleware.py#L28-L111), não é uma fronteira suficiente para uma integração que manipule dados pessoais.

## O que permanece desconhecido

- Latência, CPU, GPU, RAM, energia e tempo de inicialização de OpenJarvis neste Mac e com modelos/rotas representativos; nenhuma medição foi realizada.
- Equivalência funcional entre um serviço Python e um runtime Swift para o conjunto de ferramentas que Sieghart realmente precisará.
- Garantias de retomada após morte durante uma ferramenta com efeito externo; checkpoint de estado não implica transação reversível.
- Custo de distribuição, atualização e suporte de um runtime Python/Tauri junto a um aplicativo Swift assinado, inclusive eventuais exigências de sandbox conforme o modo de distribuição escolhido.

Nenhum código de produção foi alterado ou testado para esta comparação. Uma futura prova de conceito que modifique Sieghart deve ficar em worktree separado e incluir instruções de teste de cancelamento, retomada, autorização, privacidade e consumo em hardware real.
