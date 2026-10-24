# Arquitetura proposta do agente e dos modelos do Sieghart

**Estado:** proposta, não implementação. Esta seção combina a [pesquisa Raycast AI](../applications/raycast.md) com a [comparação de runtimes](agent-runtime-comparison.md). O Sieghart atual integra agentes de codificação e métricas de uso, mas não há evidência de um orquestrador geral para tarefas macOS; ver [comparação local](../comparisons/openjarvis-vs-sieghart-architecture.md).

## Decisão principal

Um **orquestrador por tarefa**, com papéis de produto e registro de ferramentas autorizado, é suficiente para o MVP. Sig, Ada, Toni, Gantt, Rita e Elinor podem alterar linguagem, contexto e ferramentas acessíveis sem exigir seis processos/modelos simultâneos. Só dividir em agentes especializados quando houver tarefas independentes, avaliação de qualidade e ganho medido que compense custo, latência e aprovação cruzada.

Raycast mostra uma separação útil: uma ferramenta de IA é um ponto de entrada tipado, enquanto o comando visível fica na busca; uma extensão pode definir instruções e avaliações, e a chamada de ferramenta pode pedir confirmação. Essas são [interfaces publicadas](https://developers.raycast.com/ai/learn-core-concepts-of-ai-extensions), não prova do algoritmo de orquestração interno. O manual documenta [agentes com modelo, instruções e escopo de ferramentas](https://manual.raycast.com/ai/agents). Sieghart deve usar contratos próprios e explícitos.

```text
Solicitação → escolha de papel e contexto permitido → ModelRouter
            → resposta estruturada / proposta de ferramenta
            → validação do host → ActionAuthorization → WorkflowRunner
            → fatos verificados → resposta em streaming e memória de sessão
```

## Contratos Swift propostos

```swift
struct ModelCapabilities: Sendable {
    let supportsStreaming: Bool
    let supportsTools: Bool
    let supportsVision: Bool
    let contextLimit: Int?
    let dataRoute: DataRoute // onDevice, directProvider, relay
}

protocol ModelRuntime: Sendable {
    var id: String { get }
    var capabilities: ModelCapabilities { get }
    func availability() async -> ModelAvailability
    func respond(to request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error>
}

actor ModelRouter { /* explicit user/model policy and fallback */ }
actor ContextManager { /* budget, redaction and compaction */ }
actor ConversationStore { /* local messages and task references */ }
actor AgentOrchestrator { /* one bounded task loop */ }
```

`ModelEvent` deve distinguir texto parcial, proposta de chamada, estatísticas, término e falha. `ModelRequest` inclui papel, prompt, histórico resumido, anexos permitidos e descritores de ferramentas. `ModelRouter` rejeita modelo sem capacidade exigida e revela ao usuário quando troca de rota local para remota. Fallback só ocorre se autorizado por política, com limite de tentativas; não reenviar dados privados para outro provedor silenciosamente.

## Provedores e fluxo de dados

| Opção | Papel no desenho | Limite verificado |
| --- | --- | --- |
| Apple Foundation Models | Adaptador local quando disponível no Mac e adequado ao tamanho/capacidade da tarefa | Verificar `SystemLanguageModel.availability` em execução; suporte/disponibilidade variam por dispositivo. [Apple](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum?changes=_3) |
| MLX ou llama.cpp | Possível adaptador local após protótipo e medições | Não foi benchmarkado para Sieghart; embalagem/licença/energia e streaming precisam teste. |
| API remota | Adaptador por provedor, com chave no Keychain e pedido explícito de dados | Política de retenção, preços e modelos variam; verificar antes de escolher. |
| Codex/Claude de codificação já presentes | Continuar para tarefas de código específicas | Não equivalem a um `ModelRuntime` genérico macOS; preservar seus fluxos/autorizações. |

O [Raycast documenta Ollama local](https://manual.raycast.com/ai/local-models), mas avisa que sua Extension AI API não usa modelos locais. Também distingue [provedores customizados diretos](https://manual.raycast.com/ai/custom-providers) e [rotas de dados para modelos próprios/BYOK](https://manual.raycast.com/ai/raycast-ai-privacy-security). **Proposta:** em Sieghart, mostrar a rota e a capacidade do modelo por chamada, pois “modelo local selecionado” não garante que ferramentas ou anexos permaneçam locais.

## Contexto, conversa e ferramentas

`ContextManager` deve montar o mínimo necessário por tarefa: instruções do papel, pergunta atual, fatos autorizados, trechos recuperados com origem e um resumo de sessões anteriores quando útil. Mensagens antigas são compactadas apenas com procedência; fatos financeiros e permissões não devem ser reconstruídos a partir de resumo. Anexos e contexto de tela entram só quando o usuário solicitar ou ativar recurso contextual claro. A política de retenção e exclusão fica no `ConversationStore`, não no adaptador do modelo.

O modelo pode propor `ActionRequest`, mas só o registro do host define ações. O loop deve ter limite de passos, duração e chamadas; resposta parcial não é prova de execução. Cada resultado de ferramenta volta ao modelo com status `succeeded`, `failed`, `cancelled` ou `unverified`. O `WorkflowRunner` e a política de aprovação estão definidos em [automação](sieghart-automation-architecture.md). Para ações financeiras, a fronteira de [Elinor](financial-agent-architecture.md) impõe escopo e fatos verificados, além desta política geral.

## Ciclo de vida e falhas

Uma solicitação gera `taskID`; ao cancelar, interromper stream e impedir novas ferramentas. Ferramentas já concluídas permanecem registradas. Timeout de modelo não deve repetir uma ação externa que talvez tenha ocorrido; consultar recibo/estado antes de retry. Salvar mensagem de usuário, estado da tarefa e resultado factual separadamente. Em caso de falta de rede, perguntar antes de alternar de modelo local para remoto. Um processo de agenda só é necessário quando houver tarefas que devem rodar com o app fechado; a [agenda do Raycast](https://manual.raycast.com/ai/automations) também documenta dependência do aparelho ligado e aprovações pendentes.

## Avaliação e introdução gradual

Antes de ligar ferramentas ao modelo, medir: seleção correta de ação, parâmetros válidos, taxa de pedidos de aprovação adequados, falso sucesso, cancelamento, latência até primeira resposta e custo por tarefa. Conjunto de avaliação deve incluir instruções maliciosas dentro de documentos/abas, apps não instalados, permissão negada, janela AX não redimensionável, Atalho indisponível e modelo sem tool calling. Começar com uma ação reversível (`openApp`), depois um workflow curto. Só então avaliar especialização de agentes ou extensão de terceiros.

Nenhum desses módulos foi adicionado ao Sieghart nesta pesquisa. Implementação futura usa worktree separado e instruções de teste reproduzíveis para o usuário.
