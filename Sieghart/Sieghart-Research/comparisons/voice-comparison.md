# VoiceInk × HeyClicky × Sieghart — áudio e voz

**Data:** 13–14/10/2026. **Fontes:** [VoiceInk (código público)](../applications/voiceink.md), [HeyClicky (site, pacote 1.0.53, UI e relatos de teste)](../applications/heyclicky.md), [Sieghart atual](../../Sieghart/Core/Services/Voice/VoiceCapture.swift). O usuário concluiu três ensaios neutros no HeyClicky: ditado, interrupção da fala e troca de microfone. Comparações de latência e energia **não foram medidas**.

## O que cada fluxo faz

| Fluxo | VoiceInk para Mac | HeyClicky | Sieghart atual | Direção proposta |
| --- | --- | --- | --- | --- |
| Comando curto | Ditado/assistente com modos; não foi estudado como executor de comandos macOS genéricos | Pergunta/ação por voz, segundo fornecedor | `NativeVoiceCapture` → `VoiceCommandSession` → parser determinístico de busca/app/timer | Manter caminho curto com resultado final e autorização de ações |
| Ditado em outro app | Pipeline completo de gravação, transcrição, pós-processamento e entrega | Streaming/colagem anunciados; uma frase neutra completa no TextEdit, segundo usuário | Não há fluxo geral de ditado com entrega em outro app | Criar sessão própria de ditado e entrega verificável |
| Conversa falada | Assistant/follow-ups existem no código, mas não serviram aqui de benchmark de TTS | Conversa e *barge-in* anunciados; usuário relatou interrupção limpa e nova resposta sem mistura | UI de comando, sem ciclo conversacional completo de TTS/interrupção | Turno com estados, resposta visível e TTS cancelável |
| Microfone | Seleção, preferência e fallback no código público | Fallback anunciado; usuário trocou de mic durante ditado e relatou as duas partes completas | Usa entrada do `AVAudioEngine` e tenta recuperação uma vez **antes** da fala | Política comum de rota, preservar texto confirmado, testar troca real |
| Endpoint | Streaming/batch; VAD de um provedor segmenta ASR, sem prova de fim automático do ditado | Algoritmo interno desconhecido | Silêncio 1,4 s após detectar fala; sem fala 12 s; perda de entrada 3 s; máximo 55 s; drain final 4–6 s | Perfis por comando, ditado e conversa; VAD não substitui intenção de término |
| Privacidade | Local por opção, mas provedores remotos e aprimoramento configuráveis | Política informa voz/captura via proxy e provedores de nuvem | `SFSpeechRecognizer` exige permissão; `requiresOnDeviceRecognition` só se suportado | Indicar rota por turno e bloquear fallback remoto silencioso |
| Comprovação | Fonte pública; release e `main` diferentes; app local inicial era iOS | Pacote/REA, UI/capturas e três relatos do usuário; código interno fechado | Código local inspecionado, sem medições novas nesta pesquisa | Medir tudo no Mac alvo antes da escolha final |

## Critérios pedidos para a escolha do motor

| Critério | VoiceInk | HeyClicky | Decisão provisória para Sieghart |
| --- | --- | --- | --- |
| Latência | Streaming/parciais no código; valor real não medido | O fornecedor anuncia cerca de 450 ms para texto em streaming de ditado; não reproduzido aqui | Medir início, primeira parcial, final e entrega separadamente; não adotar meta de marketing |
| Privacidade | Depende de modelo/provedor e aprimoramento escolhidos | Política publicada descreve proxy/nuvem para conteúdo | Local por padrão, rota e conteúdo externo consentidos por função |
| CPU, memória, energia | Dependem de modelo local e preparação; não medidos | Não medidos; app fechado impede atribuir custo a componentes | Baseline ocioso/ouvindo/ASR/TTS no mesmo Mac; escolher por resultado medido |
| Idiomas | Disponibilidade depende do provedor/modelo selecionado; testar pt-BR e inglês | Changelog anuncia mais de 50 idiomas e detecção automática | Sieghart atual oferece `pt_BR` e `en_US` para comandos; ampliar só após teste do provedor |
| Complexidade de integração | Muitos provedores e pipeline completo; copiar fonte GPL não é opção trivial | Produto fechado e com conta/nuvem; serve como referência de UX | Reusar contratos próprios e APIs Apple; prototipar um provedor local antes de multiprovedor |

## Conclusões técnicas

1. **Sieghart já resolve parte do problema.** [`VoiceCapture.swift`](../../Sieghart/Core/Services/Voice/VoiceCapture.swift) tem medição de nível, piso de ruído, silêncio, timeout, resultado final, cancelamento com generation ID e separação `finish`/`cancel`. [`ActivationController.swift`](../../Sieghart/Shared/Services/Activation/ActivationController.swift) integra isso com ação. Não há razão para reescrever essa parte só porque outro app oferece voz.
2. **Ditado é outro contrato.** Texto parcial pode mudar; inseri-lo repetidamente em outro app pode duplicar frases. O final precisa de destino/foco, confirmação de entrega e política de clipboard. Um comando de app/timer não deve executar por transcrição parcial.
3. **Conversa adiciona saída e interrupção.** O turno precisa controlar TTS e descartar resultados de geração antiga. `AVSpeechSynthesizer.stopSpeaking(at:)` oferece parada, mas *barge-in* exige teste de eco e coexistência de captura/reprodução. [Apple TTS](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/stopspeaking%28at%3A%29).
4. **VAD não é uma única solução para fim de fala.** `SpeechDetector` Apple pode poupar processamento durante silêncio e adverte sobre perda de fala sob sensibilidade alta; sua sequência de resultados padrão nem fornece eventos momento a momento. Política de endpoint deve continuar explícita. [Apple SpeechDetector](https://developer.apple.com/documentation/speech/speechdetector), [configuração](https://developer.apple.com/documentation/speech/speechdetector/init%28detectionoptions%3Areportresults%3A%29).
5. **A rota importa tanto quanto o modelo.** Apple informa que módulos de `SpeechAnalyzer` não enviam áudio à Apple; o caminho `SFSpeechRecognizer` requer autorização e pode usar servidores conforme configuração/suporte. VoiceInk tem provedores locais/remotos; HeyClicky publica envio remoto. Não usar a palavra “local” para uma cadeia que envia texto para aprimoramento sem mostrar isso. [Apple](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition), [VoiceInk](https://tryvoiceink.com/), [HeyClicky](https://www.heyclicky.com/privacy-policy).

## Prioridade de produto

| Ordem | Entrega original | Critério para avançar |
| --- | --- | --- |
| 1 | Inventário e ensaio do fluxo de comando atual | Nenhuma ação por parcial; cancelamento e silêncio previsíveis com mic interno e fone |
| 2 | Ditado **local** com copiar/inserir, modo de término explícito | pt-BR/inglês, sem rede, campo comum/terminal, conteúdo íntegro, clipboard preservado |
| 3 | Streaming parcial e perfis de endpoint | Texto final sem duplicação após correção, atraso medido, recuperação de mudança de entrada |
| 4 | Resposta falada e interrupção | TTS pára, nova fala não capta eco como comando, turno velho não atua |
| 5 | Contexto selecionado e provedor remoto opcional | Prévia do contexto/rota, autorização por destino e medição do valor real |

A implementação dessas etapas **não começou** nesta pesquisa. Em implementação futura, abrir um worktree separado do checkout do outro chat e entregar roteiro de teste com cada mudança.
