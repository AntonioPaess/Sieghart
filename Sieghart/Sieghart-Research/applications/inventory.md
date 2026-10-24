# Inventário inicial de aplicações e ambiente

Auditoria local de 13 de outubro de 2026. A busca inicial foi limitada a `/Applications` e `~/Applications`, profundidade 2; a ausência nessa busca não prova que o aplicativo não exista em outra pasta. Depois dessa busca, o usuário instalou Boring Notch em `/Applications/boringNotch.app`, informou que o abriu e mais tarde o removeu. Seu pacote foi inspecionado estaticamente enquanto estava disponível; esta tabela não atesta comportamento em execução.

## Ferramentas

`swift`, `xcodebuild`, `otool`, `codesign`, `lldb` e `file` estão no PATH. `rea`, `ghidraRun` e `greadelf` não estão. Nenhum servidor REA estava anunciado para esta sessão; portanto, não foi feita análise REA dos alvos. Um [estudo local anterior](../../Design/Research/rea-apps-2026-10-13.md) registra uso de REA em outros aplicativos, mas não atesta sua disponibilidade nesta sessão.

## Prioridade e material acessível

| Ordem | Aplicação | Instalação local nesta busca | Fonte pública verificada | Valor inicial para Sieghart |
| --- | --- | --- | --- | --- |
| 1 | Boring Notch | Instalado para análise: 2.7.3 (271); removido depois pelo usuário | [Código e licença GPL-3.0](https://github.com/TheBoredTeam/boring.notch) | Janela, notch, hover, gesto, múltiplos monitores |
| 2 | OpenJarvis | Não instalado nem executado; análise estática concluída | [Código oficial no commit analisado](https://github.com/open-jarvis/OpenJarvis/commit/108d257188cbad85f2e50209d9a61669ea4dec33); [dossiê](openjarvis.md) | Contratos de agentes, ferramentas, persistência e observabilidade; referência arquitetural proposta |
| 3 | Open Finance: DeseretSaint | Não instalado nem executado; análise estática concluída | [Código MIT no commit analisado](https://github.com/DeseretSaint/open-finance/commit/94d4a7e8ea875d346f5fd3d231ae1a022ddb6a26); [dossiê](open-finance-deseretsaint.md) | Modelo financeiro, MCP e permissões; lacunas de autorização e moeda identificadas |
| 4 | Open Finance: openfinance-app | Não instalado nem executado; análise estática concluída | [Código ELv2 no commit analisado](https://github.com/openfinance-app/open-finance/commit/c54668f6f9c36e0a4f9b6504d972661e4718a271); [dossiê](open-finance-openfinance-app.md) | Importação OFX/QIF/CSV, cálculo de câmbio, fatos tipados para IA; sem MCP próprio identificado; cifragem opcional/desligada por padrão |
| 5 | Raycast | Não localizada na busca inicial nem na repetição em 13/10/2026; usuário optou por pesquisa pública | [API e extensão](https://developers.raycast.com/); [modelo de segurança](https://developers.raycast.com/information/security); [dossiê](raycast.md) | Contratos de comandos/IA, autorização e limitações de isolamento; núcleo fechado não foi inspecionado |
| 6 | VoiceInk | Instalado inicialmente app **iOS no Mac** 1.33/133; não equivale ao produto macOS, cuja instalação foi solicitada | [Repositório oficial](https://github.com/Beingpax/VoiceInk) e [dossiê](voiceink.md) | Captura, streaming/batch, rotas local/remota e entrega do ditado |
| 6A | HeyClicky | App macOS 1.0.53/64 instalado; REA estático anterior, tour/Home e capturas observados; ditado, interrupção e troca de microfone relatados pelo usuário | [Site](https://www.heyclicky.com/), [release](https://github.com/farzaa/clicky-releases/releases/tag/v1.0.53) e [dossiê completo](heyclicky.md) | Notch/Home, voz, contexto de tela, Clickys, arquivos, integrações, rotinas e privacidade; viabilidade Apple Foundation Models no dossiê |
| 7 | Dayflow | Não localizada na busca inicial | A confirmar por fonte oficial | Captura consentida e linha do tempo |
| 8 | Screenpipe | Não localizada na busca inicial | [Repositório público](https://github.com/screenpipe/screenpipe) | Memória multimodal e busca; verificar licença por componente |
| 9 | Alcove | Não localizada na busca inicial | A confirmar | Polimento e interação do notch |
| 10 | Droppy | Não localizada na busca inicial | A confirmar | Prateleira de arquivos e drag and drop |
| 11 | BetterTouchTool | Não localizada na busca inicial | A confirmar | Automação e composição de ações |

**Etapa HeyClicky concluída como dossiê de produto:** VoiceInk e HeyClicky são [comparados na voz](../comparisons/voice-comparison.md) e alimentam a [arquitetura de voz](../architecture/sieghart-voice-architecture.md). Após identificar que o VoiceInk instalado era iOS, o usuário pediu foco no HeyClicky; o teste macOS do VoiceInk ficou pausado. O [dossiê HeyClicky](heyclicky.md) cobre o app inteiro e separa pacote/REA, observação, relato e declarações do fornecedor; seu comportamento interno fechado e as métricas não medidas permanecem lacunas. A [comparação dos dois Open Finance](open-finance-comparison.md), a [viabilidade brasileira](../integrations/brazilian-open-finance.md), o [dossiê Raycast](raycast.md) e as [comparações de automação](../comparisons/automation-comparison.md) e [IA](../comparisons/ai-comparison.md) também estão documentados.
