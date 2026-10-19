# Pré-sprint 6 — Migração para Swift Testing

Data: 17 de outubro de 2026.

**Atualização de 18 de outubro:** a implementação autorizada pelo usuário foi concluída, executada e aprovada na [revisão independente final](pre-sprint-6-revisao-final.md). Consultar o [registro de execução](pre-sprint-6-execucao.md). As restrições de preparação abaixo descrevem a etapa anterior. O gate da migração foi cumprido; aceites físicos e procedimentos auxiliares continuam separados.

**Estado histórico em 17 de outubro: planejado; implementação não iniciada.** A restrição de não programar aplicava-se à preparação dessa data. A autorização posterior e os resultados atuais estão no registro de execução acima.

## Objetivo e gate

Transformar as verificações existentes em casos Swift Testing organizados por funcionalidade, descobertos pelo Xcode e executáveis pela linha de comando, com resultados individuais e isolamento preservado.

**A sprint 6 só começa após implementação, execução e revisão desta migração.** Testes reais de CPU, interface, permissões, modelos e contas continuam sendo evidências separadas; a migração não encerra esses aceites automaticamente.

## Ponto de partida

- `Tests/run-checks.sh` compila executáveis Swift separados; verificações usam `precondition`, mocks e fixtures. Os grupos não equivalem a casos individuais de um framework de testes.
- O projeto Xcode inspecionado tem o target do aplicativo, sem target de testes. Ainda não há suítes Swift Testing nos arquivos inspecionados.
- O runner organiza 18 grupos: timer, callbacks, voice-integration, interactions, companions, usage, spending, activity, pricing, audio, imports, clipboard, middle-click, utilities, calendar, files-capture, agent-room e local-chat.
- Há helpers, previews, verificações auxiliares e contratos antigos fora dessa lista. O inventário deve identificá-los antes de remover ou excluir qualquer arquivo.
- A asserção legada de Team foi corrigida para a migração aprovada a Companion no checkpoint `e218a72`. Preservar essa decisão e a cobertura existente.

## Detalhamento da preparação — 17 de outubro

A leitura do runner e dos checks, o levantamento dos 36 arquivos Swift de `Tests/` e a inspeção do projeto/gerador produziram duas entregas de planejamento:

- [Inventário dos 18 grupos e material auxiliar](pre-sprint-6-inventario.md): contratos com IDs rastreáveis, origens, dependências, destinos propostos e separação entre lógica, integração isolada, integração local e contratos visuais nativos. Identifica também `NewCodexChatChecks.swift`, que não é chamado pelo runner atual, benchmarks, previews e verificação do bundle compilado.
- [Proposta de targets/schemes](pre-sprint-6-targets-schemes.md): um target de testes sem app hospedeiro, usando referências às 124 fontes reais fora de `App/`, um scheme de testes compartilhado e planos completo/rápido. Explicita alternativas, limites da cobertura no módulo de teste, isolamento, concorrência e adaptação prévia do gerador para múltiplos targets.

O inventário é estático; não equivale a casos descobertos, resultados aprovados ou cobertura medida. O desenho é uma **recomendação pendente de revisão**, não uma configuração já criada. Permanecem por resolver na implementação as dependências herdadas de `CODEX_HOME`, o reader Claude padrão em spending, recursos por bundle/cwd, estado global e sincronização temporal. O GitHub padrão dos testes de chat já é isolado e deve continuar assim.

O próximo passo de coordenação é submeter esses documentos à revisão do desenho quando o usuário solicitar. Nenhuma mensagem foi enviada a especialistas; nenhum target/scheme, código, build ou teste foi alterado/executado nesta preparação.

## Responsáveis

| Papel | Responsabilidade na execução futura |
| --- | --- |
| Coordenação — chat principal | Delimitar lotes, manter a matriz de cobertura e conferir o gate de entrada da sprint 6. |
| Sieg — Implementação · 6.1 Extra alto | Propor a arquitetura testável, configurar o target/scheme e migrar casos. |
| Sieg — Revisão · 6.1 Ultra | Conferir a arquitetura, equivalência dos cenários, qualidade das asserções, isolamento e resultados. |
| Sieg — Avatares e animações | Validar os contratos de identidade/movimento quando necessário, preservando o design aprovado. |

Esta atribuição é planejamento. Nenhuma tarefa de implementação foi enviada aos chats nesta etapa.

## Ordem de execução, após autorização

### 1. Inventário e desenho do target

- Mapear cada cenário existente para funcionalidade, comportamento esperado, tipo de teste, dependências e destino novo.
- Separar testes unitários de integração isolada, verificações de renderização e testes manuais. Previews e benchmarks não viram testes unitários por mudança de nome.
- Escolher uma estrutura que exercite as fontes reais de produção, sem cópias divergentes e sem iniciar `SieghartApp`/`ResidentAppDelegate` ou serviços residentes.
- Registrar a decisão sobre módulo testável, dependências e hospedagem do target antes de modificar o projeto. Evitar uma refatoração ampla do app sem necessidade comprovada.

**Saída:** matriz de migração e proposta de target revisadas. O inventário e a proposta vinculados acima são a versão inicial por leitura; a revisão independente ainda está pendente.

### 2. Integrar Swift Testing ao projeto

- Adicionar target de testes, grupos/fontes e scheme compartilhado; manter os registros compatíveis com o gerador de fontes do projeto.
- Preparar execução no Xcode e por comando, filtros de seleção e resultado individual por caso.
- Definir acesso às APIs internas de produção, recursos de fixture e diretórios temporários sem depender de caminhos pessoais ou caches em `/private/tmp`.
- Garantir que descoberta/execução não abra o aplicativo nem construa integrações reais como efeito colateral.

**Saída:** descoberta e execução de um primeiro conjunto significativo de testes no target correto.

### 3. Migrar regras de negócio primeiro

- Priorizar timers, interpretação de comandos, cálculos/limites de uso e preços, imports e regras puras de calendário/arquivos.
- Criar suítes e casos com nomes que expliquem o comportamento. Usar asserções Swift Testing apropriadas e requisitos explícitos para condições necessárias; eliminar falhas abruptas de teste baseadas em `precondition`.
- Dividir os executáveis monolíticos em cenários independentes. Não encapsular cada `main()` inteira em um único teste e chamar isso de migração concluída.
- Parametrizar variações relevantes quando isso melhorar identificação de falhas, inclusive identidade/animação.

**Saída:** falhas localizadas por cenário e preservação demonstrável dos contratos anteriores.

### 4. Migrar estado, concorrência e integrações isoladas

- Cobrir chat/histórico/drafts, cancelamento, streaming, identidade da conversa, persistência, corrupção/recuperação e respostas atrasadas.
- Preservar os cenários de voz, calendário, clipboard, arquivos/captura e GitHub com dependências injetadas.
- Usar credenciais/transportes em memória e armazenamento temporário. Não acessar Keychain, rede, contas, clipboard real, Finder ou permissões do usuário.
- Isolar estado global, preferências, relógios, notificações e recursos compartilhados; controlar paralelismo onde necessário. Evitar esperas temporais frágeis.
- Classificar contratos de geometria/timing/identidade como testes lógicos quando aplicável; manter renderização e medição real de CPU em verificações próprias.

**Saída:** testes repetíveis sem autenticação, hardware ou atividade residente.

### 5. Consolidar runner, relatórios e cobertura

- Atualizar o ponto de entrada dos testes para usar o novo target, com filtros documentados e status de saída correto.
- Manter o runner legado como ponte até verificar a equivalência. Depois, registrar o destino de cada cenário e retirar a duplicação desnecessária.
- Gerar evidência de resultados por caso e relatório de cobertura; avaliar lacunas relevantes, sem usar uma porcentagem arbitrária como substituto de cenários importantes.
- Documentar execução local/linha de comando e integração contínua proposta. Publicação de workflow/commit/push é uma etapa posterior autorizada.

**Saída:** um fluxo de testes documentado e reproduzível, com resultados verificáveis.

### 6. Revisão e aceite da migração

- Revisão independente do diff e da matriz de cenários.
- Conferir descoberta, seleção, falhas individuais, isolamento e correções relevantes.
- Registrar quantidade de suítes/casos efetivamente descobertos, aprovados, falhos e ignorados, com justificativas. Não confundir asserções, combinações parametrizadas e casos executados.
- Registrar os limites de verificação e as pendências físicas/externas que continuam abertas.

**Saída:** gate de testes aprovado; planejamento da sprint 6 liberado.

## Critérios de aceite

- [ ] Target/scheme Swift Testing reconhecido pelo Xcode.
- [ ] Casos individuais selecionáveis e executáveis pela linha de comando.
- [ ] Matriz contempla os 18 grupos legados e identifica testes auxiliares/previews.
- [ ] Suítes por funcionalidade e cenários independentes, sem wrappers monolíticos de `main()`.
- [ ] Contratos relevantes anteriores preservados ou alterações justificadas e revisadas.
- [ ] Asserções do framework reportam falhas por caso; pré-condições fatais deixam de ser o mecanismo de asserção dos testes migrados.
- [ ] Cancelamento, persistência, erros e limites cobertos onde aplicável.
- [ ] Execução isolada sem abrir app, contas, modelos ou serviços reais.
- [ ] Resultado individual, cobertura e instruções de reprodução documentados.
- [ ] Revisão independente concluída; exclusões/ignorados e limitações explícitos.

## Fora desta preparação

Nenhuma implementação de teste, mudança de código/target/scheme, execução de build/testes, novo recurso da sprint 6, commit ou push. O aceite visual e de desempenho real do app continua no fluxo próprio da sprint 5.

## Referências para a implementação

- [Apple — Adding tests to your Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project).
- [Apple — Swift Testing](https://developer.apple.com/documentation/testing).
- [Inventário detalhado](pre-sprint-6-inventario.md).
- [Targets, schemes e isolamento](pre-sprint-6-targets-schemes.md).
- [Fluxo dos especialistas](README.md).
