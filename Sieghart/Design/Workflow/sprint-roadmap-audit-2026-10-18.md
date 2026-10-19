# Auditoria de sprints e ROADMAP — 18/10/2026

Auditoria estática sequencial sobre a branch `sprint-6`, após o merge `04723e7`. Sem alteração de implementação, commit, push ou edição do `ROADMAP.md` local de outro chat. Não foram iniciados app/Xcode, modelos, contas, permissões ou hardware. As evidências de execução e a revisão independente da pré-S6 foram reaproveitadas.

## Parecer

**Não identifiquei omissão concreta de implementação no escopo core comprometido de S1–S5, nem módulo pendente apresentado inequivocamente como integralmente entregue.** S3/S4 estão aceitas pelo relato do usuário; S5 tem implementação entregue e aceite físico pendente. Há problemas concretos de atualização e alocação documental abaixo. A leitura não prova equivalência exaustiva de todos os comportamentos nem aceite físico.

Conferência mecânica da matriz: **77 linhas, 77 IDs únicos**. S6 tem **20 módulos pendentes**: sete Windows/Dock e treze mouse/teclado. O décimo quarto item de entrada, `middleClick`, já foi antecipado e aceito em S4; não deve ser contado novamente como entrega nova de S6 (`ROADMAP.md:271–298`).

## Achados por prioridade

### P2 — Realocar pendências antigas da ilha e especificar extensões vagas

`ROADMAP.md:362–370` ainda atribui `notchGestures`, `notchAccessories`, `notchLyrics`, `notchQueue`, `notchLiveEqualizer` e `notchWatch` a **S3–S5**, todos `Planned`. `notchTimer` e `notchAgents` dizem que restam extensões de S5 sem enumerá-las. `notch` também conserva controle central mais amplo pendente com entrega S3 + S5 (`ROADMAP.md:359`). Isso impede saber em qual marco os resíduos serão encerrados.

**Não são omissões comprovadas do core S5:** o plano limita explicitamente esse core e conserva mídia/acessórios/gestos como matriz mais ampla (`Sieghart/Design/sprint-5-plan.md:44–46`); monitoramento contínuo de área está explicitamente adiado no closeout (`Sieghart/Design/sprint-5-closeout.md:44`). Ação: preservar os IDs e registrar destino/escopo residual e critério de conclusão; não declarar esses itens entregues, nem incorporá-los silenciosamente à S6. As janelas S5–S7 de Tools também não são requisitos adicionais para fechar S5.

### P3 — GitHub e runtime de chat têm descrições correntes e históricas misturadas

`ROADMAP.md:237` afirma que nenhuma conexão GitHub está implementada, mas `ROADMAP.md:9` registra o porte token/Keychain/service-tool. O guia atual descreve esse caminho e suas fronteiras (`Sieghart/Design/ada-room-test-guide.md:26–34`), e existem `Core/Services/AI/AdaGitHubContext.swift`, `AdaGitHubCredentials.swift`, `AdaGitHubTool.swift`, `Features/AgentRoom/ViewModels/AdaGitHubViewModel.swift` e testes `Tests/SwiftTesting/Integration/AdaGitHubTests.swift`.

O registro de 13/out em `ROADMAP.md:7` descreve Codex/Claude e diz Foundation Models planejado; o de 14/out e o guia atual substituem o runtime do chat por Apple. Ação: rotular trechos antigos como históricos/superados e tornar explícito que **o adaptador implementado não equivale a conta/modelo aceito em execução real**, nem a ferramentas de edição, terminal ou navegador.

### P3 — Pré-requisito de sistema operacional desatualizado

`ROADMAP.md:9` chama macOS 26.6.2 de host atual. `Sieghart/Design/ada-room-test-guide.md:7` já registra host 27.0.1 observado em 15/out. Ação: datar a observação antiga e apontar ao guia atual. A atualização do SO não fecha disponibilidade do modelo, entitlement, provisioning ou aceite PCC (`ada-room-test-guide.md:9–12`). Não houve nova inspeção do host nesta auditoria.

## Cobertura por sprint

| Sprint | Rastreabilidade encontrada | Situação e limite |
| --- | --- | --- |
| S1 | `ROADMAP.md:20`; `Core/Helpers/TimerModels.swift`, `NotchGeometry.swift`; testes atuais `Core/TimerTests.swift` e contratos G01/G04.05 do inventário pré-S6 | Fundação, persistência e geometria preservadas em fontes/testes atuais. Não localizei closeout separado de S1; não atribuo retrospectivamente aceite físico individual. |
| S2 | `ROADMAP.md:21` registra `db2ea4f`; preferências, companions, ilha, quotas e ledger aparecem no inventário G01/G04/G05–G09 e nas suítes Swift Testing correspondentes | Implementação histórica rastreável por documento e continuidade atual. Não localizei closeout separado de S2 e não revalidei o commit antigo. Build/headless não são aceite Mac. |
| S3 | `Design/sprint-3-closeout.md:9–28`: onboarding, ilha, aparência, atalhos, voz, painel IA, custos/imports/histórico/Claude e áudio | Nove grupos e build/renders documentados; aceite agregado do usuário em `:30–42`. Sem regressão concreta nova que justifique reabrir o aceite. |
| S4 | `Design/sprint-4-closeout.md:5–20`: clipboard/editor, middle click, onboarding, monitor base, awake, áudio, displays e regressões voz | Aceite após `f77ac65`; hardware avançado e compatibilidade Challenge explicitamente separados. Fontes de System/Clipboard/Input e suítes de monitor, áudio, clipboard e middle-click existem. |
| S5 | `Design/sprint-5-plan.md:15–23` corresponde às linhas Delivered de `sprint-5-closeout.md:9–21`; fontes Calendar, Files, Capture, PlainTextPaste e hub de eventos; suítes CalendarTests/FileCaptureTests/FileReceptionTests | Dezesseis grupos, build/bundle e nove exports documentados (`closeout:25–31`). **Não encerrada fisicamente** (`:36–38`). Correção de recepção 13/out tem evidência e roteiro próprios (`sprint-5-file-drop-followup.md:18–36`). |
| Pré-S6 | `Workflow/pre-sprint-6-execucao.md:9–20,36–40`; `pre-sprint-6-revisao-final.md:7–20` | Gate de migração executado/revisado: Complete 235/235, Fast 171/171; 132 IDs automáticos + A01 rastreados. Não é aceite do app ou encerramento físico S5. |

Na tabela, caminhos de produção são relativos a `Sieghart/Sieghart/`; caminhos das suítes a `Sieghart/Tests/SwiftTesting/`; documentos a `Sieghart/`, salvo indicação `ROADMAP.md`. O inventário identifica contratos e os resultados persistidos apontam seus destinos. Esta auditoria conferiu documentos, presença de fontes/suítes e trechos dirigidos; não releu integralmente as aproximadamente 9 mil linhas de testes. A baseline de 34,71% mede as 124 fontes do módulo de testes, fora de `App/`, e não o binário completo (`Tests/README.md:23–27`).

## Backlog explícito e gates preservados

- **S5 físico:** Calendar/notificações, Automation/Accessibility/captura, Finder/drag/share/Quick Look, paste real, downloads/sleep, cores, fullscreen, Retina e CPU/memória. Continuam pendentes; não são defeitos novos desta auditoria.
- **S7/ampliado:** manutenção, packages/updates, mídia/recording, processos/rede/fans e demais Tools; temperatura numérica, SMART/eject, XDR e periféricos ampliados estão expressos como backlog (`ROADMAP.md:210,331–353,377–384`). Não classificá-los como esquecimento de S5.
- **Challenge:** narrativa, biografias, destino/package e revisão de APIs/hardware seguem trilha separada (`ROADMAP.md:212–216`). O middle-click usa capacidade não documentada e deve ser omitido do pacote Challenge (`:46`).
- **Integrações:** email/upload, Open Finance, agentes especialistas, notícias e demais ferramentas têm dependências registradas. O chat GitHub implementado é um recorte específico; não demonstra esses outros fluxos.
- **Research não integrado:** o registro `field-findings-2026-10-18.md` da worktree `research/heyclicky-parity`, em `/Users/antoniopaesdeandrade/.codex/visualizations/2026/10/13/01a135bc-4eb1-7850-a2ab-4b21a85480b9/sieghart-heyclicky-parity/Sieghart/Sieghart-Research/roadmap/`, registra SIG-IDENTITY-01 (`:5–13`), SIG-ACTIONS-01 (`:15–23`) e APPLE-PCC-01 (`:25–32`). São relatos daquela worktree/build, não regressões automaticamente comprovadas na branch S6. A abertura de app/busca por comandos determinísticos aceita em S3 não comprova ferramenta equivalente conectada ao chat. Exigir revisão/integração e aceite próprio antes de prometer voz/ditado/desenho novos na baseline.
- **Aegis:** a seção local nova `ROADMAP.md:29–35` preserva pesquisa/probe e distingue produto/lab. Toni→Gantt/hellman permanece proposta. O dossiê `aegis-tcc/2026-10-15/audit/sprint-gates.md:41–62` é snapshot de 15/out: falha companions/runner ali descrita não reabre automaticamente o gate pré-S6 aprovado em 18/out. Estabilização integrada, freeze dos compromissos e laboratório permanecem gates próprios; esta auditoria não avalia eficácia defensiva.

## Primeiro lote recomendado para S6

Começar por **infraestrutura compartilhada de entrada + `scrollInverter` e `scrollHorizontal`**, um lote pequeno dos vinte IDs. Fixar antes o comportamento de mouse versus trackpad, modificador, combinação das duas opções, persistência e conflitos com atalhos existentes. Desligado por padrão; erro/revogação/disable/sleep/encerramento devem liberar o recurso próprio e preservar o comportamento normal. Não alterar preferências globais sem guardar/restaurar o valor e sem verificar propriedade da alteração.

Usar transformação pura dos eventos e backend injetável para testes de eixos, sinais, modificadores, eventos preservados, cancelamento/teardown e ausência de duplicação. Depois, build/bundle e roteiro físico focado, mantido pendente até execução autorizada. O lote fecha apenas seus dois módulos e infraestrutura; smooth/linear/acceleration, debounce, janelas/Dock e demais itens conservam IDs/aceites próprios. A autorização atual para iniciar S6 e o gate pré-S6 aprovado não devem ser confundidos com aceite físico S5 concluído.

## Tratamento na parte 1

Após esta leitura, o lote 1 de S6 registrou as seis pendências antigas da ilha como backlog a replanejar após S6, esclareceu as extensões ainda sem contrato e qualificou as referências históricas de GitHub/macOS. Não foram implementados módulos extras nem encerrado o aceite físico S5. A seção Aegis de outro chat foi preservada separadamente.
