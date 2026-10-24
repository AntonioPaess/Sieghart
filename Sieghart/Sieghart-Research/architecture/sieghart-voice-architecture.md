# Arquitetura proposta de voz para Sieghart

**Estado:** projeto de pesquisa, não implementado. Base: [VoiceInk](../applications/voiceink.md), [HeyClicky](../applications/heyclicky.md), [comparação](../comparisons/voice-comparison.md) e o código de [captura](../../Sieghart/Core/Services/Voice/VoiceCapture.swift)/[ativação](../../Sieghart/Shared/Services/Activation/ActivationController.swift) do Sieghart. Não copiar implementação ou ativos de terceiros.

## 1. Objetivo e fronteiras

Uma entrada por voz deve produzir exatamente um destes resultados: **comando** autorizado e verificado, **texto** entregue ou copiável, ou **resposta conversacional** visível/falada. O usuário escolhe o modo; um classificador de intenção pode sugerir, mas não converte ditado livre em ação mutável sem confirmação. Cada turno tem uma rota de dados declarada (`local`, `Apple on-device`, `provedor remoto identificado`) e geração única para rejeitar callbacks tardios.

```text
hotkey / clique / manter pressionado
        ↓
 VoiceTurnCoordinator ───────→ UI de estado + medidor de entrada
        ↓
 AudioInputPolicy → captura PCM → buffer limitado → provedor ASR → parcial/final
        ↓                                     ↓
 política de endpoint                    métricas/erros
        ↓
 modo: comando | ditado | conversa
        ├─ comando → IntentResolver → contexto mínimo → ActionRegistry → autorização → execução → recibo
        ├─ ditado → formatação local → TextDelivery → inserido / copiado / incerto
        └─ conversa → contexto consentido → agente → resposta visível → TTS → interrupção
```

## 2. Contratos sugeridos

| Componente | Responsabilidade e erro explícito |
| --- | --- |
| `VoiceTurnCoordinator` | Estado do turno, ID, relógio monotônico, cancelamento e transições. Um resultado de ID antigo nunca muda UI, cola texto, fala ou chama ferramenta. |
| `AudioInputPolicy` | Identificar microfone escolhido/efetivo, formato, conexão e mudo; emitir `inputChanged`, `inputLost`, `fallbackUsed`; preparar antes de ouvir e fechar recursos após. |
| `AudioFrameSink` | Callback mínimo, sem disco/IA/UI; buffer finito com contagem de perda e tempo do último frame. Escrita de WAV opcional e com retenção clara. |
| `EndpointPolicy` | Perfis distintos: comando usa silêncio após fala; ditado prefere soltar tecla/concluir explícito; conversa usa fim de turno e permite interrupção. Timeout de silêncio, fala e finalização independentes. |
| `TranscriptionProvider` | Capacidade por locale, disponibilidade offline, streaming, parciais, final, formato PCM, custo e tratamento de cancelamento. Não há fallback remoto implícito. |
| `TextDelivery` | Destino e foco capturados no começo/fim, resultado `inserted` se verificado, `posted` se só tecla enviada, `copied` ou `failed`. Não dar Return automático em terminal. |
| `VoiceResponse` | Texto visível é fonte da resposta; TTS é saída adicional cancelável. *Barge-in* pára fala antes de aceitar nova entrada, com supressão/teste de eco. |
| `VoiceTelemetry` | Tempos de ativação→primeiro frame→primeira parcial→final→inserção→primeiro áudio, drops e razões de falha; sem reter áudio/transcrição sensíveis por padrão. |

## 3. Opções Apple e compatibilidade

- **Captura:** `AVAudioEngine` já funciona para comandos e tem tap de entrada. Para seleção de dispositivo específico ou maior controle de formato, avaliar CoreAudio/AUHAL em protótipo, com ganho medido frente ao caminho atual. A permissão de microfone é pedida no primeiro uso relevante; `NSMicrophoneUsageDescription` e entitlement de entrada quando exigidos. [Apple autorização](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media).
- **Estado das permissões Sieghart:** o projeto já declara `NSMicrophoneUsageDescription`/`NSSpeechRecognitionUsageDescription` nas configurações de build e `com.apple.security.device.audio-input` no entitlement. Validar o **app compilado** para cada configuração antes de assumir que a permissão está efetivamente embutida.
- **Reconhecimento atual:** `SFSpeechRecognizer` já é integrado, com `requiresOnDeviceRecognition=true` somente quando o recognizer afirma suportar. Se não suportar, a cadeia pode exigir rede; a UI não pode prometer offline universal. [Apple autorização Speech](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition).
- **Alternativa nova:** `SpeechAnalyzer`/`SpeechTranscriber` são on-device, têm parciais/finais e recursos dependentes de hardware/locale/modelos instalados. Detectar `isAvailable` e `installedLocales`; disponibilizar download de modelo como ação separada. Medir no macOS mínimo realmente suportado pelo projeto antes de migrar. [WWDC SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/), [API](https://developer.apple.com/documentation/speech/speechtranscriber).
- **VAD:** `SpeechDetector` pode reduzir análise durante silêncio, mas pode omitir fala, e não é por si só endpoint conversacional. Manter detector de atividade e política de fim distintos, com fixtures de ruído/pausas. [Apple VAD](https://developer.apple.com/documentation/speech/speechdetector).
- **TTS:** iniciar com `AVSpeechSynthesizer` para resposta local, selecionar voz/idioma instalados e usar `stopSpeaking(at: .immediate)` para cancelamento. Testar saída muda, fone Bluetooth, troca de saída e interrupção por chamada. [Apple TTS](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer).
- **MLX/CoreML/Whisper:** candidatos a protótipo para ASR local ou pós-processamento, não escolhas assumidas. Comparar idioma, tamanho de modelo, primeira carga, CPU/GPU/ANE, memória, energia e manutenção. Não instalar dependência antes da medição funcional com APIs do sistema.

## 4. Estados e segurança do turno

`idle → preparing → listening → finalizing → {interpreting | formatting} → {authorizing | delivering | responding} → {speaking | completed} → idle`.

Qualquer estado ativo pode ir para `cancelled` ou `failed` com motivo legível. `cancelled` fecha captura, stream, tarefa de ASR, raciocínio pendente e TTS; efeitos externos já iniciados têm recibo próprio e não são falsamente revertidos. `finalizing` aceita apenas resultado final ou política restrita de texto assentado para busca sem efeito, como já faz o caminho de comando atual. Parciais ficam na UI; não executam ferramenta, não enviam mensagem e não entram no histórico final.

## 5. Permissões, dados e retenção

| Recurso | Quando pedir | Dado que pode sair do Mac |
| --- | --- | --- |
| Microfone | Antes da primeira captura | Nada, se ASR e agente forem locais; áudio se provedor remoto for escolhido |
| Speech Recognition legado | Apenas para `SFSpeechRecognizer` | Conforme suporte/rota do serviço Apple; não presumir local sem `supportsOnDeviceRecognition` |
| Accessibility/Automation | Apenas para entrega/ação que prove necessidade | Seleção/estado de outro app pode ser lido localmente; não enviar a agente remoto sem prévia |
| Screen Recording | Só para pedido de contexto visual explícito | Captura/crop se usuário permitir provedor remoto; mostrar escopo antes de enviar |
| Provedor remoto/TTS remoto | Ação explícita para destino nomeado | Áudio, transcrição, contexto ou resposta conforme capacidade selecionada |

Guardar por padrão apenas tempos e códigos de falha sem conteúdo. Ditado final copiado ou histórico opcional deve ter retenção e exclusão claras. WAV temporário precisa prazo e limpeza inclusive após crash; conteúdo contextual nunca entra silenciosamente no prompt.

## 6. Plano de teste de uma implementação futura

1. Criar worktree separado e fixar baseline do Sieghart existente. Testar comandos atuais antes/depois em mic interno, cancelamento, silêncio e finalização; nenhuma ação por parcial.
2. Fixture determinística de PCM para pausa, ruído, fala imediata, voz curta, silêncio e perda de frames. Verificar endpoint, contagem de drops, falha e limpeza de recursos. Não escrever teste que apenas repita a implementação.
3. Teste manual em pt-BR/inglês: cinco repetições de frase neutra em TextEdit e em campo de navegador, com início/primeira parcial/final/inserção cronometrados. Repetir sem rede e com AirPods/interface USB se disponíveis.
4. Trocar/desconectar entrada enquanto prepara, antes da fala e durante a fala; preservar texto final conhecido, declarar captura incompleta e nunca executar comando truncado. Repetir após sleep/wake.
5. Ditado em terminal: nenhuma tecla Return; comparar campo final com frase esperada. Se a inserção não puder ser confirmada, exibir texto para cópia e estado `incerto`.
6. Conversa: começar TTS, falar por cima, verificar que a fala pára e a resposta antiga não reaparece ou dispara ferramenta. Testar saída muda e fone recém-conectado.
7. Comprovante de privacidade: offline deve funcionar sem conexão; seleção de remoto mostra nome/dados antes da transmissão; negada permissão de microfone oferece recuperação sem loop.

Critérios numéricos de latência/energia devem ser estabelecidos **depois** de baseline no Mac alvo, não inferidos de marketing dos aplicativos comparados. Cada alteração futura deve vir com comandos e passos reproduzíveis para o usuário; nesta pesquisa nenhum worktree ou código de produção foi alterado.
