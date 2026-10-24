# HeyClicky → Sieg: paridade de comportamento

Atualização posterior: [continuação do produto em 21/10](sieg-product-completion-2026-10-21.md)
registra o modo de conversa com interrupção/eco, os seis especialistas dentro
das ferramentas disponíveis, pesquisa com páginas/citações, tarefas retomáveis
e fluxogramas derivados dos passos do algoritmo. A tabela abaixo descreve o
marco anterior; não usar suas pendências como inventário final desta continuação.

Referência pedida pelo usuário em 20/10/2026. Escopo: reproduzir a experiência funcional com a identidade e a arquitetura do Sieg. Preparação para SSC adiada.

## Evidências reaproveitadas

- Dossiê: `/Users/antoniopaesdeandrade/Documents/ChatGPT/MyDude/Sieghart/Sieghart-Research/applications/heyclicky.md`, seções 2, 9, 10, 11, 12 e 16.
- Estudo estático: `Design/Research/hey-assistants-2026-10-11/README.md` e seu `evidence-index.json`. HeyClicky 1.0.53/build 64; análise parcial de pacote e binário, sem recuperação completa de código, prompts ou algoritmos privados.
- `Design/clicky-reference.md` e `Design/Research/herdr-clicky-followup-2026-10-14.md` distinguem proposta, observação e informação do fornecedor.
- Foto do usuário `IMG_6490.HEIC`: cursor normal e marcador azul luminoso próximos. Acompanhamento do mouse e seleção durante a fala foram descritos pelo usuário; movimento não é demonstrável pela foto estática.

Não temos uma reconstrução interna 1:1. Temos um dossiê de produto e evidências suficientes para definir o fluxo; latência, cancelamento remoto, endpointing e implementação exata do cursor ainda não foram estabelecidos pelo REA.

## O fluxo a reproduzir

Pressionar atalho → iniciar uma sessão e feedback de escuta → acompanhar o cursor → deixar o usuário apontar/circular/selecionar → juntar fala e contexto escolhido → soltar encerra a captura → Sieg responde no widget por texto/resultado visual e áudio → anotações orientam sobre o conteúdo real → nova fala interrompe a anterior sem misturar respostas.

Mensagens digitadas permanecem no chat e não produzem áudio. Um efeito pedido explicitamente, como ativar Keep Awake ou desenhar sobre a tela, continua sendo uma ação; sua confirmação digitada pertence ao chat.

## Diferenças do produto atual

| Comportamento | Estado do Sieg | Trabalho restante |
| --- | --- | --- |
| Segurar/soltar para falar | Eventos atrasados de Carbon/monitor ordenados, final do reconhecedor retido até soltar, leitura física de segurança calibrada e com debounce; testes aprovados | Validar combinação física, perda de foco e dispositivos no uso real. A automação de teclas não produziu evidência de início de escuta e não conta como aprovação física. |
| Cursor de escuta acompanhando o mouse | Integrado à sessão, com escuta/pensamento/fala e cancelamento; ciclo isolado testado | Validar acompanhamento físico, múltiplos monitores e perda de foco. |
| Seleção durante a fala | Painel de arrasto/círculo, seleção vinculada ao turno e recorte de pontos para pixels; regressões aprovadas | Validar gesto físico e ergonomia da seleção durante o atalho. Falha ou monitor ausente não pode ampliar a leitura. |
| Ler e traduzir tela real | Captura de frame e OCR local conectados, caixas reais e região selecionada; interpretação local da imagem quando suportada | Validar permissões, janelas, várias telas, seleção e qualidade. OCR não constitui compreensão completa da interface. |
| Diagramas, marcações e código | Plano factual e grafo semântico gerados; layout nativo de fluxo/ciclo/hierarquia, títulos, detalhes e setas; fixar/copiar/fechar | Ensaio real do ciclo da água agora tem quatro etapas e relações legíveis. Ampliar avaliação de qualidade factual e posicionamento. Código é exibido, sem execução pelo overlay. |
| Orientação por etapas | Plano de até cinco passos, alvo ancorado em OCR, verificação após clique, atualização e confirmação manual; testes isolados | Validar interfaces reais e alterações de layout. Não é controle autônomo geral; não inventa coordenadas para alvo ausente. |
| Conversa fluida | Antônio, snapshots progressivos e fila de frases com próximo áudio preparado em paralelo à reprodução; cancelamento isolado aprovado | Validar fluidez, latência, troca de dispositivo e Bluetooth. Supressão de eco e interrupção automática pela voz sem atalho ainda faltam. |
| Idioma | Seleção levada à geração e TTS, clima e controles do app | Validar língua trocada durante uma sessão e os textos residuais de outros comandos. |
| Chat versus voz | Separação implementada e coberta por regressões; clima digitado validado no app | Validar microfone real e todos os artefatos. Texto digitado não aciona TTS nem publica cartão climático no widget; ação sobre a tela continua possível quando explicitamente pedida. |
| Ações do app | Keep Awake e métricas reais, parser validado e ferramenta do modelo; autorização pelo pedido original e recibos idempotentes | Validar voz física. A preservação da sessão na rodada anterior é evidência histórica, não afirmação de que continua ativa. |
| Orquestrador Sieg | Ciclo local de até três ferramentas por turno e encaminhamento de código para Ada | Especialistas além de Ada e tarefas complexas ainda não estão plenamente conectados. Personagens não equivalem a especialistas completos. |
| Memória e continuidade | Histórico textual limitado persistido localmente, contexto recente entre canais e referência visual transitória; limpar contexto disponível | Validar referências ambíguas e implementar tarefas retomáveis. Imagens não são persistidas. |
| Resultados visuais | Clima e cartões de resposta, tela, código, passos, ações e fontes; copiar/fechar/interromper; estados de pensar/falar separados | Validar ergonomia em uso real e acessibilidade. Arte/coreografia aprovadas preservadas. |

Para a paridade do produto inteiro, além do fluxo de voz, ainda entram Home e conversas persistentes, artefatos/arquivos, tarefas dos especialistas, integrações de contas e rotinas com permissão e resultado verificável. Pesquisa de demonstração foi substituída por referências públicas reais com trechos e links; não é pesquisa aprofundada. Ação destrutiva sem backend permanece indisponível, sem confirmação falsa de sucesso.

## Ordem prática inicial (histórico)

1. Estabilizar Keep Awake, pressionar/soltar e separação chat/voz; preservar a sessão de Keep Awake deixada ativa pelo usuário.
2. Completar e validar canvas e captura/interpretação reais sem conteúdo de demonstração fixo.
3. Integrar cursor de sessão e seleção contextual; medir recorte e coordenadas em várias telas.
4. Ligar fala, visão e ferramentas ao mesmo turno do Sieg, com cancelamento e memória.
5. Fechar walkthrough, fluidez de áudio e apresentação de resultados, com ensaios reais e métricas.

Não atribuir porcentagem de paridade sem critérios medidos nem confundir uma fixture aprovada com teste de microfone, visão ou modelo real.

## Validação anterior de 21/10/2026 — build 14

- Build universal normal: `/tmp/sieghart-spatial-product-build-14.log`; assinatura e descrições de privacidade verificadas. Build final aberto no caminho exato de teste, processo 79907 no momento da conferência.
- `/tmp/sieghart-stable-hold-channels-fast-14/verification.json`: 296 funções / 1.040 execuções aprovadas, 160/160 fontes de produção incluídas, nenhuma alteração durante o teste, nenhum teste ausente ou inesperado. A falha anterior de isolamento do renderizador foi corrigida e o teste aguarda a passagem assíncrona da captura para a resposta.
- Serviço meteorológico real consultou Recife/Pernambuco e Bragança/Portugal conservando os qualificadores. No app final, a mensagem digitada de Bragança retornou 10 °C, sensação 7 °C, fonte e horário no chat. Isso não prova o reconhecimento acústico de nomes próprios. A grafia incorreta “bragnaça” ainda não recebe correção fonética.
- O modelo local gerou Two Sum e uma composição geométrica. O código final de ensaio retornou índices e passou em cinco casos. Não há garantia de correção de qualquer código gerado; o desenho do ciclo da água evidenciou qualidade semântica insuficiente.
- A sessão de Keep Awake foi transferida ao novo build com o mesmo `end`, continuou com a asserção real de energia e voltou a `restoreOnLaunch = false`, como antes da atualização.

## Continuação de 21/10/2026 — experiência integrada

A tabela acima foi atualizada para a implementação de cursor, seleção, diagramas,
orientação, áudio progressivo, ferramentas e cartões. Evidências e limites estão
em [sieg-integrated-experience-2026-10-21.md](sieg-integrated-experience-2026-10-21.md).
A suíte final 22 aprovou 310 funções e 1.060 execuções; build universal 23 aprovado,
com assinatura/metadados verificados. O usuário está na faculdade:
nenhum microfone, som ou teste físico foi iniciado nesta continuação. Validação
com AirPods continua pendente. Não houve commit/push nem trabalho de embalagem SSC.
