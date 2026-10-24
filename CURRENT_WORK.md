# Trabalho atual — checkpoint vivo

Atualizado em 24/10/2026, horário de Recife. Leia também `HANDOFF.md` e `KNOWN_ISSUES.md`.

## Regra de continuidade

Atualizar este arquivo ao encerrar uma mudança, antes de interromper o trabalho, antes de trocar de contexto e antes de commit/push autorizado. Não esperar o limite de contexto. Uma execução de teste simulada não comprova uso físico de voz, visão ou qualidade do modelo.

## Pedido ativo

O usuário pediu uma branch no GitHub com o estado atual para continuar no Claude, documentação portátil além do Obsidian e um registro contínuo do trabalho. Depois desse ponto de preservação, o desenvolvimento deve continuar em outra branch para não modificar o ponto de partida do Claude. Ainda não há autorização para commits/push futuros fora deste snapshot.

## Estado técnico confirmado

- Fonte ativa: esta pasta, `sieghart-spatial-assistant`. A pasta irmã `../Sieghart` é a original e deve ser preservada.
- Branch de origem: `feature/sieghart-spatial-assistant`; último commit antes do snapshot: `e229194`.
- App instalado e aberto: `/Applications/Sieghart.app`, build **106**, bundle `com.sieghart.app`, universal x86_64/arm64. SHA-256 do executável: `ce33c1cb340d35fda81fed732b7fad93925dc6aabde113adc38efbdb1fef522a`.
- Último teste amplo: **371 funções / 1141 invocações aprovadas**, fontes estáveis, 195/195 arquivos de produção instrumentados. Oito testes Python do guard de atualização também passaram.
- Sem microfone real, reprodução de áudio, AirPods ou atalho físico nesta etapa.
- Keep Awake estava realmente ativo após a atualização, com proteção nativa de tela e mesmo prazo de término: **23/10/2026, 17:23:45 em Recife**. Isso é evidência histórica, não afirmação de que permanece ativo ao ler este documento. Nenhuma sessão foi iniciada/reiniciada para teste.
- Home do build 106 observada; Tab moveu foco para Conversas e o contorno de foco foi conferido visualmente. A revisão adicional de rolagem foi interrompida por limite de uso da revisão automática da ferramenta de interface. Não contornar esse bloqueio.

## Alterações funcionais desta continuação

1. Duração de Keep Awake aceita “com 2hrs” e opções explícitas de manter a tela ligada. Persistência fica no controlador. Uma chamada de ferramenta impressa pelo modelo não conta como execução.
2. Atualizações preservam uma proteção temporária até a nova proteção nativa ser confirmada, respeitando o prazo original da sessão.
3. O contexto meteorológico não pode tratar qualquer frase curta como cidade. “E Lisboa?” continua sendo uma continuação; um pedido novo mantém a própria intenção.
4. Desenhar + explicar preserva o pedido completo e o resultado real do canvas; a explicação não é reinterpretada como clima. O motor Apple não recebe ferramentas para repetir esse desenho.
5. OCR de interface prioriza o modo rápido local; o modo preciso permanece como alternativa quando não há leitura. Imagem de teste reconhecida em 0,185 s. O modo preciso demorou cerca de 49 s neste Mac.
6. Removida a resposta pronta de pi e relatos fabricados do fallback. Sem modelo, geração retorna indisponibilidade; ferramentas nativas continuam podendo produzir resultados reais.

Detalhes: `Sieghart/Design/Workflow/sieg-intent-and-awake-recovery-2026-10-23.md`. Evidências portáteis: `Sieghart/Design/Workflow/evidence/sieg-intent-recovery-2026-10-23/`.

## Em andamento neste exato checkpoint

- Inventário concluído: documentação existente indexada; 59 arquivos de dossiês/evidências preservados da pasta original, com manifesto de origem/hash.
- Criados `HANDOFF.md`, `KNOWN_ISSUES.md`, `RESEARCH_INDEX.md` e `CLAUDE.md`; README e AGENTS indicam a ordem de leitura e o checkpoint obrigatório.
- Branch de snapshot criada: `feature/sieghart-claude-handoff-2026-10-23`. Em 24/10 o Git voltou a responder, com 6,9 GiB disponíveis no início da retomada. Os 1275 arquivos do snapshot foram lidos; 675 arquivos textuais/gzip passaram pela busca de padrões de credenciais sem ocorrências. Links dos documentos de entrada conferidos; 59 evidências de pesquisa conferidas, considerando a normalização CRLF/LF do README já existente. Commit e push ainda em andamento.
- Ainda não registrar branch remota/commit como publicados: a publicação só estará concluída após confirmação do GitHub.

## Próximo trabalho do produto

1. Validar com o usuário: clima → pedido composto de desenho/explicação; cidades e seguimento; tela real com permissão; Keep Awake com tela ligada.
2. Ensaiar diagramas gerados pelo modelo com código real de uma classe visível, sem confundir fixtures aprovadas com aceitação de qualidade.
3. Conferir rolagem e estados extensos/erros nas 16 abas, concluir traduções dinâmicas e revisão visual/acessível.
4. Medir voz física, interrupção, AirPods, segurar/soltar e troca de monitor somente quando o usuário autorizar.

## Cuidados indispensáveis

- Um agente por vez. Astra proibido; máximo autorizado para agentes: GPT-6.1 Sol. Não criar worktrees, não perder alterações de outros chats.
- Sempre abrir o app pelo LaunchServices (`Tools/launch-current-app.sh`), nunca executar `Contents/MacOS/Sieghart` diretamente: há histórico de crash por atribuição TCC ao app pai.
- Antes de encerrar o app para atualizar: `python3 Tools/hold-awake-during-update.py prepare`; depois instalar e abrir com `--resume-keep-awake-session`. Conferir resultado, não apenas o contador.
- Alguns arquivos locais estavam como placeholders do iCloud. Ler por tamanho e comparar antes de editar; não sobrescrever um arquivo que parece vazio por falha de hidratação. `/tmp/sieghart-spatial-dd/SourceWorkspace` foi usado como cópia materializada para build, não como fonte permanente do projeto.
- Não declarar “produto completo”, paridade 1:1 ou design final enquanto os critérios reais estiverem pendentes.

## Histórico do bloqueio da publicação — 23/10/2026

A branch local `feature/sieghart-claude-handoff-2026-10-23` foi criada, mas **não há commit novo nem push confirmado**. O disco atingiu 100% e houve `ENOSPC`. Foram removidos somente caches de compilação deste chat; a disponibilidade continuou baixa enquanto outros projetos trabalhavam. O iCloud passou a retornar timeout para o arquivo `.git` e a metainformação do worktree; Git deixou temporariamente de reconhecer o repositório. Não reconstruir nem sobrescrever `.git`, não apagar trabalho de outros projetos e não declarar publicação concluída.

Próximo passo: liberar espaço suficiente no Mac, materializar a pasta do projeto e seus metadados Git e então conferir estado/arquivos, commitar e fazer push do snapshot autorizado. As fontes/relatórios não foram descartados. A cópia materializada de build continua em `/tmp/sieghart-spatial-dd/SourceWorkspace`, e o app instalado é o build 106. Um backup essencial dos seis documentos de entrada foi salvo e verificado em `/tmp/Sieghart-Handoff-ESSENCIAL-2026-10-23.zip`; é uma salvaguarda de contexto, não uma distribuição completa do app ou substituto do push. A tentativa de arquivo maior encontrou as mesmas limitações do iCloud e não conta como backup completo.

Para economizar cota, não iniciar novas funcionalidades ou agentes antes de concluir a preservação. Atualizar este checkpoint quando o GitHub confirmar o SHA remoto.

## Retomada de 24/10/2026

O bloqueio de acesso ao Git não se repetiu na conferência atual. O objetivo deste lote é exclusivamente concluir o snapshot autorizado: commit, push e verificação do SHA remoto. Nenhum teste de áudio, nova funcionalidade, agente ou worktree foi iniciado. A varredura de padrões de credenciais é uma precaução de publicação, não uma auditoria de segurança completa. O produto permanece com os limites de `KNOWN_ISSUES.md`.
