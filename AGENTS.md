# Instruções do usuário — MyDude / Sieghart

- É proibido usar qualquer modelo Astra. O modelo máximo autorizado para agentes é GPT-6.1 Sol (gpt-6.1-sol); nunca herdar um modelo sem verificar esse limite ao delegar.
- Priorizar baixo consumo: trabalhar com um agente ativo por vez. Não iniciar agentes paralelos sem novo pedido explícito do usuário. Reaproveitar o trabalho e os resultados existentes.
- A pré-Sprint 6 está autorizada para implementação desde 18 de outubro de 2026. A Sprint 6 continua dependendo da migração, execução e revisão independente previstas em Sieghart/Design/Workflow/.
- Preservar alterações de outros chats. Não fazer commit ou push sem pedido do usuário.

## Checkpoint obrigatório de continuidade

- Ao retomar, ler `HANDOFF.md`, `CURRENT_WORK.md`, `KNOWN_ISSUES.md` e `RESEARCH_INDEX.md`.
- Antes de trocar de tarefa/contexto e depois de cada lote, atualizar `CURRENT_WORK.md` com objetivo, arquivos, resultado dos testes, falhas, limitações e próximo passo. Não esperar o fim da cota ou dos tokens.
- Atualizar `KNOWN_ISSUES.md` quando um bug for reproduzido, corrigido ou validado; distinguir fixtures, app/modelo real e hardware físico.
- O snapshot para Claude deve permanecer estável; a continuação usa outra branch. Não permitir duas IAs escrevendo ao mesmo tempo no mesmo checkout.
- A autorização de 23/10/2026 permite criar, commitar e enviar o snapshot de handoff solicitado; não é autorização geral para commits/push futuros.
