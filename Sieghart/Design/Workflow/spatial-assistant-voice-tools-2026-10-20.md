# Voz: ferramentas do app, informações do Mac e clima

Implementado no worktree `sieghart-spatial-assistant`, sem commit ou push.

## Comportamento

- “Ativa o Keep Awake por 2 hrs” chama o controle existente do app com duração de 120 minutos. A confirmação falada distingue ativação real, espera por condições configuradas e falha de energia. “Desativa o Keep Awake” libera o controle. As condições que o usuário configurou são preservadas.
- Perguntas sobre memória, bateria, armazenamento, processador, macOS e estado térmico consultam o monitor do app e informações locais do sistema. Valores e sensores indisponíveis não são inventados.
- Pedidos para abrir os controles de Keep Awake, monitor, áudio, calendário, arquivos e área de transferência usam as telas internas do app.
- Perguntas de clima com uma cidade usam geocodificação e condições atuais da Open-Meteo. A fala identifica o lugar resolvido, a fonte e o horário. Sem cidade, pede a cidade; sem conexão ou com dados inválidos, informa a falha. Não abre o Google nem pede ao modelo para inventar a temperatura. Datas futuras não são apresentadas como condições atuais.
- O desenho com explicação desaparece 1,2 segundo após a conclusão real da reprodução de áudio. O limite de 60 segundos permanece como proteção. Cancelar ou substituir a resposta invalida a conclusão antiga.
- Preparação, disponibilidade, tokenização e geração do modelo de voz agora ocorrem em um actor próprio, fora do fluxo da interface. Respostas são limitadas a 256 tokens; a espera tem limite de 30 segundos para não deixar o carregamento permanente.

## Evidências

- Primeira suíte completa Fast: 268 funções e 998 invocações aprovadas, sem fontes alterados durante a execução, com 153/153 fontes esperados na cobertura. Resultado em `/tmp/sieghart-voice-tools-fast/verification.json`.
- Suíte Fast final, incluindo proteção de sensação térmica extrema e fuso inválido: 268 funções e 1.000 invocações aprovadas; nenhum teste ausente/inesperado ou fonte alterado durante a execução; cobertura de 153/153 fontes. Resultado em `/tmp/sieghart-voice-tools-final-fast/verification.json`.
- O serviço de clima de produção foi compilado em um harness isolado e consultou os dois serviços reais. Retornou Recife, Pernambuco, Brasil, temperatura e sensação térmica, com fonte e horário local. Registro em `/tmp/sieghart-weather-probe.log`.
- O código do actor de geração foi executado com o modelo Apple real em um harness isolado: resposta sobre pi em 2,792 segundos, com 26 atualizações de 100 ms no actor principal durante a espera. Isso verifica responsividade da geração; não substitui a inspeção visual do indicador no app.
- Build assinado aprovado; `Tests/verify-built-app.sh` aprovado. Build em `/tmp/sieghart-spatial-dd/Build/Products/Debug/Sieghart.app`.
- O usuário confirmou no teste anterior que o pedido composto desenhou a circunferência e explicou pi por áudio. A confirmação física dos novos comandos de Keep Awake e clima foi solicitada no app atualizado.

## Fontes da integração

- [Open-Meteo: geocodificação](https://open-meteo.com/en/docs/geocoding-api)
- [Open-Meteo: condições atuais](https://open-meteo.com/en/docs)

A consulta é feita apenas por pedido de clima. Nenhuma chave, conta, permissão de localização ou navegação automática foi adicionada.

## Ajustes após o teste real

O usuário relatou que o pedido de Keep Awake caiu no modelo de conversa e que o clima falhou. O log do app confirmou uma falha de conexão por tempo esgotado (`NSURLErrorDomain -1001`). Foi adicionada uma única nova tentativa para falhas transitórias, preservando o limite geral de espera.

O parser passou a aceitar “você consegue”, “tu consegue”, “será que você pode”, “pra mim”, “por favor” e a segmentação “keep a wake”. O reconhecedor recebeu os nomes das ferramentas como vocabulário contextual. A consulta de cidade remove “nesse exato momento” e equivalentes do nome enviado à geocodificação.

Os controles e informações também foram ligados à conversa escrita, reutilizando as mesmas ações validadas da voz. Isso permite conferir a ação real na interface sem acrescentar um atalho de depuração ao produto.

- Fast final: 270 funções e 1.006 invocações aprovadas; 153/153 fontes esperados na cobertura, sem fontes alterados durante a execução. Evidência em `/tmp/sieghart-voice-tools-real-phrases-fast/verification.json`.
- Build normal assinado aprovado, com verificação de integridade aprovada. Log em `/tmp/sieghart-voice-tools-real-phrases-build.log`.
- Teste pela UI real: “Tu consegue ativar o Keep Awake por duas horas?” recebeu confirmação de 120 minutos. A tela de Keep Awake mostrou `Mac stays awake; display may sleep`, botão `Stop` e contagem `1:59:56`. O pedido foi deixado ativo, conforme a duração solicitada.
- `pmset -g assertions` confirmou a assertion `PreventUserIdleSystemSleep` criada pelo processo espacial `Sieghart` (PID 52359), com o nome de pedido de Keep Awake do app.
- A pergunta “Tu consegue me dizer a temperatura de Recife nesse exato momento?” retornou na UI real a localização Recife/Pernambuco/Brasil, temperatura e sensação térmica, com fonte Open-Meteo e horário local. A tentativa de conexão recuperada funcionou no próprio processo do app.
- “Quanta memória RAM tem meu Mac?” retornou 18,0 GB totais e 13,2 GB em uso, usando a leitura real do monitor do app.

Essas três verificações finais foram feitas pela conversa escrita no app, usando os mesmos serviços e controles da voz. A nova rodada física de reconhecimento pelo microfone ainda precisa ser repetida pelo usuário. A conversa de teste foi criada separadamente; as conversas anteriores foram preservadas.
