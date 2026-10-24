# Acabamento dos estados do widget — 22/10/2026

Entregue na versão **86**, instalada no caminho canônico `/Applications/Sieghart.app` e aberta por LaunchServices. Preservados o prazo e o estado do Keep Awake. Nenhum commit, push, reset de permissões ou teste com áudio real foi feito.

## Mudanças

- O widget recebe explicitamente o idioma selecionado no app. Os textos fixos de preparação, escuta, estado compacto e menus usam esse idioma; transcrições e respostas continuam sendo conteúdo do usuário/modelo.
- Corrigidas mensagens ociosas e reações do Sieg que permaneciam em inglês. Os seletores dos Timers e filtros da área de transferência também passaram a consultar as traduções existentes. O catálogo em português tem 689 chaves fixas; isso não representa uma auditoria completa de todas as mensagens dinâmicas de integrações.
- Cartões de resposta, erro, leitura de tela, desenho e ações seguem a paleta adaptável, tipografia e botões do design compartilhado. Removido o branco fixo que prejudicava o tema claro. Os cabeçalhos identificam o tipo de resultado e o personagem.
- A recuperação de permissão de tela destaca o botão principal, reorganiza os controles em duas linhas em larguras menores e mostra o nome do app. O caminho técnico completo fica na ajuda ao passar o mouse.
- Confirmação/cancelamento de ações têm uma linha própria e altura correspondente no painel, sem competir com Copiar/Limpar contexto.
- Removida a segunda ocorrência do mesmo status durante a preparação do microfone.

Mantida a [correção do retorno do clima à Home](sieg-weather-return-2026-10-22.md), com encerramento independente do hover e restauração opcional pelo recibo do cursor. O catálogo ilustrativo de climas continua sendo uma janela persistente de comparação, separada do resultado temporário real.

## Validação

- 26 renderizações nativas com dados fictícios: Home ociosa, preparação, escuta, pensamento e resposta; cartões de resposta, erro, permissão e revisão de ação em 320 e 532 pontos, nos temas claro e escuro. As prévias usam serviços substituídos e voz desativada. Os botões que concedem permissões não foram acionados.
- A conferência revelou status de preparação/escuta ainda em inglês; eles foram corrigidos e as imagens refeitas. A última limpeza, posterior às imagens, apenas esconde a linha duplicada de preparação.
- Suíte existente: **360 funções / 1.115 invocações aprovadas**, 195/195 arquivos de produção na cobertura registrada, sem fontes alteradas durante a execução. Depois da suíte houve somente a remoção visual da linha duplicada, seguida de compilação universal bem-sucedida.
- Verificados metadados de privacidade, assinatura e capacidades do app antes de instalar. Usado o launcher correto, evitando a atribuição de privacidade ao processo de desenvolvimento.

Evidências em [evidence/sieg-widget-states-2026-10-22](evidence/sieg-widget-states-2026-10-22/): imagens, relatório da suíte, metadados e preservação do Keep Awake. Os exemplos não contêm histórico privado do usuário.

Os testes não validam a qualidade acústica, AirPods, permissões concedidas pelo usuário, documentos longos ou integrações externas. Esses limites permanecem no [relatório de design integrado](sieg-premium-design-2026-10-22.md).
