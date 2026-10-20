# Preços adicionados ao Antigravity — auditoria de 19/out/2026

Escopo: seis equivalentes de API em `ModelTokenPrices.json`, sem alterar os preços preexistentes de outros provedores. Valores em USD por milhão de tokens. São referências públicas de API; não são cobrança, créditos, quota ou tabela oficial do produto Antigravity. Não foi feita inferência de preço por semelhança entre famílias.

| Identificador normalizado no catálogo | Entrada | Cache read | Saída | Prazo / observação |
| --- | ---: | ---: | ---: | --- |
| gemini-4-argon | 2.00 | 0.10 | 10.00 | Promoção até 30/nov/2026; depois fica sem preço até nova verificação |
| gemini-3-8-flash | 0.75 | 0.075 | 3.75 | Nome oficial gemini-3.8-flash; promoção até 31/dez/2026 |
| gemini-2-5-pro | 1.25 | 0.125 | 10.00 | Acima de 200k tokens por requisição: 2.50 / 0.25 / 15.00 |
| gemini-2-5-flash | 0.30 | 0.03 | 2.50 | Entrada de texto; armazenamento e demais modalidades não incluídos |
| claude-opus-5-5 | 4.00 | 0.20 | 20.00 | Cache write 5 min: 5.00; 1 h: 8.00 |
| claude-sonnet-5-5 | 2.00 | 0.10 | 10.00 | Cache write 5 min: 2.50; 1 h: 4.00 |

Google: [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing), seções exatas Gemini 4 Argon, Gemini 3.8 Flash, Gemini 2.5 Pro e Gemini 2.5 Flash, consulta em 19/out/2026. A revisão corrigiu Argon e 3.8 Flash, que tinham herdado preços de outros modelos, e o limiar de contexto longo do 2.5 Pro.

Anthropic: [Claude API pricing](https://platform.claude.com/docs/en/about-claude/pricing), tabela Model pricing, consulta em 19/out/2026. Cache read de Sonnet 5.5 corrigido de 0.20 para 0.10; demais valores acima conferidos.

`gemini-antigravity` não identifica modelo oficial nessa fonte e foi removido do catálogo de preços. `gpt-oss-120b` foi conferido na [documentação oficial OpenAI](https://developers.openai.com/api/docs/models/gpt-oss-120b): não foi estabelecida uma tarifa oficial aplicável a essa integração; a tarifa que apontava para Google foi removida. O modelo continua contabilizado quando observado no histórico, sem inventar custo. Sufixos de reasoning/trial não herdam preço; apenas nomes exatos normalizados e snapshots datados permanecem elegíveis.

O upgrade substitui entradas Antigravity antigas do cache pelos valores verificados, preservando preços dos outros provedores e overrides explícitos do usuário. `validThrough` impede uso de promoções vencidas. Uso não precificado fica nos totais e produz estimativa parcial/indisponível, sem virar zero silencioso. Os links de Google e Anthropic aparecem separadamente no editor do produto.

Quotas são independentes dos preços: a leitura local expira em cinco minutos ou no reset, exige proveniência nova e mantém o rótulo recebido. A resposta não estabelece duração 5h/semanal nem uma família Claude específica, portanto esses dados não são inventados na UI. Serviço local real, modelos e contas não foram acessados nesta revisão.
