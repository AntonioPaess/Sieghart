# Sieg — fluxo de especialistas

Configuração combinada em 16 de outubro de 2026. Estes papéis organizam o trabalho de desenvolvimento no Codex; não são agentes já executando dentro do aplicativo.

## Chats e responsabilidades

| Papel | Configuração | Entrega |
| --- | --- | --- |
| Coordenação | Chat principal existente | Escopo, decisões do usuário, distribuição de trabalho e integração final. |
| Avatares e animações | Modelo padrão do usuário | Conceitos, identidade, catálogo de movimentos, protótipos e recursos visuais aprovados. |
| Implementação | GPT-6.1 Sol · Extra alto (`xhigh`) | Código do app, integrações, correções e verificações necessárias. |
| Revisão | GPT-6.1 Sol · Ultra | Revisão independente de código, aparência, animações, acessibilidade e desempenho. |

O especialista visual mantém a [biblioteca de referência](avatar-animation-library.md). O código atual é a referência de implementação; os conceitos anteriores documentam opções, inclusive algumas rejeitadas. Referências de terceiros não significam autorização para reutilizar sua arte, marca ou outros recursos protegidos.

## Trabalho de cada papel

### Avatares e animações

- Ler a biblioteca e inventariar o material existente antes de propor mudanças. Registrar fonte, versão, comportamento, evidência, licença e uso no Sieg. Distinguir observado, implementado, aprovado, rejeitado e ainda não estudado.
- Preservar os seis personagens: Sig principal/orquestrador; Rita saúde/pausas; Ada código/GitHub; Gantt calendário/rotina; Elinor finanças/recursos; Toni comunicação/arquivos. Responsabilidades planejadas não equivalem a ferramentas já conectadas.
- Manter silhuetas e acessórios próprios, nitidez Retina, transparência limpa e movimentos distintos. Rita sem faixa branca permanente; Toni compacto e seguindo arquivos nos dois eixos.
- Preservar o onboarding aprovado: queda/alô/luz do Sig, cinco emergem em círculo e se posicionam, abertura do Sig apresentando a equipe, apresentações em fila, retorno do Sig e apresentação como orquestrador. Inglês padrão; português por escolha.
- Cobrir os estados comuns e os específicos de cada atividade. Não substituir loading por um corpo girando nem acrescentar cursor falso no hover.
- Entregar conceito e prévia quando solicitado; integrar no app somente quando a tarefa autorizar. Não redesenhar livremente o que o usuário já aprovou.
- Projetar idle esparso, parar trabalho quando invisível e evitar cenas/loops pesados por avatar. Declarar tamanho, escala e limites do recurso. Medições reais pertencem ao aceite no Mac.

### Implementação

- Ler o escopo e decisões recentes, preservar alterações de outros chats e implementar apenas o trabalho atribuído.
- Usar o código e recursos aprovados; não alterar a direção visual por conta própria. Concentrar alterações de projeto/recursos compartilhados neste papel durante a integração.
- Separar a experiência offline do Challenge das integrações opcionais online. Chat atual usa Apple Foundation Models; não recolocar Codex/Claude como conversas do produto sem nova decisão.
- Confirmar disponibilidade pelo SDK/OS, assinatura e serviço reais. Nunca prometer acesso a GitHub, terminal, contas ou múltiplos agentes sem adaptador funcionando.
- Entregar arquivos alterados, motivo, evidência de build/testes e limitações. Não abrir Sieg/Xcode, modelos, contas ou permissões reais sem autorização específica para a tarefa.

### Revisão

- Revisar um diff ou commit identificado. Não modificar o que está sendo revisado nem aprovar mudanças ainda desconhecidas.
- Examinar regressões, concorrência, cancelamento, persistência, permissões, privacidade, licenças, acessibilidade e funcionamento real. Conferir identidade visual, coreografia, bordas/halos, escala Retina, gesto e custo de animação.
- Ordenar achados por gravidade, com arquivo/local, reprodução, impacto e correção sugerida. Diferenciar falha comprovada, risco e pergunta.
- Distinguir testes simulados, renderização fora da tela e teste real no Mac. Não inferir CPU baixa, integração conectada ou qualidade do modelo a partir de fixtures.
- Relatar explicitamente quando não houver achados e registrar o que não foi testado. Não fazer commit/push ou corrigir automaticamente sem tarefa de implementação autorizada.

## Ciclo de entrega

1. Coordenação define objetivo, dono, arquivos/superfície, restrições e critério de aceite.
2. Especialista produz uma entrega delimitada com evidências e pendências. Um novo chat começa preparando contexto; isso não autoriza inventar a próxima sprint.
3. Revisão examina a entrega identificada. O autor corrige achados; o revisor confere as correções relevantes.
4. Coordenação integra e registra a decisão. Commit descreve o que foi entregue; push exige autorização do usuário para a entrega correspondente.

Chats próprios não compartilham memória automaticamente. O contexto persistente fica nestes documentos, no código, no catálogo e nas entregas registradas. A criação destes chats não estabelece monitoramento permanente nem comunicação automática entre eles. A coordenação deve enviar tarefas quando o usuário autorizar esse trabalho.

## Concorrência e Git

- Na mesma pasta, apenas um autor por conjunto de arquivos. Revisão permanece somente leitura enquanto o diff está aberto.
- Para implementação simultânea que se sobrepõe, usar worktrees e branches separados quando isso for solicitado; integrar depois da revisão. Evitar alterações concorrentes em `project.pbxproj`, registros de recursos e documentos centrais.
- Não usar prefixo `codex/` nas branches deste projeto. Não criar branches futuras sem escopo definido.
- Preparar commits com seleção explícita de arquivos, inspeção do diff e verificação de segredos. Excluir ambientes virtuais, builds, dumps de terceiros, credenciais e material acadêmico alheio à entrega.
- Não fazer push forçado, rebase de histórico publicado, merge em main ou publicação por consequência implícita de uma revisão.

## Estado de fechamento da sprint 5

Entrega de implementação e preservação em Git não equivalem ao aceite físico completo. Permanecem verificações reais de CPU/RAM, permissões/alertas, Finder/arraste/captura/clipboard, modelo Apple e conexão GitHub. O Mac foi observado com macOS 27.0.1 em 15 de outubro; o requisito antigo de atualização do sistema já não é a pendência observada. A disponibilidade do modelo ainda precisa ser conferida e thinking PCC depende da autorização/assinatura gerenciada da Apple. Consultar o guia atual da Ada antes de anunciar disponibilidade.

Um papel adicional de desempenho/aceite pode ser convocado para testes reais. Um operador Git permanente e um agente para criar outros agentes são opcionais; inicialmente usar este contrato e a coordenação existente.
