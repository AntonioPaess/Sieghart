# Comece aqui — Sieghart

Estado de continuidade em **24/10/2026**, horário de Recife. Este repositório é a fonte principal; não é necessário ter o histórico do chat ou o Obsidian para retomar.

**Snapshot publicado no GitHub:** [feature/sieghart-claude-handoff-2026-10-23](https://github.com/AntonioPaess/Sieghart/tree/feature/sieghart-claude-handoff-2026-10-23). O commit de código e pesquisa `cf9a118e97fe63d52340f9c9c76266da69e725dc` foi confirmado no remoto em 24/10/2026; este checkpoint documental complementa a entrega. O bloqueio anterior de disco/iCloud está registrado como histórico em `CURRENT_WORK.md`.

## Ordem de leitura

1. [Trabalho atual](CURRENT_WORK.md): checkpoint vivo, tarefa em andamento e próximo passo.
2. [Bugs e validações pendentes](KNOWN_ISSUES.md): distingue corrigido em teste, comprovado no Mac e ainda não validado.
3. [Índice de pesquisa e REA](RESEARCH_INDEX.md): dossiês de aplicativos, evidências preservadas e limites das análises.
4. [Fluxo de desenvolvimento](Sieghart/Design/Workflow/README.md), [direção do produto](Sieghart/Design/product-direction-2026-10-11.md) e [auditoria do roadmap](Sieghart/Design/Workflow/sprint-roadmap-audit-2026-10-18.md).

Os relatórios datados são históricos. Um teste aprovado num relatório antigo não supera um bug posterior relatado pelo usuário. `CURRENT_WORK.md` e `KNOWN_ISSUES.md` indicam a situação mais recente.

## Produto e decisões do usuário

Sieghart é um app macOS nativo, com widget/notch, Home, conversas e ferramentas locais. O objetivo é uma experiência contínua de assistência semelhante ao HeyClicky, com identidade visual própria. Ainda **não há paridade 1:1 comprovada**, nem produto/design declarados completos.

- Sieg é o coordenador e atende clima, informações e funções do app. Ada recebe código e matemática. Rita cuida de foco/pausas; Gantt, agenda; Elinor, recursos; Toni, arquivos/escrita. O personagem existir não significa que todas as integrações estejam prontas.
- **Mensagem digitada → resposta visual no chat. Pedido por voz → resultado visual e áudio no widget.** Não tocar áudio para respostas digitadas.
- Segurar o atalho inicia a captura; soltar finaliza e interpreta. Cursor/seleção pertencem ao mesmo turno; interrupções descartam respostas antigas.
- Resposta deve respeitar o idioma selecionado. A voz é parte da identidade de cada personagem; não recolocar uma lista enorme de vozes.
- Leitura da tela, ferramentas e diagramas precisam de evidência real. Não fabricar execução, texto OCR, temperatura ou explicações de demonstração quando o modelo estiver indisponível.
- Design premium consistente nas 16 abas, acessibilidade, transparência limpa, movimentos breves/canceláveis e Reduzir Movimento. Preservar personagens/coreografia aprovados.
- Clima usa nove estados do personagem 2.5D, efeitos no painel todo e recolhimento automático. Não colocar o avatar em um quadrado de fundo nem recolocar o X climático.
- A preparação para o Swift Student Challenge foi adiada por decisão do usuário: agora o foco é o produto.

## Estado entregue mais recente

Build **106**, universal arm64/x86_64, instalado em `/Applications/Sieghart.app`, bundle `com.sieghart.app`. Verificação final: **371 funções / 1141 invocações**, 195/195 fontes instrumentadas, sem alteração de fontes durante os testes. Oito testes Python do guard de atualização passaram. Não confundir esses contratos com validação acústica ou de todas as telas reais.

Nesta etapa foram corrigidos: interpretação de Keep Awake com duração/tela ligada; preservação da proteção durante atualização; clima herdando indevidamente um pedido de explicação; contexto de desenho + explicação; lentidão/falha de OCR; resposta pronta de pi e relatos fabricados do fallback.

Relatórios essenciais recentes:

- [Recuperação de intenção, OCR e Keep Awake](Sieghart/Design/Workflow/sieg-intent-and-awake-recovery-2026-10-23.md).
- [Abertura, transições e navegação](Sieghart/Design/Workflow/sieg-opening-polish-2026-10-22.md).
- [Padrão visual das 16 abas](Sieghart/Design/Workflow/sieg-premium-design-2026-10-22.md).
- [Finalização das animações climáticas](Sieghart/Design/Workflow/sieg-weather-finish-2026-10-22.md).
- [Crash de voz e regra de lançamento](Sieghart/Design/Workflow/sieg-voice-launch-crash-2026-10-22.md).
- [Produto integrado e limites dos especialistas](Sieghart/Design/Workflow/sieg-product-completion-2026-10-21.md).
- [Mapa de comportamento HeyClicky](Sieghart/Design/Workflow/heyclicky-behavior-gap-2026-10-20.md), histórico, com atualizações posteriores indicadas no próprio arquivo.

## Mapa de código

Os caminhos abaixo são relativos a `Sieghart/Sieghart/`:

| Assunto | Entrada principal |
| --- | --- |
| Turnos, contexto, visão, clima e canvas | `Features/SpatialOverlay/ViewModels/SpatialAssistantCoordinator.swift` |
| Reconhecimento de comandos nativos | `Core/Helpers/VoiceCommands.swift`, `Core/Services/Voice/VoiceAppTools.swift` |
| Modelo Apple, streaming e indisponibilidade | `Core/Services/AI/AppleLocalChatEngine.swift` |
| Ferramentas do modelo e autorização pelo pedido original | `Core/Services/AI/SiegDesktopTool.swift` |
| Captura, Accessibility, OCR e regiões | `Core/Services/Capture/ScreenSemanticInspector.swift` |
| Clima e identidade geográfica | `Core/Services/Voice/VoiceWeatherService.swift`, `WeatherLocationResolver.swift` no mesmo diretório |
| Formas geométricas procedurais | `Features/SpatialOverlay/Views/VectorDrawingInterpreter.swift` |
| Conteúdo gerado do canvas | `Shared/Models/GeneratedCanvas.swift` e serviços de conteúdo espacial em `Core/Services/AI/` |
| Sessão/atalho de voz | `Shared/Services/Activation/ActivationController.swift` e serviços em `Core/Services/Voice/` |
| Keep Awake e persistência | `Features/KeepAwake/ViewModels/KeepAwakeViewModel.swift` |
| Home, navegação e foco | `Features/Workspace/Views/WorkspaceView.swift` |
| Widget e ciclo dos resultados | `Features/DynamicIsland/Views/NotchWidgetView.swift`, `ViewModels/NotchWidgetViewModel.swift` |
| Desenho visual compartilhado | `Shared/Components/DesignSystem.swift`, `Shared/Components/Island/IslandChrome.swift` |
| Animações climáticas aprovadas | `Features/DynamicIsland/Views/CompanionWeatherScene.swift`, `Shared/Components/Companion/CompanionWeatherCharacter.swift` |
| Chat persistente e encaminhamento | `Features/AgentRoom/ViewModels/LocalChatViewModel.swift` |

Testes: `Sieghart/Tests/SwiftTesting/`, fixtures em `Tests/Support/`, testes do guard em `Tests/Python/test_update_awake_guard.py`.

## Compilar, testar e abrir

Requer o SDK e o macOS compatíveis com as APIs Apple utilizadas; o modelo AFM 3 depende de macOS 27 e Apple Intelligence elegível/pronto. Não substituir silenciosamente esse motor por respostas fixas.

Na pasta `Sieghart/`:

```sh
python3 Tools/run-swift-tests.py --plan fast --output /tmp/sieg-validation-unique --derived-data /tmp/sieg-validation-dd
python3 -m unittest discover -s Tests/Python -p test_update_awake_guard.py
xcodebuild -project Sieghart.xcodeproj -scheme Sieghart -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/sieg-build-dd build
```

Use um diretório de evidência novo para cada execução. Os scripts de teste guardam seleção, resultados individuais, cobertura e alterações de fonte. Não atualizar contagens manualmente sem uma execução correspondente.

O destino único de instalação é `/Applications/Sieghart.app`. **Nunca abrir diretamente `Contents/MacOS/Sieghart`**: isso já causou crash por atribuição de privacidade ao processo pai.

Antes de encerrar uma versão com Keep Awake ativo:

```sh
python3 Tools/hold-awake-during-update.py prepare
# Encerrar o app normalmente somente depois de confirmar a proteção temporária.
bash Tools/install-current-app.sh /tmp/sieg-build-dd/Build/Products/Debug/Sieghart.app
bash Tools/launch-current-app.sh --resume-keep-awake-session
```

Não reiniciar timer do usuário para teste, não mudar senha/bloqueio do macOS e não conceder permissões automaticamente. Usar os botões do app que levam aos Ajustes quando necessário.

## Trabalho entre Claude e Codex

O snapshot para Claude deve permanecer estável. A continuação do produto usa outra branch, sem novas worktrees. Cada IA precisa de sua própria pasta já existente ou de alternância exclusiva no mesmo checkout: duas branches não isolam duas IAs escrevendo na mesma pasta simultaneamente.

Não executar `reset --hard`, `clean`, checkout que descarte arquivos, rebase de histórico publicado, merge em main ou push forçado. Preservar mudanças dos outros chats. Um agente por vez; Astra proibido no Codex. Commit/push somente com autorização correspondente do usuário.

## Registro obrigatório de continuidade

Antes de alterar uma área, registrar em `CURRENT_WORK.md` a intenção, arquivos afetados e critério de aceite. Ao concluir um lote, registrar o resultado, evidência, falhas e próximo passo, mesmo que não haja commit. Atualizar `KNOWN_ISSUES.md` quando houver reprodução/correção; adicionar relatório datado quando houver mudança significativa.

Não depender de prever o fim dos tokens ou da cota. Esses checkpoints são parte da entrega. No fim do trabalho, qualquer outra IA deve conseguir responder: o que mudou, por quê, como foi verificado, o que ainda não funciona e qual é o primeiro próximo passo.
