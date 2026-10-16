# Companions por responsabilidade — proposta visual 01

Pedido: seis companions com responsabilidades próprias e nomes ligados a figuras da área, mantendo Sig como principal. Criar imagens e animações para revisão, sem aplicar no app.

## Família proposta

| Companion | Responsabilidade proposta | Referência para o nome | Identidade visual |
| --- | --- | --- | --- |
| Sig | Principal: receber pedidos e coordenar a equipe | Identidade original do Sieghart | Cápsula carvão, olhos claros, pequeno losango verde |
| Rita | Saúde, pausas e bem-estar | Rita Levi-Montalcini, Nobel de Fisiologia ou Medicina de 1986 | Seixo verde sálvia, pequeno estetoscópio creme e coral |
| Ada | Código e GitHub | Ada Lovelace, contribuição histórica para a computação | Forma âmbar com degraus, olhos quadrados, pequeno símbolo de código verde |
| Gantt | Agenda, calendário e rotina | Henry Laurence Gantt, planejamento de projetos | Moldura lavanda, rosto carvão e pequeno calendário |
| Elinor | Finanças e organização de recursos | Elinor Ostrom, prêmio de Ciências Econômicas de 2009 por governança econômica | Seixo rosa, olhos escuros e pequena moeda dourada |
| Toni | Comunicação, escrita e e-mail | Toni Morrison, Nobel de Literatura de 1993 | Origami creme com dobra coral e pequena ponta de caneta lavanda |

Os nomes e a associação com responsabilidades são sugestões de design. As referências históricas não representam endosso. A premiação de Elinor é por governança econômica; sua associação à organização financeira é uma interpretação de produto. Não há agentes implementados ou serviços conectados neste estudo.

## Fontes primárias verificadas

- Rita: [Nobel Prize — fatos](https://www.nobelprize.org/prizes/medicine/1986/levi-montalcini/facts/).
- Ada: [Computer History Museum — Ada Lovelace](https://www.computerhistory.org/babbage/adalovelace/).
- Gantt: [ASME — planejamento e gráficos Gantt](https://files.asme.org/Divisions/Management/15915.pdf).
- Elinor: [Nobel Prize — fatos](https://www.nobelprize.org/prizes/economic-sciences/2009/ostrom/facts/).
- Toni: [Nobel Prize — fatos](https://www.nobelprize.org/prizes/literature/1993/morrison/facts/).

## Entregas visuais

- `concept-board.png`: prancha ilustrada gerada com imagegen. Apresenta materiais, profundidade, acessórios e variações de expressão.
- `companions-motion.mp4`: interpretação vetorial independente da prancha, 60 fps, 12 segundos.
- `companions-motion.gif`: a mesma coreografia em 25 fps, reduzida para visualização inline.
- `motion-still.png`: quadro vetorial de repouso.
- `listening-left.png`, `listening-right.png`, `thinking.png`, `sleeping.png`: quadros para inspeção das expressões.

A animação é um estudo vetorial do mesmo conceito, não uma animação da textura raster da prancha. Os arquivos Swift neste diretório são exclusivamente do renderizador de estudo e não pertencem ao target do aplicativo.

## Coreografia

1. **Chegada** (0–1,8 s): entrada escalonada, impulso, acomodação e abertura dos olhos.
2. **Repouso** (1,8–3,2 s): respiração, pequenos olhares e piscar. Sem indicador de processamento.
3. **Escuta** (3,2–5,2 s): atenção, inclinação e olhar que atravessa os dois lados.
4. **Processamento** (5,2–7,2 s): olhar pensativo e sinal no canto com a silhueta de cada avatar. Ada mantém o formato com degraus; Toni mantém o losango.
5. **Confirmação** (7,2–9,2 s): Sig pisca; Rita faz um aceno; Ada dá um pequeno salto; Gantt inclina; Elinor se acomoda com um impulso; Toni faz um gesto curto com piscadinha.
6. **Descanso** (9,2–12 s): olhos fechados, respiração e balanço visíveis.

Os estados repetem-se automaticamente para comparação visual. Nenhuma ação real é executada. Não foram alterados onboarding, runtime, preferências ou agentes.

## Proveniência

- Prancha: ferramenta `image_gen.imagegen`, geração nova, fundo opaco. Prompt exato em `prompt.txt`.
- Original preservado: `/Users/antoniopaesdeandrade/.codex/generated_images/01a10cfa-1410-78d0-9d01-86edd7db9569/exec-d9c28c4e-b1a7-4729-ad5c-b71c6f8242e7.png`.
- Movimento: SwiftUI Canvas e ImageRenderer, renderizados sem janela. Curvas de movimento determinísticas, mola amortecida e transições interpoladas. Codificação com FFmpeg.
- Partes do desenho vetorial reutilizam o estudo original do projeto em `expressive-study-v2`; nenhum código de terceiros foi copiado para este estudo.

## Reproduzir a prévia

A partir da raiz do repositório:

```sh
swiftc -module-cache-path /private/tmp/sieghart-companion-concept-cache \
  Sieghart/Design/Concepts/responsibility-companions-v1/ConceptFace.swift \
  Sieghart/Design/Concepts/responsibility-companions-v1/ConceptMotion.swift \
  Sieghart/Design/Concepts/responsibility-companions-v1/RenderConcept.swift \
  -o /private/tmp/sieghart-companion-concept-renderer
/private/tmp/sieghart-companion-concept-renderer
```

O renderizador usa `/opt/homebrew/bin/ffmpeg`. As imagens de cada frame ficam em uma pasta temporária, removida após a codificação.
