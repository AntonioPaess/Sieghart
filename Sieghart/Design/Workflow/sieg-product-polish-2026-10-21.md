# Sieghart — integração e acabamento de 21/10/2026

Em andamento, somente na worktree espacial. Um agente, sem commit/push, sem ativar microfone ou tocar áudio. A cópia estável permanece em /Applications/Sieghart.app; a atualização será feita após verificar código e interface, preservando a sessão de Keep Awake que o usuário ativou.

## Pedidos incorporados

- Tela e diagramas como prioridade, sem respostas presas indefinidamente.
- Toulouse/França não pode virar Franca/SP; nomes e qualificadores devem ser conferidos.
- Continuação de voz “Bragança em Portugal” → “E Lisboa?”.
- Sieg como entrada; Ada para código e matemática, com conversa e histórico próprios.
- Keep Awake com estado e contagem reais no chat.
- Chat com menos brilho, sem passos técnicos artificiais, hierarquia e idioma coerentes.
- Personagem climático sem fundo retangular aparente. Resposta grande temporária; resumo animado perto do cursor após fala, com acesso aos detalhes.

## Implementação em verificação

- Parser climático preserva cidade antes de qualificadores e reconhece a elipse curta. Localização confere nome, metadados de estado/país e aliases de países fornecidos pelo sistema; não há tabela fixa de cidades. Pesquisa de nome pode usar somente a cidade, mas aceitação conserva todos os qualificadores originais.
- Orçamento total de consulta de clima de 12 segundos, timeout individual até 4 segundos, um retry dentro do orçamento e geocodificação nativa com tempo restante. Não é garantia de primeiro áudio nesse prazo.
- Contexto climático recente de dez minutos, local, com limpeza explícita e sem reutilizar valores meteorológicos antigos na próxima consulta.
- Encaminhamento tipado com recibo navegável, transferência de anexos e conservação da conversa original. Reclassificação de históricos antigos de utilidades que eram atribuídos a Ada, sem apagar mensagens. Especialista de voz registra resultado na conversa correspondente.
- Deadline do chat, interrupção imediata, restauração do pedido e bloqueio de resposta tardia, mesmo quando o backend ignora cancelamento.
- Recibo de Keep Awake associado ao prazo real; estado observa o próprio controle, diferencia ativo de configurado/aguardando e não faz um período antigo aparecer ativo por causa de uma sessão nova.
- Seleção e texto acessível de editores têm prioridade sobre OCR geral; pedidos textuais evitam primeiro uma análise visual desnecessária. Referências genéricas “isso” passam a ler tela fresca; cache só para referência explícita à leitura anterior.
- Camadas do renderer nativo configuradas com alpha e sem opacidade de grupo. Acabamento sem retângulo ainda depende de inspeção da versão final real; snapshots anteriores já tinham alpha, portanto apenas repetir snapshot não comprova o reparo do SCNView vivo.
- Resultado climático compacto ancorado perto do último cursor, com expiração; hover/click reabre o detalhe. Painel grande respeita fala, aproximação e interação do usuário.

## Evidência disponível

Ensaio público real em /tmp/sieg-weather-polish-probe/results.log: Toulouse/França (1,99 s), Bragança/Portugal (0,72 s), E Lisboa (0,49 s), Zermmat→Zermatt (0,86 s), Alasca regional (0,54 s), Paris/Texas (0,61 s). São tempos de consulta naquele ensaio, sem áudio e sem equivaler a latência acústica. Asserções de regressão e controles ainda estão sendo verificados.

## Direção para TDAH

Objetivo do produto: reduzir esforço de começar/retomar, tornar tempo e progresso visíveis, guardar próximos passos e reduzir troca entre telas. São hipóteses de apoio à organização, não resultados clínicos avaliados no Sieg. Fontes conferidas: NIH Health ADHD (rotina, anotações, organização, pausas e decomposição de tarefas) e NICE NG87 (adaptação ambiental, menos distrações, instruções escritas e pausas). O desenho precisa permitir movimento reduzido e evitar estímulo permanente sem evento real.
