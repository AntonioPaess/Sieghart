# HeyClicky — análise do aplicativo macOS completo

**Pesquisa:** 13–14/10/2026. **Alvo instalado:** `/Applications/HeyClicky.app`, versão 1.0.53, build 64, bundle `com.humansongs.clicky`, macOS 14.2+, binário universal SHA-256 `970569210a71cf1f39790f7d0fc02af2a1d64bacf0259d4741f0fa63e53dbb31`. Este hash coincide com a [inspeção estática anterior com REA 6.4.0](../../Design/Research/hey-assistants-2026-10-11/README.md) do release oficial [v1.0.53](https://github.com/farzaa/clicky-releases/releases/tag/v1.0.53). O repositório de distribuição não fornece o código completo. Esta revisão combina pacote, UI observada, capturas enviadas pelo usuário, três testes relatados por ele e fontes oficiais. Nenhuma conta ou integração foi conectada nesta pesquisa.

## 1. Resumo executivo

**Confirmado por pacote:** app nativo, universal, mínimo macOS 14.2, `LSUIElement=true`. Seu `Info.plist` declara uso de microfone, Speech Recognition, Screen Capture e pastas Desktop/Documents/Downloads. Frameworks ligados incluem AVFAudio, AVFoundation, AudioToolbox, CoreAudio e Speech. Esses vínculos mostram capacidade, **não identificam** provedor remoto, VAD, algoritmo de endpoint, TTS ou momento exato da permissão. O pacote anterior continha helper de uso do computador e runtime Codex; isso também não prova execução bem-sucedida. [Evidência anterior](../../Design/Research/hey-assistants-2026-10-11/README.md).

**Confirmado por fornecedor:** o [changelog](https://www.heyclicky.com/changelog) descreve conversa, ditado, orientação na tela, Clickys persistentes, arquivos, integrações e rotinas. O HeyClicky processa solicitações de IA por seu serviço e provedores em nuvem, conforme a [política de privacidade](https://www.heyclicky.com/privacy-policy). Sem teste de rede não há verificação independente da rota concreta por recurso.

**Decisão para Sieghart:** estudar a continuidade entre pedido, personagem responsável, progresso, aprovação e arquivo produzido, além da orquestração de voz. O notch é a entrada e o resumo; tarefas longas exigem Home. A referência informa contratos de produto, não autoriza copiar arte/código nem prova arquitetura interna. [Voz](../architecture/sieghart-voice-architecture.md), [agentes](../architecture/sieghart-agent-architecture.md), [UI](../architecture/sieghart-ui-architecture.md).

## 2. Funções relevantes e grau de evidência

| Fluxo | O que a fonte afirma | Estado da verificação |
| --- | --- | --- |
| Conversa | Hotkey invoca pergunta falada sobre a tela; resposta oral e desenho guiado. v1.0.22 descreve interrupção durante a fala. [Site](https://www.heyclicky.com/), [changelog](https://www.heyclicky.com/changelog). | O usuário relatou que, ao interromper uma resposta longa, a voz anterior parou e a nova resposta a substituiu sem mistura. Uma tentativa; sem tempo medido ou prova de cancelamento remoto. |
| Ditado | v1.0.37 descreve Fn+Control, texto em streaming, duplo toque mãos livres, detecção de idioma e dicionário. [Changelog](https://www.heyclicky.com/changelog). | O usuário relatou frase neutra completa no TextEdit. “450 ms” é número do fornecedor, não benchmark reproduzido. |
| Robustez | v1.0.47 afirma recuperação de ditado longo/interrompido; v1.0.48 trata fallback de microfone; v1.0.53 corrige rede, saída de áudio e texto espúrio em silêncio. [Changelog](https://www.heyclicky.com/changelog). | O usuário trocou de microfone durante ditado e relatou “duas partes completas”. Uma tentativa, sem traço CoreAudio. |
| Inserção | v1.0.48 descreve layout de teclado, preservação de clipboard e terminal sem execução por Return; v1.0.53 removeu wrapper `<transcript>` espúrio. [Changelog](https://www.heyclicky.com/changelog). | Comportamento anunciado; precisa teste em apps-alvo. |
| Resposta oral | v1.0.45 expôs velocidade de 0,5× a 1,5×; v1.0.48 descreve pista audível pré-carregada para fones Bluetooth e cópia da resposta ao clipboard se a saída estiver muda. [Changelog](https://www.heyclicky.com/changelog). | Comportamento anunciado; mecanismo TTS desconhecido. |
| Conta e nuvem | A [política](https://www.heyclicky.com/privacy-policy) diz que voz/capturas são enviadas ao proxy e a provedores como Anthropic, OpenAI, Deepgram e Cerebras; [trust](https://www.heyclicky.com/trust) diz que prompts e análises de capturas podem ser retidos, mas screenshots brutos não. | Declarações publicadas, sem auditoria de tráfego/retenção. |

## 3. Achados técnicos locais

| Item | Resultado |
| --- | --- |
| Executável | Mach-O `arm64` e `x86_64`, hash acima; mesmo build do estudo anterior. |
| Permissões declaradas | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSScreenCaptureUsageDescription`, `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`. Declaração não equivale a concessão pelo usuário. |
| Interface | App de menu/notch (`LSUIElement=true`). Tour de sete passos com “Listening”/“thinking”, Control+Option, orientação desenhada e modo texto. Capturas mostram Home com Clickys, busca, conversas, arquivos, sugestões e dois agentes em andamento; um resultado aparece como arquivo com miniatura. O conteúdo pessoal do tour não foi registrado no dossiê. |
| Pacote anterior | [Inventário REA e hashes](../../Design/Research/hey-assistants-2026-10-11/evidence-index.json) registraram imports nativos de áudio/fala/tela, helper `cua-driver` e runtime Codex. A inspeção atual encontrou `Contents/Resources` com cerca de 652 MB, incluindo `CodexRuntime` de cerca de 562 MB. Tamanho em disco não é uso de memória. Não se reconstruiu o algoritmo de fala ou agentes a partir desses artefatos. |

## 4. Arquitetura observável e hipóteses

```text
hotkey / ditado mãos livres / conversa → captura de áudio → processamento remoto descrito na política
                                        ↓                              ↓
                          UI de escuta e texto parcial       resposta / agente / TTS
                                        ↓                              ↓
                                inserção em campo         fala + orientação visual
```

O diagrama é **modelo de produto inferido** das interfaces e documentos públicos. Não é diagrama de processos internos. Em particular, não se sabe se o ditado e a conversa compartilham captura, qual VAD é usado, se há cancelamento server-side, como a interrupção suprime áudio do alto-falante nem se algum TTS específico roda localmente. A política remota significa que conexão, latência variável, conta, retenção e custo entram no desenho de qualquer função equivalente.

## 5. Aplicação original em Sieghart

1. Definir estados observáveis `preparando → ouvindo → finalizando → pensando → falando → concluído/erro/cancelado`, com ID de turno. Qualquer parcial/áudio/resposta tardia de turno cancelado é descartado.
2. Permitir *barge-in* somente se o modo de conversa estiver ativo e o teste de eco confirmar que a própria voz sintetizada não dispara a entrada. Parar TTS imediatamente, preservar o contexto do turno anterior e começar uma nova captura.
3. Mostrar o microfone e a saída ativos, detectar mudança/desconexão, e avisar quando usar fallback. Guardar texto final de ditado antes de trocar/reiniciar captura; não montar fala faltante como se completa fosse.
4. Separar ditado, pergunta e comando. Ditado insere texto; pergunta fornece resposta; comando só executa ferramenta após intenção autorizada. Contexto de tela é sob demanda e explícito.
5. Adotar teste de entrega no terminal sem Return e oferecer cópia manual quando a aplicação alvo não aceitar inserção verificável. [Arquitetura detalhada](../architecture/sieghart-voice-architecture.md).

## 6. Desafios, limites e plano de validação

- **Ditado observado por relato do usuário:** após o tour, o usuário executou a frase neutra solicitada em documento vazio e informou que apareceu **completa**. A ferramenta não ouviu o áudio nem leu o campo final; esta é validação de uma tentativa pelo usuário, não medição de latência, correção palavra a palavra ou confiabilidade em outros apps.
- **Ensaios concluídos por relato do usuário:** ditado completo, interrupção limpa de fala e troca de microfone com duas partes preservadas. Cada caso foi uma tentativa sem gravação/cronômetro independente.
- **Ensaios restantes:** repetir em apps-alvo, silêncio curto/longo, frase interrompida, cancelamento, nova ativação antes de resultado antigo, tela cheia, sleep/wake e falha de rede. Registrar separadamente resultado visível e relato sobre som.
- **Medições:** comparar pelo menos cinco rodadas idênticas com cronômetro/indicadores para início, primeiro texto, texto final e primeira resposta falada, junto com CPU/memória/energia. Nenhuma dessas métricas foi medida nesta etapa.
- **Privacidade:** evitar documentos/contas pessoais no teste. O texto/voz de ensaio pode sair do aparelho conforme a política; não inferir processamento local pelos frameworks ligados.
- **Licença e código:** pacote fechado; não copiar implementação/arte do personagem. A documentação de REA anterior é evidência de distribuição, não permissão de reuso.

## 7. Recomendação de voz

Priorizar no Sieghart sessões separadas de comando, ditado e conversa com cancelamento confiável e indicador fiel; testar entrada/saída Bluetooth e entrega de texto antes de adicionar voz contínua. Para conversa, começar com ativação explícita e TTS local de sistema, avaliar voz remota apenas com rota/consentimento claros. Nenhum código de produção foi alterado nesta pesquisa.

## 8. Perguntas abertas de voz

- Qual é a política real de endpoint e qual atraso entre última palavra e resposta no Mac do usuário?
- Como o HeyClicky lida, nesta instalação, com AirPods, interface USB, mudo, sleep/wake, tela cheia e app alvo sem foco?
- O que é guardado localmente após ditado cancelado e como o usuário vê/exclui esse material?
- Qual é a latência do barge-in e a taxa de acerto em testes repetidos? Uma tentativa do usuário teve substituição limpa.

## 9. Notch, Home, onboarding e personagens

**Observado na UI e nas capturas fornecidas pelo usuário:** o onboarding conduz uma conversa com personagem, resposta por Control+Option ou texto, estados de escuta/fala, demonstração de orientação na tela e entrada na Home. A Home reúne busca, lista de Clickys, conversas, sugestão, botão de voz, editor de texto e arquivos gerados. Personagens flutuantes mostram trabalho em andamento e o notch exibe estado como “Speaking”. Duas tarefas aparecem simultaneamente; isso mostra concorrência na interface, **não** isolamento de processos ou qualidade do resultado. As capturas incluem detalhes pessoais e de outra tarefa, não transcritos aqui.

**Fornecedor:** v1.0.52 introduziu *quick peek* no hover com Clickys, arquivos recentes arrastáveis e acesso à Home; v1.0.51 descreve Home redimensionável e janela destacável; v1.0.49 descreve fixar, buscar, arquivar e reabrir conversas. V1.0.53 ajustou fluidez, atualização e estado de walkthrough. [Changelog](https://www.heyclicky.com/changelog). Este desenho permite usar o notch como resumo sem tentar encaixar uma conversa longa nele. A [proposta de UI Sieghart](../architecture/sieghart-ui-architecture.md) deve mostrar estado real, responsável e resultado em superfícies adequadas.

## 10. Contexto visual, documentos e walkthrough

O tour observado mostra instruções e elementos desenhados sobre outro app. O [site](https://www.heyclicky.com/) anuncia pergunta sobre o que está na tela, ensino de ferramentas e orientação desenhada. O [changelog](https://www.heyclicky.com/changelog) afirma leitura de página/PDF/documento inteiro, memória da página recém-deixada, walkthrough de até 15 passos e preservação de passos concluídos quando uma etapa pausa ou falha. **Não** fizemos ensaio neutro de OCR, seleção de janela, documento longo, tela cheia ou precisão espacial. A promessa de funcionar “com qualquer app” é marketing, não garantia de acesso estruturado em todas as interfaces.

A [página de confiança](https://www.heyclicky.com/trust) diz que tela é capturada ao acionar hotkey, screenshot bruto é descartado após processamento e análises textuais/prompts podem ser mantidos. Para Sieghart, separar captura sob demanda, texto acessível/OCR, origem do trecho e estado do passo; quando o contexto não puder ser lido, informar isso em vez de fingir visão completa.

## 11. Clickys, tarefas e resultados

**Observado:** Home e bolhas mostram vários agentes com identidade, status e conversa própria; um resultado tem miniatura e abre como arquivo. **Fornecedor:** cada Clicky tem nome, aparência, memória, conversa e pasta; recebe texto, voz e anexos; pode mostrar progresso, parar, tentar de novo e trabalhar em paralelo a outro. O histórico e os rascunhos persistem durante a sessão, e conversas podem ser fixadas/arquivadas. A v1.0.52 afirma que **Clickys** rodam em GPT-6 Luna e respostas profundas em GPT-6 Sol; isto não identifica o modelo de voz de cada turno. [Changelog](https://www.heyclicky.com/changelog).

O pacote contém `CodexRuntime`, helper `cua-driver`, catálogo e instruções de modelo. O [REA anterior](../../Design/Research/hey-assistants-2026-10-11/README.md) inventariou esses artefatos. Eles não provam que a tarefa mostrada em uma captura usou Codex ou executou uma ação específica. Para Sieghart, usar **pedido → progresso → aprovação → resultado entregue → resultado verificado** como estados diferentes; ver [arquitetura de agentes](../architecture/sieghart-agent-architecture.md).

## 12. Arquivos, integrações e ações no computador

**Arquivos:** o fornecedor descreve anexar/arrastar/colar arquivos e imagens, prévia de PDF/documentos dentro da Home, abertura no Finder e arraste de arquivos recentes desde o notch. A captura do usuário mostra um arquivo final com miniatura, mas sua qualidade e procedência não foram auditadas. [Changelog](https://www.heyclicky.com/changelog).

**Integrações:** v1.0.53 permite várias contas por app com rótulos e pede desambiguação antes de criar conteúdo em conta incerta. v1.0.49 descreve conexões MCP por URL ou comando local com OAuth ou chave. O pacote traz diretórios para Google Tasks, Teams, Linear, ClickUp, HubSpot, Jira, Dropbox, Salesforce, Gmail, Google Docs e Outlook; são instruções empacotadas, não contas conectadas. Surgiram prompts de conexão com GitHub e YouTube na UI; o de GitHub foi dispensado com **Not now**. Nenhuma conexão foi aprovada ou testada. [Changelog](https://www.heyclicky.com/changelog).

**Controle do Mac:** o fornecedor descreve autorização “Allow once / Always allow / Not now” antes de clicar/digitar, escopo por conversa, janela de navegador dedicada quando apropriado e driver nativo de ações em segundo plano sem mover o ponteiro físico. O pacote contém um helper compatível com esse desenho, mas não testamos ações em apps pessoais nem o enforcement da permissão. [Changelog](https://www.heyclicky.com/changelog). O Sieghart deve separar conexão de conta, permissão de leitura, autorização de ferramenta e aprovação de cada efeito relevante; registrar conta, janela, tarefa e recibo. [Automação proposta](../architecture/sieghart-automation-architecture.md).

## 13. Sugestões, rotinas, limites e custo

**Observado:** uma sugestão dizia que repetiria diariamente e oferecia **No / Adjust / Yes, keep it going**. Não a aceitamos. O changelog v1.0.53 informa que esse aceite explícito foi adicionado porque a primeira rotina antes podia ser criada sem aviso claro. [Fonte](https://www.heyclicky.com/changelog).

**Fornecedor:** sugestões podem ler apps conectados e pesquisa relevante em modo de leitura; o cartão proposto aguarda aprovação. A [página trust](https://www.heyclicky.com/trust) declara leitura diária somente enquanto o app está aberto e opção de desligá-la. Rotinas rodam neste Mac com HeyClicky aberto, esperam rede/acordar, recuperam uma execução após sleep e pausam após falhas repetidas. Uma rotina não equivale a serviço que executa com o Mac desligado. [Changelog](https://www.heyclicky.com/changelog).

Em 14/10/2026, o [site oficial](https://www.heyclicky.com/) anuncia Free com 25 mensagens de conversa e 25 de agente/mês; Pro a US$20/mês com 150 de agente; Max a US$100/mês com 1.000 de agente. Ditado no Free aparece como “plenty”, sem limite numérico publicado nessa página; nos pagos, como ilimitado. Preço e quotas podem mudar. A medição de CPU ociosa de 3–5% e a latência de 450 ms no changelog são números do fornecedor, não resultados locais.

## 14. Dados, segurança e ciclo de vida

| Questão | Publicado ou observado | Limite |
| --- | --- | --- |
| Captura e retenção | [Trust](https://www.heyclicky.com/trust): tela sob hotkey, screenshot bruto descartado; análise textual e prompt mantidos. | Sem monitoramento de rede/servidor. |
| Rota de IA | [Política](https://www.heyclicky.com/privacy-policy): captura local de voz/tela enviada a proxy e provedores incluindo Anthropic, OpenAI, Deepgram e Cerebras. | Não se identificou provedor/modelo por turno. “Tudo em nuvem” na página trust refere-se ao processamento de IA; UI, captura e driver são locais. |
| Sugestões | [Trust](https://www.heyclicky.com/trust): exceção à ausência de rastreamento em segundo plano é leitura diária de integrações conectadas, desativável. | Nenhuma conta conectada neste estudo. |
| Exclusão | [Política](https://www.heyclicky.com/privacy-policy): exclusão de dados pessoais em até 14 dias após pedido confirmado, salvo obrigação legal. | Não testada. |
| Telemetria | Pacote contém PostHog/Sentry; [trust](https://www.heyclicky.com/trust) os identifica e informa ausência de SOC 2/ISO 27001. | Eventos reais enviados não foram auditados. |

O produto pede microfone, reconhecimento de fala, captura de tela e potencial acesso a arquivos. O `Info.plist` declara esses usos; isso não identifica o que foi concedido nesta instalação. Ao fechar o app, a página de confiança declara que não mantém helpers ativos, mas não fizemos teste de processo/serviço após encerramento.

## 15. É possível fazer algo similar com Apple Foundation Models?

**Sim, por composição; o modelo não é o aplicativo inteiro.** Neste Mac, `sw_vers` informou macOS 26.6.2 e o SDK disponível é 27.0. Não verificamos `SystemLanguageModel.availability` nem prototipamos a experiência. A [Apple](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) informa que disponibilidade depende de dispositivo, região e estado de Apple Intelligence.

| Função desejada | Caminho Apple | Limite |
| --- | --- | --- |
| Entender pedido, responder, escolher ferramenta | `FoundationModels`: sessões, streaming, saída tipada e `Tool` implementada pelo Sieghart. [Apple](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models), [ferramentas](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling). | Modelo local documentado para macOS 26: contexto de até 4.096 tokens; Apple desaconselha tratá-lo como solução para código e raciocínio complexo. Gerenciar histórico e fallback. |
| Ouvir e ditar | `SpeechAnalyzer`/`SpeechTranscriber` e captura AVFAudio. [Apple](https://developer.apple.com/documentation/speech/speechtranscriber). | Endpoint, troca de microfone, inserção global e barge-in são código/testes do Sieghart. Foundation Models não é ASR. |
| Responder falando | `AVSpeechSynthesizer`, que permite parar fala em curso. [Apple](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer). | Estado de turno, eco, latência e qualidade da voz dependem da integração. Foundation Models não é TTS. |
| Ler tela | `ScreenCaptureKit` e OCR `Vision`, com permissão. [Apple](https://developer.apple.com/documentation/screencapturekit), [Vision](https://developer.apple.com/documentation/vision/locating-and-displaying-recognized-text). | OCR não dá estrutura/ações de todo app. Entrada de imagem em Foundation Models é documentada para macOS 27 com avisos de beta; não presumir disponibilidade no macOS 26 atual. [Apple](https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting). |
| Clickys, arquivos, rotinas, ações | SwiftUI/AppKit, persistência, agenda, conectores e ferramentas do host. | Personagens podem ser papéis do mesmo orquestrador. O modelo não fornece sozinho memória persistente, permissões, verificação de efeito, Clickys paralelos ou execução agendada. |

**Protótipo recomendável:** pedido falado → transcrição local → intenção estruturada pelo modelo Apple → ferramenta reversível do Sieghart → recibo verificado → resposta falada. Medir português, latência, energia e cancelamento no Mac real antes de prometer equivalência ao HeyClicky. O framework Apple hoje também abstrai modelos em servidor; escolher Foundation Models **não significa automaticamente** que toda inferência fica local. [Documentação](https://developer.apple.com/documentation/FoundationModels).

## 16. Decisão e trabalho restante

1. O **dossiê de produto** está coberto: UI/notch, onboarding, voz, contexto, agentes, arquivos, integrações, rotinas, custo e dados. O REA continua sendo análise estática parcial do binário fechado.
2. Faltam testes repetidos de qualidade/latência, CPU/RAM/energia, tela cheia/monitores, OCR/documentos, cancelamento real do agente, falha de rede, sleep/wake e acesso a conectores. Não inferir esses resultados das capturas ou do changelog.
3. O Sieghart deve priorizar estados de voz confiáveis, contexto explicitamente escolhido, ações com aprovação/recibo e uma Home que mostre tarefa e resultado. Não copiar personagens, recursos ou código proprietário.
4. Esta pesquisa não alterou o app Sieghart. Qualquer protótipo de implementação deve ocorrer em **worktree separado** da tree que o outro chat utiliza e vir com instruções reproduzíveis de teste para o usuário.
