# Sieg: voz, idioma, atalho e resultados visuais — 20/10/2026

## Escopo autorizado

Foco no produto. A preparação e o recorte para o Swift Student Challenge ficam para depois, conforme instrução do usuário. Trabalho no worktree `sieghart-spatial-assistant`, sem commit ou push e sem alterar o checkout principal.

## Implementação

- Antônio (`pt-BR-AntonioNeural`) é a voz temporária do Sieg em português. A variante masculina em inglês acompanha a seleção de idioma. A interface não oferece inventário de vozes do macOS nem ajuste de tom; mantém áudio ligado/desligado, velocidade, volume, prévia e restauração.
- Transporte e reprodução nativos em Swift; nenhum Python, ambiente de desenvolvimento ou biblioteca baixada é necessário no app. Texto escapado para SSML, mensagens limitadas, resposta binária validada, conexão efêmera e cancelamento com identificação da resposta. O término acompanha o áudio reproduzido; resultados antigos não reiniciam a fala. Falha na voz online usa voz local compatível com o idioma.
- Atalho global de voz escuta enquanto a combinação está pressionada e encerra ao soltar. Carbon e monitor de teclado recebem soltura. Pausas e finais intermediários não executam a ação durante a pressão; limites de duração/perda de entrada continuam ativos. Soltar durante preparação cancela a abertura tardia do microfone. O botão continua disponível com encerramento por silêncio.
- O idioma escolhido governa a geração da resposta, voz, clima, confirmações de Keep Awake e informações do computador. A instrução ao modelo prevalece sobre o idioma de turnos anteriores. Traduções podem produzir texto no idioma alvo pedido.
- Clima retorna observação estruturada com localização, temperatura, sensação, horário/fuso e código meteorológico da Open-Meteo. O widget exibe cartão com símbolo da condição, cor, animação discreta e respeito a movimento reduzido. A janela cresce para o cartão, que pode ser fechado. Novo pedido não conserva dados de uma consulta antiga.
- Leitura da tela agora captura um frame real com ScreenCaptureKit, excluindo janelas do próprio app, e executa OCR local com Vision fora do ator principal. Não há imagem salva ou enviada a um modelo remoto. Tradução/explicação usa o texto reconhecido como dados na geração local. Permissão ausente, falha de captura e cancelamento não são apresentados como leitura bem-sucedida.

O texto efetivamente falado é enviado ao serviço de voz online. Isso também pode incluir texto lido da tela quando o usuário pede sua leitura. O mecanismo online atual usa o protocolo Read Aloud e não constitui uma integração contratada com garantia de disponibilidade. Para distribuição estável, substituir por um serviço oficial ou modelo local com licença adequada, preservando a interface `NeuralSpeechProviding`.

## Validação

- Build normal otimizado e universal: `/tmp/sieghart-antonio-product-build-4.log` — `BUILD SUCCEEDED`.
- Verificação do app: descrições de privacidade, metadados de agente de menu e assinatura aprovados por `Tests/verify-built-app.sh`.
- Suíte rápida: `/tmp/sieghart-antonio-product-final-fast-5/verification.json` — 285 funções e 1.021 execuções aprovadas; 156/156 fontes de produção incluídas; nenhum fonte alterado durante a execução; nenhum teste ausente ou inesperado.
- Regressões novas: checksum/framing/XML, limites de mensagens, reprodução e cancelamento, callbacks antigos, pressionar/soltar e preparação, limites da escuta, idioma com histórico em português, condições reais do clima, ciclo do cartão, OCR de pixels reais, permissão negada, tradução e captura cancelada.
- Transporte nativo consultado de verdade para português e inglês: `/tmp/sieghart-native-antonio.mp3` e `/tmp/sieghart-native-english.mp3`. Não são apenas mocks.
- Build atualizado aberto. Na interface, lista de vozes e controle de tom ausentes; velocidade em 97% e volume preservado em 85%. Prévia iniciou e retornou a “Ouvir prévia”, sem mensagem de fallback.
- Testes de captura usam imagem conhecida e adaptadores isolados. Eles não substituem falar ao microfone e testar o atalho físico no computador do usuário.

## Próximo trabalho para aproximar a experiência do HeyClicky

1. Conversa com início de áudio mais rápido: gerar e reproduzir por trechos, interrupção pela voz do usuário, cancelamento imediato, supressão de eco e rotas Bluetooth/dispositivo testadas. Antônio melhora a qualidade da voz; a resposta ainda espera o texto e o MP3 da vez.
2. Um ciclo do Sieg que escolhe e executa ferramentas reais, acompanha seu resultado e encaminha aos especialistas aprovados. Hoje ainda existe roteamento por intenções e expressões; memória e histórico de voz não formam uma única conversa com o chat.
3. Contexto visual além de OCR: seleção/região/janela, interpretação de imagens e interfaces, tradução com retorno visual e orientação passo a passo. A leitura atual é de texto reconhecido, não compreensão geral de qualquer conteúdo visual. Revisar também anotação em múltiplos monitores.
4. Design coeso para escuta, preparação, pensamento, fala, conclusão e falha; resultados próprios para tradução, ações e pesquisa; acessibilidade e animações consistentes. Preservar os seis personagens aprovados e atribuir as vozes dos especialistas somente após escolha do usuário.
5. Completar pesquisa genérica real e ações ainda representadas por protótipos. Em particular, o artefato de pesquisa offline é genérico e a confirmação de ação destrutiva existente não realiza a operação. Não apresentar esses caminhos como capacidades prontas; concluir seus contratos e validação antes de liberá-los.
6. Estabilização: atrasos da primeira chamada de OCR/modelo local, cancelamento entre tarefas, testes de microfone real/atalho global, permissão negada, mudanças de entrada/saída, retomada após repouso e duração dos overlays.

## Referências e proveniência

- [Apple: SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager) e [captura de imagem](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(contentfilter:configuration:completionhandler:)).
- [Open-Meteo: condições e códigos WMO](https://open-meteo.com/en/docs). As temperaturas atuais são estimativas de modelo; o cartão identifica fonte e horário.
- [edge-tts](https://github.com/rany2/edge-tts) e [mudança de protocolo em outubro](https://github.com/rany2/edge-tts/issues/490). Compatibilidade conferida com edge-tts 7.3.1 e msedge-tts 0.4.1. O código Swift de checksum foi escrito para o app com vetores independentes; não foi vendorizado o runtime Python nem o código desenrolado da biblioteca. Manter auditoria de proveniência antes da distribuição.
- [OpenJarvis](https://github.com/open-jarvis/OpenJarvis): referência de naturalidade citada pelo usuário; não foi copiada uma identidade vocal do Jarvis.
- [HeyClicky: histórico de recursos](https://www.heyclicky.com/changelog): referência de experiência. O plano acima descreve lacunas verificadas no nosso código e não uma declaração de paridade.

## Continuação — 21/10/2026

### Correções e capacidades adicionais

- Caso real “Ative o Kepa Wake por 2h00”: normalização do nome da ferramenta observado no ASR e duração `hmm`, com validação de minutos. O teste atravessa reconhecimento, controlador de ativação e o backend isolado de energia; resulta em 7.200 segundos e uma única aquisição, sem ir ao modelo de linguagem.
- Pressionar/soltar: ordenação por tempo de evento entre Carbon e monitor; solturas antigas não encerram uma sessão mais nova e pressões atrasadas não reabrem o microfone. O erro de encerramento do reconhecedor após texto final não cancela a frase enquanto a tecla continua segura. O monitor físico só atua depois de observar a tecla realmente pressionada e exige três leituras de soltura; ausência de permissão/leitura inicial não encerra a captura.
- Entrada digitada cancela a fala anterior e devolve texto no chat, sem TTS. Clima digitado não publica observação no widget. Leitura digitada da tela usa o inspetor e responde no chat. Desenho/código explicitamente pedido sobre a tela mantém o efeito visual, com confirmação silenciosa. Pesquisa preserva o canal de origem.
- Geocodificação conserva estado/país e tenta separação por vírgula de nomes compostos. Consultas reais sem pontuação de Recife/Pernambuco e Bragança/Portugal foram resolvidas pelo serviço nativo. Isso não implementa correção de todo erro fonético do reconhecimento.
- `GeneratedCanvas` valida geometria normalizada, limites de pontos/texto e códigos de até 64 linhas. O serviço local gera composição e código a partir do pedido; não existe uma implementação de Two Sum ou catálogo de assuntos embutido. Código recebe um cartão monoespaçado e explicação; não é executado. A interpretação da captura real usa attachment de imagem quando o modelo local suporta visão; sem isso, usa OCR.

### Evidência final desta rodada

- `/tmp/sieghart-stable-hold-channels-fast-14/verification.json`: 296 funções e 1.040 execuções aprovadas; 160/160 fontes de produção, sem mudanças durante execução, sem testes ausentes/inesperados.
- `/tmp/sieghart-spatial-product-build-14.log`: build normal universal aprovado. `Tests/verify-built-app.sh` aprovou assinatura, privacidade e metadados. Build final aberto no caminho de teste; PID 79907 no momento da conferência.
- `/tmp/sieghart-generated-two-sum.swift`: saída real do modelo local, revisada e executada em cinco casos públicos (índices, duplicatas, negativos e ausência de par), todos aprovados. Um ensaio anterior retornava valores; a instrução genérica de contrato de entrada/saída foi corrigida, sem inserir solução específica.
- No chat do app final, a pergunta digitada “Qual a temperatura de Bragança, Portugal agora?” retornou observação real: 10 graus, sensação de 7, fonte Open-Meteo e horário local. O pedido explícito de Two Sum na tela também atravessou a geração local e entregou a explicação no chat. A captura CUA da janela principal não serve como prova de visibilidade do painel de overlay sobre outras janelas.
- Keep Awake ativo preservado durante atualização: o `end` salvo antes/depois é idêntico, a asserção real de energia está no novo processo e a preferência temporária de restauração voltou ao valor original `false`.

### Limites que permanecem

- O teste de atalho por automação não produziu mudança observável na interface; não conta como aprovação da combinação física. Ficam pendentes fala real, teclas físicas, troca de microfone e Bluetooth.
- Um desenho gerado do ciclo da água tinha formas válidas, mas pouco conteúdo semântico. A geração precisa de planejamento e layout melhores antes de ser tratada como paridade com o Clicky.
- Cursor acompanhando o mouse, seleção/lasso durante a fala, walkthrough por alvos reais e conversa com áudio em streaming ainda faltam.
- A integração de visão exige ensaios com imagens reais, qualidade, posicionamento e múltiplos monitores; modelo/OCR podem ter inicialização lenta.
- O inventário completo e a origem das evidências estão em `Design/Workflow/heyclicky-behavior-gap-2026-10-20.md`. Não há declaração de paridade 1:1 nem de produto 100% concluído.

## Atualização posterior — experiência integrada de 21/10/2026

Os limites acima descrevem o build 14. Depois dele foram implementados cursor de
sessão, seleção de região, diagramas semânticos com layout nativo, orientação
ancorada em OCR, fila progressiva de fala, ferramentas reais do Sieg, contexto
curto compartilhado e cartões de resposta. A pesquisa de demonstração foi
substituída por fontes públicas com links; operações destrutivas sem backend
deixaram de aparentar sucesso.

O relatório [sieg-integrated-experience-2026-10-21.md](sieg-integrated-experience-2026-10-21.md)
registra a implementação, evidência atual e limites. Suíte final 22: 310 funções e
1.060 execuções aprovadas; build universal 23 e verificação do app aprovados.
O usuário pediu silêncio por estar na faculdade;
esta continuação não abriu microfone, tocou voz ou iniciou o app. Ainda faltam
os ensaios físicos de voz/atalho/AirPods, supressão de eco, interrupção automática
pela fala e conexão completa dos demais especialistas. Não declarar paridade 1:1.
