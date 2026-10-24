# Continuação: permissões, geografia e experiência — 21/10/2026

Estado: integração, verificação, build universal 57 e instalação concluídos. Sem commit/push.
O usuário autorizou o repasse visual ao chat “Sieg — Avatares e animações”;
o componente foi entregue nesse chat e integrado aqui. Nenhum subagente foi criado.
Trabalho somente na worktree `sieghart-spatial-assistant`; SSC adiado.
Não iniciar microfone ou reproduzir áudio. O usuário passou a fazer seus próprios
ensaios em casa; isso não foi tratado como autorização para tocar som automaticamente.

## Relatos incorporados

- Falha de captura é uma permissão real; mostrar acesso direto aos ajustes, localizar
  a cópia corrente e tentar novamente. Cópia executável deve ter caminho fixo.
- Não restringir clima a Recife/Bragança nem exigir estado/país. Alasca e Zermmat
  foram dados adicionais do usuário. Usar o mesmo resultado estruturado na UI.
- Cena inteira de clima com o Sieg, sete reações; cursor de escuta deve conter Sieg.
- Nome Sieg deve estar no vocabulário de reconhecimento. Corrigir só vocativo Siri
  em pedido já gravado pelo Sieg; preservar menções a Siri dentro do pedido.
- O pedido sobre CarPlay era explicar uma classe específica e diagramá-la;
  a transcrição CPT não designava um conceito a ser inventado. O nome exato ainda
  não foi fornecido. Capturar contexto ao pedir “essa classe”/seleção; escrever
  código novo “na tela” não deve forçar leitura do código existente.

## Implementação atual

- Recuperação de permissão de tela, caminho do bundle e botão de localizar/repetir.
- Home com seis personagens, conversas, busca em mensagens, fixar/arquivar,
  biblioteca, tarefas, montagem de trabalho em etapas e rotinas.
- Sete cenas de clima; consulta concisa para voz, metadados completos na UI/chat.
- Geografia: Open-Meteo, correção de grafia limitada, desempate por população e
  geocodificação Apple para resolver regiões e resultados desconhecidos.
- Texto/PDF escolhido, leitura por páginas e resposta documental com modelo local
  sem ferramentas; limites de extração explícitos. Biblioteca salva código,
  Markdown e SVG com escape, permite prévia, exportar e arrastar.
- Edição de legenda/destaque/movimento por nome exato, conservando identidade
  do documento e relações; movimento que sobrepõe blocos é recusado.
- Orientações até 15 passos e checkpoint persistido; retomada relê tela e conserva
  etapas concluídas. Nenhum replay de cliques.
- Trabalhos de 2–6 etapas escolhidos pelo usuário, execução sequencial e retomada
  sem repetir resultado concluído. Pesquisa real e respostas de especialistas.
- Rotinas diárias opt-in, criadas desligadas; executam pesquisa/resumo de agenda
  sem áudio enquanto app está aberto; falhas repetidas pausam a rotina.
- Preparação de áudio distinta de fala; respostas prontas usam fila por frases.
  Qualidade acústica/latência física continuam sem ensaio.

## Evidências até agora

- Worktrees: somente original e espacial. Worktree de pesquisa estava incompleta;
  estado, patch do index, metadados e HEAD arquivados sob
  `/Users/antoniopaesdeandrade/Documents/ChatGPT/MyDude/WorktreeArchives/research-validation-2026-10-21`.
  Nenhum commit criado; conteúdo no HEAD também foi guardado em tar.gz.
- Builds 46, 47, 50 e 55 aprovados. Cópia canônica instalada e aberta em
  `/Applications/Sieghart.app`; assinatura verificada e arquiteturas arm64/x86_64.
  Build 57 aprovado, instalado e reaberto. Uma única instância do caminho canônico;
  binário instalado idêntico ao build. Keep Awake estava inativo; opções e prazo
  salvos foram conservados. Não foi iniciado um novo período.
- Fast 49: 340/341; revelou herança excessiva da cidade em pergunta sem referência.
- Fast 51 foi interrompido após detectar que saída de código era confundida com
  entrada de código da tela. A falha foi corrigida e ganhou regressão.
- Fast 53: 345 funções/1.099 execuções, incluindo conservação do PDF original.
- Fast **56: 348 funções e 1.103 execuções aprovadas**, 193/193 fontes de produção,
  nenhuma fonte alterada durante os testes e nenhum caso ausente/inesperado.
  Inclui contexto de classe via chat/voz e bloqueio por permissão ausente.
- Geografia real v2: Alasca→AK/EUA (referência regional), Zermmat→Zermatt/Suíça,
  Porto, Curitiba, Tokyo, Ushuaia e Reykjavik, todos sem qualificador obrigatório.
  Logs `/tmp/sieg-geography-probe/results-2.log`. Alasca antes apontava Rondônia;
  o ensaio inicial reprovado não conta como aceite.
- A primeira prévia de clima foi rejeitada pelo usuário: acessórios pareciam ícones
  colados. Foi substituída por rig SceneKit do Sieg, cachecol volumétrico com grão e
  luz nativos, mãos segurando o tecido, encolhimento, tremor, reação à chuva, gesto
  de se abanar, gotas, condensação e neve acumulada. O pai integra chuva/neve em
  profundidade, respingos e sol com raios em movimento. Reduce Motion conserva poses.
  Ver [entrega do especialista](sieg-weather-character-animation-2026-10-21.md).
- Sete cenas integradas foram renderizadas de forma silenciosa em
  `/tmp/sieg-weather-scene-probe`; frio, calor e chuva foram inspecionados junto ao
  diagrama de classe. São prévias com observações explicitamente fictícias, não
  consultas meteorológicas reais. O ensaio geográfico acima é evidência separada.
- Modelo local: a primeira tentativa de diagrama de classe inventava fluxos entre
  métodos independentes e gerava grupos desconectados. A conversão agora constrói
  a contenção da classe e confere seus identificadores no código observado. Após
  ajuste, `TripPreviewCoordinator` de exemplo preservou showPreview, startNavigation
  e cancelPreview, com diagrama renderizado e legível. A classe real do usuário não
  foi identificada neste ensaio e não foi alegado acesso físico à sua tela.
- SVG exportado conserva curvas de ligação, destaque e quebra de texto nos blocos.
- Prévia inicial da Home expôs busca não renderizada no ImageRenderer e miniatura
  larga demais; ambos foram corrigidos. Interface nativa conferida: Home, busca em títulos/mensagens e abertura da
  conversa do Sieg funcionando. A leitura digitada confirmou permissão de tela
  ausente nesta cópia; resposta apareceu no chat sem áudio. O erro não é tratado
  como sucesso nem como tela lida. Recuperação também foi acrescentada ao chat,
  preservando a conversa e repetindo o pedido no mesmo canal ao tentar novamente.
- Sidebar e placeholder do chat seguem o idioma selecionado; prévias de conversas
  removem as marcações técnicas antigas apenas na apresentação, sem alterar o
  histórico salvo. Removida a barra de exemplos de formas/SSC da conversa; ela
  não representava o conjunto de capacidades. Vocabulário ASR recebe nomes de
  classes CarPlay como pistas, sem substituir ou limitar a geração por assunto.

## Conferência final e dependências de uso

A Home real foi inspecionada, incluindo busca e abertura de uma conversa do Sieg.
A leitura digitada mostrou o erro verdadeiro de permissão, sem áudio. Na versão
final, o chat exibiu os botões **Abrir permissão de tela**, **Localizar este app** e
**Tentar novamente**, com `/Applications/Sieghart.app` visível. Não foi acionada
concessão de Gravação de Tela/Acessibilidade nem modificado o banco TCC. A ativação
precisa ser feita pelo usuário no macOS; o botão conduz ao painel correspondente.
Durante a conferência, o próprio usuário consultou o clima no app. Foram observadas
as cenas de região/cidade, incluindo Islândia e Rio de Janeiro, com personagem e
resultado estruturado. Isso confirma a apresentação real, não o aceite acústico.
O agente não acionou microfone, fala, prévia de voz ou reprodução de áudio.

[Evidências integradas](evidence/sieg-product-recovery-2026-10-21/verification.json)
registram 348 funções/1.103 execuções, sem fonte alterada durante a verificação;
`installed-app.json` registra assinatura, arquitetura e identidade do executável.
O clipe do especialista é render nativo do componente, não uma gravação do app.

Permanecem dependentes de validação/implementação posterior: permissão de tela pelo
usuário; medições de primeiro áudio, AirPods, atalho físico, troca de monitores e
repouso; revisão de textos nas áreas legadas de configurações; leitura fora do
viewport em interfaces sem Accessibility ou sem documento escolhido; edição
referencial de desenhos sem nome explícito do alvo; integrações de contas ainda
não conectadas e rotinas executadas com o app fechado. Os trabalhos em etapas e
rotinas desta entrega operam com capacidades reais já presentes e não ganham
permissões por descrição de papel. Não há declaração de paridade 1:1 ou produto
100% concluído neste marco.

Não há certificado Apple Development disponível na consulta inicial (assinatura
ad hoc); o caminho fixo e a retirada das associações antigas de produtos Xcode
resolvem a seleção da cópia, mas não garantem manutenção de TCC em toda atualização
futura. Os arquivos antigos de build foram preservados, assim como a última cópia
instalada em `/private/tmp/sieghart-previous-app.oCTasu/Sieghart.app`.

Referências técnicas conferidas anteriormente: documentação do geocodificador
Open-Meteo e Apple `MKGeocodingRequest`. A busca não usa localização pessoal.
