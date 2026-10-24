# Índice portátil — pesquisas e REA

Auditoria de continuidade de **23/10/2026**. As pesquisas já existiam, mas parte do material estava apenas na pasta original do projeto. Este snapshot inclui **59 arquivos de documentação/evidência preservados**, cerca de 11,5 MB, com [manifesto de origem e SHA-256](Sieghart/Design/Research/handoff-import-manifest-2026-10-23.json).

Conferência repetida em 24/10/2026: os 59 conteúdos correspondem ao manifesto. No README de `hey-assistants-2026-10-11` já presente no checkout, normalizar CRLF para LF antes de comparar o hash; o conteúdo é idêntico e o Git normaliza essas quebras de linha.

**REA não significa análise completa de todos os binários.** Alguns estudos são leitura de código aberto, documentação oficial, pacote estático ou observação de UI. As limitações abaixo e nos relatórios fazem parte da documentação; não devem ser convertidas em funcionalidades supostamente implementadas no Sieg.

## Começar pelos índices existentes

- [Dossiê consolidado de aplicativos e arquitetura](Sieghart/Sieghart-Research/README.md).
- [Inventário de aplicativos e ambiente](Sieghart/Sieghart-Research/applications/inventory.md).
- [Índice do estudo de referências de 13/10](Sieghart/Design/Research/reference-study-index-2026-10-13.md).
- [Comparação de oportunidades de integração](Sieghart/Sieghart-Research/comparisons/integration-opportunities.md).

## Aplicativos e natureza do estudo

| Referência | Documentação no repositório | Alcance e limite |
| --- | --- | --- |
| HeyClicky | [Dossiê principal](Sieghart/Sieghart-Research/applications/heyclicky.md), [referência de design](Sieghart/Design/clicky-reference.md), [estudo do pacote](Sieghart/Design/Research/hey-assistants-2026-10-11/README.md) | Pacote/binário 1.0.53/build 64, REA estático parcial, documentação e UI/relatos. Motor nativo de voz, prompts e algoritmos completos não foram reconstruídos. |
| HeyTaby | [REA de Taby/Clicky](Sieghart/Design/Research/rea-apps-2026-10-13.md), [estudo anterior](Sieghart/Design/Research/hey-assistants-2026-10-11/README.md) | Pacote 1.0.13 e módulos JavaScript selecionados; parsing e hashes preservados. Cobertura semântica desconhecida e 1954 desconhecidos na seleção adicional. Não prova execução real ou desempenho. |
| OpenJarvis | [Dossiê](Sieghart/Sieghart-Research/applications/openjarvis.md), [referência anterior](Sieghart/Design/Research/openjarvis-reference-2026-10-11.md), [runtime](Sieghart/Sieghart-Research/architecture/openjarvis-agent-runtime-analysis.md), [comparação](Sieghart/Sieghart-Research/comparisons/openjarvis-vs-sieghart-architecture.md) | Estudo do projeto identificado no relatório. Não confundir projetos homônimos nem presumir uma voz única padrão. Integração no Sieg é uma proposta separada. |
| Boring Notch | [Dossiê](Sieghart/Sieghart-Research/applications/boring-notch.md) | Código aberto em commit fixado e pacote instalado examinado estaticamente; sem REA do binário. Há APIs privadas no projeto de referência; não incorporá-las por suposição. |
| VoiceInk | [Dossiê](Sieghart/Sieghart-Research/applications/voiceink.md) | Código macOS em commit fixado. A instalação encontrada era iOS no Mac, não validação do produto macOS. Ditado global físico continua sem aceite. |
| Raycast | [Dossiê](Sieghart/Sieghart-Research/applications/raycast.md) | Documentação/SDK públicos e limites declarados; não reconstrução completa do runtime fechado, ranking ou latência. |
| Coucou | [Chat](Sieghart/Design/Research/coucou-chat-2026-10-13.md), [arquivos/arraste](Sieghart/Design/Research/coucou-files-2026-10-13.md), [referência](Sieghart/Design/coucou-reference.md) | Rastreio de código aberto fixado e atribuição no código adaptado. Licença de código não autoriza copiar personagens/arte. |
| Vorssaint | [Índice de referências](Sieghart/Design/Research/reference-study-index-2026-10-13.md), [mapa de capacidades](Sieghart/Design/companion-capabilities.md) | Estudos locais de utilitários/arquivos. Fonte GPL estudada, não promessa de incorporar seu runtime. Nem toda a matriz de utilitários está entregue. |
| Muse / ESP32 | [SDK e referências](Sieghart/Design/Research/muse-and-references-2026-10-13.md) | Código/protocolo públicos em commit fixado. Firmware aberto não significa assistente completo local; satélite do Sieg é trabalho próprio futuro. |
| Minhas Finanças | [REA e fontes oficiais preservadas](Sieghart/Design/Research/rea-apps-2026-10-13.md) | Identidade pública e sete guias oficiais. **Não houve REA do binário**, pois não havia artefato acessível no escopo estudado. Nenhuma conta financeira conectada. |
| Open Finance / DeseretSaint | [Dossiê DeseretSaint](Sieghart/Sieghart-Research/applications/open-finance-deseretsaint.md), [openfinance.app](Sieghart/Sieghart-Research/applications/open-finance-openfinance-app.md), [comparação](Sieghart/Sieghart-Research/applications/open-finance-comparison.md) | Identidades e fontes distintas, com limites próprios descritos nos relatórios. Não confundir produtos homônimos nem tratar estudo documental como conexão bancária. |
| Herdr | [Estudo de sessões e UI](Sieghart/Design/Research/herdr-clicky-followup-2026-10-14.md) | Código público fixado. Não foi conectado daemon/PTY real do usuário. |
| Orca | [Sessões e workroom](Sieghart/Design/Research/orca-room-2026-10-14.md) | Documentação e contratos de organização; não runtime Orca integrado nem despacho autônomo comprovado. |

## Evidências de REA preservadas

- [Índice de 11/10](Sieghart/Design/Research/hey-assistants-2026-10-11/evidence-index.json): manifests de download, identidade de artefatos, inventário nativo e análise estática de voz/animação. Arquivos `.json.gz` podem ser abertos com ferramentas comuns de gzip/JSON.
- [Índice de 13/10](Sieghart/Design/Research/rea-apps-2026-10-13/evidence-index.json): seleção adicional de módulos, Evidence IDs, resumos, proveniência e tentativas interrompidas.
- [Proveniência dos módulos de Taby](Sieghart/Design/Research/rea-apps-2026-10-13/taby-context-provenance.json).
- [Manifesto das fontes financeiras públicas](Sieghart/Design/Research/rea-apps-2026-10-13/finance-public-sources/source-manifest.json).

Estes são relatórios e saídas estáticas preservadas. Instaladores, aplicativos de terceiros, credenciais, contas e dumps de execução pessoais não fazem parte desta importação.

## Arquitetura e propostas derivadas

Em [Sieghart-Research/architecture](Sieghart/Sieghart-Research/architecture/) há estudos separados de voz, UI, automação, agentes, runtime OpenJarvis e dados financeiros. Em [comparisons](Sieghart/Sieghart-Research/comparisons/) ficam as comparações; em [integrations](Sieghart/Sieghart-Research/integrations/), viabilidade e contratos propostos. O [roadmap de pesquisa](Sieghart/Sieghart-Research/roadmap/implementation-roadmap.md) é histórico e deve ser reconciliado com `CURRENT_WORK.md` e `KNOWN_ISSUES.md` antes de implementar.

## Obsidian e portabilidade

O vault local observado é `~/Documents/2nd-Brain`, com o projeto em `Projects/Sieghart` e contexto anterior em `Projects/MyDude/Context`. O Obsidian é uma visão complementar; o código e este índice devem bastar para continuar em outro computador. Caminhos absolutos e `/tmp` dentro de relatórios antigos são proveniência histórica, não dependências obrigatórias da retomada.

O subprojeto acadêmico separado `aegis-tcc` permanece na pasta original/vault e não foi importado nesta entrega do produto. Não é uma análise de outro aplicativo necessária para continuar o Sieg.
