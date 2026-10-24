# Clima retorna à Home — 22/10/2026

O resultado permanecia ativo porque o prazo usava a mesma tarefa do recolhimento por hover. Entrar na área cancelava essa tarefa, e recolher o painel não apagava o clima da Home.

Corrigido na versão **80**, instalada em `/Applications/Sieghart.app` e aberta por LaunchServices:

- O cartão tem uma tarefa de encerramento própria, independente do hover e da visibilidade do painel.
- Após a fala há uma pausa de 2 segundos, respeitando uma exposição mínima de 6 segundos desde que o cartão apareceu. Depois o resultado sai da Home, inclusive com o mouse sobre ele, e o Sieg volta à apresentação normal.
- A prévia junto ao cursor pode conservar o resultado pelo seu prazo curto. Reabri-la recupera os detalhes do próprio recibo, por 8 segundos, sem depender de um cartão antigo ainda ativo na Home.
- Cancelar ou iniciar outro pedido limpa a apresentação anterior. O encerramento tardio confere a observação atual antes de apagar um resultado.

A suíte existente passou: **360 funções / 1.115 invocações**, cobertura registrada em 195/195 arquivos de produção. A regressão agora mantém o ponteiro dentro do painel, alterna saída/entrada para cancelar o temporizador de hover, aguarda a retirada do clima, confere Home visível sem cartão, reabre pelo recibo e cancela. Tudo com serviços substituídos e voz desativada; nenhum microfone ou reprodução real foi usado.

Compilação universal e verificação do app assinado aprovadas. O catálogo ilustrativo de nove climas continua disponível e foi reaberto a pedido do usuário; ele permanece aberto para comparação e não usa o prazo de um resultado real do widget.

Evidências: [evidence/sieg-weather-return-2026-10-22](evidence/sieg-weather-return-2026-10-22/).
