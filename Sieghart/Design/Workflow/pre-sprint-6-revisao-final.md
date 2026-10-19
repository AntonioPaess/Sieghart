# Pré-Sprint 6 — Revisão independente final

Data: 18 de outubro de 2026. Revisão sequencial, sem agentes adicionais, sem alteração da implementação e sem commit/push. Instruções de `AGENTS.md` lidas e respeitadas.

## Parecer

**Aprovada, com o alcance abaixo. Não encontrei achado P1/P2 concreto que impeça fechar o gate da migração para Swift Testing.** O parecer é independente da implementação e reaproveita as execuções já registradas; não houve nova compilação ou execução integral de Swift nesta revisão.

O fechamento referido é o gate da migração: target não hospedado, descoberta, rastreabilidade, execução e seleção dos testes migrados. Não equivale à aprovação dos aceites físicos ou da composição/inicialização do aplicativo.

## Verificações realizadas

- Li o registro de execução, o guia de testes, o scheme e o plano Complete. Examinei os cinco diffs de produção, o gerador do projeto, o indexador, o runner e seus testes de infraestrutura.
- Reconferi os 201 hashes de `source-manifest.json` e os 101 hashes de `review-manifest.json`: nenhuma divergência no momento da revisão. Isso vincula as evidências persistidas à implementação atual. Conferir hashes não significa leitura integral de todos esses arquivos.
- Consultei diretamente os quatro bundles brutos com `xcresulttool`: Complete 235/235, Fast 171/171, seleção individual 1/1 e entrada filtrada 15/15 funções aprovadas; todos com zero falhas e zero skips. Os relatórios persistidos registram respectivamente 945, 850, 1 e 21 invocações.
- O índice possui 235 declarações e 235 funções descobertas, sem ausências. Os perfis somam 65 de lógica, 106 de estado isolado, 45 de integração local e 19 de views nativas. Fast seleciona as 171 primeiras. A matriz possui 133 chaves: os 132 IDs Gxx.yy e A01, todas com resultados aprovados.
- Executei novamente os três testes do gerador e os três da fronteira de seleção: seis aprovados. Os testes trabalham em projetos/saídas descartáveis.
- Comparei semanticamente o PBX atual com o HEAD: os objetos preexistentes alterados são os grupos raiz/Products/Shared e o objeto do projeto para inclusão do target. Target, configurações e fases existentes do app permanecem preservados nesta alteração. O target de testes compila as fontes reais fora de `App/`; o cache do runner mantém links para essas fontes.
- Confirmei byte a byte que `Tests/run-legacy-checks.sh` preserva `HEAD:Sieghart/Tests/run-checks.sh`.

## Pontos de maior risco examinados

As injeções de relógio/calendário/ativação e de entrega do middle-click mantêm os padrões de produção. O shutdown de ativação remove registros próprios, usa o centro de notificações observado e evita limpar a propriedade de outro controlador. O escopo síncrono de artwork restaura caches e nomes com `defer`; a sonda persistida chama os testes reais de menu/raster e verifica a restauração em duas ordens. A drenagem de notificações aguarda também tarefas canceladas; o teste de opt-out habilita explicitamente o módulo e exige uma entrega pendente antes de desabilitá-lo.

O runner usa descoberta Complete antes da seleção, exige correspondência com as declarações e confere funções efetivamente presentes no resultado contra a seleção. Rejeita execução vazia, ausências, funções inesperadas, fontes alteradas e resultados skipped/unknown. A seleção Fast usa a árvore nativa de Swift Testing; os controles negativos documentados cobrem filtro/identificador inexistente e expectativa falsa sem abortar o caso seguinte. A revisão conferiu o código e as evidências desses controles, sem repetir a sonda.

A amostragem de equivalência incluiu os casos corrigidos: normalização geométrica conserva a tolerância já usada pelo legado; a fixture GitHub reproduz o primeiro refresh falho antes de existir snapshot; o timeout exige o erro correto, prazo limitado e ausência do PID criado; a apresentação decodifica o recurso como `[ModelPrice]` para construir o catálogo esperado. Não identifiquei enfraquecimento desses contratos.

## Limites e pendências de produto

A cobertura registrada é a baseline de **9.552/27.519 linhas (34,71%), 124/124 arquivos de produção no módulo `SieghartTests`**, com 47 arquivos sem linhas cobertas. Não é cobertura do binário do aplicativo nem prova de equivalência percentual com o legado.

Esta revisão não repetiu todos os cenários, não leu integralmente as aproximadamente 9 mil linhas de testes e não realizou auditoria exaustiva de cada asserção legada. A aprovação combina a revisão anterior, rastreabilidade completa, amostragem dirigida, verificações estáticas e os resultados brutos existentes. Não foi iniciado `Sieghart.app`, nem validado app host/startup, assinatura, recursos compilados, benchmark Metal, hardware, contas ou permissões reais. **A02–A10 e os aceites físicos continuam separados e pendentes conforme seus procedimentos.**

Nenhum bloqueador concreto da migração foi encontrado no alcance revisado. A Sprint 6 continua sujeita às demais condições de execução e aceite previstas em `Design/Workflow/`.
