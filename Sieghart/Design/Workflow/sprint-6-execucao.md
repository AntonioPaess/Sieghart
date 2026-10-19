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
| 2: `switcher`, `windowLayout` | Implementados; Fast/build e aceite detalhados abaixo |
| Windows/Dock — `dockPreview`, `dockClick`, `windowMaximizer`, `autoQuit`, `spacesOrder` | Cinco IDs planejados; não confundir ação de preencher a tela com interceptação do botão verde |

Total após a parte 2: quatro IDs com implementação, dezesseis ainda planejados. `middleClick` já era entrega S4 e não é recontado como módulo novo de S6. Os demais lotes não foram iniciados.


## Parte 2 — layouts, encaixe e seletor de apps/janelas

19 de outubro de 2026, na mesma branch `sprint-6`, após `2b9d5e8`. Implementação sequencial pela sessão principal; nenhum agente adicional iniciado. Este lote cobre os IDs `windowLayout` e `switcher`. `windowMaximizer` significa o botão verde e permanece planejado. As referências de voz/ditado/desenho e Aegis continuam fora deste lote, com os limites registrados na auditoria.

Workspace → Windows e menu → More tools → Windows compartilham o mesmo controller. A lista só consulta o sistema após Refresh, tem busca local, seleção explícita para layouts, botões próprios para solicitar ativação do app ou elevar uma janela e feedback de falha. Não substitui Cmd-Tab. As mensagens de ativação descrevem a solicitação enviada à API, não confirmação visual de foco. A lista exclui o próprio app, apps sem interface regular, janelas minimizadas/full-screen e janelas sem geometria legível. Apps com data de lançamento não verificável não são ativados pelo backend.

O backend nativo usa Accessibility pública e revalida permissão, PID/data de lançamento e elemento AX antes da operação. IDs de janela são UUIDs associados à igualdade do elemento AX e à instância do processo, nunca à posição na lista. A descoberta consulta até 64 apps, 32 janelas por app e 128 janelas no total, com orçamento de um segundo verificado entre consultas e timeout AX de 80 ms por mensagem; a última sequência de atributos pode ultrapassar o orçamento. Uma lista interrompida é marcada Partial e pode ser atualizada explicitamente. Mantém no máximo 256 handles AX. Não lê imagens, conteúdo das janelas ou teclas.

Os oito layouts são metades esquerda/direita, quatro cantos, preencher a área útil e centralizar. Usam visibleFrame convertido para coordenadas AX a partir da tela primária; telas acima/à esquerda e origens negativas são suportadas. A tela de destino do botão é a de maior interseção com a janela atual; se desconectada, usa a mais próxima. O Dock/menu ficam fora da área útil. Centralizar limita o tamanho à área útil. Escrita verifica se posição e tamanho são alteráveis, lê o resultado efetivo e informa restrições do app. Falha parcial tenta restaurar ambos os atributos e distingue restauração confirmada de falha de restauração.

Undo guarda até 32 mudanças efetivas e só restaura a mesma janela se sua geometria atual ainda corresponder à última escrita (tolerância de dois pontos). Não sobrescreve reposicionamento manual posterior nem janela fechada. Se a restauração for recusada e a geometria continuar inalterada, conserva a entrada para Retry. Não altera preferências globais nem restaura automaticamente no encerramento.

Edge snapping fica desligado por padrão, persistido em `desktop.edgeSnapping`. O monitor global só é instalado após opt-in e Accessibility; observa down/dragged/up do botão esquerdo, sem consumir nem publicar eventos e sem polling. Guarda a janela sob o ponto de down; exige arrasto do ponteiro superior a quatro pontos, mesma janela/processo, deslocamento real de origem e tamanho sem mudança relevante. Clique simples, movimento do app sem arrasto, resize e janela fechada são ignorados. No release, proximidade de 20 pontos da borda física escolhe metade/canto; topo preenche área útil e base isolada não age. Undo restaura a posição onde o usuário soltou, preservando seu próprio arrasto.

Sono, lock e sessão inativa são gates independentes. Disable, stop e suspensão removem o monitor e invalidam candidatos/callbacks por geração; retomar requer o opt-in ainda ativo. Revogação é reavaliada em cada evento e ação; não existe tarefa periódica de saúde neste controller. Retry é explícito após permissão ou falha de instalação. Inicialização, previews e fixtures `managesWindows: false` não instalam monitor nem consultam janelas.

### Validação da parte 2

- Infraestrutura Python: 3 testes do gerador e 4 do índice aprovados. Projeto: 131 fontes no app, 129 de produção e 77 de testes/support no target de testes.
- Primeira execução focada `/private/tmp/sieghart-s6-desktop-part2`: 13 funções / 20 invocações aprovadas. Depois dessa execução, a revisão adicionou a exigência de evento dragged, posição obtida do próprio CGEvent, validação de data de lançamento e Retry seguro do Undo.
- Fast final `/private/tmp/sieghart-s6-part2-fast-reviewed`: **195/195 funções e 887/887 invocações aprovadas**, 129/129 fontes de produção, nenhuma fonte alterada, nenhum caso ausente ou inesperado. Todos os contratos G20.01–G20.13 foram incluídos. Complete descobriu 259 funções; não foi reexecutado integralmente nesta parte.
- Build Debug do aplicativo completo: **BUILD SUCCEEDED**, arm64 + x86_64, sem assinatura e sem executar o app. A tentativa inicial no workspace exclusivo dos testes não tinha o Info.plist da raiz; a execução final usou o projeto original. Nenhuma fonte diverge do manifesto Fast aprovado.
- Geometria, múltiplas telas, falha parcial/rollback, limite de Undo, handles antigos, constraints, opt-in/permissão, clique/resize/arrasto, callbacks obsoletos, lock/sono/sessão e ativação explícita foram exercitados com fixtures. Nenhum teste instalou monitor global, chamou AX nativo ou ativou apps/janelas reais.

Aceite físico pendente: Refresh e ativação em apps nativos/terceiros, app sem janelas, limites de tamanho e janelas que recusam AX; monitores Retina e secundários acima/à esquerda; Dock em lados diferentes; encaixe real por título, resize/clique sem encaixe, Spaces/full-screen; Undo após mover manualmente/fechar janela; revogação, lock/wake e encerramento; CPU e responsividade de apps lentos. A revisão independente de fechamento da Sprint 6 continua pendente, além do aceite físico. Este commit não declara a sprint inteira concluída.

Evidências da parte 2: [Fast](../Validation/sprint-6-part2/verification.json), [contratos G20](../Validation/sprint-6-part2/contract-results.json), [manifesto](../Validation/sprint-6-part2/source-manifest.json) e [build do app](../Validation/sprint-6-part2/app-build.json). Logs e xcresult ficam nas pastas temporárias acima.
