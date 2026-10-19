# Testes de comportamento

Os 18 grupos antigos, os quatro casos de abertura de novo chat e o grupo `input` da Sprint 6 estão em `SwiftTesting/`. `Support/` contém fixtures; `TestPlans/` contém os planos compartilhados do scheme `Sieghart-Checks`.

Requisitos: macOS com sessão gráfica, Xcode completo selecionado, Python 3 e Node disponíveis no PATH. Os testes usam imagens, arquivos, bancos e processos próprios; nenhum fluxo requer conta, rede, microfone, clipboard real ou inicialização do app. Vision e as views nativas são exercitados localmente no plano Complete.

```sh
# Plano completo, resultados individuais e cobertura de produção.
bash Sieghart/Tests/run-checks.sh --derived-data /private/tmp/sieghart-test-build

# Reutiliza a compilação; somente lógica e estado com dependências substituídas.
bash Sieghart/Tests/run-swift-tests.sh --plan fast --derived-data /private/tmp/sieghart-test-build

# Mantém a seleção por expressão regular dos grupos antigos.
SIEGHART_CHECK_FILTER='^(timer|callbacks)$' bash Sieghart/Tests/run-swift-tests.sh

# Identificador exato obtido em test-index.json.
bash Sieghart/Tests/run-swift-tests.sh --only 'MacContractsTests/IslandPresentationTests/currentAIWork()'
```

`--output` recebe uma pasta nova. Sem essa opção, o runner cria uma pasta temporária e mostra seu caminho. Cada execução salva descoberta do Xcode, índice com fontes/tags/IDs de contrato, seletores, logs, `Results.xcresult`, resultados por contrato e cobertura. O cache indicado por `--derived-data` admite uma execução por vez e mantém um projeto sem estado pessoal do Xcode, ligado às fontes reais. Nenhuma cópia alternativa de produção é compilada.

Na baseline histórica da pré-Sprint 6, Complete executou 235 funções e Fast continha 171 funções com perfis `logic`/`isolated`; exclui as 45 integrações locais e as 19 funções de views nativas. Os totais de funções e de invocações parametrizadas são relatados separadamente. Seleção inexistente retorna erro; omissão, seleção inesperada e mudança das fontes durante a execução impedem aceite.

A baseline histórica cobria 124 fontes fora de `App/`; o lote de scroll acrescenta uma (125). Essas fontes são compiladas no módulo `SieghartTests`. Ela não mede o binário do aplicativo. Assinatura/privacidade do bundle, recursos compilados, benchmark Metal e aceites físicos continuam nos procedimentos A02–A10 do [inventário](../Design/Workflow/pre-sprint-6-inventario.md). O catálogo de preços é recurso explícito do bundle de testes.

`run-checks.sh` agora usa Swift Testing, após execução aprovada de Complete/Fast e rastreabilidade dos contratos. O runner anterior está preservado byte a byte em `run-legacy-checks.sh`; os programas legados continuam disponíveis para consulta e reprodução.

Para o lote de entrada: `bash Sieghart/Tests/run-checks.sh --filter '^input$'`. Os grupos aceitos são derivados de `GROUP_TAGS` no índice, sem lista duplicada no runner. Contagens atuais são descobertas pelo Xcode em cada execução; os números pré-S6 acima são históricos.

Na Parte 1 da Sprint 6, a descoberta inclui 246 funções no Complete e 182 elegíveis no Fast. A validação focada `input` executou 11 funções / 17 invocações; isso não representa uma nova execução completa desses planos.
