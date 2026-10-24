# Raycast — launcher, extensões e Raycast AI no macOS

**Pesquisa:** 13/10/2026. **Escopo:** macOS; documentação oficial e código público. **Estado local:** Raycast não foi localizado em `/Applications` ou `~/Applications` (busca até profundidade 2); o usuário optou por pesquisa pública, sem instalar. Nenhum pacote, `Info.plist`, entitlement, processo, janela, métrica de desempenho ou tráfego foi inspecionado. O código do aplicativo principal é fechado; o [repositório público](https://github.com/raycast/extensions) cobre extensões, exemplos e documentação, não o núcleo. O exemplo de código citado abaixo foi fixado no [commit `ef642d185d100f0aeba5b1bc08cf3ccba9c2dc51`](https://github.com/raycast/extensions/commit/ef642d185d100f0aeba5b1bc08cf3ccba9c2dc51).

## 1. Resumo executivo

**Verificado:** Raycast reúne busca de aplicativos/comandos, aliases, atalhos globais, ações contextuais, links rápidos, gerenciamento de janelas e scripts. A API de extensões declara comandos e ferramentas de IA separadamente; comandos têm modos `view`, `no-view` e `menu-bar`. A UI de extensão é declarada em React e traduzida para componentes nativos do Raycast. Ferramentas de IA recebem entradas estruturadas e podem expor confirmação antes da execução. [Manifest](https://developers.raycast.com/information/manifest), [terminologia](https://developers.raycast.com/information/terminology), [UI](https://developers.raycast.com/api-reference/user-interface), [ferramentas de IA](https://developers.raycast.com/ai/learn-core-concepts-of-ai-extensions).

**Decisão para Sieghart:** adotar a descoberta rápida de comandos e uma fronteira explícita entre **encontrar, planejar, autorizar, executar e verificar**. Não copiar a pilha React/Node nem supor que o runtime Raycast seja seguro como sandbox de automação. A arquitetura Swift proposta aparece em [automação](../architecture/sieghart-automation-architecture.md) e [agentes](../architecture/sieghart-agent-architecture.md).

## 2. Descoberta do aplicativo e limites

| Item | Resultado e natureza da evidência |
| --- | --- |
| Produto / responsável | Raycast, da equipe Raycast; [site](https://www.raycast.com/) e [manual](https://manual.raycast.com/quickstart). **Verificado por fonte oficial.** |
| Distribuição | Site/loja própria e extensões pela Raycast Store. A [documentação de segurança](https://developers.raycast.com/information/security) descreve o app como Developer ID assinado e notarizado. **Descrição do fornecedor, não verificação local de assinatura.** |
| Código aberto | [Extensões, exemplos e documentação](https://github.com/raycast/extensions) são públicos sob licença do repositório; o executável principal não está nesse repositório. **Não existe acesso ao código interno nesta análise.** |
| Linguagens e UI | Extensões: JavaScript/TypeScript + React; UI renderizada em elementos nativos pelo host. Scripts aceitam AppleScript, shell, Swift e outros intérpretes. Linguagem/frameworks do executável principal: **desconhecidos sem pacote**. [UI](https://developers.raycast.com/api-reference/user-interface), [scripts](https://manual.raycast.com/script-commands). |
| Caminho, bundle ID, versão | **Não verificados.** Uma busca limitada nas pastas padrão não encontrou `Raycast.app`; não extrapolar para outras pastas. |
| Permissões | Variam por recurso: por exemplo, Accessibility para mover janelas e texto selecionado; Automation para ler URL/título de aba em Quicklinks; scripts podem exigir Accessibility, Automation ou Full Disk Access. **Não há matriz única de permissões obrigatórias na instalação.** [Janelas](https://manual.raycast.com/window-management), [Quicklinks](https://www.raycast.com/core-features/quicklinks), [scripts](https://manual.raycast.com/script-commands). |

## 3. Funcionalidades relevantes

| Área | Fato verificado | Valor para Sieghart |
| --- | --- | --- |
| UI/UX | Busca raiz apresenta apps, arquivos, links e comandos; `⌘K` abre Action Panel, cujas ações podem ter atalhos. [Manual](https://manual.raycast.com/quickstart), [API UI](https://developers.raycast.com/api-reference/user-interface) | Uma paleta única com resultados rápidos e ações secundárias descobríveis. |
| Automação | Aliases e hotkeys globais para comandos; scripts configurados por metadados e argumentos. [Atalhos](https://manual.raycast.com/command-aliases-and-hotkeys), [scripts](https://manual.raycast.com/script-commands) | Entrada por teclado/voz convergindo para o mesmo catálogo de operações. |
| Sistema | Window Management usa Accessibility; Quicklinks abrem caminhos/URLs e podem captar seleção e aba ativa com permissões adicionais. [Janelas](https://manual.raycast.com/window-management), [Quicklinks](https://www.raycast.com/core-features/quicklinks) | Adaptadores macOS específicos, ativados conforme necessidade. |
| Extensões | Manifesto declara comandos, ferramentas de IA, preferências e intervalos para comandos em background. [Manifest](https://developers.raycast.com/information/manifest) | Registro de capacidades tipadas, sem dependência de plugins de terceiros no MVP. |
| IA | AI Extensions expõem funções com entrada/saída; `@` seleciona extensões e um chat pode usar mais de uma. Permissões de ferramentas têm modos Ask/Auto/Always Allow. [Conceitos](https://developers.raycast.com/ai/learn-core-concepts-of-ai-extensions), [manual](https://manual.raycast.com/ai/ai-extensions) | Ferramentas disponíveis ao agente somente sob política de autorização por chamada. |
| Modelos | Raycast documenta modelos locais via Ollama e provedores customizados; o AI API das extensões **não usa** o modelo local segundo o manual. [Local Models](https://manual.raycast.com/ai/local-models), [Custom Providers](https://manual.raycast.com/ai/custom-providers) | Interface `ModelRuntime` com capacidades e rota de dados explícitas; não presumir que toda função use o modelo escolhido. |
| Agenda | Automations executam prompts no aparelho, verificando vencimentos enquanto Raycast está aberto; solicitações pendentes de aprovação pausam a execução. [Automations](https://manual.raycast.com/ai/automations) | Tarefa agendada precisa estado persistente, política de perda/retomada e interação humana. |

## 4. Achados técnicos e evidências

### Contrato de extensão e lifecycle

**Verificado:** o `package.json` identifica ponto de entrada, título, modo, argumentos, preferências, `tools` e atualização em segundo plano (mínimo documentado de 1 minuto para `no-view`/`menu-bar`). O ponto de entrada executa ao abrir o comando. Ao sair da tela ou concluir um comando sem tela, o comando é descarregado da memória. A API `launchCommand` pode chamar comandos de outra extensão mediante alerta de permissão; a Promise resolve quando o comando **foi iniciado**, não quando terminou. [Manifest](https://developers.raycast.com/information/manifest), [lifecycle](https://developers.raycast.com/information/lifecycle), [`launchCommand`](https://developers.raycast.com/api-reference/command).

**Consequência de engenharia (inferência):** encadear comandos só por `launchCommand` não oferece confirmação de resultado, rollback ou transação. Um workflow Sieghart precisa `ActionResult` de cada passo e verificação de estado antes de declarar sucesso.

### Exemplo aberto examinado: Todo List

**Verificado no commit fixado:** [`package.json`](https://github.com/raycast/extensions/blob/ef642d185d100f0aeba5b1bc08cf3ccba9c2dc51/examples/todo-list/package.json) declara um comando `view` e quatro ferramentas de IA. A [tela](https://github.com/raycast/extensions/blob/ef642d185d100f0aeba5b1bc08cf3ccba9c2dc51/examples/todo-list/src/index.tsx) usa `List`, `ActionPanel`, estado React e `useLocalStorage`. [`get-todos`](https://github.com/raycast/extensions/blob/ef642d185d100f0aeba5b1bc08cf3ccba9c2dc51/examples/todo-list/src/tools/get-todos.ts) filtra leitura por status; [`create-todo`](https://github.com/raycast/extensions/blob/ef642d185d100f0aeba5b1bc08cf3ccba9c2dc51/examples/todo-list/src/tools/create-todo.ts) grava diretamente; [`delete-todo`](https://github.com/raycast/extensions/blob/ef642d185d100f0aeba5b1bc08cf3ccba9c2dc51/examples/todo-list/src/tools/delete-todo.ts) exporta `confirmation` com nome/status do item antes da exclusão. Esse é um **exemplo didático**, não prova do fluxo de dados ou da política de todas as extensões.

**Lição de desenho:** uma mutação pode ter confirmação própria; não inferir que qualquer ferramenta que escreve recebe confirmação automática. Para Sieghart, a política é do host, avaliada para toda ação, e a ferramenta só acrescenta uma prévia específica.

### Fronteira de segurança

**Verificado por documentação do fornecedor:** Raycast descreve um processo filho Node.js com extensões carregadas/descarregadas, RPC limitado para operações do host e isolate V8 por extensão. A mesma página diz que as extensões **não têm sandbox adicional para I/O de arquivos ou rede** do Node. Preferências de senha e armazenamento local usam banco criptografado por extensão; o app também usa Keychain. Permissões macOS dadas ao processo pai podem beneficiar o código de extensão, conforme o recurso. [Segurança](https://developers.raycast.com/information/security).

**Inferência sustentada:** isolate de linguagem e RPC limitado não equivalem a contenção de capacidade do sistema. Sieghart deve tratar adaptadores e futuros plugins como código com potencial efeito, limitar dados/capacidades no host e evitar conceder Accessibility/Automation por conveniência de uma extensão.

**Verificado:** deeplinks `raycast://extensions/...` podem iniciar comandos instalados; o Raycast pede confirmação ao abrir por deeplink. [Deeplinks](https://developers.raycast.com/information/lifecycle/deeplinks). Para automação própria, não usar um deeplink como prova de conclusão da tarefa.

### IA, dados e modelos

**Verificado:** ferramentas de extensão são funções com entrada objeto e saída; podem exportar `confirmation` chamada antes da função. Instruções e avaliações podem constar do manifesto/`ai.yaml`. [Conceitos de AI Extensions](https://developers.raycast.com/ai/learn-core-concepts-of-ai-extensions). Os modos de aprovação das ferramentas são Ask, Auto e Always Allow; o manual descreve regras e prévia da chamada. [Permissões de IA](https://manual.raycast.com/ai/ai-extensions).

**Verificado:** modelos locais via Ollama são usados em Quick AI, AI Chat e AI Commands; chamadas locais vão diretamente ao servidor Ollama, mas ferramentas específicas ainda podem usar servidor Raycast. Modelos customizados podem ter provedores compatíveis com API OpenAI; capacidades como visão e ferramentas são declaradas no arquivo de configuração. Ferramentas web customizadas não fazem fallback automático quando o provedor falha. [Local Models](https://manual.raycast.com/ai/local-models), [Custom Providers](https://manual.raycast.com/ai/custom-providers). O manual de privacidade distingue tráfego de modelos Raycast, BYOK, OpenRouter e provedores customizados, além de Cloud Sync e anexos. [Privacidade](https://manual.raycast.com/ai/raycast-ai-privacy-security).

**Limite:** não há evidência pública aqui para algoritmo de ranking, índice local, latência, CPU/RAM, scheduler interno, protocolo RPC concreto, isolamento real sob ataque, política de retries por ferramenta, persistência detalhada de conversas nem mecanismo de fallback entre modelos do aplicativo. Onde o manual descreve comportamento, isso é afirmação do fornecedor, não validação instrumental.

## 5. Arquitetura observável e hipóteses

```text
Busca raiz / hotkey / alias / deeplink / agenda
       ↓
Manifesto → comando (view | no-view | menu-bar) → Action Panel
       ↓                                  ↘ ferramenta de IA tipada
Host Raycast ↔ RPC documentado ↔ processo Node / isolate de extensão
       ↓
Permissões macOS do aplicativo + APIs locais/externas da extensão
```

O diagrama é uma **síntese das interfaces documentadas**, não um mapa completo dos processos internos. A UI nativa do host pode exibir componentes declarados em React; o código aberto não revela como a busca raiz ordena resultados ou como o app programa hotkeys. Background refresh documentado não prova execução contínua após o app fechar. [UI](https://developers.raycast.com/api-reference/user-interface), [segurança](https://developers.raycast.com/information/security), [menu bar](https://developers.raycast.com/api-reference/menu-bar-commands), [agenda](https://manual.raycast.com/ai/automations).

## 6. Aplicação original em Sieghart

**Proposta, não implementada:** `CommandDescriptor` inclui ID estável, título, aliases, termos, categoria, parâmetros e ações secundárias. `CommandCatalog` busca em memória com normalização local e resultados progressivos; `PaletteViewModel` só mantém estado de apresentação (`query`, seleção, carregamento, erro). `ActionRegistry` expõe operações tipadas ao teclado, voz e agente sem transformar texto do usuário em AppleScript/shell. `WorkflowRunner` executa um plano de passos com dependências, prévia, `ActionAuthorization`, `ActionResult`, timeout, cancelamento e diário mínimo. [Arquitetura detalhada](../architecture/sieghart-automation-architecture.md).

**Compatibilidade com o código atual:** `ActivationController` já registra hotkeys e interpreta alguns comandos de voz deterministicamente; `LocalAppLauncher` já usa `NSWorkspace.openApplication`. `CodexCodingAgent`/`ClaudeCodingAgent` atendem fluxos de codificação, enquanto métricas de uso são outro módulo. O registro proposto deveria integrar esses pontos, não criar um segundo atalho global nem presumir que os agentes de codificação sejam o orquestrador geral. [Trecho de ativação](../../Sieghart/Shared/Services/Activation/ActivationController.swift), [launcher](../../Sieghart/Core/Helpers/VoiceCommands.swift), [comparação anterior](../comparisons/openjarvis-vs-sieghart-architecture.md).

**Exemplo “preparar ambiente de desenvolvimento”:** resolver Xcode/Obsidian por bundle ID ou escolha do usuário; montar plano legível; abrir apps com `NSWorkspace`; conferir `NSRunningApplication`; organizar janelas só se Accessibility estiver concedida e cada janela suportar tamanho/posição; executar um Atalho do usuário para Focus se houver um Atalho configurado; relatar cada passo como feito, negado, indisponível ou incerto. Apple documenta [`NSWorkspace.openApplication`](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication%28at%3Aconfiguration%3Acompletionhandler%3A%29), [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement), [URL de Atalhos](https://support.apple.com/en-au/guide/shortcuts-mac/apd624386f42/mac) e [CLI `shortcuts`](https://support.apple.com/en-au/guide/shortcuts-mac/apd455c82f02/mac). **Ativar Focus do sistema sem Atalho autorizado não foi confirmado por API pública geral.** `SetFocusFilterIntent` adapta *o próprio app* ao Focus, não liga o Focus do sistema. [Apple Focus](https://developer.apple.com/documentation/appintents/focus).

## 7. Desafios, limites e recomendação

1. **Permissões:** pedir Accessibility só para operações que exigem AX. Apple Events exigem `NSAppleEventsUsageDescription` e autorização específica; entitlement pode ser necessário conforme assinatura/distribuição. [Apple Events](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription), [entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events). Uma permissão TCC não substitui aprovação da ação no Sieghart.
2. **Resultados reais:** iniciar app, comando ou Atalho não comprova que o ambiente ficou pronto. Conferir estado observável; quando não houver verificação confiável, marcar como “iniciado” ou “não confirmado”.
3. **Cancelamento e retries:** cancelar uma `Task` não desfaz efeitos já feitos em outro processo. Repetir apenas ações idempotentes ou com chave de idempotência; oferecer compensação explícita quando possível.
4. **Desempenho:** manter a paleta leve e indexação separada; medir tempo para primeira resposta, estabilidade de ranking, RAM/CPU e consumo apenas quando houver protótipo. Não existem números de benchmark Raycast nesta pesquisa.
5. **Compatibilidade macOS:** App Intents podem expor ações do Sieghart à app Atalhos; a [diretriz Apple](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts) diz que *App Shortcuts* não são suportados no macOS, embora ações de App Intents possam compor Atalhos personalizados. Evitar prometer descoberta automática por frases no Mac.

**Recomendação:** priorizar paleta + catálogo de comandos e, em seguida, um workflow curto com apps/Atalhos escolhidos. Deixar extensão de terceiros, AppleScript genérico e automação AX ampla fora do MVP até existir caso de uso, modelo de segurança e medição. O [roadmap](../roadmap/implementation-roadmap.md) detalha portões e como testar uma futura implementação em worktree isolado.

## 8. Perguntas abertas

- Em hardware real, qual latência de invocação/busca e qual consumo o Raycast alcança no conjunto de comandos relevante? Sem instalação, não medido.
- Quais permissões e frameworks a versão específica distribuída ao usuário declara? Sem pacote, não verificado.
- Que opções de Focus do usuário são executáveis por Atalho no Mac dele, com confirmação de estado? Requer teste autorizado.
- Quais comandos Sieghart devem ser expostos como App Intents para outras apps e quais ficam internos à paleta?
- Há necessidade demonstrada de extensões de terceiros ou basta um registro interno e conectores oficiais?

**Teste realizado nesta etapa:** verificação estática de documentação/código público e referências locais. Nenhum aplicativo Raycast foi executado e nenhum código de produção Sieghart foi alterado.
