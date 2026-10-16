# Sieghart — biblioteca animada v6

Revisão de 11 de outubro de 2026. Todos os 49 movimentos listados abaixo possuem uma animação nos MP4 desta revisão. Os 45 comportamentos pesquisados no Coucou têm links para a fonte; quatro movimentos comuns adicionais são adaptações próprias. A contagem é desta biblioteca, não uma contagem oficial do Coucou.

## Direção definida pelo usuário

- Sig é o companion principal fixo. Não existe seleção de outro principal.
- Rita: saúde e pausas.
- Ada: código e GitHub.
- Gantt: calendário, agenda e rotina.
- Elinor: finanças e recursos.
- Toni: comunicação e arquivos.
- Personalizações do Sig podem alterar seu estilo; os especialistas têm responsabilidades próprias.
- O onboarding apresenta os seis e conduz os cinco especialistas aos lugares deles no widget.

## Assistir

Abra `preview.html`. Selecione a família e depois o movimento. É possível ir direto ao trecho, repeti-lo isoladamente e reduzir a velocidade para 0,5× ou 0,25×. Os seis são exibidos lado a lado para comparar suas identidades. Isso não indica seis agentes executando a mesma tarefa ao mesmo tempo no produto.

## Onboarding — 30 segundos

| Tempo | Apresentação |
|---|---|
| 0.0–4.6 s | Alô do Sig |
| 4.6–7.4 s | Os cinco saem de trás dele |
| 7.4–10.2 s | Ocupam seus lugares no widget |
| 10.2–13.2 s | Rita · saúde e pausas |
| 13.2–16.2 s | Ada · código e GitHub |
| 16.2–19.2 s | Gantt · agenda e rotina |
| 19.2–22.2 s | Elinor · finanças e recursos |
| 22.2–25.2 s | Toni · comunicação e arquivos |
| 25.2–30.0 s | Sig e a equipe prontos |

O vídeo `onboarding-widget-60fps.mp4` mantém o alô com luz e rebote do Sig, faz os cinco saírem de trás dele e rodeá-lo e os leva a uma faixa de especialistas na base do widget. Cada um tem uma apresentação curta com sua responsabilidade. O Sig ocupa o centro da experiência e também aparece na ilha compacta.

## Vídeos completos por família

| Família | Arquivo | Movimentos | Duração |
|---|---|---:|---:|
| Alôs | [entrada-60fps.mp4](entrada-60fps.mp4) | 2 | 8.2 s |
| Repouso, olhar e sono | [vida-60fps.mp4](vida-60fps.mp4) | 8 | 25.5 s |
| Toque e irritação | [interacao-60fps.mp4](interacao-60fps.mp4) | 3 | 9.3 s |
| Tarefas e agentes | [agentes-60fps.mp4](agentes-60fps.mp4) | 10 | 31.0 s |
| Emoções | [emocoes-60fps.mp4](emocoes-60fps.mp4) | 6 | 18.0 s |
| Escutar e falar | [voz-60fps.mp4](voz-60fps.mp4) | 6 | 20.0 s |
| Dançar | [musica-60fps.mp4](musica-60fps.mp4) | 1 | 6.0 s |
| Arquivos e upload | [arquivos-60fps.mp4](arquivos-60fps.mp4) | 8 | 25.0 s |
| Acessórios e personalização | [acessorios-60fps.mp4](acessorios-60fps.mp4) | 2 | 8.0 s |
| Ilha, desktop e interrupção | [transicoes-60fps.mp4](transicoes-60fps.mp4) | 3 | 12.0 s |

## Aparência e movimento

- Silhuetas, volume, material fosco e acessórios seguem os modelos 2.5D dos conceitos anteriores.
- Ada mantém a forma pixelada; Gantt conserva as proporções quadradas.
- Rita continua sem a faixa branca e sem o coração como acessório permanente. Os corações são partículas temporárias da emoção carinho.
- A dobra da Toni acena para fora. Os gestos de papel usam a superfície curva com frente, verso e espessura.
- Sono tem respiração e Z animados; Ada e Gantt respiram por escala uniforme para manter suas formas.
- Pensamento, busca e atividade mostram o indicador; repouso, sono e fim da conversa o removem.
- São demonstrados gestos de arquivo, receptor, recepção, processamento, progresso, conclusão e retorno. A silhueta do avatar continua reconhecível, inclusive durante a miniatura de progresso.
- As reações de atividade usam os gestos próprios: rotas do Sig, respiração da Rita, linhas da Ada, cartões do Gantt, barras da Elinor e papel da Toni.

## Origem

Tempos e comportamentos adaptados do motor macOS do Coucou, commit `1dc314f632ff646b44191dbd4e89b042e07b3670`. A fonte de cada um está em `animation-catalogue.md`, com hashes em `source-audit.json`. O alô conserva a adaptação de tempos/easing da v4. Não foram usados a arte do Mochi ou áudios do Coucou. A licença MIT está em `source/COUCOU-MIT-LICENSE.txt`.

## Escopo e verificação

Somente conceitos e vídeos. Nenhum target, view, view model ou serviço do Sieghart foi alterado nesta revisão. Não foram abertos o aplicativo, microfone, atalhos, contas ou agentes reais. O onboarding aqui é uma apresentação animada para avaliação visual, não o fluxo integrado ao app.

`export-validation.json` registra metadados dos 11 vídeos, cobertura dos 49 controles, sintaxe da galeria, quadros inspecionados e diferença temporal do sono nas seis silhuetas. Não foi realizado teste de UI no navegador.

## Reproduzir a exportação

Compile todos os `.swift` em `source/` com `swiftc` e execute o binário com `all`, `onboarding`, `stills` ou o identificador de uma família do manifesto. Renderização offscreen SceneKit requer acesso à GPU. O renderizador grava apenas nesta pasta v6; o caminho está em `ExportGreeting.folder`.
