# Sieghart · acabamento de abertura e navegação · 22/10/2026

A versão 95 mantém o desenho e os personagens aprovados, com transições curtas, interrompíveis e consistentes. O alvo instalado continua sendo `/Applications/Sieghart.app`, com o mesmo identificador e assinatura.

## Entrega

- A silhueta do widget abre a partir do recorte da câmera, em 380 ms na abertura comum, 520 ms na apresentação e 240 ms ao fechar. Mudanças de tamanho entre estados usam 260 ms. As curvas não extrapolam o tamanho de destino.
- Conteúdo aparece em conjunto com a expansão, com deslocamento de apenas 6 pt. Ao fechar, o conteúdo desaparece antes da silhueta. Tema e transparência são conservados durante o fechamento, incluindo o modo claro.
- Repetir uma atualização de layout com o mesmo destino mantém a animação em andamento. Reabrir cancela a conclusão antiga; um fechamento interrompido não pode esconder o painel reaberto. A janela continua se ancorando ao monitor mesmo quando seu tamanho não muda.
- As 16 páginas compartilham uma entrada curta de 300 ms, sem bloqueio de controles. A coluna lateral fica estável. Cada troca de página começa no topo da nova página.
- Os botões usam feedback mais discreto. A coluna lateral usa botões nativos com uma única ação acessível por item, estado selecionado e contorno de foco de teclado.
- A apresentação da equipe tem um botão explícito para pular; Escape também retorna à Home. Quando os personagens estão sem movimento ou Reduzir Movimento está ativo, a Home abre diretamente, sem deixar uma apresentação estática aguardando 31 segundos.
- A coreografia e os modelos 2.5D aprovados, inclusive os nove estados de clima, foram preservados.

## Referências de design

Aplicação local das orientações da Apple para [movimento com propósito, breve e cancelável](https://developer.apple.com/design/human-interface-guidelines/motion), [alternativas para Reduzir Movimento](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria) e [apresentações opcionais](https://developer.apple.com/design/human-interface-guidelines/onboarding). Isto não constitui certificação ou auditoria completa da HIG.

## Verificação

A rodada ampla passou com 363 funções e 1.118 invocações, cobrindo os 195 arquivos de produção previstos. Depois dos últimos ajustes visuais e de navegação, as 100 funções do grupo de interações passaram em 464 invocações; o resultado está em `verification-navigation.json`. Não houve fontes modificadas durante essas execuções, testes ausentes ou inesperados.

Os novos contratos verificam a entrega duplicada de layout, interrupção de fechamento/reabertura, descarte de conclusão antiga, a alternativa sem animação, curvas sem extrapolação e a apresentação opcional.

Foram renderizadas as 16 páginas em claro e escuro usando dados de exemplo, além da conferência da janela instalada. Os painéis estáticos em `evidence/sieg-opening-polish-2026-10-22` mostram a composição; não são medição de FPS. Foram gerados antes dos ajustes finais de rolagem/foco, que não alteram sua composição sem foco. Um marcador amarelo na prévia de Janelas vem do Menu nativo não representado pelo ImageRenderer e não corresponde a um controle amarelo no app. Ainda há textos fixos e dados de integração que merecem revisão de tradução; o polimento não é tratado como conclusão de todos os bugs do produto.

A compilação universal e a validação de assinatura/descrições de privacidade passaram. Instalação, abertura pelo LaunchServices e preservação do prazo do Keep Awake foram verificadas. Nenhuma captura real de microfone, voz reproduzida, teste de AirPods ou atalho físico foi iniciado. Não houve commit, push ou nova worktree.

## Arquivos alterados

- `Shared/Components/Island/IslandChrome.swift`: cronologia, continuidade de camadas, cancelamento e feedback do widget.
- `Shared/Components/DesignSystem.swift`: cadência compartilhada e entrada de página.
- `Features/Workspace/Views/WorkspaceView.swift`: navegação, rolagem por destino e foco acessível.
- `Features/DynamicIsland/Views/NotchWidgetView.swift`: pular apresentação e Escape.
- `Features/DynamicIsland/ViewModels/NotchWidgetViewModel.swift`: deduplicação da transição, ancoragem e alternativa sem apresentação estática.
- `Tests/SwiftTesting/Presentation/IslandFlowTests.swift`: regressões de continuidade e acessibilidade do movimento.

## Limite da última conferência visual

A janela principal foi observada em execução na versão 94, incluindo a navegação nativa e o problema de rolagem que foi corrigido a seguir. A versão 95 passou nas verificações, foi instalada e aberta pelo LaunchServices. A última inspeção visual de foco e rolagem foi impedida pelo bloqueio do Mac informado pela ferramenta de interface. Requer desbloqueio pelo usuário; nenhuma tentativa de contornar o bloqueio foi feita.
