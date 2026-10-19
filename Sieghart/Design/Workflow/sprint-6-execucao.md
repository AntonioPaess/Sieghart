# Sprint 6 — execução por partes

## Parte 1 — scroll e infraestrutura de entrada

18 de outubro de 2026, branch `sprint-6`, baseline `04723e7`. Início autorizado pelo usuário após o gate pré-S6 executado e revisto. Este lote implementa somente `scrollInverter` e `scrollHorizontal`; não fecha a Sprint 6 nem o aceite físico do Mac. Um commit próprio registra esta parte; nenhum push foi solicitado para a Sprint 6.

As duas opções ficam desligadas por padrão e persistem em `input.scroll.*` no domínio fornecido pelas preferências do app. Workspace → Activation inclui os controles, modificador Shift/Option/Control, inclusão explícita de eventos contínuos, estado, Retry e botão de Accessibility. A ativação acompanha `startUtilities`/`stopUtilities`; fixtures `managesWindows: false` não iniciam o recurso.

Um pipeline recebe somente `scrollWheel`, no main run loop, usando `.defaultTap`; não lê teclas ou texto. A transformação pura inverte os dois eixos em linhas, pixels e valores fixos 16.16; depois soma o vertical no horizontal e zera o vertical quando o modificador está presente. Remove somente o modificador usado. Outros flags, phase, momentum, precisão, posição e timestamp são preservados. Soma/negação inválida ou representação fora do intervalo de 32 bits preservam o evento inteiro. Um evento sem componente vertical não é redirecionado novamente.

Eventos contínuos ficam intactos por padrão. A opção para incluí-los afeta mouse e trackpad conforme os eventos recebidos: a API pública não distingue confiavelmente o dispositivo. Não prometemos identificação por hardware. O conflito com qualquer atalho só de modificadores que inclua o modificador escolhido impede a instalação; também é reavaliado em cada amostra e na checagem de saúde, cobrindo alterações tardias de companion/voice/clipboard/audio. Nenhum modificador conflitante é consumido pelo scroll. MiddleClick mantém sua implementação anterior.

Sem opção ligada ou sem Accessibility disponível, nenhum tap é criado. O prompt de permissão existe somente no botão explícito. Desligar, parar, revogar permissão, dormir ou bloquear a tela ou perder sessão ativa liberam o backend. Sono, bloqueio da tela e sessão ativa são três gates independentes; wake só retoma opt-in ainda válido. A saúde verifica revogação/conflito a cada segundo enquanto ativo e cada evento verifica novamente antes da transformação. Timeout/disable agenda reavaliação no main loop, com geração para invalidar callbacks antigos e evitar taps duplicados. Falha de instalação limpa o backend e permite Retry explícito.

## Evidências e aceite

- Testes Python da infraestrutura: `test-swift-test-index.py` e `test-project-sources.py`, 4 + 3 casos aprovados.
- Primeira execução isolada: `/private/tmp/sieghart-s6-input-part1`, 10/10 funções, 16/16 invocações, 125/125 fontes de produção; sem fontes alteradas, casos ausentes ou inesperados.
- Execução final focada: `/private/tmp/sieghart-s6-input-part1-verified`, **11/11 funções e 17/17 invocações aprovadas**, 125/125 fontes na cobertura, sem fontes alteradas, casos ausentes ou inesperados. Após finalizar screen lock e a invalidação de callback de start falho, somente o grupo `input` foi reexecutado. Contratos G19.01–G19.11, grupo/tag próprio `input`, roots LogicTests e MacContractsTests serializado. Fixtures usam defaults isolados e backend injetado. O teste da ponte CGEvent cria apenas uma amostra em memória; não instala taps ou publica eventos.
- Projeto sincronizado pelo gerador: 127 fontes app / 125 produção no target de testes. O runner deriva os grupos diretamente de GROUP_TAGS. O plano Fast foi atualizado pela descoberta final: 182 funções elegíveis; Complete descobre 246. A revisão de integração separou os gates de bloqueio/sessão e executou Fast: **182/182 funções e 867/867 invocações aprovadas**, em `/private/tmp/sieghart-s6-part1-fast-final`, sem alterações das fontes durante a execução. O Complete foi apenas descoberto nesta parte.
- Nenhum Sieg ou Xcode UI foi aberto; não houve acesso a hardware, event tap real, pedido de permissão, modelo ou conta. Build/testes CLI não demonstram comportamento físico ou desempenho.

Aceite Mac pendente: ligar cada opção em app autorizado, conferir roda mouse e trackpad/contínuos, signs/precision e inércia em apps diferentes, Shift sem dupla conversão, coexistência dos três modificadores com atalhos, revogação no painel do sistema, screen lock/sono/wake, encerramento e ausência de duplicação/CPU indevida. A revisão de integração corrigiu a independência dos gates e validou as regressões de atalhos/voz no Fast. A revisão independente de fechamento da Sprint 6 permanece para o conjunto final.

A pesquisa HeyClicky/voz recebida de outra worktree serve de referência e permanece não integrada; não houve cherry-pick nem alegação de merge. Aegis e migração Toni/Gantt/hellman não pertencem a este lote.

A [auditoria de aderência ao roadmap](sprint-roadmap-audit-2026-10-18.md) conferiu 77 IDs únicos e os compromissos S1–S5. As seis pendências antigas da ilha foram explicitadas como backlog para replanejar após S6; histórico GitHub/macOS e extensões vagas foram esclarecidos. A seção Aegis local de outro chat foi preservada e não incluída neste commit.

Evidências duráveis resumidas: [Fast revisado](../Validation/sprint-6-part1/fast-verification.json), [verificação](../Validation/sprint-6-part1/verification.json), [contratos](../Validation/sprint-6-part1/contract-results.json), [hashes das fontes](../Validation/sprint-6-part1/source-manifest.json). Logs, índice completo, descoberta e xcresult permanecem na pasta temporária da execução.

## Vinte IDs de S6 e próximos lotes

| Lote / IDs | Estado |
| --- | --- |
| 1: `scrollInverter`, `scrollHorizontal` | Implementação e revisão de integração nesta parte; aceite Mac pendente |
| Entrada — `smoothScroll`, `linearScroll`, `mouseAcceleration` | Planejados; definir pipeline de suavização/linearidade e limites de configuração sem alterar preferências globais sem restauração |
| Entrada — `focusFollowsMouse`, `mouseNavigation`, `mouseButtonShortcuts` | Planejados; definir foco, navegação e conflitos de botões |
| Entrada — `mouseClickDebounce`, `keyboardDebounce`, `textSnippets`, `superKey`, `quitWindowProtection` | Planejados; cada módulo exige escopo, permissões e aceite próprios |
| Windows/Dock — `switcher`, `dockPreview`, `dockClick`, `windowMaximizer`, `windowLayout`, `autoQuit`, `spacesOrder` | Sete IDs planejados; sequência e contratos a definir pela coordenação |

Total: dois IDs implementados neste lote, dezoito ainda planejados. `middleClick` já era entrega S4 e não é recontado como módulo novo de S6. Nenhum lote futuro foi iniciado.
