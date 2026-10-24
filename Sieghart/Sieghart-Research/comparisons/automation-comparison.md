# Automação macOS — Raycast, OpenJarvis e Sieghart

**13/10/2026.** Raycast foi analisado por [documentação oficial e exemplo público](../applications/raycast.md), sem executável local. OpenJarvis foi [analisado estaticamente](../applications/openjarvis.md) no commit fixado em seu dossiê. A coluna Sieghart descreve o checkout atual, que pode mudar em outro chat; as ações propostas ainda não existem.

| Aplicação | Recurso | Abordagem comprovada / evidência | Complexidade para Sieghart | Relevância |
| --- | --- | --- | --- | --- |
| Raycast | Paleta, aliases, hotkeys, Action Panel | [Manual de atalhos](https://manual.raycast.com/command-aliases-and-hotkeys), [UI de extensões](https://developers.raycast.com/api-reference/user-interface) | Média: índice local e estado de UI; integração com atalhos atuais | Alta |
| Raycast | Comandos `view`, `no-view`, `menu-bar` e ferramentas de IA distintas | [Manifest](https://developers.raycast.com/information/manifest), [exemplo Todo List](https://github.com/raycast/extensions/blob/ef642d185d100f0aeba5b1bc08cf3ccba9c2dc51/examples/todo-list/package.json) | Média: catálogo tipado; sem runtime de plugins no MVP | Alta |
| Raycast | Script Commands e AppleScript | [Manual](https://manual.raycast.com/script-commands); permissões ficam no app hospedeiro | Alta: execução arbitrária demanda controle amplo | Condicional; evitar no MVP |
| Raycast | Gerenciamento de janelas | [Manual](https://manual.raycast.com/window-management) documenta Accessibility | Alta: AX, estados de janela e monitores | Média/alta para workflows de ambiente |
| Raycast | Chamar outro comando | [`launchCommand`](https://developers.raycast.com/api-reference/command) confirma início, não conclusão | Média: recibo/verificador próprio | Alta como alerta de desenho |
| OpenJarvis | Ferramentas, orquestração, checkpoints | [Análise de runtime](../architecture/openjarvis-agent-runtime-analysis.md) | Alta: lifecycle e persistência | Alta como referência, sem dependência obrigatória |
| Sieghart atual | Hotkeys, voz determinística, abrir app e busca | [`ActivationController`](../../Sieghart/Shared/Services/Activation/ActivationController.swift), [`LocalAppLauncher`](../../Sieghart/Core/Helpers/VoiceCommands.swift) | Baixa para integração inicial; alta para workflow geral | Base concreta |

## Padrões e diferenças

**Adotar:** entrada rápida, descritores estáveis, ações contextuais e separação entre comando visível e ferramenta de agente. **Adaptar:** confirmação contextual como política do host, somada à checagem de permissões macOS; workflow com recibos e verificação real. **Evitar inicialmente:** interpretação direta de linguagem natural em shell/AppleScript e um runtime de extensões de terceiros. A [documentação de segurança do Raycast](https://developers.raycast.com/information/security) declara que extensões Node não têm sandbox adicional para arquivo/rede, apesar de isolate V8 e RPC limitado.

Raycast otimiza acesso rápido a comandos; OpenJarvis aprofunda execução de agentes e persistência; Sieghart já possui entrada por notch/voz e funcionalidades nativas. A oportunidade original é **uma única camada de ações tipadas** para paleta, voz e agente, com estado `planned → approved → running → verified`, evitando fluxos duplicados. Isso é [proposta](../architecture/sieghart-automation-architecture.md), não achado de código Raycast.

## Limites da comparação

Sem instalar Raycast, ranking, latência, RAM/CPU, consumo e tratamento real de conflitos de atalhos não foram medidos. Sem executar OpenJarvis, não há benchmark comparável. A comparação cobre interfaces públicas e código lido, não equivalência de desempenho. Para avaliar os dois, seria preciso versões fixadas, máquina/OS anotados, corpus de comandos e métricas idênticas.
