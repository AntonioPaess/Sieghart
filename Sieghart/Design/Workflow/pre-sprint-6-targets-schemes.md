# Pré-sprint 6 — Proposta de targets, schemes e isolamento

Data da proposta: 17 de outubro de 2026. O texto abaixo registra o desenho original; implementação autorizada e validada em 18 de outubro, com [resultados atuais e revisão](pre-sprint-6-execucao.md). Complementa o [plano](pre-sprint-6-swift-testing.md) e o [inventário dos 18 grupos](pre-sprint-6-inventario.md).

## Recomendação

Adicionar inicialmente **um target macOS de testes Swift Testing sem aplicativo hospedeiro**, `SieghartTests`, compilando referências aos próprios arquivos de produção de `Core/`, `Features/` e `Shared/`, junto das novas suítes e helpers. Excluir os dois arquivos de `App/`. Adicionar um scheme compartilhado de testes, `Sieghart-Checks`, com dois test plans: completo e rápido.

Esta é uma recomendação específica para a migração: replica a fronteira de fontes já usada pelo runner e evita transformar todo o app em framework para obter acesso a tipos internos. Não cria cópias das fontes nem um módulo paralelo com implementações substitutas. A decisão ainda depende de revisão independente e de uma prova pequena de descoberta/execução, **somente após autorização para implementar**.

## Evidência que orienta a escolha

- [project.pbxproj](../../Sieghart.xcodeproj/project.pbxproj) tem um `PBXNativeTarget`, o aplicativo `Sieghart`, sem target de testes. As configurações declaram Swift 6.0 e deployment target macOS 14.6; atributos do projeto indicam atualização 2700 e compatibilidade Xcode 16.0. Isso não comprova qual SDK/toolchain será usado na futura execução.
- Há 126 fontes registradas: 124 fora de `App/` e `SieghartApp.swift`/`ResidentAppDelegate.swift` em `App/`. O [runner](../../Tests/run-checks.sh) maior já compila as 124 sem composição residente.
- [SieghartApp.init](../../Sieghart/App/SieghartApp.swift) constrói modelos de produção e inicia monitoramentos. Um target hospedado no app violaria a fronteira pedida antes de qualquer teste poder injetar mocks.
- A árvore inspecionada não contém arquivo `.xcscheme` compartilhado; há apenas o registro de nome/ordem em `xcuserdata`. Não depender de scheme autocriado ou da configuração pessoal do autor.
- A arquitetura atual reúne tipos internos entre ViewModels, serviços e componentes. Extrair só `Core/` não cobre voz/ilha/chat/companions nem os testes mistos identificados no inventário.

## Alternativas consideradas

| Opção | Benefício | Custo/limite nesta base | Proposta |
| --- | --- | --- | --- |
| Teste hospedado com `@testable import Sieghart` | Exercita módulo do app e seus símbolos internos | Inicializa composição residente; exige mecanismo adicional para impedir efeitos de startup | Não usar como entrada desta migração |
| Framework de produção, por exemplo `SieghartRuntime`, e testes não hospedados que o importam | App e testes exercitam o mesmo módulo; melhor fronteira de longo prazo | Mover quase toda a árvore cria fronteira de acesso entre app/framework, tratamento de recursos e alterações de integração; não há evidência de necessidade desse escopo agora | Reavaliar depois; exige desenho próprio se necessário |
| Referências das fontes reais no target não hospedado | Menor mudança arquitetural, acesso a internos no mesmo módulo; fronteira conhecida do runner | Compila outro módulo; risco de flags/membership/recursos divergirem; cobertura pertence ao binário de testes | **Recomendada com os controles abaixo** |
| Um target/scheme por grupo ou por feature | Separação rígida de processos | Repete compilação e configuração, multiplica manutenção sem relação com fronteiras reais de isolamento | Usar suítes/tags; separar processo só quando uma dependência comprovadamente exigir |
| Swift Package com núcleo extraído | Runner `swift test` e módulo explícito | Nova estrutura de build/recursos/macros; não elimina dependência macOS/SwiftUI/AppKit dos 18 grupos | Fora da migração inicial |

## Desenho proposto

| Elemento | Papel e associação |
| --- | --- |
| Target `Sieghart` existente | Continua contendo as 126 fontes do aplicativo e recursos de produção. Sem dependência no target de testes. |
| Novo target `SieghartTests` | Produto de unit tests macOS, Swift Testing, Host Application = None, `TEST_HOST` e `BUNDLE_LOADER` vazios; sem dependência/embedding de `Sieghart.app`. |
| Membership de produção no teste | As mesmas 124 referências físicas de Core/Features/Shared; nenhum `App/`, preview ou `@main` legado. As suítes usam tipos internos do próprio módulo de teste; não usar `@testable import Sieghart` nesta opção. |
| Suítes novas | Diretório futuro `Tests/SwiftTesting/`, organizado por funcionalidade; suporte futuro `Tests/Support/`. Nomes físicos finais ficam para a implementação. |
| Fixtures/recursos | URLs de fixtures explícitas, pasta exclusiva por caso, JSON versionado copiado como recurso de teste quando necessário; catálogo visual/bundle compilado com verificação própria. |
| Scheme compartilhado `Sieghart` | Publicar arquivo de scheme do app se ainda ausente, preservando ações equivalentes; build/Run normais do produto. Não iniciar este scheme na preparação atual. |
| Scheme compartilhado `Sieghart-Checks` | Build/Test apenas do target não hospedado; nenhum Run executável do app, pre/post-action que o abra ou dependência implícita nele. Test plan padrão completo. |

Não herdar automaticamente o `Info.plist` do app, suas privacy strings, `LSUIElement`, entitlements de Calendar/Apple Events, bundle ID ou hardened runtime para o bundle de testes. O projeto hoje contém opções também em nível de projeto: a implementação deverá explicitamente isolar/neutralizar a herança inadequada e manter apenas o necessário ao runner de testes do Xcode. Assinatura do bundle de teste será a mínima exigida pelo ambiente local, sem conceder capacidades do app para contornar uma fixture.

Manter a linguagem Swift e as condições de compilação relevantes equivalentes às de Debug do app. A combinação concreta Xcode/SDK/macOS/arquitetura fica registrada no primeiro resultado. O deployment target 14.6 existente não significa que o modelo Apple funcionará nessa versão; os testes de elegibilidade fornecem OS/entitlement sintéticos e não fazem inferência.

## Planos e seleção

Segundo a [documentação de test plans da Apple](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback), um scheme pode ter vários planos, um deles padrão, com seleção por testes/tags. A proposta usa essa separação para manter o aceite completo visível.

| Test plan proposto | Seleção | Ambiente / uso |
| --- | --- | --- |
| `Sieghart-Complete` — padrão | Todos os casos migrados dos 18 grupos e A01, sem filtro que omita novos testes. Inclui U/I/L/V. | Mac com ferramentas locais de fixture e sessão gráfica para os contratos AppKit. Coleta resultados e cobertura. É o plano que atende a migração. |
| `Sieghart-Fast` | Somente tags `logic` ou `isolated`, depois de comprovar ausência de dependências L/V. | Feedback de regras/estado, sem OCR/watcher/subprocessos/renderização. Não aprova o gate sozinho. |

Tags propostas: `logic`, `isolated`, `localIntegration`, `nativeView`; tags de funcionalidade quando úteis (`voice`, `timers`, `files`, `chat`, `companions`, etc.). Tags expressam seleção, não garantem isolamento. Não etiquetar uma suíte mista inteira como `logic` por conveniência.

Benchmark Metal A02, verificações do produto assinado A03/asset compilado A04 e previews continuam ferramentas separadas identificadas no inventário. Nenhum target UI/XCUIAutomation ou target de benchmark novo é necessário para migrar os 18 grupos. A suíte V testa objetos/painéis próprios fora da tela; não abre a interface do Sieghart nem controla aplicativos do usuário.

Futuros comandos documentados usarão `xcodebuild` com projeto, scheme, `-testPlan`, destination macOS, result bundle e diretórios de build explícitos; a forma concreta dos filtros por suíte/caso deverá ser conferida contra os identificadores efetivamente descobertos. Não prometer sintaxe de seleção ainda não validada. O runner legado manterá seus filtros até equivalência; ao trocar a entrada, documentar a correspondência entre nomes legados e suítes. Filtro sem correspondência não pode retornar sucesso como se tivesse executado testes.

## Suítes, concorrência e teardown

A [documentação de paralelismo do Swift Testing](https://developer.apple.com/documentation/testing/parallelization) esclarece que testes normalmente compartilham processo e executam em paralelo. `serialized` em uma suíte ordena apenas seus descendentes, sem exclusão mútua com outras suítes independentes. `@MainActor` não torna casos assíncronos mutuamente exclusivos entre `await`s.

Proposta de organização lógica, sem criar arquivos nesta etapa:

```text
SieghartTests
├── LogicTests                       funções/valores sem global mutável
│   ├── FocusVoiceParserTests
│   ├── Timer/price/quota/context rules
│   └── Geometry/pose/identity rules
└── MacContractsTests                 uma raiz serialized
    ├── Timers / VoiceFlow / Island / Preferences
    ├── Usage / Audio / Clipboard / Calendar / Utilities
    ├── Files / Capture / FileReception / Events
    └── AgentRoom / LocalChat / AdaGitHub / NativeViews
```

Todos os casos I/L/V com estado mutável, caches, notificações ou objetos de UI ficam sob **a mesma raiz serializada** na primeira migração. U só pode rodar em paralelo se não tocar esses recursos. Marcar apenas suítes irmãs independentes com `serialized` não resolve o compartilhamento entre elas. A execução inicial deverá também evitar múltiplos workers do Xcode duplicando a fixture; diferenciar isso do paralelismo interno do Swift Testing.

Serialização não estabelece dependência de ordem nem substitui cleanup. Cada caso constrói sua fixture e deve sobreviver sozinho, em ordem diferente e repetido. Liberar explicitamente tasks, continuations, timers, observers, security scopes, watchers, subprocessos, field editors e painéis. A integração local que mede um watcher/processo usa evento e deadline limitado, sem depender de um sleep fixo como prova de conclusão.

Se um cache privado ou registro global de imagem não puder ser restaurado sem contaminação, a implementação propõe a menor seam de isolamento ou uma execução dedicada em novo processo para esse subconjunto. Isso exige evidência e atualização do desenho antes de adicionar mais targets. Não alterar comportamento de produção para retornar respostas artificiais quando detectar que está sob teste.

## Fontes e gerador do projeto: requisito antes de criar o target

O [gerador atual](../../Tools/update-project-sources.py) não está preparado para vários targets:

- A substituição por regex atinge todas as seções `PBXSourcesBuildPhase` com comentário `Sources`, preenchendo-as com a lista completa de produção. Se surgir um target de testes sem adaptação, ele poderá receber `App/` e perder seus testes.
- O gerador reconstrói a seção inteira de grupos preservando apenas o grupo raiz e Products existentes; grupos novos de Tests podem ser removidos.
- A chave de referências usa basename e presume um build reference por arquivo. Com membership em dois targets, o mesmo file reference precisa de build references específicos por fase/target; basenames repetidos não podem colidir.

A primeira mudança de infraestrutura futura deverá tornar seleção de grupos/fontes/recursos **específica por target**, com identidade por caminho e preservação de produtos, dependências, configurações e grupos de teste. Não criar um segundo manifesto manual independente que se desalinhe do gerador.

Aceite futuro desse ponto: duas execuções do gerador sem segunda alteração; comparação dos conjuntos esperados, sem duplicações; 126 fontes no app e as mesmas 124 não-App no módulo de teste na base atual, além dos arquivos de teste/suporte. Os números serão atualizados se o código mudar; o contrato principal é a diferença explícita de membership e a exclusão da composição residente. Inspecionar também recursos e o diff do projeto. Não executar o gerador nesta preparação.

## Dependências a fixar por fixture

| Fronteira | Tratamento proposto |
| --- | --- |
| Defaults, data, relógio e agendamento | Suíte UUID por caso e remoção garantida; relógio controlado; datas de calendário com timezone explícito. Não mudar defaults, relógio ou ambiente globais do usuário. |
| Histórico de provedores | `home` **e** `codexHome` explícitos para leitor; `read` **e** `readClaude` injetados nos modelos. Não usar configuração herdada de `CODEX_HOME`. |
| Credenciais/GitHub | Stores em memória, transportes falsos e clock; manter o default já isolado de `AdaGitHubViewModel()` sem serviço. Nenhum Keychain/URLSession real nas suítes. |
| Voz/áudio/input | Buffers e eventos sintéticos, backends injetados; atalhos/sensores/monitores nativos desligados; autorização/captura de microfone e process taps não iniciados. |
| Calendário/notificações/eventos | Reader/notifier inertes ou gravadores, observers próprios quando possível, sem EventKit/UserNotifications reais. Preservar teste de opt-out antes da entrega. |
| Arquivos/captura | Diretório exclusivo, bookmarks/scopes fechados; processo de DMG falso; Vision só em imagem gerada local; nenhum Finder/clipboard/captura da tela real. |
| Processos/SQLite/SDK | Somente executáveis/scripts/DB próprios, dependências locais explícitas e timeout/cancelamento/exit observáveis. Node/Python ausente é requisito não satisfeito, com resultado registrado, sem autoaprovação. |
| Recursos visuais/preços | URL/bundle explícito do fixture; não depender do cwd, `.app` em `/private/tmp` nem de `.main` ser o app. Verificar fallback e recursos compilados em fluxos distintos. |
| Caches/imagens/notificações globais | Uma raiz serializada, save/restore ou seam mínima; fixture de imagem `Companion-ada` não pode contaminar retrato de outra suíte. |

Falhas de isolamento hoje localizadas por leitura são D01–D09 do inventário. A migração preserva os contratos e corrige essas dependências do teste, sem adicionar recursos da Sprint 6.

## Asserções, resultados e cobertura

Converter cada cenário em teste com nome de comportamento e fixture independente. Usar `#expect` para verificação, `#require` para pré-requisito de continuação e expectativa de erro com tipo/condição adequada. Callbacks inesperados reportam issue do teste em vez de abortar todo o processo. Não envolver `main()`/`run()` inteira em um `@Test` único. Parametrizar matrizes de parser/PCM/personagem/OS preservando identificação da combinação que falhou.

O [guia de cobertura da Apple](https://developer.apple.com/documentation/xcode/determining-how-much-code-your-tests-cover) trata cobertura como evidência complementar aos cenários. Nesta arquitetura, a instrumentação mede as fontes compiladas no **módulo `SieghartTests`**, não a composição, linkedição, assinatura ou execução de `Sieghart.app`.

O primeiro piloto precisa confirmar que a toolchain coleta/exporta cobertura das fontes de produção compiladas no bundle de teste. Selecionar o binário instrumentado correspondente e apresentar recorte por caminho de produção, excluindo helpers/testes do denominador do relatório útil. Conferir que as 124 fontes esperadas aparecem ou que toda ausência seja explicada; arquivos com zero execução não devem desaparecer silenciosamente. Se o relatório do Xcode não suportar esse recorte diretamente, documentar a exportação por caminho ou reconsiderar a arquitetura antes de declarar o critério cumprido.

O runner legado não tem baseline numérico de cobertura medido nesta preparação. A equivalência será demonstrada por IDs de cenários e evidências por caso; o primeiro relatório novo estabelece a baseline de linhas/funções, com lacunas explicadas. Não afirmar que uma porcentagem foi preservada sem medição comparável anterior. Medições de CPU/p95 do benchmark continuam separadas da execução com instrumentação de cobertura.

## Sequência futura e pontos de decisão

| Lote | Entrega delimitada | Saída para revisão |
| --- | --- | --- |
| 0 — aprovar desenho | Revisão desta proposta, matriz, alternativas, limitação de módulo/cobertura e requisitos de ambiente | Decisão registrada sobre arquitetura; nenhum gate de execução aprovado |
| 1 — infraestrutura e piloto | Gerador por target, target não hospedado, schemes/plans compartilhados; primeiro conjunto de timers/parser e um fluxo de estado com dependências controladas | Descoberta Xcode/CLI, seleção de caso e erro individual, ausência de startup do app, primeira cobertura exportada e gerador idempotente |
| 2 — regras e estado | G01/G02, parte pura de G04/G05/G10/G12–G16/G18; quota/preços/imports e modelos com mocks | Casos independentes, variantes identificáveis, equivalência por IDs e plano rápido verificável |
| 3 — integrações locais e views | G06 stdio, G07/G08/G11 logs, G12 disco, G16 arquivos/watch/OCR/processo, G17 protocolos/SQLite/SDK/views, G18 JSON e A01 | Plano completo com requisitos de ambiente satisfeitos, teardown e limites documentados |
| 4 — consolidar | Substituir entrada do runner após equivalência, remover só duplicação comprovada, documentar reprodução e relatórios | 18 grupos + A01 rastreados; A02–A10 com destino explícito; nenhum `@main` legado indevido no target |
| 5 — revisar gate | Revisor independente confere diff identificado, matriz, descoberta, resultados, falhas relevantes corrigidas, coverage e limitações | Decisão explícita sobre liberação da Sprint 6 |

Coordenação mantém escopo/matriz; implementação faz a mudança futura; revisão confere uma entrega identificada. Especialista visual participa apenas se houver dúvida de contrato de identidade/movimento, sem redesenho. Nenhum trabalho foi disparado para outros chats.

## Critérios para aceitar a proposta e depois a implementação

**Desenho ainda a revisar:** aceitar a compilação das fontes no target de teste como etapa inicial; confirmar necessidade de sessão gráfica/ferramentas e o plano para cobertura; concordar com uma raiz serializada e separação U/I/L/V. Se o requisito mudar para exercitar exatamente o módulo binário importado pelo app, escolher a alternativa de extração antes de implementar, sem mascarar a diferença.

**Na implementação:** discovery real, execução isolada e resultados por caso; falha individual sem abortar suíte, seleção confiável, gerador idempotente, zero dependência de app host, 18 grupos e A01 rastreados, cobertura útil exportada e revisão independente. Ausência de Node/Metal/sessão gráfica não vira aprovação por skip. A02/aceites físicos permanecem em seu fluxo; V obrigatório ausente deixa a migração incompleta até execução em ambiente adequado ou decisão de escopo justificada e revisada.

Esta proposta documenta o desenho da preparação de 17 de outubro. A implementação foi autorizada pelo usuário em 18 de outubro; seu aceite depende do [registro de execução e revisão](pre-sprint-6-execucao.md).
