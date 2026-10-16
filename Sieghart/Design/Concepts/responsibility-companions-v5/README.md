# Sieghart — equipe, Rita e papel vivo da Toni (v5)

Estudo visual solicitado em 10 de outubro de 2026. Nenhuma alteração no código ou funcionamento do aplicativo.

## Assistir

Abra `preview.html`. Escolha o clipe, avance para um momento pelo botão correspondente e use 0,5× ou 0,25× para observar o papel. Os MP4 são a versão de melhor qualidade, em 60 fps.

- `ensemble-hello-60fps.mp4`: 10 s. O alô aprovado do Sig segue os tempos de referência; aos 4,5 s os cinco especialistas começam a sair de trás dele, fazem uma órbita e se acomodam ao redor com nomes e áreas.
- `rita-hello-60fps.mp4`: 6 s. Retirados faixa branca e coração. Um pequeno traço coral de pulso fica integrado ao corpo.
- `toni-hello-60fps.mp4`: 6 s. Retirada a cauda fixa sobreposta ao papel. A nova dobra é uma superfície curva fechada com duas faces, normais, textura e espessura. Fica articulada na lateral esquerda e acena para fora; não gira para dentro do corpo. A lateral coral fica atrás da face creme.
- `agent-flow-60fps.mp4`: 16 s. Demonstração dos seis em escuta → pensamento → busca → execução → espera de aprovação → conclusão → repouso. Na execução os conceitos exibem os gestos próprios de atividade. O halo e o indicador retornam ao repouso ao final.
- Os alôs individuais de Sig, Ada, Gantt e Elinor são os vídeos preservados da v4.

## Pesquisa

`animation-catalogue.md` e `.json` registram o inventário de gestos, expressões, voz, recepção de arquivos, minis dos agentes e transições da ilha/desktop. Cada comportamento possui link direto para o arquivo e a linha do código público auditado, commit `1dc314f632ff646b44191dbd4e89b042e07b3670` de Louis-CFM/coucou. `source-audit.json` registra hashes dos arquivos lidos.

O catálogo separa famílias demonstradas nesta revisão de comportamentos apenas catalogados para uma futura adaptação. Não houve envio de arquivo/email, integração de calendário/GitHub, leitura de microfone ou ativação de agente real. Não foi aberto o Sieghart.

Os 11 estados e 8 emotes definidos no código de referência foram conferidos; rotinas complementares geram os demais comportamentos do inventário. Não é uma contagem oficial de animações do projeto, nem uma auditoria dos clientes em outras plataformas.

## Origem e aparência

O alô reutiliza a adaptação de tempos/easing da v4; seu código de origem permaneceu idêntico entre os dois commits auditados. Busca, ritmo de aprovação e tempo da volta de conclusão foram adaptados do motor do Coucou. A ordem do fluxo é uma demonstração visual, não um comando executado.

A órbita dos cinco e a folha curva com gesto exterior da Toni são coreografias próprias para os conceitos Sieghart. Os modelos têm volume e iluminação; continuam sendo uma interpretação procedural da prancha, não a reprodução de sua textura raster. Não foram usados a arte do Mochi ou áudios do Coucou. A licença MIT do código acompanha `source/COUCOU-MIT-LICENSE.txt`.

## Reprodução

`source/` contém o renderizador isolado da prévia, fora dos targets do aplicativo. Compilar todos os `.swift` do diretório em um executável e executá-lo gera os vídeos na pasta de conceitos desta revisão. `--stills-only` gera só os quadros de inspeção. SceneKit exige acesso à GPU para renderização offscreen. As versões anteriores permanecem preservadas.

`export-validation.json` registra dimensões, duração, contagem de quadros, inspeção de movimento do papel e sintaxe do JavaScript da galeria. Não foi realizado teste de UI no navegador.
