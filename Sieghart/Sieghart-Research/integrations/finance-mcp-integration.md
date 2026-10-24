# Integração financeira por ferramentas e MCP

**Estado:** desenho original; nenhum servidor MCP financeiro foi implementado. **Data:** 13/10/2026. Fontes: [DeseretSaint](../applications/open-finance-deseretsaint.md), [openfinance-app](../applications/open-finance-openfinance-app.md), [MCP 2026-07-28: ferramentas](https://modelcontextprotocol.io/specification/2026-07-28/server/tools), [MCP 2026-07-28: autorização](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization). MCP é uma interface opcional sobre o serviço financeiro nativo, **não o local onde a política de acesso mora**.

## Evidência e decisão

`DeseretSaint/open-finance` já publica ferramentas MCP/REST e tokens com escopos, mas o dossiê encontrou caminhos que não propagam `accountAllowlist` e confirmação destrutiva não aplicada quando o escopo de escrita existe. [Registro](https://github.com/DeseretSaint/open-finance/blob/94d4a7e8ea875d346f5fd3d231ae1a022ddb6a26/src/server/authz/route-registry.ts#L96-L161), [dispatcher](https://github.com/DeseretSaint/open-finance/blob/94d4a7e8ea875d346f5fd3d231ae1a022ddb6a26/src/server/mcp/server.ts#L653-L730), [análise](../applications/open-finance-deseretsaint.md#4-lacunas-de-segurança-verificadas-no-fluxo-de-código). `openfinance-app/open-finance` tem assistente interno e guard de fatos, mas não foi identificado servidor MCP/capacidades por agente. [AIService](https://github.com/openfinance-app/open-finance/blob/c54668f6f9c36e0a4f9b6504d972661e4718a271/src/main/java/org/openfinance/service/AIService.java#L78-L188).

**Decisão proposta:** primeiro definir chamadas Swift internas tipadas para Elinor. Só publicar MCP quando um agente externo autorizado precisar dessas mesmas chamadas. A especificação MCP atual permite descoberta/chamada de ferramentas com schemas; ela aconselha mostrar ferramentas e confirmação para operações. A lista de ferramentas pode variar pela autorização de **cada requisição** e não deve substituir a verificação na própria execução. [MCP tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools).

## Capacidades propostas

| Capacidade | Ferramenta interna / MCP opcional | Resposta máxima | Aprovação |
| --- | --- | --- | --- |
| `ReadAccounts` | `finance.list_accounts`, `finance.get_account` | Conta autorizada, moeda, saldo com `asOf`, origem; sem credenciais/número integral | Concessão por fonte/conta e prazo |
| `ReadTransactions` | `finance.list_transactions`, `finance.get_transaction` | Período limitado, paginação, campos mínimos; filtros aplicados também por ID | Concessão por conta, período e classe |
| `ReadBudgets` | `finance.list_budgets` | Metas e execução de categorias autorizadas | Concessão de leitura |
| `AnalyzeExpenses` | `finance.expense_summary`, `finance.recurring_summary` | Agregados determinísticos, cobertura e fact IDs; se detalhe não autorizado, nenhum drill-down | Concessão de análise das contas usadas |
| `GenerateReports` | `finance.report` | Relatório de fatos, fontes, taxa, data, avisos; exportar arquivo só com permissão separada | Concessão de relatório |
| `ProposeBudgetChanges` | `finance.propose_budget_change` | Prévia com valor anterior/novo, período, motivo, ID/hash da proposta; sem mutação | Concessão de proposta |
| `ModifyBudgetsWithApproval` | `finance.commit_budget_change` | Resultado de uma proposta previamente aprovada, ID de auditoria | **Aprovação humana para aquela proposta exata** |

**Fora do catálogo inicial:** transferir dinheiro/Pix, iniciar pagamento, operar ativos, abrir conexão bancária, ler senha/token, consulta SQL arbitrária, exportação irrestrita, exclusão em massa. “Marcar como paga” uma obrigação **local** também é mutação e exige regra separada; não deve parecer uma transação bancária.

## Pipeline de autorização — proposta

1. O `Sieghart Core` associa cada chamada a usuário local, agente/cliente, tarefa, finalidade, hora e versão da política. Para MCP remoto, autenticar o cliente conforme versão vigente da [especificação](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization); para IPC local, vincular identidade do processo/cliente e evitar confiar só em porta `localhost`. Nunca encaminhar token bancário como token MCP.
2. `PermissionManager` calcula **interseção** entre capacidade, contas/fontes, classes, período e validade. O escopo calculado vira `FinancialAccessContext` imutável e é passado ao serviço. Resolução vazia encerra a chamada. Não existe botão “acesso global” que silenciosamente adicione escrita.
3. O serviço financeiro consulta **somente** IDs autorizados em listas, consultas por ID, buscas, totais, projeções, relatórios e cache. `get_transaction(id)` deve verificar que `transaction.accountID ∈ allowlist` e que o tipo de conta está no grant. `expense_summary` agrega o mesmo subconjunto. Paginação e campos retornados são limitados no servidor.
4. Cálculos produzem fatos tipados com ID, período, moeda, taxa e proveniência. O agente pode redigir explicação, mas a UI/servidor renderiza números a partir desses fatos, inspirado conceitualmente em [`FinancialResponseGuard`](https://github.com/openfinance-app/open-finance/blob/c54668f6f9c36e0a4f9b6504d972661e4718a271/src/main/java/org/openfinance/service/ai/FinancialResponseGuard.java#L33-L139). As verificações precisam cobrir português e BRL; regex isolada não é fronteira suficiente.
5. Para mutação, a ferramenta de proposta grava um objeto com versão/diff. O usuário vê origem, escopo e impacto e aprova **aquela** proposta. `commit` confere hash, prazo, versão dos dados e chave idempotente, aplica uma vez e registra resultado junto ao efeito. Nenhum pedido de permissão por escopo equivale a essa aprovação operacional.
6. A auditoria registra concessão, negação, leitura resumida, proposta, aprovação, execução e revogação sem payload financeiro. Revogação invalida próximas chamadas e tarefas agendadas.

## Exemplo de contrato tipado — proposta, não código existente

```text
FinancialAccessContext {
  principalID, agentID, taskID, purpose,
  sourceAllowlist, accountAllowlist,
  dataClasses, capabilities, validUntil, policyVersion
}

FinancialFact {
  factID, metric, amount, currency, period,
  accountIDs, sourceIDs, asOf, fxQuoteIDs,
  status: observed | estimate | partial,
  assumptions, missingCoverage
}
```

A ferramenta `finance.expense_summary({start,end,currency?})` recebe apenas argumentos de consulta; o `FinancialAccessContext` vem da identidade autenticada do runtime, **não** de um parâmetro livre gerado pelo modelo. O resultado expõe `Money` e `status`, nunca um número sem moeda. Contratos JSON Schema do MCP devem rejeitar campos extras, período desmedido e identificadores de conta de outro grant. A [especificação MCP](https://modelcontextprotocol.io/specification/2026-07-28/server/tools) define `inputSchema` e `outputSchema`, mas a validação de negócio continua responsabilidade do Sieghart.

## Provedores brasileiros e MCP de terceiros

MCP **não cria** direito de acessar a rede regulada. A integração brasileira exige fluxo e contrato do participante/agregador; o backend/provedor guarda consentimento e tokens conforme sua função, enquanto o Sieghart recebe apenas dados autorizados. [BCB FAQ](https://www.bcb.gov.br/meubc/faqs/s/open-finance), [especificação de contas](https://github.com/OpenBanking-Brasil/all-services-repo/blob/main/api_accounts_-_open_finance_brasil/2.5.0.yaml).

A [Pluggy publica um MCP de documentação e portal de desenvolvedor](https://docs.pluggy.ai/en/docs/developer-tools/mcp): sem autenticação, ele lê **documentação**, não as contas pessoais; autenticado, expõe ferramentas do portal de desenvolvedor. Seu [Meu Pluggy](https://meu.pluggy.ai/) anuncia API/MCP/CLI para dados pessoais, mas detalhes de permissão, limites e contrato para uso em um produto Sieghart requerem validação separada. A [Belvo anuncia Data Access MCP](https://belvo.com/pt-br/recursos/belvo-mcps/) com consentimento por consulta e cobrança como chamadas de API; é serviço comercial e não substitui política local por agente. Nenhum desses MCPs foi conectado/testado nesta pesquisa.

## Testes necessários quando for implementar

Em worktree exclusivo: grant de uma conta e transação por ID de outra; `list` versus `get` versus `summary` com o mesmo grant; banco/investimento separados; expiração e revogação durante tarefa; decisão de orçamento alterada após aprovação; chamada repetida com mesma chave; modelo tentando alterar `accountAllowlist` nos argumentos; resposta com “R$”/número inventado; logs sem payload. Medir latência/memória apenas com dados sintéticos. Hoje não há implementação nem comando de teste de produto a executar.
