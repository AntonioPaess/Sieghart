# Spatial Assistant — triângulo, rótulo e crash

Entrega local de 19/10/2026, exclusivamente na worktree `sieghart-spatial-assistant`, branch `feature/sieghart-spatial-assistant`. Sem commit, push, merge ou avanço de sprint.

## Evidência do problema

- O relatório `Sieghart-2026-10-19-215211.ips` mostra `EXC_BAD_ACCESS` na verificação de executor de `MainActor.assumeIsolated`, chamada pelo timer de `CompanionRenderView`. Isso não comprova corrupção por captura fraca.
- A primeira reprodução desta sessão voltou a encerrar o app. O relatório `Sieghart-2026-10-19-222924.ips` mostra a mesma verificação de executor, desta vez dentro de `SwiftUI.TooltipBridge`.
- A reprodução sob LLDB registrou uma exceção anterior e concreta em `SigVoiceSynthesizer`: `_outputFormat.channelCount == buffer.format.channelCount`, ao agendar a fala. O grafo usava formato implícito, diferente do buffer sintetizado. Essa exceção foi corrigida; não se afirma que os dois relatórios, isoladamente, provam uma única causa de corrupção.
- A [documentação da Apple para AVAudioPlayerNode](https://developer.apple.com/documentation/avfaudio/avaudioplayernode) descreve as exigências de canais e taxa de amostragem ao reproduzir buffers.

## Alterações

- `CompanionRenderer.swift`: troca do `assumeIsolated` do timer por tarefa no MainActor; descarte de callbacks de uma janela anterior; invalidação do timer e remoção de observadores ao parar, desanexar e destruir a view.
- `VectorDrawingInterpreter.swift`: triângulo simples e retângulo, reconhecimento de hipotenusa/catetos em português e inglês, marca de ângulo reto e posicionamento do rótulo junto à diagonal. Pedidos desconhecidos retornam ao chat, sem fallback para foguete.
- `SpatialCanvasOverlay.swift` e `SpatialOverlayViewModel.swift`: rótulo neon revelado após o tempo do traçado, com cancelamento quando o desenho é substituído.
- `SpatialAssistantCoordinator.swift`: resposta do chat identifica o triângulo retângulo e a Hipotenusa.
- `SigVoiceSynthesizer.swift`: grafo criado com o formato do primeiro buffer; conversão de saída pelo mixer; cópia dos bytes antes da transferência assíncrona; consumo ordenado por AsyncStream; callbacks associados à fala correta; conclusão somente após síntese e reprodução terminarem. Pitch de +500 cents preservado.
- Testes: linguagem, geometria e rótulo, integração do comando exato com o chat, propriedade dos bytes PCM, reprodução nativa offline mono/estéreo e ciclo de vida real do renderizador.

## Validação executada

- Build Debug universal aprovado, com assinatura local ad-hoc preservada. `verify-built-app.sh` passou; o entitlement assinado `com.apple.security.device.audio-input` foi conferido.
- Fast: **248 funções / 964 invocações aprovadas**. Nenhum teste ausente ou inesperado, nenhuma fonte alterada durante a execução. As 151 fontes de produção esperadas constam no relatório de cobertura; isso não significa 100% das linhas cobertas.
- Complete focado: **1 função / 1 invocação aprovada**, `CompanionRasterLifecycleTests/renderViewWindowLifecycle()`, com timer real, troca de janela, callback antigo e liberação da view.
- O comando exato foi enviado três vezes no build final, na mesma instância, incluindo pedidos consecutivos. O chat confirmou triângulo retângulo e Hipotenusa; o processo permaneceu ativo após desenho, fala e desaparecimento do overlay. Não reapareceu a exceção de incompatibilidade de canais no intervalo observado. A geometria e o posicionamento do rótulo foram verificados pelos testes; as capturas da automação mostram a janela principal, sem uma captura independente do painel transparente.
- A comparação dos manifestos com o Fast anterior confirmou somente as oito fontes listadas nesta correção. Alterações anteriores de outros chats foram preservadas.

O projeto original em Documents ficou aguardando `NSFileCoordinator`, e fontes/ferramentas estavam marcadas como `dataless` pelo iCloud. Foram solicitados downloads somente da worktree, sem mudar permissões ou contas. O build aprovado usou o projeto temporário já adotado pelo runner em `/tmp/sieghart-spatial-dd/SourceWorkspace`, atualizado com o projeto atual e com fontes e Info.plist ligados à worktree real:

```sh
xcodebuild -project /tmp/sieghart-spatial-dd/SourceWorkspace/Sieghart.xcodeproj -scheme Sieghart -configuration Debug -derivedDataPath /tmp/sieghart-spatial-dd build
bash Tests/verify-built-app.sh /tmp/sieghart-spatial-dd/Build/Products/Debug/Sieghart.app
bash Tests/run-swift-tests.sh --plan fast --derived-data /tmp/sieghart-spatial-dd --output /tmp/sieghart-spatial-fix-fast-final
bash Tests/run-swift-tests.sh --only 'MacContractsTests/CompanionRasterLifecycleTests/renderViewWindowLifecycle()' --derived-data /tmp/sieghart-spatial-dd --output /tmp/sieghart-spatial-fix-native
```

Evidências locais: `/tmp/sieghart-spatial-fix-build.log`, `/tmp/sieghart-spatial-fix-signature.txt`, `/tmp/sieghart-spatial-fix-fast-final/verification.json`, `/tmp/sieghart-spatial-fix-native/verification.json` e `/tmp/sieghart-spatial-fix-lldb.log` (reprodução anterior à correção de áudio).

## Reprodução para o usuário

1. O build final está aberto na Ada Room. Para abri-lo novamente sem encerrar outras instâncias: `open -n /tmp/sieghart-spatial-dd/Build/Products/Debug/Sieghart.app`.
2. Enviar exatamente: **Desenha um triangulo e escreve a hipotenusa**.
3. Conferir triângulo retângulo, ângulo reto, palavra **Hipotenusa** junto à diagonal, voz do Sig e desaparecimento suave. Repetir o pedido antes de a fala anterior terminar; o app deve continuar aberto.

Nenhuma instância de outra frente foi encerrada. Os reinícios atingiram somente processos identificados do executável desta entrega.
