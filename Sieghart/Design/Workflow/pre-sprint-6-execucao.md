# Pré-Sprint 6 — Execução

Implementação autorizada em 18 de outubro de 2026. Continuação sequencial, reaproveitando a migração existente. Astra é proibido; agentes limitados a GPT-6.1 Sol, um por vez, conforme AGENTS.md.

## Resultado de implementação e validação

Target macOS não hospedado `SieghartTests`, scheme compartilhado `Sieghart-Checks` e planos Complete/Fast. O target compila as mesmas 124 fontes fora de `App/`, sem cópias de produção. O gerador preserva o target do aplicativo e configurações/recursos alheios à migração.

| Verificação | Resultado |
| --- | --- |
| Descoberta real pelo Xcode | 235 funções; zero omissões em relação às declarações |
| Complete | 235 funções / 945 invocações aprovadas; zero falhas/skips |
| Fast | 171 funções / 850 invocações aprovadas; 65 de lógica e 106 de estado isolado |
| Equivalência | Todos os 132 IDs automáticos dos 18 grupos e A01 têm destino e resultado |
| Seleção individual | Exatamente `IslandPresentationTests/currentAIWork()` executado e aprovado |
| Seleção inexistente | Grupo inexistente retorna 2 antes do build; identificador exato inexistente rejeitado, sem produzir índice de aprovação |
| Falha individual | Sonda descartável: expectativa falha, caso seguinte passa; duas repetições no mesmo processo; Xcode retorna 65 |
| Imagens/estado global | Mesma sonda executa menu dos seis avatares e raster Retina em ambas as ordens, verifica restauração dos nomes; aprovada nas duas repetições |
| Gerador e seleção | Três testes do gerador e três testes da fronteira de seleção aprovados |
| Cobertura útil | 124/124 fontes; 9.552 de 27.519 linhas executáveis (34,71%), módulo `SieghartTests` |

As invocações incluem funções sem parâmetros e combinações parametrizadas. Fast exclui 45 funções de integração local e 19 de views nativas. Seus seletores usam a árvore `selectedTests.suites/testFunctions` salva pelo próprio Xcode; a forma de array usada por XCTest selecionava zero funções. O runner rejeitou esse falso sucesso antes da correção.

Na migração foram corrigidas comparações de coordenadas sem tolerância, a sequência da fixture de erro GitHub, um deadline de processo menor que seu tempo de inicialização e a decodificação do catálogo de preços na fixture de apresentação. O OCR real em imagem gerada passou isoladamente e no Complete; o aparente travamento anterior não se reproduziu. Logs dos frameworks registram tentativas negadas de acesso a serviços de Contatos e avisos de modelos Vision; não houve pedido de permissão nem liberação desses acessos.

As pequenas adaptações de produção permitem relógio/ação de calendário injetados, entrega de middle-click controlada, shutdown de ativação, escopo/restauração dos caches de artwork e drenagem de notificações. Os padrões usados pelo app foram preservados. A revisão anterior também corrigiu opt-out de notificações vacuamente verde e teardown assíncrono que escapava do fim do caso.

## Evidência e reprodução

Resultados e hashes persistidos em [Validation/pre-sprint-6](../Validation/pre-sprint-6/README.md), incluindo matriz por contrato, índice de funções/tags/perfis, cobertura por arquivo e controles negativos. [Tests/README](../../Tests/README.md) documenta os comandos.

`Tests/run-checks.sh` agora usa Swift Testing. `run-legacy-checks.sh` preserva byte a byte o runner anterior; checks/previews legados permanecem disponíveis. Build reutilizável e lock evitam recompilação por mudança de pasta de resultados e execuções concorrentes sobre o mesmo cache.

Os bundles completos desta sessão estão em `/private/tmp/sieghart-pre6-complete-fixed`, `/private/tmp/sieghart-pre6-fast-fixed`, `/private/tmp/sieghart-pre6-single-final` e `/private/tmp/sieghart-pre6-entry-final`. São evidências locais, não dependências do produto.

## Gate

**Gate da migração concluído e aprovado em 18 de outubro de 2026**, conforme a [revisão independente final](pre-sprint-6-revisao-final.md), realizada por um único agente GPT-6.1 Sol. Nenhum bloqueador P1/P2 concreto encontrado no alcance revisado. Nenhuma funcionalidade da Sprint 6 foi iniciada.

A cobertura estabelece a primeira baseline, sem afirmar equivalência percentual com o legado. Há 47 fontes com zero linhas cobertas; views completas, adaptadores reais e composição do app continuam fora do alcance de muitos cenários isolados. Assinatura/privacidade do app compilado, benchmark Metal, recursos compilados e aceites físicos/contas/permissões permanecem nos procedimentos A02–A10; esta migração não os aprova.

Nenhum commit ou push realizado.
