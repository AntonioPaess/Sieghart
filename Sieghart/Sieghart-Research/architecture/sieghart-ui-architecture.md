# Proposta inicial: interface macOS de Sieghart

**Estado:** proposta de evolução baseada no [estudo fixado de Boring Notch](../applications/boring-notch.md), no código local de Sieghart e nas [áreas auxiliares de NSScreen documentadas pela Apple](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea-gr2n). Não é descrição de implementação concluída.

Sieghart já tem painel AppKit, conteúdo SwiftUI, animação, medição do notch, hover, drop de arquivos e tratamento de fullscreen. A proposta abaixo concentra-se em responsabilidades e validação do comportamento atual; não pressupõe reescrever a interface.

## Responsabilidades

```text
Eventos do sistema e comandos
         ↓
IslandCoordinator (@MainActor): estado e prioridades de apresentação
         ↓
WindowController (AppKit): janela, monitor, foco, visibilidade
         ↓
NSHostingView → IslandView (SwiftUI): layout, animação, controles
```

O `IslandCoordinator` deve receber eventos tipados como `.hoverEntered`, `.dragStarted`, `.voiceListening`, `.taskCompleted` e `.displayChanged`. Uma política de prioridade decide se uma notificação transitória interrompe ou aguarda uma interação em curso. O conteúdo SwiftUI recebe estado pronto para renderização e envia intenções de volta; não reposiciona a janela.

O controlador de janela deve identificar a tela escolhida de forma estável, recalcular geometria ao mudar configuração e ter fallback para tela sem notch. Manter uma instância por display é uma opção futura, dependente de necessidade real do usuário. A área física pode ser estimada com `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` quando ambas existirem, sempre em coordenadas globais. Há uma implementação de partida em [`NotchGeometry.swift`](../../Sieghart/Core/Helpers/NotchGeometry.swift); a proposta é validar seus resultados em uma matriz real de displays antes de alterar constantes.

Um contrato **proposto**, ainda não implementado, deixa a política de estado independente dos detalhes de `NSPanel`:

```swift
struct IslandDisplayID: Hashable, Sendable { let value: String }

struct IslandPresentation: Sendable {
    enum State: Sendable { case compact, expanded, transient }
    let state: State
    let contentID: String?
    let priority: Int
}

enum IslandIntent: Sendable {
    case clicked, hoverEntered, hoverExited, dragEntered, dragExited
    case displayChanged(IslandDisplayID)
}

@MainActor
protocol IslandWindowControlling: AnyObject {
    func show(_ presentation: IslandPresentation, on display: IslandDisplayID) throws
    func reposition(on display: IslandDisplayID) throws
    func hide()
}
```

`IslandPresentation` seria um valor imutável e `Sendable` com estado, identificador de conteúdo e prioridade; não transportaria `NSScreen` ou `NSWindow` para fora do `MainActor`. O coordenador recebe `IslandIntent`, resolve conflitos (por exemplo, drag em andamento antes de um aviso transitório), cancela tarefas de hover antigas e só então chama o controlador. O controlador resolve `IslandDisplayID` para `NSScreen` no ator principal, calcula frame e informa erro de display ausente; o coordenador escolhe fallback e registra o evento. A view SwiftUI apenas emite intenções e renderiza a apresentação. Esta separação permite testar política e geometria sem criar uma janela real, mantendo testes de integração para foco e Spaces em hardware.

## Contrato de interação

| Estado | Entrada | Saída esperada |
| --- | --- | --- |
| Compacto | Início, fechamento, fim de aviso | Hit region pequena e conteúdo resumido |
| Expandido | Clique, atalho ou drop | Controles completos, foco somente quando necessário |
| Transitório | Evento de voz, progresso, conclusão | Prazo/cancelamento explícito e retorno ao estado anterior |
| Oculto/pausado | Preferência ou contexto impeditivo | Sem captura de eventos fora da área necessária |

Hover em Sieghart destaca o estado compacto, sem expandir: isto consta no [teste local](../../Tests/InteractionChecks.swift). Uma tarefa cancelável controla o fechamento. Arraste, confirmação e popover mantêm a interface aberta por razões explícitas, para que uma saída momentânea do cursor não feche conteúdo em uso. Evitar depender de timers sem vínculo com o ciclo de vida da view.

## Fronteira de APIs

AppKit oferece `NSWindow`/`NSPanel`, `NSScreen`, `NSHostingView`, eventos, tracking areas e [collectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct). SwiftUI oferece views e animação. O estudo de Boring Notch encontrou caminhos privados CGS e SkyLight, que não fundamentam uma recomendação de API pública. Tela bloqueada e presença universal sobre fullscreen são requisitos a validar, não promessas da arquitetura. Também não se deve prometer ocultação de captura com [sharingType.none](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none), marcado como legado pela Apple.

## Validação antes da implementação

1. Teste de geometria: MacBook com notch, display externo sem notch, mudança de display principal, escalas e resolução.
2. Teste de interação: hover que apenas destaca, clique que expande, arraste de arquivo, popover, teclado e VoiceOver.
3. Teste de Spaces/fullscreen e foco: identificar onde a janela pode aparecer com as APIs públicas escolhidas.
4. Perfil de CPU, memória e energia em repouso e durante animação; definir orçamento a partir de medidas do app atual.

Esta pesquisa não modifica o código do aplicativo. Qualquer mudança futura deve ser implementada como código original e revisada contra as permissões e modos de distribuição de Sieghart.

Um ponto concreto a reproduzir antes de propor correção: [positionPanel()](../../Sieghart/Features/DynamicIsland/ViewModels/NotchWidgetViewModel.swift) retorna quando o tamanho do canvas não muda; uma troca de monitor ou posição com tamanho idêntico pode deixar o painel na origem anterior. Os testes atuais usam views fora da tela e não confirmam esse cenário. Se houver implementação, fazê-la em worktree separado e entregar o teste manual de troca de monitor junto com a verificação automatizada pertinente.
