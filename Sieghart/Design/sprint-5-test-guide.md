# Sprint 5 — Como testar no Mac

Build de entrega: `/private/tmp/sieghart-s5-final/Build/Products/Debug/Sieghart.app`.

Encerre a versão antiga antes de abrir esta. Use arquivos de teste que você criou. Os controles continuam em inglês; a introdução tem a opção explícita de português. O app ficou fechado durante a minha verificação: estes passos validam as interações reais que os testes isolados não exercitam.

## 1. Entrada e aparência

1. Abra **Review introduction**. Confira a queda/olá/luz do Sig, os cinco saindo em círculo, a fila das apresentações e a volta do Sig para o Companion. Não deve existir o retângulo atrás dele, duplicações ou salto no final.
2. Abra **Calendar**. Gantt deve aparecer tanto antes da autorização quanto na agenda. Confira mês/data selecionada, dias agrupados e o próximo evento. Conceda Calendar apenas pelo botão da página, se necessário.
3. Abra **Files**, **Downloads** e **Capture** pela janela e pelo menu/island. Os mesmos arquivos/resultados devem aparecer nas três superfícies. Em **Dynamic Island**, substitua um botão lateral ou tile por cada nova função; feche/reabra para conferir a posição salva.
4. Confira no tamanho nativo da tela a nitidez do Sig, dos cinco pequenos e do Toni/Gantt das novas páginas. Ative Reduce Motion ou desative animações nas preferências: não deve continuar uma animação ativa nesses cabeçalhos.

## 2. Shelf — arquivos próximos

**Correção de 13 de outubro:** comece com o widget fechado e arraste um arquivo do Finder sobre a câmera/island. Ele deve abrir sozinho. Enquanto você segura, mova para os lados, para cima/baixo e nas diagonais: Toni e a luz de fundo devem acompanhar o arquivo nos dois eixos, dentro do contorno, sem cobrir os textos. Repita nos três tamanhos do widget. Solte: a entrada acontece pelo topo, seguida pelo cartão de arquivo com Preview/Files. Não deve existir o retângulo atravessando a frente do avatar. Cancele outro arraste e confira a página/anexo anteriores; teste também em tela cheia e sem animações, quando Toni deve permanecer parada na posição central. [Detalhes e prévia](sprint-5-file-drop-followup.md).

1. Em **Files → Shelf**, arraste dois arquivos do Finder ou use **Choose files**. Abra, revele no Finder e confira **Preview**.
2. Arraste um deles para outra pasta/app compatível. Confira o destino e **Share** no menu nativo.
3. Renomeie/mova um original no Finder; saia e retorne à página. O bookmark deve seguir o mesmo arquivo quando o sistema conseguir resolvê-lo. Se faltar acesso/arquivo, use **Reconnect** e selecione-o novamente. Depois de reconectar, arrastar deve usar o novo arquivo.
4. Remova uma referência e use **Clear shelf**. Os originais devem continuar onde estavam. Reabra o app: as referências mantidas devem persistir.

## 3. Downloads — observação real

1. Crie uma pasta de teste. Em **Downloads → Choose folder**, escolha somente ela. Os arquivos já existentes aparecem como disponíveis; não devem gerar uma conclusão nova.
2. Dentro dessa pasta, crie um arquivo `teste.txt.part`, espere dois segundos e renomeie para `teste.txt`. Deve aparecer uma conclusão e uma reação do Toni, uma única vez. Também faça um download real para a pasta escolhida: tamanho parcial e conclusão precisam acompanhar o arquivo quando o navegador expõe esse estado.
3. Clique **Open**, **Reveal** e **Keep on shelf** no arquivo final. Ele deve aparecer no Shelf.
4. Teste o cancelamento: mantenha um `outro.txt` antigo; crie um `outro.txt.part`, espere e apague apenas o parcial. Isso não deve anunciar que o arquivo antigo acabou de baixar.
5. Desative **Observe changes** e faça outra alteração: não deve haver uma nova reação automática. Reative, coloque o Mac para dormir/acordar e confira retomada sem notificações repetidas. Remova a pasta da lista para parar sua observação.

O app observa até cinco pastas escolhidas. Ele mostra bytes parciais, sem inventar porcentagem. Arquivos que sumiram ficam indisponíveis no histórico; limpar a lista preserva os originais.

## 4. File helpers — sempre revisar

1. Em **File helpers**, use **Choose files to move**, escolha um destino e revise. Antes de **Confirm**, nada deve sair do lugar. Cancelar mantém tudo intacto.
2. Repita com **Use Finder selection** e **Current Finder folder**. Aceite Automation para Finder somente quando o macOS pedir por essa ação. Negar deve mostrar um erro recuperável; escolher arquivos/pasta pelo seletor continua disponível.
3. Crie uma colisão de nomes no destino. **Cancel** deve impedir a operação; **Keep both** deve criar outro nome preservando o existente.
4. Adicione um arquivo ao Shelf e faça **Review rename** com outro nome, incluindo a extensão. Confira a revisão e confirme. Teste caracteres como espaços e acentos.
5. Cole `https://example.com/?utm_source=mail&q=a%2Bb&ref=keep#parte` na limpeza de links. A revisão deve remover só `utm_source`; copiar precisa manter `q`, `ref` e o fragmento.
6. Se tiver um DMG de teste confiável com um app no nível principal, escolha-o, selecione o app/destino e revise. Cancelar não instala; confirmar copia sem abrir o app automaticamente. Uma colisão preserva o app existente. **Eject** fecha a imagem; o DMG original continua intacto.

Em **Activation → Finder file shortcuts**, grave os atalhos opcionais: por exemplo ⌘X para preparar, ⌘V para revisar o destino e F2 para renomear. Eles começam desligados. Se F2 controlar brilho, grave usando Fn ou ajuste o uso das teclas de função no macOS. No Finder, selecione um arquivo e teste: nada deve mover/renomear antes da confirmação. Depois selecione TextEdit/Safari e confira que essas teclas continuam com a função normal do app. Teste novamente depois de fechar a janela do Sieghart. Uma combinação ocupada deve mostrar indisponível; grave outra.

## 5. Clipboard — colar sem formatação

1. Copie texto formatado. Selecione um campo de texto em outro app e abra Clipboard pelo menu/island ou **⌃⌥C**.
2. Use **Paste plain text**. Caso precise, conceda Accessibility nas configurações que já existem para direct paste. O destino deve receber texto sem formatação.
3. Cole normalmente depois: os formatos originais do clipboard devem continuar disponíveis. Se você fizer uma cópia nova durante a ação, ela deve prevalecer.
4. Feche/reabra o app e confira histórico/pins/limite. Se um histórico antigo já estiver ilegível, o app deve informar isso e oferecer recuperação explícita; não deve apagar silenciosamente seus dados.

## 6. Capture — tela e processamento local

1. Sem permitir captura, **Bring an image** deve abrir uma imagem e permitir leitura de texto/QR. Teste offline com uma imagem que tenha texto legível e um QR conhecido.
2. Use **Allow screen access** e aceite Screen Recording se solicitado. Se o macOS pedir reabrir o app, reabra o mesmo build. Faça **Select an area**: island/hover strip devem se esconder durante a seleção e retornar depois. Repita cancelando com Escape.
3. Na imagem, desenhe com Pen, Box e Arrow; adicione Text. Teste Undo/Clear. Salve o PNG e confira o desenho no arquivo, incluindo posicionamento e resolução original. A referência salva aparece no Shelf.
4. Use **Read text & QR**, copie o texto e confira o QR. Um link só abre quando você clicar no resultado.
5. Use **Pick a color**, confira o hex e a cópia. Repita cancelando o seletor. Nada deve ficar preso em loading.
6. Repita a seleção em um app em tela cheia. Interrompa a página, troque de ferramenta e cancele: uma seleção antiga não deve substituir uma ação mais nova.

## 7. Alertas e reações

1. Adicione um lembrete curto no Calendar. Confira Gantt, cartão, entrega, dismiss e snooze. Confira próximo evento/meeting link com um evento seu.
2. Em Files/Downloads/Capture, ative notificações apenas para a função que quer testar e use **Allow notifications**. Uma conclusão real deve produzir um cartão; nenhuma ação deve ser executada só por recebê-lo.
3. Configure quiet hours no Calendar. Nesse período, eventos continuam no histórico, mas não devem disparar um alerta de tarefa. Desative a preferência e confirme que novos eventos não notificam.
4. Faça a mesma ação duas vezes e alterne entre páginas. A reação nova deve tocar; o indicador de loading deve existir só durante uma operação real. Os cinco especialistas não devem abrir páginas aleatórias ao clicar.

## 8. CPU, memória e fechamento

No Monitor de Atividade, acompanhe **Sieghart** por 30 segundos em cada condição. Anote a faixa estável, o pico e a memória separadamente:

| Condição | CPU estável | Pico | Memória | Travou? |
| --- | --- | --- | --- | --- |
| Companion parado, ponteiro longe | | | | |
| Introdução completa | | | | |
| Nova reação de arquivo/lembrete | | | | |
| Downloads aberto, sem alteração | | | | |
| Widget fechado e janela minimizada | | | | |

A introdução/reação pode ter um pico breve. O estado parado/oculto deve cair novamente; não deve ficar sustentado nos 38–70% que você relatou antes. Uma captura de tela sozinha não prova consumo de todos os estados: grave o período ou mande as faixas da tabela. Os benchmarks anteriores mediram renderização isolada, não o processo completo.

Feche a janela pelo botão vermelho e confira **⌃⌥S / ⌃⌥V / ⌃⌥C** em outro app/tela cheia. Depois use Quit: as observações e serviços próprios devem parar. Abrindo novamente, listas/preferências devem voltar sem repetição de eventos antigos.

## Aceite

Reporte os números que falharem, a ação/frase exata, a mensagem exibida e, para fluidez, a tabela ou gravação. Se os grupos passarem, isso fecha o aceite físico da Sprint 5. Integrações de email/upload/GitHub/bancos e o pacote offline do Challenge têm etapas próprias.

## Ada na atividade de IA — 13 de outubro

Abra AI agents: Ada deve aparecer em Now tanto sem trabalho quanto nos agentes ativos. Quando uma atividade de código recolher para a island, deve aparecer Ada junto ao ícone do provedor. Sig continua como o Companion principal. As integrações novas de agentes e IA local estão documentadas como proposta; esta correção não as ativa.
