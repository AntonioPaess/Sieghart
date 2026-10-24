# Crash de voz — atribuição do processo, 22/10/2026

O crash informado pelo usuário na versão 78 ocorreu às 11:37. O relatório apresenta encerramento TCC por ausência de `NSSpeechRecognitionUsageDescription`, mas a chave e a descrição do microfone **existem** no app instalado e passaram em `Tests/verify-built-app.sh`.

Os registros do macOS confirmaram a causa: o executável foi iniciado diretamente como filho do processo de desenvolvimento. O processo 53386 tinha `responsibleProc = ChatGPT`. Na solicitação de reconhecimento de fala, o TCC escolheu `subject=com.openai.codex` e recusou a operação porque esse aplicativo responsável não tem a descrição de fala do Sieghart. Não era uma chave ausente no bundle do Sieghart. A primeira hipótese baseada apenas no texto do crash foi corrigida após essa conferência.

## Correção e prevenção

- Adicionado `Tools/launch-current-app.sh`, que valida a cópia canônica e usa LaunchServices (`open -a`), incluindo a opção explícita de preservar uma sessão existente de Keep Awake.
- O instalador agora executa a verificação existente de descrições de privacidade, metadados e capacidades assinadas antes de substituir o aplicativo. Sua saída orienta a abertura pelo launcher.
- Não executar `/Applications/Sieghart.app/Contents/MacOS/Sieghart` diretamente pelo agente. Isso transfere a atribuição de privacidade para o aplicativo de desenvolvimento, afetando também verificações de tela e Acessibilidade.
- O binário 78 já tinha os metadados corretos; não foi necessário recompilar nem alterar sua assinatura para esta correção de abertura.

## Verificado

O app foi reaberto pelo launcher. O processo novo, 54840, tem pai 1. Os registros TCC de inicialização passaram a mostrar `subject=com.sieghart.app`, sem o responsável ChatGPT herdado. A janela principal foi conferida pelo controle nativo. A sessão de Keep Awake permaneceu ativa, com o mesmo prazo e a mesma preferência de retomada.

Sintaxe dos dois scripts e verificação do app instalado aprovadas. Não houve reset de permissões, concessão de acesso, captura de microfone ou reprodução de áudio pelo agente. A confirmação do turno de fala completo continua pendente do teste do usuário.

O estado do design permanece o documentado em [sieg-premium-design-2026-10-22.md](sieg-premium-design-2026-10-22.md): padrão aplicado às 16 abas e cenários climáticos integrados, com validação de estados reais e acabamento pontual ainda pendentes. As verificações de permissão feitas em processos anteriormente iniciados diretamente não comprovavam a autorização independente do Sieghart; revalidar na cópia aberta corretamente.

Resumo do diagnóstico em [evidence/sieg-voice-launch-crash-2026-10-22/diagnosis.json](evidence/sieg-voice-launch-crash-2026-10-22/diagnosis.json), sem transcrições privadas.
