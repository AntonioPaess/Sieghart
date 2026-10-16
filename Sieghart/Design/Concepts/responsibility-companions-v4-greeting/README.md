# Sieghart — estudo de saudação v4

Revisão solicitada em 10 de outubro de 2026. Apenas conceito e vídeos; não integrado ao aplicativo.

## Ver

Abra `preview.html` e escolha um dos seis avatares. Cada MP4 tem 6 segundos, 1280 × 480 pixels e 60 fps. Os primeiros 4,6 segundos demonstram a sequência de entrada; o final permite observar o repouso. O vídeo mantém a qualidade principal; o GIF é uma amostra reduzida.

## Origem da coreografia

Tempos, curvas de easing, pose de entrada e dados de partículas foram adaptados diretamente de [GreetingCanvasView.swift](https://github.com/Louis-CFM/coucou/blob/5cb2a27af352cf7319569920aac899efd42b54bc/NotchBuddy/Sources/App/GreetingCanvasView.swift), commit `5cb2a27af352cf7319569920aac899efd42b54bc` do repositório público Louis-CFM/coucou. O arquivo baixado foi comparado com a referência local: conteúdo idêntico. A licença do código acompanha `source/COUCOU-MIT-LICENSE.txt`.

| Tempo | Movimento do código de referência |
|---|---|
| 0,20–0,60 s | Avatar aparece, cresce e cai com curva back/cúbica. |
| 0,52–0,84 s | Compressão da aterrissagem e rebote. |
| 0,30–0,70 s | Halo dourado ganha intensidade. |
| 0,45–1,80 s | Anel de partículas da chegada. |
| 1,20–1,60 s | Pequeno mergulho e impulso antes do alô. |
| 1,30 / 1,34 s | As mãos surgem com atraso de 40 ms entre elas. |
| 1,45–2,45 s | Mão esquerda sobe/desce a 5 Hz; a direita oscila ±0,04 rad a 2,5 Hz sobre a inclinação de −0,61 rad. Corpo acompanha com movimento de 2% da altura. |
| 2,45–2,70 s | Mãos se recolhem, com entradas e saídas separadas. |
| 2,85–3,45 s | Corpo retorna ao centro. |
| 3,85–4,15 s | Halo passa do dourado ao azul. |

## Adaptação visual

Os modelos, olhos, cores e acessórios são os seis conceitos do Sieghart v3. Não foi usado o personagem Mochi, o nome ou o áudio do outro aplicativo. Os tempos comuns vêm do código de referência; a aparência é uma interpretação com volume, diferente da arte raster da prancha.

- As mãos usam a cor/material do avatar. A mão esquerda é redonda e a direita alongada nos modelos orgânicos. Ada tem mãos retangulares com cantos mínimos. Toni mantém a mão alongada como uma peça de papel.
- Ada e Gantt usam escala uniforme para manter suas formas quadradas, em vez do squash anisotrópico do personagem de referência.
- A profundidade, a iluminação material e uma leve rotação da cabeça vêm da prévia v3. O halo usa as duas camadas radiais e as cores/tempos da referência.
- Não há badge de loading durante o alô. O badge de atividade e a mudança azul na cor do corpo da referência foram omitidos para preservar as escolhas anteriores do usuário. A luz de fundo continua mudando de cor.
- Após a saudação as mãos desaparecem. Esta prévia não executa o ciclo de fechamento da ilha nem funções reais do aplicativo.

`source/` contém o renderizador isolado e a adaptação dos tempos para tornar esta prévia reproduzível. Nenhum arquivo de produção foi alterado. Sem música nesta revisão.
