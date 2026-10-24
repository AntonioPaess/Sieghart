# IA e agentes — Raycast AI, OpenJarvis e direção Sieghart

**13/10/2026.** Raycast AI: fontes públicas oficiais, sem app instalado. OpenJarvis: código estático no [commit do dossiê](../applications/openjarvis.md). O alvo Sieghart é [proposto](../architecture/sieghart-agent-architecture.md), ainda não implementado.

| Critério | Raycast AI documentado | OpenJarvis verificado | Sieghart proposto |
| --- | --- | --- | --- |
| Ferramentas | Entrada `tools` no manifesto, função com objeto, confirmação opcional; [docs](https://developers.raycast.com/ai/learn-core-concepts-of-ai-extensions) | Registry/execução e gates; [análise](../architecture/openjarvis-agent-runtime-analysis.md) | `ActionRegistry` com política do host obrigatória e preview por ação |
| Descoberta | `@` seleciona AI Extensions; permissões Ask/Auto/Always Allow; [manual](https://manual.raycast.com/ai/ai-extensions) | Ferramentas registradas no sistema/configuração | Papel disponibiliza subconjunto de ferramentas à tarefa |
| Modelos | Ollama local e custom providers disponíveis; Extension AI API não usa modelo local; [manual](https://manual.raycast.com/ai/local-models) | Engines locais/remotos, com seleção padrão na construção; [comparação](../architecture/agent-runtime-comparison.md) | `ModelRuntime` com disponibilidade/capacidades, rota de dados e fallback consentido |
| Persistência/agenda | Memória e automações no produto; automação depende de Raycast rodando e aprovação pode pausar; [manual](https://manual.raycast.com/ai/automations) | SQLite/checkpoints/agendador em processo; [análise](../architecture/openjarvis-agent-runtime-analysis.md) | Store local mínimo por tarefa; agenda só após caso validado |
| Privacidade | Rotas variam entre modelo Raycast, BYOK, custom e local; Cloud Sync e anexos têm implicações próprias; [manual](https://manual.raycast.com/ai/raycast-ai-privacy-security) | Controles no código, mas integração com macOS requer novo limite | Rotular destino dos dados por chamada, excluir conteúdo sensível do diário |
| Especialização | Agentes configuram modelo/instruções/ferramentas; [manual](https://manual.raycast.com/ai/agents) | Mais de um tipo de agente no runtime | Um orquestrador por tarefa; personas não exigem instâncias separadas |

**Decisão:** implementar o contrato de modelo e ferramenta antes de selecionar um provedor definitivo. Ferramentas precisam retornar status factual; texto gerado não é recibo. O modelo que atende uma conversa pode não atender uma função da extensão; o manual do Raycast torna esse limite explícito para modelos locais. Um fallback de modelo muda custo e destino dos dados, portanto requer política visível.

**Lacunas:** algoritmos internos Raycast de planejamento, compactação, seleção de ferramenta e fallback não são públicos nesta pesquisa. Não transformar recursos anunciados em garantia de comportamento. Testar Sieghart com um único orquestrador antes de acrescentar agentes especializados.
