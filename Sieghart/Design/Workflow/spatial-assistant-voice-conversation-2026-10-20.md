# Conversa falada e desenho com explicação — 20/10/2026

Implementado somente no worktree `sieghart-spatial-assistant`, sem commit ou push.

## Comportamento

- Perguntas e assuntos livres seguem para uma conversa local com resposta falada. Somente pedidos explícitos de pesquisa seguem para o navegador.
- “Desenha uma circunferência na minha tela e explica sobre o pi” desenha o círculo e envia a explicação ao modelo de voz, sem interrompê-la com a confirmação curta do desenho. O desenho permanece durante a explicação.
- A conversa mantém até seis turnos recentes. Cancelar ou fazer outro pedido impede que uma resposta anterior seja falada depois.
- A conversa usa o modelo Apple no dispositivo com instruções próprias para fala. Quando o modelo não está pronto, informa a indisponibilidade por áudio; a explicação básica de pi também possui uma resposta local determinística.
- O caminho de áudio corrigido anteriormente, a assinatura e as permissões foram preservados. O recolhimento automático do painel não cancela a resposta falada.

## Validação

- Plano `Sieghart-Fast`: 255 funções e 977 invocações aprovadas; nenhuma função ausente ou inesperada; nenhum fonte alterado durante a execução; 151/151 fontes esperados na cobertura.
- Casos cobrem perguntas sem navegador, pesquisa explícita, circunferência com explicação, contexto de continuação, cancelamento e substituição de resposta pendente, além da remoção de Markdown e pensamentos da fala.
- Build Debug assinado aprovado e `Tests/verify-built-app.sh` aprovado. Build espacial deixado aberto em `/tmp/sieghart-spatial-dd/Build/Products/Debug/Sieghart.app`.
- Resultado: `/tmp/sieghart-voice-conversation-fast/verification.json`. Log do build: `/tmp/sieghart-voice-conversation-build.log`.

## Limite da verificação

Os testes injetam o texto final reconhecido e um gerador de respostas controlado. A tentativa de acionar a conversa no app pelo depurador não conseguiu acessar os tipos internos; o processo foi liberado e permaneceu aberto. Captação física pelo microfone e uma resposta completa do modelo Apple com áudio real ainda dependem da conferência no app. Não foram alteradas permissões para tentar automatizar essa etapa.

O projeto temporário em `/tmp/sieghart-spatial-dd/SourceWorkspace` referencia os fontes deste worktree. Foi necessário materializar arquivos novamente pelo iCloud para concluir leitura e compilação.
