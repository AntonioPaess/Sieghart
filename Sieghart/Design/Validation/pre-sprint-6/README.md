# Evidências da pré-Sprint 6

Execução local em 18 de outubro de 2026: macOS 27.0.1 arm64, Xcode 27.0 (27A266a), Swift 6.4, Python 3.12 e Node local. Nenhuma inicialização de `Sieghart.app`.

- [Complete](complete-verification.json): 235 funções, 945 invocações, todas aprovadas.
- [Fast](fast-verification.json): 171 funções, 850 invocações, todas aprovadas; somente lógica/estado isolado.
- [Seleção individual](single-verification.json): uma função, uma invocação aprovada.
- [Matriz por contrato](contract-results.json): 132 IDs automáticos Gxx.yy e A01, com função, arquivo, linha, perfil e resultado.
- [Índice real de descoberta](test-index.json): 235 funções com identificadores, tags, grupos e perfis; zero declarações ausentes.
- [Hashes das fontes](source-manifest.json): fontes de produção, testes e suporte imutáveis durante Complete; reconferidos após Fast e a sonda.
- [Cobertura de produção](coverage-production.json): 124 arquivos, 9.552/27.519 linhas (34,71%). Recorte por caminho, sem helpers/testes no denominador, módulo `SieghartTests`; não mede o aplicativo compilado.
- [Controle negativo e ordem dos caches](negative-and-order-probe.log): falha deliberada não aborta o caso seguinte, que chama os testes reais de menu/raster nas duas ordens e verifica restauração dos nomes. Duas repetições, sem relançar o processo; resultado 65 esperado.

A [fonte da sonda](sieghart-pre6-artwork-probe.swift) e seu [procedimento](sieghart-pre6-evidence-probe.py) registram a reprodução exata desta sessão. Foram inseridos somente na cópia temporária de um arquivo de teste; o link às fontes reais foi restaurado em `finally`. Não fazem parte do target do repositório. Ajustar os caminhos locais antes de reproduzir em outro checkout. Os resultados brutos permanecem nos `.xcresult` indicados no [registro de execução](../../Workflow/pre-sprint-6-execucao.md).

Também foram verificados retorno 2 para filtro inexistente antes de compilar, rejeição de identificador exato inexistente, os seis testes de infraestrutura e preservação byte a byte do runner legado. A nova entrada oficial é `Tests/run-checks.sh`; comandos estão no [guia de testes](../../../Tests/README.md).
