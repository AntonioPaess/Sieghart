# Sieghart — Papel vivo / conceitos v3

Estudo visual para revisão. Os nomes e as responsabilidades são propostas. Estes arquivos não foram integrados ao Sieghart e não executam tarefas ou integrações reais.

## Direção visual

A prancha gerada é a referência de acabamento. As animações são uma interpretação modelada em 3D, com superfícies curvas, espessura, bordas, acessórios e luz. A textura da prancha não é reproduzida pixel a pixel.

| Avatar | Identidade preservada ou proposta | Gesto da atividade |
| --- | --- | --- |
| Sig | Cápsula carvão; pequeno diamante verde facetado | Acompanha e encaminha dois sinais de trabalho |
| Rita | Folha em verde sálvia; faixa creme e coração coral | Respiração acompanhada por contorno e pulso do coração |
| Ada | Cabeça amarela em degraus; olhos quadrados e brackets verdes | Linhas de código surgem em sequência e um pequeno salto conclui o trabalho |
| Gantt | Agenda **quadrada**, páginas creme, capa lilás e marcador coral | A dobra da página se move e três compromissos se organizam |
| Elinor | Hexágono pêssego; lateral rosada e monóculo bronze | Inspeciona com o monóculo enquanto um pequeno gráfico cresce |
| Toni | **Carta viva**: corpo creme, dobra coral, cauda de papel e selo lilás | A cauda se abre como uma asa; uma mensagem de papel parte e os olhos a acompanham |

A Toni também usa a dobra para saudar, escutar e falar. A Ada mantém a silhueta em degraus e não se transforma em esfera. O Gantt mantém as proporções quadradas.

## Animações gerais

Todos os seis têm os 17 estados abaixo, mais o gesto da própria atividade. A montagem passa por cada estado com seu nome na tela.

| Tempo no vídeo | Estado |
| --- | --- |
| 00:00–00:04 | Chegada e alô da primeira abertura |
| 00:04–00:06 | Repouso, respiração e piscada |
| 00:06–00:08 | Olhar para os dois lados |
| 00:08–00:10 | Passear |
| 00:10–00:12 | Preparando |
| 00:12–00:14 | Escutando |
| 00:14–00:17 | Loading / pensando |
| 00:17–00:21 | Trabalhando / atividade própria |
| 00:21–00:23 | Falando |
| 00:23–00:25 | Entendi |
| 00:25–00:27 | Contente |
| 00:27–00:30 | Comemorando |
| 00:30–00:32 | Irritado |
| 00:32–00:33.5 | Susto |
| 00:33.5–00:35.5 | Algo deu errado |
| 00:35.5–00:38.5 | Dormindo, com respiração |
| 00:38.5–00:41 | Despertando |

O indicador de atividade só aparece em preparando, pensando e trabalhando. Não aparece em repouso. As transições da montagem usam interpolação curta; a saudação tem entrada com acomodação suave. Os clipes são estudos de movimento, não o controlador de estados definitivo do app.

## Arquivos

- `preview.html`: página local para escolher um avatar e ir diretamente a qualquer estado. Os vídeos ficam na mesma pasta; não há upload ou publicação.
- `concept-board.png`: prancha de referência, com a nova Toni e exemplos de saudação e irritação.
- `all-states-3d-60fps.mp4`: montagem de 41 segundos, 1668 × 1520, 60 fps. Use este vídeo para avaliar acabamento e fluidez.
- `first-opening-3d.mp4`: primeira abertura e acomodação em repouso.
- `sig-all-states-3d.mp4`, `rita-all-states-3d.mp4`, `ada-all-states-3d.mp4`, `gantt-all-states-3d.mp4`, `elinor-all-states-3d.mp4`, `toni-all-states-3d.mp4`: cada personagem separado, com a mesma ordem de estados.
- `all-states-3d.gif`: montagem leve; tem resolução e paleta reduzidas em relação ao vídeo.
- `hello-3d.gif`, `loading-3d.gif`, `looking-3d.gif`, `annoyed-3d.gif`, `activities-3d.gif`: recortes rápidos.
- `00-state.png` a `16-state.png`: imagens de revisão de cada estado.
- `prompt.txt`: instruções exatas usadas na geração da prancha.
- `motion-manifest.json`: tempos, responsabilidades e arquivos.

## Proveniência

- Prancha: edição com a ferramenta de geração de imagens, partindo de `responsibility-companions-v2/concept-board.png`. A prancha anterior foi mantida.
- Animações: modelos e movimentos criados em um renderizador temporário fora do app, usando SceneKit. A referência técnica de extrusão é a [documentação de SCNShape da Apple](https://developer.apple.com/documentation/scenekit/scnshape).
- Nenhum arquivo Swift deste estudo foi acrescentado ao aplicativo. Os vídeos não são gravações do Sieghart em execução.
