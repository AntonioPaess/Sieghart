# Seis companions — identidades e atividades 02

Estudo visual solicitado pelo usuário. Não aplicado ao aplicativo: esta pasta contém conceitos, quadros e prévias de movimento. Nenhum agente ou função real é executado pelas animações.

## Direção visual

- **Sig:** preservado como cápsula carvão, olhos claros e losango verde. O losango sugere uma bússola para coordenação.
- **Ada:** preservada como forma âmbar com degraus, olhos quadrados e sinais de código. Mantém a geometria de pixels nos movimentos.
- **Toni:** base de origami creme/coral e pena lavanda preservada.
- **Rita:** redesenhada como folha/gota vertical e assimétrica. Uma faixa creme acompanha a lateral e sustenta um pequeno coração coral.
- **Gantt:** redesenhado como folio com capa lavanda, face creme, páginas sobrepostas, argolas e marcador coral integrados.
- **Elinor:** redesenhada como hexágono baixo e facetado, frente pêssego, plano lateral rosa e monóculo bronze em um olho.

Rita e Elinor agora têm silhuetas, proporções, materiais, acessórios e atividades diferentes, em vez do mesmo corpo com outra cor.

## Uma atividade por responsabilidade

| Avatar | Coreografia da atividade | Prévia |
| --- | --- | --- |
| Sig | Uma pequena bússola distribui sinais entre dois companions; o olhar acompanha os destinos. | `sig-activity.gif` |
| Rita | Guia um ciclo de inspirar e expirar: corpo e contorno expandem lentamente, o coração pulsa e o ritmo desacelera. | `rita-activity.gif` |
| Ada | Linhas de código são construídas em etapas, o cursor pisca, surge uma confirmação e o avatar dá um pequeno salto. | `ada-activity.gif` |
| Gantt | Uma página se curva, três compromissos deslizam para seus lugares em uma linha do tempo e o olhar acompanha a organização. | `gantt-activity.gif` |
| Elinor | O monóculo sugere uma projeção de gráfico; uma moeda viaja entre duas pilhas até equilibrá-las, seguida de um gesto de satisfação. | `elinor-activity.gif` |
| Toni | Um envelope se prepara, dobra-se na transição para um avião de papel e segue uma trajetória; os olhos acompanham e confirmam com uma piscadinha. | `toni-activity.gif` |

## Estados completos de cada personagem

A galeria de 24 segundos contém nove estados para os seis personagens:

| Intervalo | Estado |
| --- | --- |
| 0–2 s | Chegada: entrada, acomodação e primeiro olhar |
| 2–4 s | Repouso: respiração, olhares pequenos e piscar; sem loading |
| 4–6 s | Escuta: atenção e olhar nos dois sentidos |
| 6–8 s | Pensamento: indicador com a silhueta do próprio companion |
| 8–10 s | Fala: ritmo facial e pequenos movimentos sincronizados |
| 10–16 s | Atividade: coreografia específica da responsabilidade |
| 16–18 s | Confirmação: gestos próprios de cada personagem |
| 18–20 s | Impasse: reação breve de atenção, sem comemorar |
| 20–24 s | Descanso: olhos fechados, respiração e balanço visíveis |

O ciclo é uma demonstração para revisão; não representa o comportamento automático do app.

## Arquivos

- `concept-board.png`: prancha ilustrada com os seis concepts e suas atividades.
- `all-animations-60fps.mp4`: galeria completa, 24 s a 60 fps.
- `all-animations.gif`: galeria completa em GIF a 25 fps.
- `activities.gif`: as seis atividades simultâneas, 6 s a 25 fps.
- `sig-all-animations.mp4`, `rita-all-animations.mp4`, `ada-all-animations.mp4`, `gantt-all-animations.mp4`, `elinor-all-animations.mp4`, `toni-all-animations.mp4`: todos os nove estados isolados por avatar, 24 s a 60 fps.
- `*-activity.gif`: uma prévia em loop da atividade própria de cada avatar, 6 s a 25 fps.
- `arrival.png`, `idle.png`, `listening.png`, `thinking.png`, `speaking.png`, `activities.png`, `success.png`, `problem.png`, `sleeping.png`: quadros de inspeção.

## Proveniência e limites do estudo

- Prancha: `image_gen.imagegen`, edição da prancha anterior para preservar Sig/Ada e a base da Toni. Prompt exato salvo em `prompt.txt`.
- Referência: `../responsibility-companions-v1/concept-board.png`.
- Original da nova ilustração preservado em `/Users/antoniopaesdeandrade/.codex/generated_images/01a10cfa-1410-78d0-9d01-86edd7db9569/exec-529bcfc1-2217-4be4-a9b3-62bffd9beb49.png`.
- As prévias de movimento são interpretações vetoriais do concept. Preservam formas e identificadores, com acabamento suave e profundidade por planos e sombras; não animam a textura raster da prancha.
- Renderização independente, sem abrir o app, usando desenho vetorial e codificação de mídia. Fontes auxiliares temporárias fora do projeto; nenhum arquivo Swift foi adicionado nesta pasta nem ao target do aplicativo.
- Só foram adicionados os artefatos desta pasta. As alterações já existentes no projeto foram preservadas.
