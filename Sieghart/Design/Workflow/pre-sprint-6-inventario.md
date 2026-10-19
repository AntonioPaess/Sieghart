# Pré-sprint 6 — Inventário dos testes existentes

Data: 17 de outubro de 2026. Base inspecionada: `e218a72`, branch `sprint-5`, com as alterações de documentação já presentes preservadas.

**Estado original em 17 de outubro: inventário por leitura.** Este documento detalha o [plano pré-sprint 6](pre-sprint-6-swift-testing.md). Os nomes abaixo registram a proposta daquela data. Em 18 de outubro, os 132 IDs automáticos e A01 foram migrados e executados; destinos e resultados reais estão na [matriz por contrato](../Validation/pre-sprint-6/contract-results.json) e no [registro de execução](pre-sprint-6-execucao.md).

## Como usar esta matriz

Cada ID identifica um contrato legado rastreável. Uma linha pode exigir vários casos independentes ou um teste parametrizado; não representa uma contagem de casos descobertos. Na execução futura, registrar para cada ID: arquivo/função Swift Testing, argumentos relevantes, resultado e evidência. Se um contrato for dividido ou consolidado com outro, manter os IDs de origem. Exclusões exigem justificativa e revisão.

Os intervalos de linhas referem-se aos arquivos atuais e servem de localização, não de seleção automática. Funções auxiliares que preparam fixtures também precisam acompanhar o contrato. Toda a matriz está **inventariada e pendente de implementação/revisão**, sem afirmação de aprovação ou cobertura medida.

| Perfil proposto | Fronteira | Exemplos |
| --- | --- | --- |
| U — lógica | Valores e funções, sem estado externo mutável | Parser, aritmética, geometria, amostras de pose |
| I — integração isolada | Objetos reais com dependências em memória, relógio e agendamento controlados | ViewModels, cancelamento, persistência em memória |
| L — integração local | Sistema de arquivos temporário, subprocessos próprios ou frameworks nativos offline | SQLite, stdio, watcher, OCR/QR |
| V — contrato visual nativo | AppKit/SceneKit/Core Animation fora da tela; pode precisar de sessão gráfica | Field editor, hierarquia de nós, pixels e ciclo de layers |

U e I compõem o plano rápido somente após comprovar isolamento. L e V continuam obrigatórios no plano completo. V não equivale a aceite visual humano; L não equivale a serviço online conectado. Um cenário misto deve ser dividido antes de receber os perfis definitivos.

## Ponto de partida conferido

- [run-checks.sh](../../Tests/run-checks.sh) declara **18 chamadas `check`**, cada uma compilando e executando um programa, com filtro por expressão regular em `SIEGHART_CHECK_FILTER`. Um erro interrompe a sequência por `set -e`.
- Existem **36 arquivos Swift em `Tests/`**: 24 arquivos `*Checks.swift`, 11 `*Preview.swift` e `PlatformFixtures.swift`.
- Dos 24 arquivos de checks, 18 contêm os pontos de entrada do runner; quatro são auxiliares chamados por `agent-room`/`local-chat`; dois ficam fora do runner: `NewCodexChatChecks.swift` e `CompanionPerformanceChecks.swift`.
- As verificações usam `precondition`, `preconditionFailure`, `fatalError` e helpers próprios `expect`/`check`. Há loops que executam muitas combinações. As mensagens `PASS` não são resultados individuais do framework.
- Há **126 fontes Swift de produção**, das quais duas ficam em `App/` e 124 fora de `App/`. A fase de fontes atual registra as 126. O runner maior já exclui `App/`, mas isso não torna toda construção de objeto automaticamente isolada.

## 1. `timer`

Origem: [PomodoroChecks.swift](../../Tests/PomodoroChecks.swift). Produção: `TimerModels`, `AssistantViewModel`, `SensorEngine`, `SensorViewModel`. Os sensores são compilados; o cenário atual não inicia nem exercita hardware de impacto.

Dependências: `UserDefaults` de suíte exclusiva, relógio mutável injetado, `schedulesTimer: false`. Destinos: `PomodoroTests` e `UtilityClockTests` em `MacContractsTests.Timers`.

| ID | Linhas | Contrato a preservar | Perfil |
| --- | --- | --- | --- |
| G01.01 | 20–29 | Foco de 50 minutos: pausar após 75 segundos, restaurar 2.925 segundos e configuração, retomar e concluir uma única vez | I |
| G01.02 | 30–39 | Iniciar pausa curta, pausar/restaurar/retomar; fim da pausa não aumenta sessões de foco | I |
| G01.03 | 40–47 | Conclusão pelo widget, seleção de pausa longa por rodada e reinício do contador do ciclo | I |
| G01.04 | 49–72 | Pausas automáticas curta/longa; expiração durante reabertura de foco ou pausa e ausência de contagem duplicada | I |
| G01.05 | 73–78 | Configuração inválida volta ao padrão; trocar a aba de ferramenta não inicia sessão | I |
| G01.06 | 79–89 | Countdown: fração e formatação, pausa sem consumir tempo, reabertura, conclusão e reset | I |
| G01.07 | 91–106 | Stopwatch: precisão, pausa/retomada, restauração, formato com horas e reset; ferramentas não alteram rodadas de foco; countdown expirado reabre em zero | I |

## 2. `callbacks`

Origem: [VoiceCallbackChecks.swift](../../Tests/VoiceCallbackChecks.swift). Produção: `VoiceCapture` e seus tipos de política/PCM/bridge. Não solicita permissão nem captura microfone.

Dependências: callbacks sintéticos em fila global, timestamps explícitos e buffers PCM gerados. Destinos: `LogicTests.VoiceSessionTests`, `LogicTests.SpeechPCMTests` e `MacContractsTests.SpeechAuthorizationTests`.

| ID | Linhas | Contrato a preservar | Perfil |
| --- | --- | --- | --- |
| G02.01 | 10–18 | Callback de autorização fora da main thread retorna authorized/denied/restricted corretamente | I |
| G02.02 | 22–32 | Ruído residual após frase encerra áudio; resultado final autoritativo encerra mesmo sem silêncio | U |
| G02.03 | 34–52 | Fala de 40 segundos e pausa final; não despachar parcial; incorporar palavras finais e consumir comando uma vez | U |
| G02.04 | 55–76 | Pausa breve não termina fala; cancelar ignora resultado tardio; nova sessão limpa transcrição; input perdido, ausência de fala, limite e timeout final | U |
| G02.05 | 78–90 | Resultado final curto e drain fecham request/task, em ordem, uma vez | U |
| G02.06 | 92–116 | Voz baixa continua; busca parcial só é usada após estabilizar; cancelamento a invalida; recuperação de input limitada e sem retry após fala | U |
| G02.07 | 118–144 | PCM Float32 a 16/24/48 kHz, planar/interleaved, seleção de canal, buffer vazio, Int16 e Int32 preservam decibéis/duração | U |

## 3. `voice-integration`

Origem: [VoiceIntegrationChecks.swift](../../Tests/VoiceIntegrationChecks.swift) e [PlatformFixtures.swift](../../Tests/PlatformFixtures.swift). Produção: todas as fontes fora de `App/`; foco em `ActivationController`, `NotchWidgetViewModel`, parser e sessão de voz.

Dependências: captura, abertura de app e busca substituídas, calendário/notificador silenciosos, janelas e atalhos desligados. Há sleeps reais de 10–730 ms e polling de produção: substituir espera por sincronização/relógio controlado onde o tempo não é o objeto do contrato. Destino: `MacContractsTests.VoiceFlowTests`.

| ID | Linhas | Contrato a preservar | Perfil |
| --- | --- | --- | --- |
| G03.01 | 58–59, 70–100 | Preparação/escuta/finalização mantêm ilha visível; não executar parcial; palavra final e callback duplicado geram uma busca com URL correta; saída do ponteiro volta a recolher | I |
| G03.02 | 102–122 | Final autoritativo com áudio alto; final emitido dentro de `finish()`; ação e confirmação não duplicam nem são sobrescritas | I |
| G03.03 | 124–147 | Cancelar finalização e substituir sessão ignora callback antigo; ferramenta sem final não executa após timeout | I |
| G03.04 | 149–175 | Input alterado, permissão negada e autorização pendente cancelada não iniciam captura nem executam resultado atrasado | I |
| G03.05 | 176–202 | Cinco reproduções de busca em português; fase listening/thinking; recuperação de busca estabilizada quando recognizer termina sem final | I |
| G03.06 | 204–233 | Cinco comandos foco/pomodoro com duração; aguardar texto final, executar uma vez, não buscar, não contar conclusão antecipada | I |
| G03.07 | 235–270 | Sinal visual mínimo de processamento sem atrasar ação; idle sem loading; cancelar/substituir não deixa confirmação velha interromper a nova | I |

## 4. `interactions`

Origem: [InteractionChecks.swift](../../Tests/InteractionChecks.swift), `PlatformFixtures`. Produção: todas fora de `App/`. Este grupo deverá se dividir em suítes de parser, atalhos, preferências, movimento e ilha.

Dependências: defaults e relógio próprios, `managesWindows: false`, `registersShortcuts: false`, launchers substituídos. Usa `NotificationCenter.default`, RunLoop e sleeps; esses pontos não podem vazar entre casos assíncronos.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G04.01 | 12–46 | EN/PT, repetição de palavra, números por extenso e hífen, negação, conflitos, limites; produto 6 verbos × 3 alvos × 12 durações | `LogicTests.FocusVoiceParserTests` / U |
| G04.02 | 47–100 | Busca explícita/implícita, tópicos e pontuação; negação/entrada longa/quebra de linha; encoding literal; apps, rejeição de comandos compostos e limites AI | `LogicTests.VoiceIntentTests` / U |
| G04.03 | 102–112 | Atalho só de modificadores, liberação única, supressão por tecla comum e flags extras | `LogicTests.ModifierShortcutTests` / U |
| G04.04 | 114–129, 224–229, 291–298 | Tema/vidros independentes; avatar legado migra para Sig; tamanhos de widget persistem e ordenam largura | `MacContractsTests.PreferenceTests` / I |
| G04.05 | 130–136, 157–159, 365–367 | Cobertura de monitor com origem negativa, nível de janela, notch compacto e tamanho intermediário do contorno interrompido | `LogicTests.IslandGeometryTests` / U |
| G04.06 | 141–156, 163–193 | Todos os avatares/moods/tamanhos; sono/piscar, Reduce Motion, poses finitas; voz e transições contínuas, loading/êxito distintos, mesma fase não reinicia | `LogicTests.CompanionMotionTests` / U |
| G04.07 | 195–209 | Prioridade de voz sobre tarefa/loading e loading escalonado da Ada sem curvas | `LogicTests.CompanionActivityTests` / U; geometria SwiftUI sem renderização |
| G04.08 | 211–223, 368–371 | Sequência happy/annoyed/asleep/waking/idle, janela temporal de toques, erro/sucesso de ferramenta e reset | `MacContractsTests.CompanionReactionTests` / I |
| G04.09 | 235–249 | Primeiro clique aceito e hit regions; clique abre/fecha sem reabrir | `MacContractsTests.IslandHitTargetTests` / V |
| G04.10 | 251–289, 299–307 | Tarefa AI ou timer determina conteúdo compacto/expandido; hover não expande; expiração do countdown anuncia uma vez; cruzar regiões de hover não fecha prematuramente | `MacContractsTests.IslandPresentationTests` / I |
| G04.11 | 230–234, 309–364 | Abandono/fechamento de gravador e mudança de Space liberam atalhos; recuperação, persistência e colisões entre voz/áudio | `MacContractsTests.ShortcutLifecycleTests` / I |
| G04.12 | 373–424 | Busca/app/foco/pausa/resume por dispatcher; confirmação e transcrição; comando inválido; cancelar/ocultar; ferramentas/áudio/clipboard/avatares/AI limits | `MacContractsTests.ActivationDispatchTests` / I |
| G04.13 | 426–473 | Foco ativo, gesto, setup, celebração antes de pausa automática, recolhimento de páginas, conclusão sem replay ao relançar | `MacContractsTests.IslandSessionTests` / I |
| G04.14 | 474–517 | Atalhos só de modificadores; monitor/Carbon sem duplicação nem inversão temporal; tolerância de reveal e cruzamento de hover; match exato de flags | `LogicTests.ShortcutDeliveryTests` (regra) e `MacContractsTests.IslandRevealTests` (estado) / U, I |
| G04.15 | 137–140 | Imagem de menu dos seis avatares existe em 22×22 pontos e não é template; classificar separadamente da amostragem pura de movimento | `MacContractsTests.CompanionMenuImageTests` / V |

## 5. `companions`

Origem: [CompanionTeamChecks.swift](../../Tests/CompanionTeamChecks.swift). Produção: conjunto `ui_shared` do runner, com componentes/feature CompanionTeam, preferências e eventos.

Dependências: defaults, AppKit, SceneKit e Core Animation. Parte verifica números; parte constrói nós, retratos e views. O grupo inteiro não deve receber o rótulo de teste puro. Preservar a migração **Team → Companion** corrigida em `e218a72`.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G05.01 | 7–25 | Seis identidades e cinco especialistas, trilho legado para Companion, Sig principal; inglês padrão, português persistido; equipe antes da apresentação do orquestrador | `LogicTests.CompanionIdentityTests` / U e `MacContractsTests.CompanionPreferenceTests` / I |
| G05.02 | 26–34 | Catálogo de 49 animações, resolução por voz/mood, loading, duração, continuidade e pose final | `LogicTests.CompanionAnimationTests` / U |
| G05.03 | 35–56 | Intake amostrado, abertura dentro da silhueta, arquivo atrás da abertura, sumiço final e hover aberto sem arquivo falso; halo abaixo do corpo | `LogicTests.FileIntakePoseTests` / U e `MacContractsTests.CompanionSceneTests` / V |
| G05.04 | 57–102 | Loading imóvel com progresso sem reconstruir mesh; cancelamento contínuo; sono vivo/Reduce Motion; gaze sem cursor falso; olhos reutilizam geometria | `MacContractsTests.CompanionSceneTests` / V |
| G05.05 | 103–112 | Seis personagens × 49 animações, tempos de início/intermediários/fim, poses finitas e escala coerente para Ada/Gantt | `MacContractsTests.CompanionRigTests` / V |
| G05.06 | 114–144 | Ordem de apresentação, layout, queda/alô/luz antes dos especialistas, círculo aprovado e transição quente/azul do halo sem borda de profundidade | `LogicTests.TeamFormationTests` / U e `MacContractsTests.TeamSceneTests` / V |
| G05.07 | 145–188 | Dock estabilizado não atualiza poses; seis saudações distintas; fila avança um slot, Sig visível, um herói e cinco slots únicos; fim/Reduce Motion; espera seletiva | `LogicTests.TeamFormationTests` / U e `MacContractsTests.TeamSceneTests` / V |
| G05.08 | 189–212 | Acessório estático em um mesh; fonte Retina 1024, raster 76 px para 38 pt e cache; retrato/cena desconectados sem animação contínua e sem capturar input | `MacContractsTests.CompanionRasterLifecycleTests` / V |

## 6. `usage`

Origem: [CodexUsageChecks.swift](../../Tests/CodexUsageChecks.swift). Produção: `CodexUsage`, `CodexUsageViewModel`.

Dependências: resposta JSON local, script stdio temporário, timeout, defaults e load substituído. A opção `--live` é um caminho externo explícito, fora dos planos automáticos.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G06.01 | 6–23 | Preferência pelo bucket Codex correto, fallback legado, títulos, restantes, reset Unix, ausente/expirado e clamp | `LogicTests.CodexQuotaTests` / U |
| G06.02 | 25–44 | Handshake initialize/initialized/rateLimits com executável próprio | `MacContractsTests.CodexUsageProcessTests` / L |
| G06.03 | 46–49 | Processo que não responde termina dentro do limite; cleanup do processo | `MacContractsTests.CodexUsageProcessTests` / L |
| G06.04 | 51–62 | Opt-in, leitura, desconexão limpa estado e erro não expõe detalhe sensível | `MacContractsTests.CodexQuotaModelTests` / I |
| G06.05 | 63–68 | Desligar durante refresh impede aplicar resposta atrasada; trocar sleep por barreira da fixture | `MacContractsTests.CodexQuotaModelTests` / I |
| G06.X | 71–74 | Leitura `--live` da instalação/conta real permanece procedimento manual separado | Aceite externo; excluído com motivo explícito |

## 7. `spending`

Origem: [TokenSpendingChecks.swift](../../Tests/TokenSpendingChecks.swift). Produção: conjunto `ai_sources` do runner.

Dependências: logs Codex/Claude temporários, defaults, preços Decimal, data. **Isolamento a completar:** `AIUsageViewModel` recebe `read`, mas o `readClaude` padrão ainda pode ler histórico Claude real ao habilitar Claude e atualizar. Injetar ambos na futura migração.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G07.01 | 5–23 | Contadores cumulativos e clones Codex sem duplicar cache/reasoning; soma entre sessões | `MacContractsTests.LocalTokenReaderTests` / L |
| G07.02 | 24–32 | Claude usa última versão da mensagem, ignora usuário, soma cache creation/read corretamente; pasta ausente retorna nil | `MacContractsTests.LocalTokenReaderTests` / L |
| G07.03 | 31–38 | Estimativa Decimal exata e dados/preços ausentes | `LogicTests.TokenEstimateTests` / U |
| G07.04 | 39–49 | Opt-in por provedor e desligamento limpa tokens; mocks de contador e quota sem ler conta real | `MacContractsTests.SpendingModelTests` / I |
| G07.05 | 50–63 | Ledger separa USD/BRL/provedor/mês, rejeita valor negativo, persiste preço/câmbio/cobranças e remove por identidade | `MacContractsTests.ChargeLedgerTests` / I |
| G07.06 | 65–71 | Relatório Claude datado, importação/persistência, percentual inválido rejeitado e limpeza | `MacContractsTests.ClaudeReportTests` / I |

## 8. `activity`

Origem: [AIActivityChecks.swift](../../Tests/AIActivityChecks.swift). Produção: `ai_sources` + `ui_shared`.

Dependências: logs temporários e relógio. `AIAnalyticsReader(home: root)` ainda pode herdar `CODEX_HOME`: passar também `codexHome` da fixture. A suíte `activity-motion-*` precisa remoção explícita ao fim.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G08.01 | 5–37 | Deduplicar contador/clone/reasoning e reter metadados mínimos; start/complete, opt-out e atividade antiga sem trabalho fantasma | `MacContractsTests.AIActivityReaderTests` / L |
| G08.02 | 38–43 | Só trabalho atual aciona processing; expiração e conclusão removem sinal; idle não inventa leitura | `MacContractsTests.AIActivityStateTests` / I |
| G08.03 | 44–66 | Recuperar start/terminal/model/tier antes do tail de 2 MiB; metadado sem lifecycle não inventa trabalho; contexto futuro não relabela passado | `MacContractsTests.AIActivityReaderTests` / L |
| G08.04 | 67–78 | Response records prevalecem sobre quota counters; deduplicação por response ID e tier alterado preservados | `MacContractsTests.AIActivityReaderTests` / L |
| G08.05 | 79–92 | Scan inicial conserva uso antes do tail; polling acrescenta sem apagar histórico anterior | `MacContractsTests.AIActivityReaderTests` / L |
| G08.06 | 93–100 | Heatmap/streak preservam dados fornecidos; Claude conserva cache creation e estado terminal | `LogicTests.AccountActivityDecodeTests` / U e `MacContractsTests.AIActivityReaderTests` / L |
| G08.07 | 101–107 | Primeiro uso com seis personagens; onboarding concluído e avatar antigo persistem como Sig | `MacContractsTests.OnboardingPreferenceTests` / I |

## 9. `pricing`

Origem: [PricingChecks.swift](../../Tests/PricingChecks.swift). Produção: `ai_sources`.

Dependências: JSON versionado de preços, markdown sintético e defaults. O caminho relativo ao diretório de trabalho deve virar URL explícita do recurso. Os números verificam o **snapshot versionado**, sem afirmar que são preços atuais da internet.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G09.01 | 5–12 | Catálogo decodifica; modelo exato/snapshot datado/tier/router prefix; aliases não confirmados ficam sem preço | `LogicTests.PriceCatalogTests` / U; recurso explícito |
| G09.02 | 13–30 | Parser distingue standard/batch e duração de cache-write Claude; formato inesperado não fabrica tarifa | `LogicTests.PriceCatalogParserTests` / U |
| G09.03 | 31–32 | Cotação datada mantém taxa Decimal, base e moeda | `LogicTests.ExchangeQuoteTests` / U |
| G09.04 | 35–46 | Ícones só de provedores usados; cache descontado; contexto longo só por request; desconhecido gera lower bound com tokens sem preço | `MacContractsTests.UsagePricingTests` / I |
| G09.05 | 47–53 | Override explícito, retorno ao automático, persistência da preferência e desconexão removem provedor | `MacContractsTests.UsagePricingTests` / I |

## 10. `audio`

Origem: [AudioChecks.swift](../../Tests/AudioChecks.swift). Produção: `AudioEngine`, `AudioViewModel`.

Dependências: `MockAudio`, árvores de PID/responsibility, buffers próprios e defaults. Não conectar process taps, dispositivo ou captura real. Destinos em `LogicTests.Audio*` e `MacContractsTests.Audio*`.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G10.01 | 51–71 | Ancestral/responsible PID de helpers WebKit, ciclo/daemon/ownership desconhecido, fallback; símbolos AirPods/headphones | `AudioIdentityTests` / U |
| G10.02 | 72–91 | Sem captura antes do enable; app sem áudio não roteia; clamp de gain/volumes, mute, falha preserva ganho e troca de dispositivo libera/reaplica rota | `AudioRoutingTests` / I |
| G10.03 | 92–105 | Alteração de output/sample rate e desaparecimento de app encerram rotas; cap de cinco apps reais, disable e favoritos/reordenação | `AudioRoutingTests` / I |
| G10.04 | 106–122 | Prioridade só com opt-in, escolha manual até mudança de topologia, reconexão por UID, ciclo/mute, shutdown e restauração sem reautorizar captura | `AudioDevicePreferenceTests` / I |
| G10.05 | 124–136 | Permissão negada/retry e resposta de autorização cancelada não habilitam mistura | `AudioPermissionStateTests` / I |
| G10.06 | 138–186 | Finder excluído, helper atual vence callback velho; hide/restore persistido libera só rota própria e mantém cap; app fechado/oculto nunca recebe tap por callback antigo | `AudioApplicationTests` / I |
| G10.07 | 188–207 | PCM interleaved/planar, limites de frame, limpeza/mute, offset ignora microfone, estéreo→mono e mono→estéreo | `AudioPCMTests` / U |

## 11. `imports`

Origem: [UsageImportChecks.swift](../../Tests/UsageImportChecks.swift). Produção: `ai_sources`.

Dependências: JSON/CSV, defaults, árvore de logs temporária, data/calendário. Fixar data/fuso na fixture e informar `home`/`codexHome` explicitamente no leitor.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G11.01 | 6–16 | Claude history v1/v2, organização/leitura mais recente sem mistura, scoped quotas; stale/futuro, boolean/percentual e versão inválidos | `LogicTests.ClaudeHistoryDecodeTests` / U |
| G11.02 | 18–25 | Relatório automático só com opt-in, origem local identificada e limpeza ao desligar | `MacContractsTests.ClaudeHistoryModelTests` / I |
| G11.03 | 27–34 | CSV BOM/CRLF/aspas/vírgula, precisão monetária e data local; importação idempotente e roundtrip JSON | `LogicTests.ChargeFileTests` / U e `MacContractsTests.ChargeImportTests` / I |
| G11.04 | 35–46 | Referência com valor conflitante e lote inválido rejeitados atomicamente; CSV malformado, restauração de origem e export de cobrança manual deduplicado | `LogicTests.ChargeFileTests` / U e `MacContractsTests.ChargeImportTests` / I |
| G11.05 | 48–68 | Scan recente limitado a 80, full history com 84 arquivos/arquivos arquivados, total 247 sem clones duplicados, polling retém amplitude e opt-out retorna vazio | `MacContractsTests.ExpandedHistoryTests` / L |

## 12. `clipboard`

Origem: [ClipboardChecks.swift](../../Tests/ClipboardChecks.swift). Produção: `ClipboardHistory`, `ClipboardViewModel`, `PlainTextPaste`, `FileItems`, `ui_shared`.

Dependências: board/storage falsos, relógio fixo, monitor desligado e disco temporário. O grupo inclui preferências e entrada dos companions, que receberão destinos próprios.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G12.01 | 29–49 | Desabilitado não lê; enable estabelece baseline; captura seguinte, deduplicação preserva ID/pin, busca case-insensitive | `MacContractsTests.ClipboardModelTests` / I |
| G12.02 | 50–61 | Tipos text/image/files, filtros, fonte excluída, media off, URL não local/tamanho excessivo/imagem inválida | `LogicTests.ClipboardPayloadTests` / U e `MacContractsTests.ClipboardModelTests` / I |
| G12.03 | 62–83 | Pausa sem leitura; resposta atrasada após disable descartada; cópia própria não recapturada; fallback só copia; erro de escrita | `MacContractsTests.ClipboardConcurrencyTests` / I |
| G12.04 | 84–107 | Persistir/pin/remover/limpar; limite total/pins/retenção e 5/10; cleanup por evento correto e reabertura; sem retenção opcional | `MacContractsTests.ClipboardRetentionTests` / I |
| G12.05 | 108–131 | Gaze bilateral; seis rails com swaps e none repetido, presets; dez tools, substituição/movimento/reset/persistência e recuperação de duplicadas | `LogicTests.CompanionGazeTests` / U e `MacContractsTests.IslandToolPreferenceTests` / I |
| G12.06 | 132–141 | Disco ignora revisão antiga, mantém itens e aplica arquivo 0600/diretório 0700 mesmo quando diretório já existe | `MacContractsTests.ClipboardStorageTests` / L |
| G12.07 | 142–151 | Entrada contínua a 240 amostras/s, limites de pose, invisível no início, repouso final e Reduce Motion imediato | `LogicTests.CompanionEntranceTests` / U |

## 13. `middle-click`

Origem: [MiddleClickChecks.swift](../../Tests/MiddleClickChecks.swift). Produção: `MiddleClickController` e tipos de contatos/tap.

Dependências: contatos e timestamps sintéticos; backend/trust/requestAccess/emit falsos, observação do sistema desligada.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G13.01 | 12–20 | Três dedos, debounce, rejeitar dois/quatro dedos, toque longo e deslocamento; entrada/saída escalonada | `LogicTests.ThreeFingerTapTests` / U |
| G13.02 | 21–27 | Opt-in desligado não inicia; sem confiança só informa; pedido explícito não emite evento; confiança permite backend | `MacContractsTests.MiddleClickStateTests` / I |
| G13.03 | 28–31 | Callback emite uma vez, callback antigo após disable não emite, backend indisponível não aparece ready | `MacContractsTests.MiddleClickStateTests` / I |

## 14. `utilities`

Origem: [UtilityChecks.swift](../../Tests/UtilityChecks.swift). Produção: sampler/monitor, awake/KeepAwake e display/DisplayPower.

Dependências: `SampleMonitor`, `SampleAwake`, `SampleDisplay`, defaults e relógio. Não amostra CPU real, não cria assertion IOKit, não muda brilho/Bluetooth/reprodução.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G14.01 | 41–49 | Deltas CPU/rede/disco, reset de contador, tempo zero e dado ausente sem valor fabricado | `LogicTests.MonitorReadingTests` / U |
| G14.02 | 50–54 | Construção não lê o Mac; histórico limitado a 60 leituras | `MacContractsTests.SystemMonitorTests` / I |
| G14.03 | 55–69 | Awake por AC, token único, trocar keepDisplay libera anterior, sleep/wake/retirada de AC, prazo e data vencida | `MacContractsTests.KeepAwakeTests` / I |
| G14.04 | 70–81 | Condições app/display, restore só no lifecycle explícito, shutdown e falha de acquire | `MacContractsTests.KeepAwakeTests` / I |
| G14.05 | 83–96 | Construção sem ação; clamp/dimming mínimo, erro de brilho; Bluetooth opt-in restaura só desconectados próprios uma vez; sleep/restore e gate temporal de música | `LogicTests.PlaybackGateTests` / U e `MacContractsTests.DisplayPowerTests` / I |

## 15. `calendar`

Origem: [CalendarChecks.swift](../../Tests/CalendarChecks.swift). Produção: `CalendarContext`, `CalendarViewModel`.

Dependências: reader/notifier falsos, defaults, `observesSystem: false`. Há `Date()` e `Calendar.current`: tornar a referência temporal/fuso explícita ou documentar o pequeno ajuste de injeção necessário. Não instanciar notificações/EventKit reais ao migrar.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G15.01 | 27–40 | Eventos do dia/nextEvent e filtro por calendário; alerta de evento e dismiss persistido ao reabrir | `MacContractsTests.CalendarEventTests` / I |
| G15.02 | 41–42 | Intervalos de semana/mês respeitam duração mínima do contrato atual | `MacContractsTests.CalendarRangeTests` / I; extrair regra pura só se necessário |
| G15.03 | 43–56 | Reminder com título aparado, snooze, restauração de reminder/filtro e dismiss cancela notificação | `MacContractsTests.ReminderTests` / I |
| G15.04 | 57–62 | Quiet hours cruza meia-noite e termina às 08h; início=fim desabilita janela | `LogicTests.QuietHoursTests` / U |
| G15.05 | 63–69 | Permissão denied limpa eventos; request explícito de notDetermined atualiza com leitor falso | `MacContractsTests.CalendarAccessTests` / I |

## 16. `files-capture`

Origem: [FileCaptureChecks.swift](../../Tests/FileCaptureChecks.swift), `PlatformFixtures`. Produção: todas fora de `App/`, principalmente Files, Capture, FileReception, eventos, PlainTextPaste e atalhos Finder.

Dependências: pasta temporária, bookmarks locais, disco, watcher nativo, processos próprios, Vision/CoreImage/CoreText; captura/clipboard/Finder/notificador/instalação substituídos onde indicado. Dividir por fronteira para não transformar todo o grupo em teste lento.

| ID | Linhas | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G16.01 | 123–162 | Identidade de bookmark, nomes literais, review sem efeito, rename/move, conflito/keepBoth, nomes inválidos, alteração após review, rollback e impedir pai→filho | `LogicTests.FileNameTests` / U e `MacContractsTests.FileOperationTests` / L |
| G16.02 | 164–190 | Shelf em memória/disco, ordem de revisão e modos 0700/0600; relink atualiza URL por superfície, fim libera URL; remover item mantém original | `MacContractsTests.FileShelfTests` / I e `FileStoreTests` / L |
| G16.03 | 191–213 | Observação por opt-in/lifecycle, partial cancelado não anuncia final velho, download pronto real, dedup e indisponibilidade; dono Toni | `MacContractsTests.DownloadStateTests` / I |
| G16.04 | 214–223 | Watcher real em pasta exclusiva recebe alteração; `stopAll` impede novos eventos; teardown confirmado | `MacContractsTests.FolderObservationTests` / L |
| G16.05 | 225–228 | Limpeza de tracking preserva encoding, parâmetros funcionais repetidos e fragmento; identifica URL assinada e rejeita scheme não web | `LogicTests.URLCleanupTests` / U |
| G16.06 | 229–242 | Plain paste restaura clipboard rico após sucesso/falha, preserva cópia mais recente e checa acesso antes de ler | `MacContractsTests.PlainPasteTests` / I |
| G16.07 | 244–260 | Instalação de DMG simulada preserva imagem, passa por review, conflitos/revalidação/keepBoth e limpeza no cancelamento do attach | `MacContractsTests.DiskImageInstallTests` / L; sem montar imagem real |
| G16.08 | 262–271 | Imagem local gerada: OCR/QR reais offline, anotação exporta e preserva dimensões, bytes inválidos rejeitados | `MacContractsTests.OfflineCaptureTests` / L |
| G16.09 | 272–289 | Modelo com captura falsa: undo, OCR, copy image/text, cor; cancelar seleção chama before/after uma vez e não pede/captura sem acesso | `MacContractsTests.CaptureStateTests` / I |
| G16.10 | 291–311 | Argumentos de processo literais sem shell e cancelamento do filho; dedup persistido de tarefas, Gantt como dono, opt-out antes de entrega e quiet hours | `MacContractsTests.ToolProcessTests` / L e `CompanionEventTests` / I |
| G16.11 | 312–345 | Toni recebe arquivos; drag registra tipo local, revela/fixa ilha; movimento nos dois eixos, normalização por escala/origem/Retina | `LogicTests.FileReceiverGeometryTests` / U, `MacContractsTests.FileReceptionTests` / I e `FileDropViewTests` / V |
| G16.12 | 346–399 | Corpo permanece dentro da área; Reduce Motion; handoff strip/painel, abandono/restauração da página, conclusão, dedup, leitor tardio, substituição/cancelamento, URL remota inválida e troca de página mais recente | `LogicTests.FileReceiverGeometryTests` / U e `MacContractsTests.FileReceptionTests` / I |
| G16.13 | 400–438 | Mesmos modelos em app/menu/ilha; calendário isolado; atalhos Finder opcionais/persistidos/com colisão, só foreground Finder, sem duplicar monitor; rename/cut/paste abre review sem mover | `MacContractsTests.FileFeatureRoutingTests` e `FinderShortcutTests` / I |

## 17. `agent-room`

Origens: [AgentRoomChecks.swift](../../Tests/AgentRoomChecks.swift), [AgentChatMotionChecks.swift](../../Tests/AgentChatMotionChecks.swift), [CodexDesktopChecks.swift](../../Tests/CodexDesktopChecks.swift), `PlatformFixtures`. Produção: todas fora de `App/`.

O cenário legado exercita adaptadores Codex/Claude mantidos no repositório. Migrar esses contratos não autoriza recolocar esses chats na experiência atual do produto, que usa Apple. Processos Python/Node/SDK são fixtures próprias, sem provedor online.

| ID | Origem/local | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G17.01 | AgentRoom 55–113 | Construção sem conectar, conexão explícita, draft por sessão, resposta de histórico antiga não troca seleção, deltas sem duplicação/em ordem; envio/receipt, requests/resposta única, falha/retry preserva draft novo; disconnect libera estado | `MacContractsTests.AgentRoomStateTests` / I |
| G17.02 | AgentRoom 114–144 | Sala/chat ficam fixos ao sair ponteiro, draft sobrevive hide/reveal, página correta, ferramentas aprovadas, reconnect para enviar e limite de 16 KB | `MacContractsTests.AgentRoomPresentationTests` / I |
| G17.03 | AgentRoom 146–193 | Workers por root/subárvore sem alheios; seleção/desconexão; tail incremental/linha parcial/cache; terminal não ressuscita trabalho e fork não vira subagente | `MacContractsTests.AgentFleetTests` / I, L; dividir parsing em U quando independente de arquivo |
| G17.04 | AgentRoom 195–219 | Composer mantém texto nativo ainda não notificado, atualiza draft, envia uma vez e limpa só no contexto certo; field editor em painel fora da tela | `MacContractsTests.AgentComposerTests` / V |
| G17.05 | AgentRoom 221–258 | Chat externo pode enfileirar sem assumir autoria; metadata waiting não vira aprovação própria; request próprio bloqueia; callback não envia draft de outra seleção; Claude trabalhando bloqueia novo envio | `MacContractsTests.AgentSendAdmissionTests` / I |
| G17.06 | AgentRoom 260–316 | Codex stdio: estado/RPC, histórico, streaming, turnos, aprovação, interrupção, workers; timeout/cancel/disconnect encerram espera | `MacContractsTests.CodexProtocolTests` / L; decoders puros em U |
| G17.07 | AgentRoom 318–388 | SDK Claude local: descoberta/history, ausência de chave, streaming/IDs/estado, permissão e pergunta, texto multipart, árvore de workers sem misturar saída filha e ignorando conclusão antiga | `MacContractsTests.ClaudeBridgeTests` / L |
| G17.08 | AgentChatMotion 12–54 | Ada idle esparso; gesto de envio rápido; falha vence confirmação coalescida e não celebra; retry limpa falha; invisível/troca de conversa/stop param layers/timer | `MacContractsTests.AgentChatMotionTests` / V |
| G17.09 | CodexDesktop 5–47 | SQLite de fixtures: raiz selecionada, árvore/nomes/parent/estado/mensagens; excluir chat alheio e atualizar término | `MacContractsTests.CodexDesktopStoreTests` / L |
| G17.10 | CodexDesktop 48–96 | Identidade clientId; fila em desktop-owned/writer conflict sem resume/turn.start; observar workers; precisão de timestamp terminal vence tail; filho só pelo dono | `LogicTests.CodexMessageIdentityTests` / U e `MacContractsTests.CodexOwnershipTests` / L |

Antes da implementação, definir caminho/versionamento do Python/Node usado pelas fixtures. Não depender do Node instalado para conta real nem baixar SDK do provedor para satisfazer o teste; o fixture atual escreve seu próprio pacote mínimo.

## 18. `local-chat`

Origens: [LocalChatChecks.swift](../../Tests/LocalChatChecks.swift), [AppleChatEligibilityChecks.swift](../../Tests/AppleChatEligibilityChecks.swift), [AdaGitHubChecks.swift](../../Tests/AdaGitHubChecks.swift), `PlatformFixtures`. Produção: todas fora de `App/`.

Dependências: engine de geração falso, stores em memória/JSON temporário, defaults, credenciais/transportes GitHub em memória e clock. **Verificado:** `LocalChatViewModel(generator:)` usa `AdaGitHubViewModel()` sem serviço por padrão; seu `restore()` é inerte. O teste de restauração GitHub fornece serviço com credenciais/transportes falsos. Preservar essa fronteira.

| ID | Origem/local | Contrato a preservar | Destino / perfil |
| --- | --- | --- | --- |
| G18.01 | Eligibility 5–30 | Matriz OS/mode/entitlement do código atual; modo local não depende de PCC; nil só libera verificação posterior, sem provar modelo disponível | `LogicTests.AppleChatEligibilityTests` / U |
| G18.02 | LocalChat 37–48 | Configuração inicial PCC/deep do contrato atual, troca/persistência e forwarding sem inferência | `MacContractsTests.LocalChatConfigurationTests` / I |
| G18.03 | LocalChat 50–63 | Contexto limitado aos últimos pares, descarta system antigo, orçamento de histórico e input >8.000 rejeitado | `LogicTests.LocalChatContextTests` / U |
| G18.04 | LocalChat 65–87 | Criar sem inferência; streaming cumulativo coalescido, bloqueio de configurar durante geração, draft/seleção separados e um envio ativo; fim grava conversa original | `MacContractsTests.LocalChatConversationTests` / I |
| G18.05 | LocalChat 88–110 | Restauração, falha/retry sem perder draft, stop e snapshots tardios descartados, indisponibilidade/input longo sem gerar, envio para view antiga não usa draft novo, exclusão | `MacContractsTests.LocalChatConversationTests` / I |
| G18.06 | LocalChat 112–132 | Store vazio/roundtrip/0600; corrupção preservada impede overwrite e IDs duplicados rejeitados | `MacContractsTests.LocalChatStorageTests` / L |
| G18.07 | AdaGitHub 53–70 | Construção sem load; abrir chat restaura credencial salva uma vez; disconnect impede nova restauração | `MacContractsTests.AdaGitHubRestoreTests` / I |
| G18.08 | AdaGitHub 72–138 | Desconectado sem requests, restore sem credencial, token inválido, conexão/snapshot e projeção bounded/read-only, cache TTL, domínio/método/auth/query corretos, disconnect limpa e restore não regrava | `MacContractsTests.AdaGitHubConnectionTests` / I |
| G18.09 | AdaGitHub 140–173 | Redirect/scheme recusados, 401/429, body excessivo/JSON inválido, refresh falho limpa snapshot sem vazar token e títulos grandes limitados | `MacContractsTests.AdaGitHubErrorTests` / I |
| G18.10 | AdaGitHub 175–201 | Cancelar connect não salva; busy rejeita refresh concorrente; disconnect invalida resposta atrasada e apaga estado/credencial | `MacContractsTests.AdaGitHubCancellationTests` / I |

## Material fora dos 18 pontos de entrada

| ID | Arquivo(s) | Classificação e destino proposto |
| --- | --- | --- |
| A01 | [NewCodexChatChecks.swift](../../Tests/NewCodexChatChecks.swift) | Regressão lógica/local escrita, **sem chamada no runner atual**. Incluir explicitamente em `MacContractsTests.NewCodexChatTests` (L): chat vazio sem history read, refresh/seleção preservam sessão não materializada, primeiro envio falho é retryable, primeiro turno/history ainda não persistido não apaga texto; erro normal de histórico continua visível. Evidenciar como cobertura antes órfã, sem alegar execução anterior. |
| A02 | [CompanionPerformanceChecks.swift](../../Tests/CompanionPerformanceChecks.swift), [run-companion-render-checks.sh](../../Tests/run-companion-render-checks.sh) | Benchmark Metal nativo: cenas isoladas/simultâneas/onboarding, warmup, render fora da main, CPU e p95. Manter fluxo separado, registrar máquina/OS/configuração/validação/frame count. Limiares atuais (<40% CPU, <16,7 ms p95) são contratos desse benchmark, não promessa de CPU do app. Não entra silenciosamente no plano rápido/completo de correção. |
| A03 | [verify-built-app.sh](../../Tests/verify-built-app.sh) | Contrato do bundle **compilado/assinado**: privacy strings, LSUIElement, assinatura, Calendar e Apple Events. Preservar ferramenta separada, caminho explícito e resultado próprio; teste das fontes não a substitui. |
| A04 | [CompanionRuntimePreview.swift](../../Tests/CompanionRuntimePreview.swift) | Ferramenta híbrida: export PNG/movie/file-receive/display-quality/border-check e `--check-bundle` que verifica seis assets 1024×1024 no catálogo compilado. Separar contrato de recurso do gerador visual; preservar ambos fora do target unitário nesta migração. O tempo médio de update no fim é medição auxiliar, não aceite do app. |
| A05 | [CompanionPreview.swift](../../Tests/CompanionPreview.swift), [VoiceMotionPreview.swift](../../Tests/VoiceMotionPreview.swift) | Geração de conceitos/prévias de companions e gestos; revisão visual, sem baseline automático comprovado. Manter ferramentas e destinos explícitos. |
| A06 | [Sprint4Preview.swift](../../Tests/Sprint4Preview.swift), [Sprint5Preview.swift](../../Tests/Sprint5Preview.swift), [UtilityPreview.swift](../../Tests/UtilityPreview.swift) | Prévias de sprint/utilidades; manter para reprodução visual, trocar caminhos pessoais/efêmeros somente na etapa autorizada de manutenção dessas ferramentas. |
| A07 | [CalendarPreview.swift](../../Tests/CalendarPreview.swift), [AgentRoomPreview.swift](../../Tests/AgentRoomPreview.swift), [LocalChatPreview.swift](../../Tests/LocalChatPreview.swift) | Prévias por funcionalidade com modelos/fixtures e bundle externo. Preservar; não importar seus `@main` no target de testes. |
| A08 | [WorkspacePreview.swift](../../Tests/WorkspacePreview.swift), [IslandEditorPreview.swift](../../Tests/IslandEditorPreview.swift) | Prévias de workspace/layout; continuam evidência visual separada. |
| A09 | [PlatformFixtures.swift](../../Tests/PlatformFixtures.swift) | Helper, não caso: calendário/notificador inertes, falha se pedir acesso real. Tornar suporte comum das suítes isoladas, com erro reportável em vez de abortar todo o processo. |
| A10 | `render-sprint-5-preview.sh`, `render-calendar-preview.sh`, `render-agent-room.sh`, `render-local-chat.sh`, `render-file-reception.sh`, `export-companion-artwork.sh` | Entradas de reprodução/export dos previews; preservar, sem inclusão automática na migração dos 18 grupos. |

## Dependências e lacunas que condicionam a migração

Estes itens são conclusões de leitura, não falhas reproduzidas nesta preparação.

| ID | Evidência | Providência na implementação futura |
| --- | --- | --- |
| D01 | `AIAnalyticsReader.init` aceita `home`, mas `codexHome` tem default derivado de `CODEX_HOME`; G08 passa apenas `home` | Informar os dois caminhos da fixture. Não alterar `HOME`/`CODEX_HOME` globais do processo para simular isolamento. |
| D02 | G07 injeta contador `read`, mas `AIUsageViewModel.refresh` também chama `readClaude` quando Claude está habilitado | Injetar reader de quota em memória/nil. Auditar demais defaults de serviço e proibir uso acidental de histórico real. |
| D03 | G09 resolve JSON pelo cwd; `PriceCatalog.bundled()` e `AIProviderResources.bundle` usam `.main`; portraits podem cair em snapshot SceneKit | Fixtures com URL/bundle explícitos; separar teste de catálogo empacotado do teste do parser; não mascarar asset ausente com fallback. |
| D04 | G17.08 registra imagem global nomeada `Companion-ada`; `CompanionArtwork` tem caches estáticos; G04 usa notificações globais | Serializar a fronteira mutável inteira, restaurar imagem/estado quando possível e provar que ordem inversa/repetição não muda resultado. Se cache não for restaurável, usar processo dedicado ou seam mínimo revisado. |
| D05 | Sleeps/RunLoop/yield polling em voz/ilha/clipboard/chat/watchers/RPC | Barreira/continuação/clock de teste para coordenação lógica; timeout só como limite de falha. Watcher/processo nativo conserva integração real com espera bounded por evento. |
| D06 | Datas atuais/calendário/fuso, boot time real na fixture de reboot do clipboard e suite `activity-motion-*` sem cleanup explícito | Data/fuso/boot time controlados e teardown de defaults, tasks, continuations, observers, scopes, views/painéis e processos mesmo quando o caso falha. |
| D07 | Scripts de protocolo com shebang Python, descoberta Node e SQLite; benchmark Metal e AppKit fora da tela | Documentar ferramenta/versão disponível na execução, distinguir requisito ausente de teste aprovado e não baixar nem chamar provider real. |
| D08 | `NewCodexChatChecks` não é referido pelo runner nem por `AgentRoomChecks.main` | Migrar A01 explicitamente e adicionar seleção/evidência na matriz; não reduzir o inventário aos arquivos já ligados ao runner. |
| D09 | Compilar fonte não significa exercitar recurso/serviço: sensor só é listado em G01, assinatura só em A03, pixels compilados só em A04 | Relatar cobertura de cenário e cobertura de código separadamente; preservar aceites físicos/externos e não inventar cenários executados. |

## Registro a preencher durante a execução

Para cada ID G01–G18 e A01, adicionar o destino real `target/suíte/teste`, variantes parametrizadas, tipo/perfil final, resultado individual e localização do `.xcresult`. A02–A10 mantêm sua classificação e evidência própria quando executados. O responsável pela implementação atualiza a matriz; o revisor confere equivalência e justifica exclusões.

O fechamento deverá informar separadamente: funções de teste descobertas, invocações parametrizadas executadas, aprovadas, falhas, ignoradas e requisitos de ambiente ausentes. **Não há contagem nem relatório de cobertura de execução nesta preparação.** O gate continua fechado até implementação, execução e revisão independente.
