# Sprint 6 — roteiro manual completo (partes 1–7)

Projeto: `/Users/antoniopaesdeandrade/Documents/ChatGPT/MyDude/Sieghart/Sieghart.xcodeproj`, branch `sprint-6`. Use o scheme **Sieghart**, destino **My Mac** e ⌘R. Encerre a instância anterior antes de executar o build atualizado. `Sieghart-Checks` é o scheme dos testes automáticos.

## Primeiro: permissão e trackpad

1. Na janela principal do Sieg, clique **Activation** na lateral e localize **Scrolling**.
2. Ligue **Invert scrolling** e **Include trackpad and smooth-scroll mice**. O segundo controle é necessário para o trackpad do MacBook e para mouses que enviam eventos contínuos. Não é necessário ter mouse externo. No build da parte 2, o mesmo controle se chama **Include smooth scrolling**.
3. Clique **Open Accessibility settings**. O botão abre o painel mesmo quando não aparece um novo alerta do macOS. Ative o Sieghart que está executando.
4. Havendo várias cópias do app, use **Locate this copy of Sieghart**: o Finder selecionará a cópia atual. No painel do macOS, use **+** e selecione essa cópia se ela não estiver listada. Não autorize uma cópia antiga por engano.
5. Volte ao Sieg e clique **Retry**. Role uma página longa no Safari com dois dedos: a direção deve inverter. Desligue **Invert scrolling**: a direção deve voltar à anterior.
6. Se a inclusão do trackpad estiver desligada, o novo build mostra um aviso ao receber eventos contínuos ignorados. Se não funcionar com a inclusão ligada, registre o texto de estado exibido; isso ainda requer investigação e não é aceite concluído.

A chamada de pedido de acesso é assíncrona e não confirma autorização imediatamente ([Apple Developer](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)). A aprovação é feita pelo usuário em Privacy & Security; um app ausente pode ser adicionado pelo botão + ([guia da Apple](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)). O app não altera essa aprovação sozinho.

## Escolher uma janela e trazê-la à frente

1. Abra o **Finder** e pressione **⌘N** duas vezes. Deixe uma janela na pasta **Downloads** e a outra em **Documentos**. Não minimize nem use tela cheia.
2. Volte à janela principal do **Sieg** e clique **Windows**, na barra lateral esquerda. Deixe **Focus window under pointer** e **Snap windows at screen edges** desligados durante este teste.
3. Clique **Refresh list**. Na seção **Windows — select one for layouts**, procure a janela **Downloads**, do Finder. O campo de busca pode filtrar por `Downloads` ou `Finder`.
4. Clique no **nome da janela Downloads**: isso só seleciona a janela que receberá o próximo layout. O texto acima dos layouts passa a mostrar o alvo escolhido.
5. Clique em **Show**, ao lado dessa janela: Downloads deve vir à frente. Para voltar ao Sieg, use seu ícone na barra superior e **Open Sieghart**, se a janela ficou encoberta.
6. Na seção **Apps — bring an app forward**, **Open Finder** ativa o Finder. Não escolhe uma janela para o layout; essa seleção é feita pelo nome na seção Windows.

Se a lista continuar vazia e pedir acesso, volte ao primeiro bloco. Não é possível validar layouts antes de conseguir listar uma janela elegível.

## Mover a janela com os botões e desfazer

1. Em **Windows**, selecione novamente o nome **Downloads** na lista.
2. Clique **Left half**: Downloads deve ocupar a metade esquerda da área útil da tela. A outra janela do Finder não deve receber esse layout.
3. Clique **Right half**: Downloads deve ir para a metade direita.
4. Clique **Undo last layout**: Downloads deve voltar à metade esquerda.
5. Teste **Top left**, **Top right**, **Bottom left** e **Bottom right**: cada botão deve colocar a mesma janela no respectivo quarto da tela.
6. **Fill usable screen** deve usar a área disponível sem entrar no modo tela cheia. **Center** deve centralizar a janela. Alguns apps impõem um tamanho mínimo; o Sieg deve informar quando o app ajustou o resultado.
7. Teste a proteção do Undo: aplique **Left half**, vá ao Finder e arraste Downloads pela barra do título para outra posição. Volte ao Sieg e clique **Undo last layout**. A janela deve permanecer onde você a colocou; o estado deve explicar que a mudança manual foi preservada.

## Encaixar arrastando até a borda

1. Antes de ligar o recurso, arraste a janela Downloads até uma borda e observe o comportamento atual. O macOS pode ter seu próprio encaixe; compare com essa referência.
2. No Sieg → **Windows**, ligue **Snap windows at screen edges**.
3. No Finder, segure o botão esquerdo ou o clique do trackpad **na barra do título de Downloads**, arraste até a borda esquerda da tela e solte. A janela deve ocupar a metade esquerda.
4. Repita na direita. Soltar em um canto deve usar um quarto da tela; soltar no topo deve preencher a área útil. A borda inferior, fora dos cantos, não tem ação própria.
5. Clique sem arrastar: o Sieg não deve aplicar encaixe. Redimensione segurando uma borda da janela: o Sieg também não deve aplicar encaixe.
6. Desligue a opção. O comportamento deve voltar à referência observada no passo 1.

## Parte 3: foco seguindo o ponteiro

1. Deixe duas janelas de apps diferentes parcialmente visíveis, por exemplo Finder e Safari. A área sob o ponteiro precisa pertencer a uma janela visível; não funciona sobre uma janela coberta por outra.
2. No Sieg → **Windows**, ligue **Focus window under pointer** e retorne aos dois apps.
3. **Sem clicar**, mova a seta para dentro da área visível da janela do Finder e pare por cerca de meio segundo. O Sieg deve solicitar ativação e trazer essa janela à frente.
4. Faça o mesmo no Safari. Funciona com mouse ou trackpad, pois usa a posição da seta.
5. Passe rapidamente sobre a outra janela sem parar: não deve ativá-la. Clique, role ou comece um arrasto durante a espera: a ativação pendente deve ser cancelada.
6. Desligue a opção: mover a seta sem clicar não deve mais provocar ativação pelo Sieg.

## Parte 4: botões extras do mouse (Side 4 / Side 5 e auxiliares)

1. Em **Activation** → **Extra mouse buttons**, ligue **Back and Forward with side buttons** (ou configure ações individuais para Side 4, Side 5 e Extra 6–8).
2. Com mouse externo que possua botões laterais, abra o Safari ou Finder com histórico de navegação e pressione Side 4 / Side 5: o app sob o cursor deve voltar/avançar sem afetar cliques esquerdo/direito/meio.
3. A ação ocorre uma vez ao pressionar o botão lateral. Segurar, arrastar e soltar não devem executar uma segunda ação. Desligar enquanto o botão está pressionado deve preservar o pareamento da liberação.

## Parte 5: rolagem linear/suave e aceleração do ponteiro

1. Em **Activation** → **Scrolling & Pointer**, ligue **Linear wheel scrolling** e **Smooth wheel scrolling**, ajustando **Wheel step**. Com roda de mouse discreta, picos rápidos devem manter passo previsível por notch; o trackpad permanece intacto enquanto **Include trackpad and smooth-scroll mice** estiver desligado.
2. Em **Scrolling & Pointer**, ligue **Mouse acceleration**; observe o backup exibido de `com.apple.mouse.scaling`. Teste **Flat 1:1 pointer curve** ou o controle de velocidade e clique **Restore original Mac acceleration**: o valor original deve ser restaurado imediatamente.

## Parte 6: debounce de clique/teclado, Hyper Key, proteção ⌘Q/⌘W e snippets

1. Em **Activation** → **Input Guards, Hyper Key & Snippets**, teste **Mouse click debounce** (`15–100 ms`) e **Keyboard key debounce** (`15–80 ms`): cliques normais e autorepeat contínuo de tecla continuam funcionando.
2. Ligue **Hyper key (⌃⌥⌘⇧)** (ex.: **F18**): segurar a tecla gatilho e pressionar uma letra deve enviar `⌃⌥⌘⇧`.
3. Ligue **Quit & close confirmation (⌘Q / ⌘W)** (e opcionalmente **Also require confirmation for ⌘W (Close Window)**): no Safari ou Notes, o primeiro `⌘Q` é interceptado e mostra o lembrete no Sieg; pressionar `⌘Q` novamente em até 1,5 s confirma o encerramento.
4. Em **Text Snippets**, adicione um gatilho (ex.: `;sig` → `Sieghart Companion`), ligue **Expand text snippets while typing** e digite `;sig` no Notes: o gatilho deve ser apagado e substituído pelo texto. Em campos de senha (Secure Input), o estado informa pausa automática.

## Parte 7: Dock preview, clique no Dock, botão verde, auto-quit e ordem dos Spaces

1. Em **Windows** → **Dock, Green Button & Spaces**, ligue **Inspect Dock app windows** e clique em **Preview Dock** ao lado de um app na seção **Apps — bring an app forward**: os cartões mostram a proporção de cada janela e permitem **Show** ou **Minimize/Restore**.
2. Em **Active Dock click action**, escolha **Minimize or restore windows** e use **Dock action** em um app ativo para alternar minimização/restauração de suas janelas.
3. Ligue **Green button fills usable desktop (instead of full-screen)**: clicar no botão verde de uma janela externa deve preencher a área útil (sem criar Space de tela cheia) e um segundo clique no botão verde deve restaurar o tamanho anterior.
4. Ligue **Quit app when its last window closes**: abra uma janela em um app comum (ex.: Notes ou TextEdit) e feche sua última janela; após o tempo configurado (`1–15 s`), o app deve encerrar. O Finder, Ajustes do Sistema e o próprio Sieghart nunca são encerrados.
5. Ligue **Keep Spaces in fixed numerical order (disable MRU)** e depois clique **Restore original** (ou desligue a opção): `mru-spaces` deve retornar ao valor original salvo.

## Extensão de IA: Monitoramento local do Antigravity

1. Na barra lateral do Sieg, clique em **AI limits** (ou abra **Tokens, charges & connections**).
2. Caso o Antigravity ainda não esteja conectado, clique em **Connect local Antigravity usage** no cartão **Antigravity activity**.
3. Verifique que o seletor de provedores no topo da tela **AI agents** passa a exibir **Antigravity** ao lado de **Codex** e **Claude**, lendo automaticamente as sessões locais em `~/.gemini/antigravity/brain` (contagem de sessões, tokens de entrada, saída, leitura de cache, estimativa de custo equivalente de API, gráfico de barras por hora, ranking de modelos/projetos e mapa de 13 semanas).

## Retomada e registro

Com cada recurso ligado, teste lock/desbloqueio e sono/retomada. Desligue o recurso antes de mudar para o próximo teste, para isolar o resultado. Se tiver segundo monitor, repita os layouts e encaixes nele. Os testes físicos, a experiência de permissões, a responsividade e CPU continuam pendentes até relato/execução real.

Para relatar uma falha, registre: **bloco/passo, app, mouse ou trackpad, texto de estado do Sieg e resultado observado**. O relato de 19/out de ausência de alerta e scroll inoperante no trackpad motivou a recuperação por Ajustes e a explicação de eventos contínuos; a causa física completa e o aceite desse relato continuam pendentes.



## Limites encontrados na revisão rápida

Os cartões de janelas ficam na UI do Sieg; hover/clique diretamente nos ícones do Dock ainda não têm integração completa. Não considerar esses testes aprovados por contratos injetados. **Deixe auto-quit desligado** até corrigir a leitura AX desconhecida e a observação do fechamento. As correções estão reservadas para [Sieg — Revisão](revisao-pos-sprint-6/README.md).
