# Recuperação de interpretação e Keep Awake — 23 de outubro de 2026

## Falhas reproduzidas

- Depois de consultar clima, uma frase curta extraída de um pedido composto podia ser tratada como cidade. “Explicar sobre circunferência” escapava da lista de ações; o desenho era executado, mas a explicação consultava clima novamente.
- “Ativa o Keep Awake com 2hrs” não era reconhecido como ativação: o interpretador aceitava outras preposições e caía na resposta de estado. A resposta posterior podia mostrar uma chamada de ferramenta como texto, sem executar nada.
- O bloqueio relatado em 22/10 ocorreu durante uma atualização. Os eventos locais de energia registram a liberação da proteção de tela às 15:35:54, bloqueio às 15:36:16 e nova proteção às 15:36:27. A continuidade do contador não bastava para cobrir esse intervalo.
- Na verificação de 23/10, o OCR real falhou ao carregar recursos do Neural Engine do macOS. O erro não foi substituído por texto inventado.

## Alterações

### Intenção e desenho

Uma cidade isolada só completa uma pergunta pendente de localização. O contexto recente aceita continuação explícita, como “E Lisboa?”. Pedidos novos de explicação, desenho e leitura mantêm a própria intenção. Nenhuma lista fixa de cidades foi adicionada.

Depois de desenhar, a explicação recebe o pedido original e o resultado confirmado do canvas. Não passa novamente pelo reconhecimento de clima ou captura de tela. O modelo Apple recebe esse resultado sem ferramentas para repetir o desenho. A explicação continua sendo gerada pelo modelo, sem respostas matemáticas predefinidas.

### Respostas sem modelo

A inspeção final encontrou uma exceção antiga em `OfflineFallbackChatEngine.generateVoice`: ela respondia sobre pi com texto fixo quando o modelo falhava. Essa exceção foi removida. Também foram removidos passos de raciocínio fabricados e uma frase que afirmava ter inspecionado a tela sem confirmação. Sem inferência disponível, o mecanismo agora retorna indisponibilidade; apenas ferramentas nativas com resultado real podem continuar entregando respostas. A correção recebe testes de indisponibilidade em português e inglês.

### Keep Awake

O build 100 já inclui duração com “com/em”, opção explícita de manter a tela ligada, persistência no controlador e reparação de uma ativação recente usando somente o pedido do usuário. Uma resposta textual do modelo não conta como ação executada.

Os scripts de atualização agora verificam a proteção nativa e mantêm uma proteção temporária independente durante a troca do aplicativo. Para uma sessão finita, o limite é o prazo original; para uma sessão sem limite, a ponte dura até 180 segundos. A liberação exige confirmação da nova proteção ou encerramento/alteração da sessão. Nenhuma configuração de senha, bloqueio ou repouso do sistema é alterada.

### OCR local

O Vision usa primeiro o reconhecimento rápido nos dispositivos CPU oferecidos pela API. O modo preciso continua disponível quando o primeiro não encontra texto ou falha. Os pixels e as regiões reconhecidas continuam sendo reais. Permissão negada e cancelamento continuam sendo erros explícitos.

A medição local com uma imagem gerada reconheceu o mesmo texto em 0,215 segundo no modo rápido e 48,528 segundos no preciso. A escolha reduz a espera de leitura de interfaces neste Mac; não garante a mesma precisão para fontes pequenas ou idiomas que dependam do modo preciso. Referência da API: [dispositivos de processamento do Vision](https://developer.apple.com/documentation/vision/vnrequest/supportedcomputestagedevices).

## Evidências e limites

- Baseline anterior: `/tmp/sieg-checks-awake-98/verification.json`, 367 funções e 1122 invocações aprovadas.
- Primeira verificação de intenção: `/tmp/sieg-checks-intent-103`, identificou uma variante em inglês, uma expectativa antiga de teste e a falha real de OCR descrita acima. Esses resultados não foram tratados como aprovação.
- A execução intermediária `/tmp/sieg-checks-intent-104` aprovou as 370 funções, mas o verificador detectou três arquivos alterados durante a preparação. Não é a evidência final; a execução seguinte parte dos arquivos estabilizados.
- Proteção de atualização: oito verificações aprovadas em `/tmp/sieg-guard-104-tests.log`.
- A validação usa captura sintética de pixels, controles de app isolados e transcrições de teste. Não houve uso de microfone, reprodução de voz ou teste físico de AirPods/atalho.
- Não houve commit, push ou criação de worktree. A instalação mantém `/Applications/Sieghart.app` como destino único.

## Resultado final

- Build **106**, universal, compilado e instalado em `/Applications/Sieghart.app`; assinatura e descrições de privacidade verificadas. A cópia anterior foi preservada em `/private/tmp/sieghart-previous-app.pZI6PE/Sieghart.app`.
- `/tmp/sieg-checks-intent-106/verification.json`: **371 funções / 1141 invocações aprovadas**, 195/195 arquivos de produção cobertos, nenhum teste ausente/inesperado e nenhum arquivo alterado durante a execução.
- O teste real de OCR de pixels passou em **0,185 segundo**, incluindo a verificação separada de permissão negada sem texto inventado.
- Conferência das datas de modificação: os arquivos de produção alterados desde o build 100 são os três serviços/coordenadores de intenção/OCR e `AppleLocalChatEngine.swift`, onde foi removido o fallback fabricado. As alterações anteriores de design e animação foram mantidas.
- Instalação aberta pelo LaunchServices, processo filho de `launchd` (PID pai 1), identidade `com.sieghart.app` preservada.
- **Handoff real do Keep Awake confirmado:** proteção de tela mantida após a atualização, prazo original **17:23:45 de 23/10, horário de Recife** e guarda temporária liberada somente após a troca. A interface confirmou “Mac e tela permanecem acordados”, tela ligada e contador de aproximadamente 1h43 restante. Não foi iniciada nem reiniciada uma sessão para teste.
- Evidências pequenas foram copiadas para [`evidence/sieg-intent-recovery-2026-10-23`](evidence/sieg-intent-recovery-2026-10-23), incluindo o estado instalado e a verificação dos testes.

No build 106, Tab e o contorno visível de foco foram conferidos na Home. A inspeção adicional de rolagem foi impedida por limite de uso na revisão automática da ferramenta de interface; não foi contornado.

Ainda não foram validados fisicamente microfone, qualidade da voz, AirPods, atalho mantido pressionado ou a leitura da tela do usuário após permissões. Estes resultados não significam conclusão de todo o design ou paridade total com HeyClicky.
