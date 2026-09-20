# Sieghart

Projeto macOS nativo em SwiftUI para o assistente pessoal anteriormente chamado de MyDude.

O Sieghart vai reunir contexto do dia, calendário, lembretes, pomodoro, voz, integrações de IA e um acionamento físico por impacto detectado no acelerômetro do Mac.

## Estado atual

O projeto tem janela principal, entrada na barra de menus e um leitor experimental do acelerômetro AppleSPUHIDDevice. O detector usa amostras dos três eixos, remoção simples da gravidade por baseline e cooldown para evitar disparos repetidos.

O ambiente de desenvolvimento confirmou um Mac15,7 com Apple M3 Pro e um serviço AppleSPUHIDDevice de uso 3 com relatórios de 22 bytes. A leitura pelo aplicativo ainda precisa ser executada no hardware com a permissão adequada.

O projeto também compila para `x86_64`, mas isso só comprova compatibilidade do binário. Não significa que o Intel possua o acelerômetro necessário.

## Primeiro marco técnico

Executar o Sieghart no MacBook Pro M3 Pro, pressionar “Iniciar sensor” e documentar se o dispositivo abre, a taxa de amostragem, o consumo e os falsos positivos antes de conectar o sensor a ações do assistente.

## Nome

`Sieghart` é o nome técnico atual do projeto. `MyDude` permanece como nome do conceito nas notas do vault até que a identidade do produto seja definida.
