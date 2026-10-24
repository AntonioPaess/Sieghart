# VoiceInk — ditado e transcrição no macOS

**Pesquisa:** 13/10/2026. **Alvo:** VoiceInk para macOS da [Beingpax](https://github.com/Beingpax/VoiceInk), código público no commit [`5628765`](https://github.com/Beingpax/VoiceInk/commit/5628765e92f7630ecdeb9a09f798fbd80b76b243). O release público v2.21 aponta para outro commit (`640b0c8`); portanto, o código de `main` examinado não demonstra equivalência binária ao release. **Situação da instalação:** o `/Applications/VoiceInk.app` encontrado era o aplicativo **iOS** 1.33 (build 133) executado no Mac: `DTPlatformName=iphoneos`, `MinimumOSVersion=18.0`, extensões de teclado/widget e bundle `com.prakashjoshipax.VoiceInk`. Isso não valida o ditado global do produto macOS. O usuário pediu para focar HeyClicky; a validação do VoiceInk macOS fica pausada por essa preferência.

## 1. Resumo executivo

**Verificado no código:** a aplicação para Mac separa seleção do dispositivo, captura PCM, sessão de transcrição, streaming/batch, pós-processamento, entrega do texto e persistência. O gravador CoreAudio usa AUHAL e produz áudio mono de 16 kHz/Int16 sem trocar o microfone padrão do sistema. A camada de streaming mantém buffer limitado enquanto o provedor inicia, mostra parciais e pode recorrer à transcrição do WAV gravado quando a sessão de streaming falha. [Captura](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift), [orquestração](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Workflows/VoiceInkEngine.swift), [sessão](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Workflows/TranscriptionSession.swift).

**Decisão para Sieghart:** aproveitar a **separação de estados e responsabilidades**, não o código GPL-3.0. A captura de comandos já existe no Sieghart; o próximo produto distinto é ditado de texto com entrega verificável, modelo/rota de dados explícitos e sessão longa resiliente. A [comparação](../comparisons/voice-comparison.md) e a [arquitetura proposta](../architecture/sieghart-voice-architecture.md) mostram a diferença.

## 2. Identidade, distribuição e limites

| Questão | Evidência |
| --- | --- |
| Produto | [Site oficial](https://tryvoiceink.com/), [fonte](https://github.com/Beingpax/VoiceInk) e [releases](https://github.com/Beingpax/VoiceInk/releases). O site declara Apple Silicon/macOS 14.4+ para a versão de Mac. |
| Licença | O repositório contém [GPL-3.0](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/LICENSE). Conceitos e contratos originais podem inspirar Sieghart; código ou ativos exigiriam avaliação separada de licença. |
| Versão examinada | Código `main` fixado acima; v2.21 é o último release público consultado em 13/10/2026. Não presumir que todos os caminhos do `main` estejam no binário v2.21. |
| Artefato local inicial | `VoiceInk.app/Wrapper/VoiceInk.app/Info.plist`, versão 1.33, `iphoneos`, binário arm64 SHA-256 `d5585088c2711522bf9ab5334104614231f549f1c252bf6442ab733ae9f370e2`. É o app iOS em compatibilidade no Mac; nenhuma conclusão sobre o executável macOS é tirada dele. |
| Execução inicial | Onboarding iOS observado até “What will you use VoiceInk for?” com modos Default/Chat/Email; não se testou gravação, transcrição ou colagem. |

## 3. Funções relevantes

| Área | Evidência | Consequência para Sieghart |
| --- | --- | --- |
| Captura | `Recorder` resolve entrada e `CoreAudioRecorder` captura por AUHAL, entrega blocos à sessão e grava WAV. [Recorder](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Capture/Recorder.swift), [CoreAudioRecorder](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift). | Estudar dispositivo escolhido e buffer sem trabalho pesado no callback; não substituir a captura curta de comandos sem medir. |
| Transcrição | `TranscriptionServiceRegistry` seleciona serviços locais (Whisper/FluidAudio/transcribe.cpp/Apple) ou remotos, e sessão em tempo real ou por arquivo conforme configuração. [Registro](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Workflows/TranscriptionServiceRegistry.swift). | Provedor deve expor idiomas, privacidade, latência, formatos, custo e capacidade de streaming. |
| Parciais e final | `VoiceInkEngine`/`StreamingTranscriptionService` rejeitam callbacks obsoletos por ID de sessão, limitam fila inicial e têm estados de conexão, streaming, finalização, erro e cancelamento. [Engine](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Workflows/VoiceInkEngine.swift), [streaming](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Streaming/StreamingTranscriptionService.swift). | A UI deve distinguir hipótese parcial de texto final e impedir resultado velho após cancelar/reiniciar. |
| VAD | O provedor FluidAudio usa VAD para segmentar/estabilizar parciais e faz fallback batch em certas condições. Isso **não prova** que o VAD encerre automaticamente o ditado. [Provedor](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Infrastructure/Providers/Transcription/FluidAudio/Streaming/FluidAudioStreamingProvider.swift). | Separar “há fala?” de “o usuário terminou?”; comando curto, ditado longo e conversa têm políticas de término diferentes. |
| Contexto | A sessão pode capturar texto selecionado, área de transferência e OCR da tela sob permissão, e usar isso para aprimoramento/assistente. [Snapshot](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Context/RecordingContextSnapshot.swift), [pipeline](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Workflows/TranscriptionPipeline.swift). | Solicitar contexto por caso de uso e exibir precisamente o que será usado. |
| Entrega | `TranscriptionDelivery` separa colagem, follow-up, resposta e comando customizado. `CursorPaster` publica ⌘V quando há Accessibility ou usa alternativa AppleScript; restaura clipboard apenas se ainda o controla. Um ⌘V publicado **não confirma** que o campo aceitou o texto. [Entrega](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Workflows/TranscriptionDelivery.swift), [colagem](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift). | Resultado da entrega deve ser `confirmado`, `enviado ao sistema` ou `incerto`; nunca declarar inserção só por emitir tecla. |
| Rota de dados | O [site](https://tryvoiceink.com/) descreve transcrição local e aprimoramento em nuvem opcional; o código suporta provedores remotos de **transcrição** e a [versão 2.21](https://github.com/Beingpax/VoiceInk/releases/tag/v2.21) adicionou OpenRouter. A alegação de privacidade local não descreve todas as configurações possíveis. | Política local por padrão, com consentimento separado para enviar áudio ou texto a cada provedor. |

## 4. Cadeia técnica observável no código

```text
hotkey / modo → resolver microfone → AUHAL → PCM 16 kHz mono → chunks + WAV
                                                 ↓                 ↓
                                         provedor streaming     fallback batch
                                                 ↓                 ↓
                                          parcial / final ← finalização
                                                 ↓
                                    filtro / dicionário / aprimoramento
                                                 ↓
                                colagem | resposta | comando | histórico
```

O desenho é uma síntese dos módulos lidos, não um traço instrumentado do release instalado. O caminho de fallback usa o serviço correspondente à configuração; **não é promessa de fallback local** se o usuário escolheu um provedor remoto. A fila finita registra perdas; nem `AsyncStream` nem WAV removem a necessidade de testar pressão, formato de dispositivo, crash e duração real.

## 5. Proposta original para Sieghart

1. Preservar `VoiceCommandSession` e `NativeVoiceCapture` para comandos curtos. Criar `DictationSession` distinta, com término explícito ou mãos livres configurável, buffer limitado, parciais substituíveis, finalização e cancelamento.
2. Usar `AudioInputPolicy` comum para padrão do sistema, dispositivo preferido, desconexão, sleep/wake e perda de entrada; a UI deve mostrar o microfone realmente ativo e quando um fallback ocorreu.
3. Introduzir `TranscriptionProvider` com contrato de formato/idioma/privacidade/streaming; medir `SFSpeechRecognizer` atual, `SpeechAnalyzer`/`SpeechTranscriber` quando disponíveis e um modelo local antes de escolher. [Apple SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer).
4. Introduzir `TextDelivery` que verifique foco/seleção quando possível, preserve clipboard com ownership, e exponha “copiado; cole manualmente” se não puder comprovar inserção. Auto Send só com escolha explícita e teste contra envio acidental.
5. Contexto, aprimoramento e comandos customizados ficam fora do ditado básico; cada rota externa deve aparecer antes da primeira transmissão. [Arquitetura detalhada](../architecture/sieghart-voice-architecture.md).

## 6. Desafios e testes que faltam

- **Instalação macOS:** confirmar `CFBundleVersion`, assinatura, permissões e se o binário corresponde ao código estudado. A versão iOS instalada não serve para isso.
- **Uso real:** testar português brasileiro e inglês, fala curta e longa, pausas, ruído, silêncio, AirPods/interface USB, troca de mic, sleep/wake, cancelamento e sem rede. Medir início da captura, primeira parcial, final e inserção separadamente, em repetições comparáveis.
- **Aplicativos alvo:** TextEdit/Notas, campo web, Electron e terminal. O terminal deve receber texto sem Return automático. Medir se o texto foi de fato inserido, não apenas se o atalho foi emitido.
- **Recursos:** medir CPU, memória e energia com o app parado, ouvindo, transcrevendo e aprimorando. Nenhum número de desempenho foi medido nesta etapa.
- **Privacidade:** verificar seleção efetiva de provedor e permissões. Não inferir ausência de tráfego só pelo rótulo “local”.

## 7. Recomendação

Primeiro entregar ditado local simples e confiável como fluxo distinto do comando de voz, com fallback claro e teste reproduzível. Depois avaliar streaming refinado, dicionário, contexto selecionado e aprimoramento opcional. Não portar o código GPL para o aplicativo fechado. Esta etapa é pesquisa; nenhuma mudança de produção ou teste de implementação foi feita.

## 8. Perguntas abertas

- O executável macOS instalado usa a mesma cadeia do commit público e de qual tag?
- Qual provedor local oferece melhor latência e precisão no Mac do usuário para pt-BR sem rede?
- Como cada app alvo reage a texto parcial, correções e cancelamento?
- Há permissão Accessibility necessária para o primeiro caso de uso, ou copiar texto basta?
