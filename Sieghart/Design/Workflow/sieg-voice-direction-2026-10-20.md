# Direção de voz do Sieg — revisão de 20 de outubro de 2026

## Decisão do usuário

Alex e Santa do Kokoro foram rejeitadas por naturalidade/fluidez. Não reutilizar essas opções como escolha aprovada. O usuário referencia a naturalidade ouvida em tutoriais do OpenJarvis, sem querer reproduzir a voz do Jarvis. Repositório indicado: https://github.com/open-jarvis/OpenJarvis.

Identidade desejada: voz masculina, grave, calma, com humor discreto e identidade própria do Sieg. A qualidade precisa ser avaliada em português brasileiro e em conversa, antes da integração.

## Evidência na referência

Inspeção de fontes primárias em 20 de outubro:

- `src/openjarvis/core/config.py`, `SpeechConfig`: saída configurável, padrão `tts_backend=kokoro`, `voice_id=bm_george`, `voice_speed=1.0`. Esse perfil é inglês britânico. A configuração não prova qual provedor foi usado em um tutorial específico.
- `src/openjarvis/speech/cartesia_tts.py`: adaptador online Cartesia via API, com credencial, modelo e voz configuráveis.
- `src/openjarvis/speech/kokoro_tts.py`: backend local multilíngue com pipelines por idioma e vozes por identificador.

Fontes: [configuração](https://github.com/open-jarvis/OpenJarvis/blob/main/src/openjarvis/core/config.py), [Cartesia](https://github.com/open-jarvis/OpenJarvis/blob/main/src/openjarvis/speech/cartesia_tts.py), [Kokoro](https://github.com/open-jarvis/OpenJarvis/blob/main/src/openjarvis/speech/kokoro_tts.py).

## Próxima seleção recomendada

Avaliar primeiro vozes prontas em português brasileiro de categoria conversacional na ElevenLabs Voice Library; a documentação permite filtrar idioma, variante regional, gênero e categoria. Se nenhuma servir, usar Voice Design para gerar três opções originais a partir da direção abaixo. A qualidade final depende de escuta; não foi gerada nem aprovada uma voz ElevenLabs nesta entrega. São serviços online, com créditos/condições de plano; a API da Voice Library exige plano pago atualmente. Não foi criada conta, assinatura ou cobrança.

Cartesia também é candidata de saída para conversa contínua, com português e biblioteca de vozes. Não se deve adotar uma voz britânica de referência e presumir que a naturalidade se conserva em português.

Fontes: [Voice Library](https://elevenlabs.io/docs/eleven-creative/voices/voice-library), [Voice Design](https://elevenlabs.io/docs/eleven-creative/voices/voice-design), [vozes brasileiras Cartesia](https://www.cartesia.ai/pt/voices).

## Descrição para uma voz original

Native Brazilian Portuguese. Adult male voice. Excellent audio quality.
Persona: warm, witty desktop companion. Emotion: calm, friendly, quietly confident.
A naturally low, smooth, warm voice with relaxed conversational pacing. Connected, fluid speech with subtle changes in emphasis and pitch, and pauses guided by the meaning of each sentence. A gentle smile and understated playfulness suit occasional light humor. Clear pronunciation and an intimate, everyday conversational delivery.

O humor permanece ocasional. Explicações, confirmações e erros devem ser claros e naturais; piadas não são acrescentadas a toda resposta. O grave deve vir do timbre de origem, em vez de depender de desacelerar/pitch-shift intenso depois da geração.

## Nova amostra de comparação

Arquivo: `/Users/antoniopaesdeandrade/.codex/visualizations/2026/10/20/01a156df-70d8-7fa2-b3a9-518f532009ae/vozes-sieg/antonio-neural-conversa.mp3`.

Microsoft `pt-BR-AntonioNeural`, serviço online via `edge-tts 7.3.1`, ritmo -3%, pitch +0 Hz e nenhuma pausa inserida. Apenas frase genérica de apresentação enviada. Catálogo retornou Antonio como voz masculina pt-BR disponível e a geração produziu 68.112 bytes de MP3. A amostra é uma referência adicional de escuta; não é a voz final, não foi aprovada e não está integrada ao app. O cliente de demonstração Edge não foi adotado como dependência de produção.

Nas primeiras amostras Kokoro, o experimento usou velocidade 0,85 e pausas extras de 320 ms por frase; esses parâmetros também afetam a cadência. A rejeição do usuário é preservada, sem atribuir todo o problema a um único modelo ou tentar aprovar as mesmas vozes novamente.

## Integração depois da escolha

Preservar Apple Foundation Models e o fluxo de ferramentas existente. O novo provedor implementa a fronteira de fala `SigVoiceSynthesizing`, recebe texto e entrega áudio com cancelamento/conclusão reais. O modelo da conversa continua separado do sintetizador. Para fluidez, validar streaming contínuo e limites de frases sem lacunas artificiais, início de fala, cancelamento e ausência de bloqueio na interface. Não publicar um adaptador que dependa do ambiente temporário de desenvolvimento.

Critério de aceite: escuta aprovada de uma resposta simples, uma explicação de pi, uma confirmação com duração/números e uma falha de consulta; voz estável em português brasileiro, personalidade moderada e resposta sem cortes ou pausas estranhas. Não há backend neural novo implementado nesta revisão. Nenhum commit/push.
