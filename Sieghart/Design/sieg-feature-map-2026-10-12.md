# Sieg — mapa consolidado de funcionalidades

12 de outubro de 2026. Direção de produto consolidada a pedido do usuário. Este documento distingue a base implementada das funcionalidades propostas. A Sprint 5 continua em andamento; esta revisão não instala integrações nem altera o código do app.

## Decisões atuais

- Sig é o principal e o orquestrador permanente. Rita, Ada, Gantt, Elinor e Toni têm responsabilidades próprias. Personalizações do Sig e as biografias serão refinadas com o usuário.
- A conexão bancária será uma funcionalidade do próprio Sieg: selecionar instituição, autorizar no banco e retornar ao Sieg. Pierre é referência de experiência, não o serviço escolhido para conectar os bancos. A infraestrutura de Open Finance, o enquadramento de participação/parceria, cobertura, contratos e custos serão definidos numa etapa técnica posterior.
- O produto completo poderá ter integrações online opcionais. A edição do Swift Student Challenge terá uma jornada completa offline, inclusive depois do onboarding, com recursos locais e exemplos identificados como demonstração.
- Utilidade central: capturar uma intenção, apresentar um primeiro passo, ajudar a começar e permitir retomar depois de uma interrupção. Os avatares expressam o estado real dessas ações.
- Fontes e técnicas estudadas orientam a implementação original do Sieg. A inclusão de componentes de terceiros depende da licença e compatibilidade; a existência de um recurso numa referência não significa que já foi implementado aqui.

## Equipe e responsabilidades

| Avatar | Responsabilidade proposta | Experiência local | Extensões conectadas |
| --- | --- | --- | --- |
| Sig | Orquestração, foco e continuidade | Captura de tarefas, primeiro passo, Pomodoro, pausa, próxima ação e retomada | Coordenar tarefas que envolvem serviços autorizados |
| Rita | Bem-estar e pausas | Lembretes escolhidos pelo usuário, descanso e horários silenciosos | Apple Watch/Health e movimento de AirPods, com fontes e compatibilidade verificadas |
| Ada | Código, tecnologia e conhecimento | Organizar uma tarefa de código e consultar material local | GitHub, PRs, builds e resumo finito de notícias de tech/IA |
| Gantt | Agenda e compromissos | Planejamento do dia, eventos disponíveis localmente e lembretes | Sincronização de calendários externos e ações em contas escolhidas |
| Elinor | Organização financeira | Importação de extratos, categorias, orçamento e compromissos | Conexões bancárias de Open Finance oferecidas pelo Sieg |
| Toni | Comunicação e arquivos | Receber e organizar um arquivo, preparar um texto ou rascunho | Upload, compartilhamento, email e entrega em serviços conectados |

Os especialistas ainda não executam esses papéis como agentes. O núcleo de Pomodoro e a primeira implementação de calendário são componentes existentes; a delegação e a continuidade propostas precisam de um runtime de tarefas. Nenhum avatar deve abrir uma ferramenta sem relação com sua responsabilidade.

## Funcionalidades mapeadas

| Área | O que trazer para o Sieg | Referências e evidência | Situação |
| --- | --- | --- | --- |
| Voz contextual | Fim de fala por atividade/silêncio, progresso da pausa, transcrição, cancelamento, escolha de microfone, respostas faladas e distinção entre pergunta, ditado e ação na mesma superfície | Clicky: experiência publicada; Taby: observações estáticas de captura e endpointing | Comandos locais e busca existentes; conversa contextual e ditado ainda propostos |
| Contexto escolhido | Anexar texto, arquivo, imagem ou captura; extrair texto e oferecer orientação visual sobre um alvo verificável | Clicky, Vorssaint e Coucou | Captura/OCR fazem parte da S5; contexto conversacional e orientação por IA propostos |
| Planejamento e retomada | Despejo de ideias, poucos passos concretos, uma ação atual, fila de tarefas e registro de onde o usuário parou | OpenJarvis, Taby e objetivo próprio de apoio à organização | Proposto |
| Motor compartilhado | Sessões vinculadas a uma tarefa, seleção de ferramentas por papel, memória controlável, limites, cancelamento e resultados verificáveis | OpenJarvis e Coucou | Proposto; a leitura de uso de Codex/Claude não é esse runtime |
| IA local | Foundation Models para interpretação, extração, planejamento e resumos; verificação de disponibilidade e caminho útil sem modelo | Framework Apple e adaptador de fonte do OpenJarvis | Proposto; ainda não integrado |
| Animações e relação | Apresentação aprovada da equipe, expressões por estado, gestos próprios por papel, fala sincronizada, espera/interrupção e memória de preferências | Choreografia do Coucou; Rive/vídeos no pacote do Taby; identidade original do Sieg | Equipe/apresentação e renderer aplicados; qualidade e desempenho em validação; novos gestos/fala propostos |
| Calendário e rotina | Dia/semana/mês, próximo evento, lembretes, snooze, horários silenciosos e plano do dia | Vorssaint, Taby, OpenJarvis | Primeiro recorte da S5 implementado; aceite físico pendente; planejamento por agente proposto |
| Arquivos até o resultado | Prateleira temporária, referências a arquivos, downloads de pastas escolhidas, preparação de mensagem e etapas retomáveis de upload/envio | Vorssaint e Coucou | Prateleira/downloads/helpers na S5; upload/email conectados posteriores |
| Conectores e agentes | GitHub, Obsidian, calendário, email, chats suportados e ferramentas MCP; destino, resultado e permissões por conexão | Coucou, OpenJarvis e interfaces públicas documentadas | Proposto; cada serviço precisa de um adaptador verificado |
| Finanças | Conectar bancos dentro do Sieg, consolidar dados autorizados, organizar gastos/parcelas, orçamento, lembretes e possíveis recorrências | Experiência Pierre; especificações de Open Finance e documentação de provedores | Proposto; seleção de infraestrutura pendente; primeiro recorte de leitura/organização |
| Notícias | Fontes reais, datas, deduplicação, lista finita, salvar para depois e entrega escolhida fora do foco | OpenJarvis e papel tech/IA da Ada | Proposto; notícias atuais exigem rede |
| Bem-estar | Pausas configuráveis, duração da sessão e lembretes; fontes reais para eventuais sinais de relógio/fones | Objetivo próprio e extensões consideradas com APIs Apple | Lembretes como base; dispositivos e sinais ainda por validar |
| Utilitários e personalização | Painéis compactos, botões laterais editáveis, atalhos, clipboard, mixer, energia, monitor e escolha de módulos | Vorssaint; MiddleClick para referência do gesto opcional | Base relevante entregue; módulos restantes no roadmap |
| Controle dos apps | Executar ações suportadas e verificar o resultado em vez de presumir que um clique funcionou | Documentação empacotada do driver de computer use do Clicky | Pesquisa inicial; sem integração de controle geral |

### Base já implementada

O registro de aceite continua no [roadmap](../../ROADMAP.md): foco/Pomodoro, clipboard local e limpeza configurável, editor visual da ilha e laterais, aparência/Glass opcionais, atalhos globais, lançamento de apps por voz, busca no navegador, mixer com até cinco apps elegíveis e volume geral, dispositivos de áudio, manter acordado, controles compatíveis de tela e monitor básico. As Sprints 3 e 4 foram aceitas pelo usuário.

A Sprint 5 tem um primeiro recorte de calendário e lembretes implementado. Prateleira, downloads de pastas escolhidas, helpers e captura seguem pendentes. As alterações posteriores da equipe/animação têm verificações isoladas e uma apresentação visual aprovada; isso não substitui o aceite de qualidade e consumo do app completo.

### Cobertura ampliada do Vorssaint

O inventário completo existente contém 77 módulos e permanece no roadmap, com status por módulo. Além da base atual, inclui:

- Janelas/Dock: alternador, previews, comportamento de clique, maximização, encaixes/layouts, fechamento e Spaces.
- Mouse/teclado: rolagem, aceleração, botões adicionais, snippets, Hyper key e proteção de fechar/sair.
- Arquivos/captura: colar texto simples, cortar/colar/renomear, prateleira, limpeza de URLs, instalação explícita de DMGs, screenshot, anotação, OCR/QR e cor.
- Outras ferramentas: scratchpad, barra de comandos, menu radial, limpeza/desinstalação, pacotes/atualizações, mídia/gravação, processos e portas.
- Ilha: notificações, gestos, acessórios, fila/letras de música, barras de áudio, downloads e monitoramento de área escolhida.
- Hardware avançado: tráfego por processo, testes de rede, SMART/ejeção, temperatura numérica, ventoinhas e capacidades específicas de tela.

Esses módulos não se tornam obrigatórios para a demonstração de três minutos. As faixas S5–S7 indicam planejamento do produto Mac, não que todas as funções já existam.

## Desempenho e fidelidade visual

Preservar a apresentação aprovada. Comparar as mesmas animações e dimensões do Sieg em seu renderer atual, num protótipo Rive e numa alternativa de animações autoradas. Validar Retina, bordas transparentes, gaze, cancelamento e transições interrompidas.

Medir CPU/GPU, memória, energia e responsividade no app completo; pausar superfícies invisíveis e limitar trabalho à função em uso. A presença de Rive ou vídeos em outro app não comprova menor consumo. Papéis diferentes podem compartilhar o motor de IA; não exigem seis modelos continuamente ativos.

## Edição Swift Student Challenge

Os [requisitos publicados pela Apple](https://developer.apple.com/swift-student-challenge/eligibility/) estabelecem julgamento offline, experiência em até três minutos, recursos locais, ZIP de até 25 MB e conteúdo em inglês. A [política publicada](https://developer.apple.com/swift-student-challenge/policy/) permite tecnologias de Apple Intelligence no dispositivo. Esses documentos ainda identificam a edição 2026; os requisitos da próxima edição devem ser revalidados na preparação da inscrição.

### Contrato da demonstração

- A jornada inteira termina sem rede, login, chave de API, banco real ou download de modelos/recursos.
- Os dados de calendário, documentos, código e finanças usados como exemplos vêm no pacote e são claramente identificados como demonstração.
- As tarefas locais demonstradas produzem mudanças locais reais: organizar, planejar, iniciar foco, salvar estado e retomar. Envio de email, upload, dados bancários ao vivo ou notícias atuais não são apresentados como execução real offline.
- Foundation Models e voz no dispositivo são opcionais à disponibilidade do ambiente. A entrada por teclado e um fluxo local sem modelo permitem completar a mesma história.
- Conteúdo e personagens ficam disponíveis localmente, com animação reduzida, VoiceOver, teclado e opção de pular/repetir a apresentação.
- A cena funciona dentro do playground, sem depender de uma notch física, atalhos globais, sensores ou serviços Mac específicos. Recursos incompatíveis/privados ficam fora do pacote.
- Atualização de preços/FX, web search, bancos, conectores, telemetria e notícias online não iniciam tarefas de rede na edição Challenge. Essa separação ainda precisa ser implementada e verificada.

### História proposta — conteúdo final do usuário

1. **0–35 s:** Sig recebe o usuário e apresenta a equipe pela animação aprovada.
2. **35–80 s:** o usuário escolhe uma situação de excesso de tarefas; o app apresenta um primeiro passo concreto.
3. **80–120 s:** organiza um arquivo ou compromisso local e inicia uma interação de foco.
4. **120–160 s:** uma interrupção demonstra salvar e retomar exatamente o próximo passo.
5. **160–180 s:** mostra o resultado, autonomia e controles locais.

Apresentar todos os avatares não obriga o juiz a testar seis fluxos separados. A história escolhida deve demonstrar uma transformação útil, enquanto os demais especialistas ficam disponíveis para exploração.

## Ordem recomendada

1. Validar desempenho/nitidez no app completo e preservar a apresentação aprovada.
2. Fechar o núcleo atual da Sprint 5: calendário/lembretes, arquivos, helpers/captura e aceite.
3. Construir o motor local de tarefas, memória controlável e retomada; depois interpretação local e voz contextual.
4. Montar e medir a jornada completa do Challenge, com pacote offline e conteúdo do usuário.
5. Evoluir o produto conectado: GitHub/Obsidian/email, notícias, conexão bancária do Sieg e rotinas dos especialistas.
6. Continuar a cobertura dos utilitários Mac e as integrações de dispositivos/saúde ou bloqueio do celular conforme suporte e validação.

Fontes de pesquisa internas: [Clicky/Taby](Research/hey-assistants-2026-10-11/README.md), [OpenJarvis](Research/openjarvis-reference-2026-10-11.md), [capacidades dos companions](companion-capabilities.md) e [direção de produto](product-direction-2026-10-11.md). Prioridades são propostas; não há início automático de serviços ou conexões por este documento.
