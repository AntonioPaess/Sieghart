# Boring Notch — dossiê macOS, aplicação prioritária 1

**Data:** 13 de outubro de 2026. **Fonte de código fixada:** commit [64b545929cf31681e09b5c375859c1eceeb733eb](https://github.com/TheBoredTeam/boring.notch/commit/64b545929cf31681e09b5c375859c1eceeb733eb), de 10 de outubro de 2026. A pesquisa leu documentação e código públicos e, depois que o usuário instalou o aplicativo, inspecionou de forma estática o pacote em `/Applications/boringNotch.app`. Não compilou o projeto nem usou REA no binário. O código do commit e o aplicativo instalado podem diferir.

## 1. Resumo executivo

**Verificado:** Boring Notch usa um painel AppKit transparente que hospeda uma interface SwiftUI. O código implementa geometria do notch, estados compacto/expandido, hover, gestos, HUD e uma prateleira de arquivos. A janela e o conteúdo são separados: o delegate cria e posiciona a janela, enquanto ContentView renderiza e anima a ilha. [Janela](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/boringNotchApp.swift#L234-L280), [conteúdo](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/ContentView.swift).

**Limite decisivo:** o projeto também chama APIs privadas CGS/SkyLight para sua política de Spaces e tela bloqueada. A presença de opções públicas de NSPanel não demonstra que todo o comportamento do produto seja reproduzível apenas com APIs públicas. [CGSSpace](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/private/CGSSpace.swift), [SkyLightWindow](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/components/Notch/BoringNotchSkyLightWindow.swift).

**Para Sieghart:** a combinação AppKit/SwiftUI já existe. A maior utilidade do estudo é avaliar separação de responsabilidades, monitores, ciclo de vida, arraste e validação em hardware. Não há justificativa para copiar a interação de hover do concorrente: os testes locais de Sieghart dizem que hover destaca e clique expande.

## 2. Descoberta e identidade

| Campo | Resultado e grau de certeza |
| --- | --- |
| Nome / desenvolvedor | Boring Notch / TheBoredTeam, conforme [repositório oficial](https://github.com/TheBoredTeam/boring.notch) — **verificado** |
| Site | [theboring.name](https://theboring.name/) indicado pelo projeto — **verificado** |
| Instalação neste Mac | `/Applications/boringNotch.app`, instalado pelo usuário depois da auditoria inicial — **verificado no pacote local** |
| Bundle ID | `theboringteam.boringnotch` no [projeto Xcode fixado](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch.xcodeproj/project.pbxproj#L1219-L1258) e no Info.plist do pacote instalado — **verificado** |
| Versão | Projeto Xcode: MARKETING_VERSION 2.7.3 e deployment target macOS 14.0. Pacote instalado: versão 2.7.3, build 271 e mínimo macOS 14 — **verificado separadamente** |
| Distribuição | [README](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/README.md) oferece DMG, Homebrew e código fonte — **verificado** |
| Licença | [GPL-3.0](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/LICENSE) para o repositório; alguns arquivos atribuem outras origens/licenças. Ideias de arquitetura podem orientar código original; reutilização de código exige análise própria de licença |
| Stack | Swift, SwiftUI, AppKit, Combine, XPC e dependências do projeto Xcode — **verificado no código**. O build setting SWIFT_VERSION é 5.0; não atribuir a ele conformidade com Swift 6 estrito |

O [README](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/README.md) lista controles de mídia, calendário, lembretes, câmera, prateleira, HUD e dimensionamento. Isto verifica intenção e documentação de produto; somente os fluxos de janela, interação e arquivos abaixo foram rastreados no código deste lote.

## 3. Funcionalidade relevante e cobertura

| Pergunta da pesquisa | Estado | Evidência ou lacuna |
| --- | --- | --- |
| Como a janela é criada e posicionada? | Respondida no código | Delegate, NSPanel, NSHostingView e cálculo pelo frame da tela |
| Como mede o notch? | Respondida no código | Áreas auxiliares e safeAreaInsets; defaults para tela sem notch |
| Como abre, fecha e anima? | Parcial em execução | Estado SwiftUI, spring e tarefas de hover canceláveis no código; usuário confirmou abertura no hover e no clique, sem medição temporal independente |
| Como funciona em vários displays? | Parcial | Estruturas por UUID e recriação por mudanças de tela; ajustes da instalação lidos, mas troca real de monitor não testada |
| Como funciona em fullscreen/Spaces? | Parcial | Opções AppKit e chamadas CGS privadas; efeito real por versão do macOS desconhecido |
| Como recebe e entrega arquivos? | Parcial | NSItemProvider, bookmarks, persistência e drag source lidos; não houve teste com Finder/outros apps |
| Teclado e VoiceOver? | Não resolvida | Painel não se torna key/main; comportamento acessível não observado |
| CPU, GPU, memória, energia, latência? | Não resolvida | Processo observado aberto; medidores locais inconsistentes, sem medição controlada nem benchmark |
| Entitlements e permissões da versão instalada? | Parcial | Entitlements da assinatura local e declarações do Info.plist inspecionados; uso efetivo e diálogos de permissão não observados |

### Inspeção estática do aplicativo instalado

**Escopo e procedência:** a inspeção leu o aplicativo instalado em `/Applications/boringNotch.app` e o DMG em `/Users/antoniopaesdeandrade/Downloads/boringNotch.dmg` em 13/10/2026. Os fatos abaixo pertencem a esses artefatos locais, não provam que o executável foi compilado do commit de código fixado e não são testes de interface, desempenho ou comportamento em fullscreen.

| Artefato ou propriedade | Evidência local e conclusão |
| --- | --- |
| Identidade | Info.plist: bundle ID `theboringteam.boringnotch`, nome exibido `TheBoringNotch`, versão 2.7.3, build 271, mínimo macOS 14 e `LSUIElement=true` — **verificado** |
| Executável principal | Binário universal arm64/x86_64. SHA-256: `f136e7334c4c197c9d0fbdcbb0d95649771ed7427bcf361b28aa76af03ed3900` — **verificado para o arquivo local** |
| DMG baixado | SHA-256: `23786382548d33c59b309db558e513a92e3f95b63d611544dcddf5d196e46698` — **verificado para o arquivo local**; equivalência bit a bit entre a cópia instalada e o conteúdo do DMG não foi estabelecida |
| Assinatura do aplicativo principal | Metadados de assinatura indicam Team ID `JPWMG84CH8` e hardened runtime. A validação de confiança/notarização ficou **inconclusiva**: `codesign --verify` retornou `CSSMERR_TP_NOT_TRUSTED` também para o Calculator do macOS neste ambiente, e `spctl --assess` retornou erro interno. Estes resultados não permitem afirmar aprovação ou reprovação de confiança do pacote |
| Sandbox e capacidades | A assinatura do aplicativo principal declara sandbox, Apple Events, câmera, calendário, bookmarks, leitura e escrita em arquivos escolhidos pelo usuário e rede — **verificado nos entitlements locais**. O Info.plist inclui textos de uso para câmera, calendário, Apple Events e lembretes; isso não demonstra que o usuário concedeu essas permissões |
| Helper e dependências | O pacote contém helper XPC com sandbox desativado; SHA-256 do executável do helper: `7b65796f065bde704d4a6dc2d52dde6dde32fc6fa337985945a6b3d6e72097bb`. Também contém Sparkle 2.8.0, Lottie, MediaRemoteAdapter 0.1 e `MediaRemoteAdapterTestClient` — **presença verificada no pacote**, sem concluir que todo componente seja usado em execução |
| APIs privadas | Strings do executável contêm caminho para SkyLight, consistente com a pesquisa do fonte. `otool -L` não mostrou vínculo direto com SkyLight — **verificado**; strings isoladas não comprovam que uma chamada privada tenha ocorrido nesta instalação |

O pacote também declara um appcast Sparkle e `NSAllowsArbitraryLoads=true` no Info.plist. O primeiro indica infraestrutura de atualização; o segundo merece revisão específica se a política de rede for tomada como referência para Sieghart. Não se deve inferir destino ou conteúdo de tráfego sem observação de rede.

### Observação direta da versão aberta

Após o usuário abrir o aplicativo, a janela **Sobre o App TheBoringNotch** mostrou `boringNotch Versão 2.7.3 (271)`, corroborando os metadados do pacote. Na primeira abertura observada, apareceu uma pergunta para buscar atualizações automaticamente. Ela foi dispensada com Esc, sem selecionar a busca nem conceder permissões. O usuário então abriu a janela de Configurações; sua interface e árvore de acessibilidade foram observadas diretamente. A aba “Sobre” mostrou o nome de lançamento “Flying Rabbit” e busca automática de atualizações desativada. Esta inspeção leu valores atuais sem acionar interruptores, serviços ou atalhos. [Entrada de Configurações no código](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/boringNotchApp.swift#L31-L49), [janela de ajustes](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/components/Settings/SettingsWindowController.swift#L61-L102).

| Área da configuração instalada | Valor observado em 13/10/2026 | Alcance da evidência |
| --- | --- | --- |
| Geral | Tela preferida “Tela Retina Integrada”; ícone da barra de menus e troca automática de tela ligados; exibição em todos os displays desligada | Confirma valores da instalação, sem testar troca física de monitor |
| Notch | Altura acompanha notch real nesta tela e barra de menus em tela sem notch; abertura por hover ligada com atraso de 0,3 s; gestos e fechamento por gesto ligados | Confirma controles configurados, não a resposta temporal real |
| Aparência | Guias e ícone de ajustes no notch ligados; colorização/espectrograma de mídia ligados; espelho desligado | Confirma opções visíveis, não renderização ou uso de câmera |
| Mídia | Fonte “Now Playing”; atividade ao vivo ligada; prévia temporária desligada; editor de controles com reprodução, navegação, volume e outros itens | Confirma superfície de configuração, sem reproduzir mídia ou medir latência |
| Calendário | Exibição do calendário desligada; listas locais aparecem desabilitadas | Nomes de calendários e contas foram omitidos deste dossiê; não inferir permissão ativa apenas da listagem |
| HUDs | Substituição do HUD do sistema desligada e seus controles dependentes desabilitados | Não houve teste de volume ou brilho |
| Bateria | Indicador, percentual, ícones e notificações de energia ligados | Não houve mudança de carga para testar notificações |
| Shelf | Prateleira e detecção expandida de arraste ligadas; copiar itens no arraste e remover após arrastar desligados; Quick Share mostra AirDrop | Não houve drop nem compartilhamento; este último poderia transmitir um arquivo |
| Atalhos | Alternar notch: ⇧⌘I; alternar prévia de mídia: ⇧⌘H | Atalhos cadastrados; abertura não foi confirmada pela árvore da janela de Configurações |
| Avançado | Sombra e escala do raio ligados; extensão da área de hover, notch na tela bloqueada e ocultação em gravações desligados | A opção de ocultar captura existe, mas não implica proteção garantida pela API legada |

O usuário realizou uma checagem manual neste Mac e informou que o painel expande tanto após manter o cursor sobre o notch por cerca de um segundo quanto ao clicar nele. Isto é **relato do usuário**, não observação direta da ferramenta nem medição do atraso de 0,3 s. O Monitor de Atividade listou `TheBoringNotch` e `BoringNotchXPCHelper` em execução, além de processos de interface de compartilhamento associados. A vista de memória mostrou `0 bytes` para todos eles, dado implausível neste ambiente; a amostra de CPU também não serve de referência de consumo. **Não há benchmark confiável.** O painel flutuante continua sem captura ou acionamento confiável pela ferramenta, embora a janela comum de Configurações tenha sido capturada. Drop, fullscreen, VoiceOver e consumo continuam sem confirmação experimental.

## 4. Achados técnicos verificáveis

### Janela e ciclo de vida

O delegate instancia BoringNotchSkyLightWindow com máscaras borderless, nonactivatingPanel, utilityWindow e hudWindow, injeta ContentView por NSHostingView, ordena a janela à frente e a registra no espaço CGS do projeto. A classe configura fundo transparente, nível mainMenu + 3, políticas fullScreenAuxiliary/stationary/canJoinAllSpaces/ignoresCycle e impede tornar-se key ou main. A classe BoringNotchWindow.swift também existe, mas **não** é a classe construída nesse caminho do delegate. [Criação](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/boringNotchApp.swift#L234-L264), [configuração](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/components/Notch/BoringNotchSkyLightWindow.swift#L54-L113).

A entrada do aplicativo usa SwiftUI MenuBarExtra para ajustes, atualização, reinício e encerramento. O delegate não encerra o processo ao fechar a última janela e limpa detectores e janelas ao terminar. [Código de entrada e ciclo de vida](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/boringNotchApp.swift#L14-L88).

O app usa instâncias de janela e view model por UUID de monitor quando configurado para todos os displays; caso contrário, usa a tela preferida. Reage a mudanças de contagem, UUID e frame. Preferência antiga por nome é migrada para UUID. **Inferência:** isso reduz fragilidade quando o usuário renomeia um display, mas a navegação compartilhada pelo coordenador ainda pode sincronizar conteúdo entre janelas. [Delegate](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/boringNotchApp.swift), [coordenador](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/BoringViewCoordinator.swift).

### Geometria, animação e eventos

O tamanho expandido é fixado em 640 × 190 pontos, com 20 pontos extras para a janela. O compacto parte de 185 pontos, recalculando largura pelas áreas auxiliares e altura por safeAreaInsets.top ou preferências de barra de menus. O delegate centraliza a janela no frame do display e alinha seu topo. A API da Apple define áreas auxiliares como retângulos visíveis em coordenadas globais; ela não fornece uma forma detalhada da peça física da câmera. [Dimensionamento](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/sizing/matters.swift), [NSScreen](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea-gr2n).

ContentView usa um estado no MainActor, um Shape com raios animáveis, spring, hover, toque e pan. Ao sair do hover, cancela/reagenda uma Task e evita fechar enquanto compartilhamento ou popover estão ativos. O gesto pan combina DragGesture SwiftUI e monitor **local** de scroll do AppKit. Isso confirma a lógica estática, não fluidez percebida em execução. [ContentView](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/ContentView.swift), [NotchShape](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/components/Notch/NotchShape.swift), [PanGesture](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/extensions/PanGesture.swift).

### Prateleira de arquivos

Detecção expandida de arraste é opcional e usa monitores globais de mouse, pasteboard de drag e um retângulo no display para abrir a prateleira. O drop efetivo usa o mecanismo público de NSItemProvider: extrai URL de arquivo, URL web, texto ou dados, usa bookmark para arquivo e cria cópia temporária quando necessário. Os itens são salvos atomicamente como JSON em Application Support; arquivos temporários usam diretórios sob a pasta temporária. Arrastar para fora usa NSDraggingSource. [Detector](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/observers/DragDetector.swift), [drop](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/components/Shelf/Services/ShelfDropService.swift), [bookmark](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/components/Shelf/Models/Bookmark.swift), [persistência](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/components/Shelf/Services/ShelfPersistenceService.swift), [drag para fora](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/components/Shelf/Views/ShelfItemView.swift).

A [documentação Apple de monitor global](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29) destaca autorização de Accessibility para eventos de **teclado**. O detector estudado observa mouse; não inferir automaticamente a mesma exigência para esse fluxo sem execução. A API pública de [file promises](https://developer.apple.com/documentation/appkit/supporting-table-view-drag-and-drop-through-file-promises) precisa ser avaliada para origens que não entregam fileURL imediatamente.

## 5. Limite de APIs públicas e permissões

O arquivo CGSSpace.swift declara símbolos CGS privados com @_silgen_name e coloca janelas em um Space criado pelo aplicativo. O caminho de lock screen usa a biblioteca SkyLightWindow e carrega a framework privada SkyLight com dlopen/dlsym. A dependência MacroVisionKit usa CGSCopyManagedDisplaySpaces para detectar Spaces fullscreen. Esses mecanismos são **verificados no código**; não são recomendados para Sieghart. [CGS](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/private/CGSSpace.swift), [SkyLight](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/components/Notch/BoringNotchSkyLightWindow.swift), [MacroVisionKit](https://github.com/TheBoredTeam/MacroVisionKit/blob/da481a6be8d8b1bf7fcb218507a72428bbcae7b0/Sources/MacroVisionKit/FullScreenMonitor.swift).

AppKit documenta collectionBehavior, incluindo canJoinAllSpaces e fullScreenAuxiliary; a opção mais recente canJoinAllApplications tem elegibilidade específica. A documentação não promete que um nível de janela vencerá todas as superfícies do sistema. Essa diferença torna a presença real em fullscreen e lock screen uma pergunta experimental. [CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct), [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications).

O fonte alterna sharingType para none quando o usuário habilita ocultação da captura. A [documentação atual da Apple](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none) diz que none é legado e não deve ser usado para omitir conteúdo de captura. Portanto, não prometer essa proteção em Sieghart com esse método.

O [entitlement da aplicação no fonte](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/boringNotch/boringNotch.entitlements) declara sandbox, Apple Events, câmera, calendário, bookmarks, arquivos escolhidos pelo usuário e rede. O [helper XPC no fonte](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements) declara sandbox false e seu [código](https://github.com/TheBoredTeam/boring.notch/blob/64b545929cf31681e09b5c375859c1eceeb733eb/BoringNotchXPCHelper/BoringNotchXPCHelper.swift) consulta Accessibility e usa frameworks privados para brilho. A inspeção local confirmou as declarações correspondentes na assinatura do aplicativo instalado e a presença do helper; não verificou cada recurso em execução. Uma ilha básica de AppKit não exige, por si, Screen Recording ou Accessibility; pedir permissões somente quando um recurso concreto delas depender.

## 6. Comparação com o Sieghart existente

O checkout de Sieghart já define [NotchPanel e HoverZonePanel](../../Sieghart/Core/Services/Windowing/IslandPanels.swift), mede [geometria via NSScreen](../../Sieghart/Core/Helpers/NotchGeometry.swift), hospeda conteúdo SwiftUI, anima o contorno, recebe arquivos e controla a duração do hover. O [view model atual](../../Sieghart/Features/DynamicIsland/ViewModels/NotchWidgetViewModel.swift) concentra estado, serviços e política de janelas. O [teste de interação](../../Tests/InteractionChecks.swift) registra que hover destaca a ilha e não a expande; essa escolha deve ser preservada salvo decisão de produto.

Há duas oportunidades **inferidas do código local**, ainda sem reprodução em hardware: uma política explícita para escolher display além do primeiro notch disponível, e rever positionPanel, que retorna quando o tamanho do canvas não muda, mesmo se o monitor/posição mudou. Não classificar isso como falha confirmada sem teste. Os testes atuais usam views fora da tela e managesWindows: false; não verificam janelas reais, Spaces, VoiceOver ou consumo.

## 7. Arquitetura original proposta

Manter o comportamento de Sieghart e separar gradualmente três responsabilidades: (a) política de apresentação e precedência de eventos no MainActor; (b) controlador AppKit de janela, monitor, foco e posição; (c) conteúdo SwiftUI que recebe estado de renderização e devolve intenções. Não é necessário criar um sistema genérico de widgets para fazer isso. Um painel por display só deve ser adicionado se houver valor de usuário claro; a configuração atual de um display pode ser suficiente.

Para o caso de arquivos, preferir drop local público e bookmarks quando o usuário fornece arquivos; avaliar file promises e persistência/limpeza de temporários antes de ampliar a zona global de detecção. Para atalhos, foco e VoiceOver, desenhar o contrato de ativação e escape separadamente da animação. Para fullscreen, experimentar as opções públicas documentadas no conjunto de versões suportadas, sem atribuir a elas as garantias obtidas pelo caminho CGS do concorrente. Veja a [proposta de UI](../architecture/sieghart-ui-architecture.md).

## 8. Desafios e validação futura

Este dossiê **não** implementou nem testou funcionalidades de Sieghart. Quando houver implementação em worktree separado, entregar ao usuário estes passos de teste:

1. Em MacBook com notch e display externo sem notch: abrir/fechar, mudar monitor principal, desconectar/reconectar, alterar escala e conferir centro, hit region e retorno após sleep.
2. Em cada monitor: alternar Spaces, Stage Manager e fullscreen de outro app; conferir visibilidade e que cliques continuam chegando ao app correto.
3. Acionar clique, hover curto/longa permanência, saída do cursor durante voz, popover e drag; confirmar que o estado não fecha no meio da operação. Testar teclado, Tab, Esc e VoiceOver.
4. Soltar arquivo do Finder, URL, texto e promessa de arquivo de app compatível; arrastar item para fora, reabrir Sieghart e excluir o item. Conferir que arquivos temporários e bookmarks são tratados corretamente.
5. Medir CPU, memória e energia em repouso e durante animação em hardware real; registrar versão do macOS e taxa de atualização. Comparação numérica com Boring Notch exige execução equivalente, ainda não feita.

## 9. Recomendações

| Decisão | Motivo |
| --- | --- |
| **Adotar como princípio:** AppKit governa janela, SwiftUI governa conteúdo | Separação sustentada pelo código estudado e compatível com Sieghart existente |
| **Adaptar:** geometria, seleção de monitor, tarefas canceláveis e política de estado | Há uma base local; evoluir após testes, sem trocar o modelo de interação por imitação |
| **Evitar:** CGS/SkyLight, caminho privado de brilho e promessa de ocultação por sharingType.none | Compatibilidade e privacidade não são garantidas por APIs públicas estudadas |
| **Adiar:** suporte a todos os displays e efeitos avançados de fullscreen/lock screen | Valor, custo de manutenção e comportamento real ainda precisam de prova |

## 10. Questões abertas

- Qual o comportamento do pacote instalado em fullscreen, displays externos, VoiceOver e macOS suportados? Exige observação controlada no hardware; a inspeção estática do pacote não responde.
- Qual o consumo em repouso/animando de Boring Notch comparado a Sieghart no mesmo hardware? Exige execução e metodologia idêntica.
- O fluxo de arraste de Fotos/Safari ou aplicativos com file promises funciona em todos os casos? Precisa teste.
- Quais diferenças de código e comportamento há entre o commit analisado e o executável instalado? A inspeção de metadados e arquivos embutidos não estabelece equivalência de código.
- Qual política de display e fullscreen é melhor para a identidade de Sieghart? Requer decisão de produto e teste de usabilidade, não pode ser inferida do concorrente.

**Estado do tópico:** arquitetura estática de UI respondida; identidade, versão, configurações expostas e presença dos processos principal/helper foram confirmadas na instalação aberta. O usuário relatou expansão por hover e clique; demais comportamentos do painel, desempenho e acessibilidade permanecem sem medição direta. Após a pausa deste tópico, a fila atualizada pelo adendo V3 começa por OpenJarvis e pelos dois projetos Open Finance, cada um em sua própria etapa; Raycast permanece na fila.
