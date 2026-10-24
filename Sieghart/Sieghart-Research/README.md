# Sieghart Research — macOS

Pesquisa iniciada em 13 de outubro de 2026. O escopo é exclusivamente macOS. O código principal existente permanece em `../Sieghart/`; `../Sieghart-macOS` é um link relativo para essa pasta, criado para apresentar a estrutura pedida sem mover arquivos com alterações locais nem quebrar referências do projeto Xcode. A pesquisa não altera o código do aplicativo.

## Estado

| Pasta | Conteúdo |
| --- | --- |
| `applications/` | Dossiês por aplicativo, com fatos, inferências e lacunas |
| `comparisons/` | Comparações após cada lote investigado |
| `architecture/` | Propostas originais para Sieghart, separadas da implementação atual |
| `integrations/` | Viabilidade de integração, permissões e dependências |
| `roadmap/` | Sequência de investigação e implementação proposta |

Comece por [inventário](applications/inventory.md), [Boring Notch](applications/boring-notch.md), [arquitetura da interface](architecture/sieghart-ui-architecture.md) e [roteiro](roadmap/implementation-roadmap.md). A pesquisa avança **uma aplicação prioritária por vez**, com pausa após cada dossiê, como solicitado pelo usuário. Boring Notch é a aplicação 1 e foi instalado pelo usuário para observação. [OpenJarvis](applications/openjarvis.md) é a aplicação 2, estudada pelo código público no commit registrado no dossiê. Seus aprofundamentos estão na [análise do runtime](architecture/openjarvis-agent-runtime-analysis.md), na [comparação com Sieghart](comparisons/openjarvis-vs-sieghart-architecture.md), na [comparação das opções de runtime](architecture/agent-runtime-comparison.md) e na [viabilidade de integração](integrations/openjarvis-integration-feasibility.md). Os dois projetos Open Finance foram estudados **separadamente**: [DeseretSaint](applications/open-finance-deseretsaint.md) é a aplicação 3 e [openfinance-app](applications/open-finance-openfinance-app.md) é a aplicação 4. A [comparação](applications/open-finance-comparison.md) leva à [arquitetura de Elinor](architecture/financial-agent-architecture.md), [segurança financeira](architecture/financial-data-security.md), [fronteira de ferramentas/MCP](integrations/finance-mcp-integration.md) e [viabilidade brasileira](integrations/brazilian-open-finance.md). [Raycast](applications/raycast.md) é a aplicação 5; seu estudo público gerou [comparação de automação](comparisons/automation-comparison.md), [comparação de IA](comparisons/ai-comparison.md), [arquitetura de automação](architecture/sieghart-automation-architecture.md) e [arquitetura de agentes](architecture/sieghart-agent-architecture.md). A pedido do usuário, o lote de áudio inclui **dois dossiês separados**: [VoiceInk](applications/voiceink.md) e [HeyClicky](applications/heyclicky.md), com [comparação](comparisons/voice-comparison.md) e [arquitetura de voz](architecture/sieghart-voice-architecture.md). A pesquisa pausa antes de Dayflow.

O [dossiê HeyClicky](applications/heyclicky.md) foi ampliado para o aplicativo inteiro: notch/Home, onboarding, voz, tela/documentos, Clickys, arquivos, integrações, rotinas, dados, custos e uma análise de viabilidade com Apple Foundation Models. O REA feito anteriormente permanece uma análise estática parcial do binário fechado; os três testes de áudio são relatos do usuário, separados das observações da interface. A pausa após este aplicativo continua antes de Dayflow.

A [matriz de oportunidades de integração](comparisons/integration-opportunities.md) reúne todos os apps já investigados, inclusive o estudo REA anterior do HeyTaby. Ela distingue conectores reais, runtimes opcionais e funcionalidades a implementar originalmente no Sieghart, com prioridades e limites de licença/permissão.

## Convenção de evidência

- **Verificado**: documentação oficial, código público lido, artefato local ou observação direta especificada.
- **Inferido**: proposta ou conclusão plausível derivada dessas evidências.
- **Desconhecido**: sem evidência suficiente.

O usuário instalou Boring Notch 2.7.3 (build 271) para a etapa 1 e informou que o removeu depois. O pacote passou por inspeção estática enquanto estava disponível; observações em execução e medições devem ser declaradas separadamente em seu dossiê quando disponíveis. Código publicado e versões instaladas podem divergir; cada dossiê registra esse limite. Não copiar código ou ativos de terceiros para Sieghart; conferir a licença de cada projeto antes de reutilizar qualquer material.

Esta fase entrega apenas pesquisa e propostas. Para Raycast, o usuário escolheu fontes públicas sem instalação. VoiceInk e HeyClicky foram instalados pelo usuário; o primeiro pacote VoiceInk encontrado era a edição iOS executada no Mac, portanto seus dados não validam o ditado global macOS. Uma futura implementação ou teste que altere o aplicativo deve ocorrer em worktree separado e vir acompanhada de instruções para o usuário reproduzir o teste. Nenhum worktree de implementação foi criado neste lote.
