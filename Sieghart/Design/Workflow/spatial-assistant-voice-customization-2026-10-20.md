# Personalização da voz — 20 de outubro de 2026

## Pedido

Voz masculina, mais grave e calma, natural como referência de estilo, com humor leve. O usuário perguntou por vozes prontas; não pediu clonagem de uma pessoa específica.

## Implementado no worktree espacial

- `SigVoiceConfiguration`: identificador da voz, tom, velocidade, volume e ativação; normalização de valores e persistência em preferências próprias do app.
- `SigVoiceCatalog`: enumera vozes realmente disponíveis, remove vozes de efeitos/novidade e respeita a escolha. A seleção automática procura opções masculinas em português antes do fallback do sistema.
- `SigVoiceSynthesizer`: elimina a elevação duplicada (antigo +500 cents no grafo e 1,15 no utterance). O tom agora é aplicado apenas no grafo; o padrão é -100 cents, velocidade 94% do padrão nativo e volume 85%. Desativar áudio interrompe a fala em andamento.
- `CompanionPreferences` e `NotchWidgetViewModel`: ajustes persistidos chegam ao sintetizador usado pelas respostas reais, inclusive depois de relançar o app.
- `WorkspaceView`: cartão **Voz do Sieg** no início de **Activation**, com seleção, tom, velocidade, volume, ouvir/parar prévia e restaurar padrão. A prévia usa uma instância própria e não inicia microfone. Ao sair da seção, para a prévia.
- `AppleVoiceGeneration`: conversa calma e calorosa, permitindo humor breve quando apropriado, sem forçar piadas em erros ou assuntos sensíveis. Os resultados de ferramentas continuam determinísticos.

Foram preservados a cópia de PCM antes de sair do callback, o roteamento de formatos, os identificadores de cancelamento e a conclusão após a drenagem do áudio, introduzidos na correção de crash anterior.

## Validação

Plano rápido final: `/tmp/sieghart-voice-customization-final-fast-20261020/verification.json`.

**272 funções / 1.008 invocações aprovadas; cobertura das 153/153 fontes esperadas; sem fontes alteradas durante a execução, testes ausentes ou inesperados.** Inclui persistência entre instâncias, aplicação ao sintetizador vivo, desativação durante a fala, recuperação de preferências inválidas e regressões PCM/formato/cancelamento existentes.

Build universal Debug assinado: `/tmp/sieghart-voice-customization-final-build.log`, `BUILD SUCCEEDED`. `Tests/verify-built-app.sh` aprovou assinatura, metadados de agente e descrições de privacidade.

Teste real de interface no build espacial:

- O seletor ofereceu as vozes instaladas; Reed pt-BR foi selecionada e reapareceu após relançar.
- **Ouvir prévia** mudou para **Parar prévia**; parar e restaurar padrão retornaram ao estado inicial.
- Sliders aplicaram velocidade 0,43 (86%) e tom -150 cents, e uma segunda prévia iniciou com esses valores.
- A segunda prévia terminou sozinha: o botão retornou a **Ouvir prévia**, sem intervenção.
- A interface foi inspecionada visualmente: cartão completo e controles legíveis no início dos ajustes.
- Antes de reiniciar, Keep Awake estava desativado na interface e não havia assertion do Sieghart em `pmset`; não se iniciou outra sessão de Keep Awake.

Não houve novo teste por microfone nem avaliação independente nesta entrega. Naturalidade/timbre dependem da escuta do usuário.

## Vozes prontas avaliadas

**Atualização do usuário:** Alex e Santa foram rejeitadas por naturalidade. A direção atual e a investigação do OpenJarvis estão em `sieg-voice-direction-2026-10-20.md`. Nenhuma das duas está aprovada para integração.

O identificador Nando apareceu no catálogo de um processo interpretado de desenvolvimento, mas não foi construído no executável compilado nem oferecido pelo app assinado. Não é anunciado como voz funcionando no produto.

Foram geradas duas amostras locais dos perfis masculinos brasileiros **pm_alex** e **pm_santa** do Kokoro v1.0 int8, com `kokoro-onnx 0.6.1`, velocidade 0,85 e pausa de 320 ms entre frases. Áudios e manifesto: `/Users/antoniopaesdeandrade/.codex/visualizations/2026/10/20/01a156df-70d8-7fa2-b3a9-518f532009ae/vozes-sieg/`.

As amostras têm aproximadamente 12 segundos cada e foram apresentadas para escolha. Modelo/runtime de avaliação ficam fora do app. **Kokoro ainda não está integrado ao produto**; a entrega distribuível precisa de empacotamento, licenças e validação de desempenho/cancelamento. Nenhuma assinatura ou conta paga foi criada.

Fontes primárias: [catálogo de vozes](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md), [modelo/licença](https://huggingface.co/hexgrad/Kokoro-82M), [runtime de avaliação](https://github.com/thewh1teagle/kokoro-onnx).

A proposta de coordenação do principal e evolução das ferramentas está em `sieg-orquestracao-voz-ferramentas-2026-10-20.md`. Sem commit, push, nova sprint ou agentes paralelos.
