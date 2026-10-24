# Sieg — continuação do produto em 21/10/2026

Pedido: implementar as lacunas de conversa, tela, especialistas, pesquisa,
continuidade e acabamento. Um agente; worktree espacial; sem commit/push.
Preparação SSC adiada. Restrição mantida: nenhum teste de microfone ou som.

## Implementação

- Modo de conversa explicitamente iniciado pelo usuário, com reconhecimento
  durante respostas, cancelamento de eco via AVAudioEngine e interrupção por
  fala reconhecida. Sessão termina por Stop/Esc, troca de dispositivo, entrada
  protegida, repouso/perda de sessão, mensagem digitada ou limite de sessão.
  Inatividade limitada a 60 segundos; sessão limitada a dez minutos. Não é
  restaurada automaticamente. Segurar/soltar continua separado. Testes usam
  captura simulada; qualidade acústica e latência física ainda não foram medidas.
- Identidades de voz fixas por personagem e idioma; Sieg continua Antônio em
  português. Outras identidades usam vozes disponíveis/multilíngues do provedor.
  Disponibilidade dos nomes foi consultada sem síntese ou reprodução. Todos os
  caminhos de streaming carregam a identidade da resposta. Naturalidade das novas
  vozes e pronúncia em português exigem avaliação futura do usuário.
- Os seis personagens têm conversas persistentes próprias e arte correspondente.
  Sieg mantém a coordenação. Rita recebe timers e sessões reais e pode iniciar
  uma pausa explicitamente pedida; Gantt recebe agenda autorizada e lembretes
  locais e pode criar lembretes relativos com título/prazo claros; Elinor recebe
  totais mensais calculados pelo app, cobranças registradas e contagens parciais
  de tokens; Toni prepara rascunhos e lê um arquivo de texto escolhido quando
  pedido pelo nome. Ada mantém código e GitHub somente leitura quando conectado.
  Delegação local e chat não executam código gerado. Nenhum envio de mensagens,
  conta bancária ou escrita em calendário externo foi inventado.
- Ferramenta de arquivo resolve o bookmark já escolhido, verifica identidade,
  tipo/tamanho e lê UTF-8 limitado a 128 KB. Excertos entram no contexto local
  como dados. Nomes de arquivo não equivalem a conteúdo. Não usa caminhos
  arbitrários propostos pelo modelo nem lê arquivos só por aparecerem na lista.
- Controle de tela por alvos reais de Accessibility, incluindo descrições de
  ícones. Tokens correspondem à instância do app, janela, elemento e geometria.
  Alvo/ação precisam corresponder ao pedido original; revalidação antes de agir.
  Pressionar e rolar usam ações AX disponíveis; escrever exige revisão e leitura
  de retorno. Controles sensíveis exigem confirmação visual. Mudança de alvo ou
  rejeição da API não recebe confirmação de sucesso. Interfaces sem AX acessível
  continuam dependendo de leitura/seleção/orientação e intervenção do usuário.
- Pesquisa dentro do app por padrão; Google/navegador só no pedido explícito.
  Busca referências, lê até três páginas públicas e prepara síntese local com
  citações numeradas. Verifica URLs, DNS público, redirects, tipo e tamanho;
  não usa cookies, scripts ou sessão do navegador. Cada parágrafo precisa citar
  uma fonte existente. Fallback identifica trechos de busca quando leitura ou
  síntese falhar. A validação de citações não prova correção factual de cada frase.
- Histórico local de até 30 tarefas com pedido, progresso e resultado; tarefas
  em execução voltam pausadas após reinício. Retomar exige ação do usuário e
  atualiza o mesmo registro. Orientação relê a tela em vez de repetir coordenadas
  antigas. Ações como Keep Awake não são colocadas em fila para replay. Resultados
  de pesquisa preservam o chat de origem. Overview exibe abrir, copiar, pausar e
  retomar. Armazenamento inválido é preservado e informa falha.
- Fluxogramas de algoritmos: passos gerados em sintaxe limitada de função são
  convertidos em grafo nativo, sem executar Python ou depender desse runtime.
  A conversão determina condições, caminhos alternativos, continuação e voltas.
  Entradas, operações e retornos vêm do conteúdo gerado, sem algoritmo específico
  embutido. Importação de subconjunto inerte de Mermaid também usa desenho nativo.
  Grafos de fluxo/hierarquia aceitam até 12 nós, ciclos até oito, com limites e
  layout de três colunas para maiores. Validação rejeita destinos inexistentes,
  arestas duplicadas, decisões incompletas, saídas ausentes e loops que reiniciam
  a entrada. Conteúdo e código gerados ainda podem conter erros semânticos.
- UI mostra identidade de quem respondeu, microfone ativo na conversa e revisão
  de ação no widget/Overview. Mensagem digitada permanece silenciosa no chat.
  Personagens aprovados preservados; não há inventário gigante de vozes.
- Atualização pode transferir uma sessão já ativa de Keep Awake com
  `--resume-keep-awake-session`, conservando prazo e preferência de restauração.
  O parâmetro não inicia uma sessão ausente ou já expirada.

## Validação

- Fast final 43: **332 funções / 1.086 execuções aprovadas**, 177/177 fontes de produção,
  nenhuma alteração durante execução, nenhum teste ausente ou inesperado.
  `/tmp/sieghart-product-completion-fast-43/verification.json`, também em
  `evidence/sieg-product-completion-2026-10-21/verification.json`.
- Build universal final 44 aprovado (`x86_64 arm64`), assinatura, metadados e
  descrições de privacidade verificados. App atualizado aberto no caminho de
  teste, PID 20180 na inspeção. Overview mostrou o histórico de tarefas;
  Activation mostrou Start conversation e Voice is off. Nenhum botão de
  microfone, conversa ou prévia foi acionado. Não foi feito ensaio falado.
- Pesquisa nativa real leu três páginas públicas e gerou síntese com citações.
  Logs em `/tmp/sieg-product-research-probe/result-2.log`.
- Ensaios reais de fluxograma revelaram que formas válidas não garantiam caminhos
  corretos. O gerador passou a derivar o fluxo da sintaxe dos passos. A inspeção
  final gerou uma busca binária correta como algoritmo e converteu dez nós e
  onze relações, com sucesso/falha e atualização correta dos dois limites.
  Renderização inspecionada e trajetos ajustados para contornar cartões.
  `evidence/sieg-product-completion-2026-10-21/algorithm-native.txt` e
  `algorithm-native-layout.png` registram o grafo real e uma prévia nativa com
  título descritivo; não são captura da tela do usuário nem código executado.
  Ensaios rejeitados não contam como recurso aprovado.
- Testes novos cobrem persistência/retomada, dados corrompidos, revisão de escrita,
  alvos alterados, tokens consumidos, ecossistema de vozes como metadados, eco e
  interrupção simulados, cancelamento durante preparação, busca silenciosa,
  arquivos de teste limitados e transferência de prazo do Keep Awake.
- O Keep Awake foi observado ativo durante o trabalho, mas estava desligado na
  conferência imediatamente anterior ao reinício. Esse estado foi conservado;
  prazo salvo e preferência de restauração permaneceram idênticos. O teste
  isolado comprova a transferência de uma sessão ativa; não alegar que uma
  asserção ativa foi transferida nesta abertura quando já estava desligada.

## Referências

- [Apple — processamento de voz](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)). A configuração também foi conferida no header AVAudioIONode do SDK instalado.
- [Microsoft — idiomas e vozes](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support). O catálogo Read Aloud foi consultado apenas para nomes disponíveis; isso não constitui integração contratada Azure nem comprova qualidade sonora.

## Aceite que permanece externo

O usuário avaliará voz, AirPods, atalho físico, seleção e múltiplos monitores
quando puder. Conexões/permissões de calendário, GitHub e arquivos precisam
estar autorizadas pelo usuário no app. Operações em interfaces arbitrárias,
envio de e-mail, contas financeiras e execução de código não são capacidades
gerais concluídas. Não declarar paridade interna 1:1 com HeyClicky, qualidade
universal do modelo ou produto 100% validado só por testes isolados.

Projeto: `/Users/antoniopaesdeandrade/Documents/ChatGPT/MyDude/sieghart-spatial-assistant/Sieghart`.
App: `/private/tmp/sieghart-spatial-dd/Build/Products/Debug/Sieghart.app`.
