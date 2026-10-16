# Biblioteca do especialista em avatares e animações

Ponto de entrada para o chat visual do Sieg. Atualizado em 16 de outubro de 2026. Este índice aponta o material disponível; não afirma que todas as animações de todos os aplicativos de referência já foram estudadas.

## Biblioteca própria

- `../Concepts/responsibility-companions-v6/README.md`: biblioteca de 49 movimentos e famílias exportadas em vídeo, onboarding e limites da revisão conceitual.
- `../Concepts/responsibility-companions-v6/animation-catalogue.md` e `.json`: estados, comportamentos e fontes pesquisadas.
- `../Concepts/responsibility-companions-v6/motion-manifest.json`, `source-audit.json` e `export-validation.json`: catálogo temporal, proveniência e evidência da exportação.
- `../Concepts/responsibility-companions-v6/preview.html` e MP4 locais: prévia comparativa dos seis personagens. São conceitos; o runtime integrado é a referência atual de comportamento no app.
- `../Concepts/responsibility-companions-v1` até `v5` e `v4-greeting`, além de `specialist-companions-v1`: histórico de conceitos e correções. Há opções rejeitadas; não reaplicar automaticamente.
- `../../Sieghart/Shared/Components/Companion/`: animações, rigs, pose, geometria, renderer, alô e formação/introdução da equipe.
- `../../Sieghart/Shared/Resources/ProviderAssets.xcassets/Companion-*.imageset`: recursos integrados de cada personagem.
- `../../Sieghart/Shared/Components/CompanionFileReceiver.swift`: entrada de arquivo e rastreamento do Toni.
- `../../Sieghart/Features/AgentRoom/`: chat e gestos da Ada.
- `../../Tests/CompanionTeamChecks.swift`, `CompanionPerformanceChecks.swift` e `AgentChatMotionChecks.swift`: contratos verificados no código.
- `../Validation/`: imagens e vídeos de validação, com dados fictícios quando declarado. Não são prova de aceite físico ou de CPU no Mac.

## Decisões e correções aprovadas

Ler `../companion-performance-checkpoint.md`, `../sprint-5-file-drop-followup.md`, `../companion-capabilities.md`, `../product-direction-2026-10-11.md`, `../ada-room-test-guide.md` e `../sprint-5-closeout.md`. O pedido mais recente do usuário prevalece sobre conceitos antigos e atas históricas.

Sig é o principal fixo, personalizável; os demais têm responsabilidades próprias. O alô aprovado, a fila de apresentações, o retorno ao Companion, a transparência sem borda branca, a luz sem retângulo e a nitidez em telas Retina são requisitos centrais. Toni recebe arquivos; Gantt aparece no calendário; Ada representa código/chat e atividade de desenvolvimento.

## Referências externas já estudadas

- Coucou: `../coucou-reference.md`, catálogos/fontes da v5/v6, `../Research/coucou-chat-2026-10-13.md` e `../Research/coucou-files-2026-10-13.md`. A v6 registra 45 comportamentos pesquisados e quatro adaptações próprias; isso não é uma contagem oficial de tudo que existe no Coucou.
- Vorssaint e fluxo de arquivos: `../sprint-5-file-drop-followup.md`, `../sprint-5-calendar-checkpoint.md` e `../Research/reference-study-index-2026-10-13.md`.
- HeyClicky/HeyTaby, Herdr e Orca: `../clicky-reference.md`, `../Research/rea-apps-2026-10-13.md`, `../Research/herdr-clicky-followup-2026-10-14.md` e `../Research/orca-room-2026-10-14.md`.
- Muse e outras oportunidades: `../Research/muse-and-references-2026-10-13.md` e `../Research/reference-study-index-2026-10-13.md`.

Pacotes, extrações comprimidas e caches de investigação podem existir apenas localmente em `Design/Research` ou `/private/tmp`; não são dependências de build nem garantidos em outro checkout. Confirmar existência antes de usá-los. Os relatórios da outra frente em `../../Sieghart-Research/` são contexto independente, não alterações desta entrega.

## Regras de catálogo e uso

Para cada novo movimento, registrar personagem, intenção, gatilho real, duração/repetição, entrada/saída/cancelamento, idle, redução de movimento, resolução/alpha, fonte/licença, evidência e status de aprovação. Não representar atividade de agente inexistente.

Estudar código aberto diretamente. Para comportamento não estabelecido pelo código, usar a skill REA quando adequada e autorizada. Não reutilizar arte, marca, áudio ou recursos protegidos por observar o comportamento de outro app. Preservar atribuição MIT do Coucou nos trechos adaptados; consultar `../../THIRD_PARTY_NOTICES.md`. Referências com outra licença exigem análise de compatibilidade antes de reutilização de código.

No início do chat, produzir um mapa curto de material existente, lacunas e fontes indisponíveis. Não gerar novamente os 49 vídeos ou iniciar um redesign sem uma tarefa específica.
