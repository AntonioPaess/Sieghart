# Conferência final — revisão pós-Sprint 6

Baseline `e229194`, branch `revisao/pos-sprint-6`. [Registro por lote](../../Workflow/sprint-6-revisao-execucao.md) e [roteiro manual](../../Workflow/sprint-6-teste-manual.md).

- Fast: **254 funções / 968 invocações**, todas aprovadas.
- Complete IA/RPC/preços: **75 funções / 77 invocações**, todas aprovadas.
- Ambos usaram os mesmos 221 inputs Swift, sem mudanças durante/depois das execuções, e incluíram 139/139 arquivos de produção esperados na cobertura.
- Build Debug universal **arm64/x86_64** aprovado com `CODE_SIGNING_ALLOWED=NO`; app não foi executado. Info.plist, projeto e catálogo de preços empacotado conferem com o ROOT original.

[Resumo](verification.json) · [Fast](fast-verification.json) · [Complete IA](ai-verification.json) · [Build](app-build.json) · [Fontes Swift](source-manifest.json) · [Outros inputs](additional-input-manifest.json) · [Auditoria de preços e fontes](price-source-audit.md).

Contratos individuais estão em fast-contracts.json e ai-contracts.json. Logs e xcresult atuais permanecem em `/private/tmp/sieg-pos-s6/dock-followup/{final-fast,final-complete-ai}`. As pastas de mesma finalidade diretamente em `/private/tmp/sieg-pos-s6/` são histórico anterior à correção do Dock. O projeto temporário do runner usa symlinks para as fontes originais; não houve troca do runtime por fixtures de implementação. O transporte/contas/modelos são injetados nos testes apropriados. O primeiro build encontrou Info.plist ausente na pasta temporária; esse input foi copiado com hash idêntico e só o build foi repetido.

Snapshots cumulativos e patches em `/private/tmp/s6-review-lotes/`, com manifestos e índice commit-lotes.json. Nenhum commit/push/merge foi feito. O Mac físico, permissões, event taps/AX/Dock reais, CPU/RAM e serviços/contas/modelos reais continuam gates de aceite. Evidência de fixture, cobertura ou compilação não equivale a esse aceite.


Após conferência independente, o Dock deixou de interceptar eventos: observa um clique curto no up, preserva arrasto/hold/contexto/modificadores e usa a intenção anterior ao restore nativo. O hover revalida posição e identidade atuais ao expirar o dwell. [Recorte Dock](dock-verification.json): **35 funções / 54 invocações**, todas aprovadas; [contratos](dock-contracts.json). Fast, Complete IA e build desta pasta são atualizados para essa mesma versão; os logs atuais ficam em `/private/tmp/sieg-pos-s6/dock-followup/`. Evidências anteriores continuam em `/private/tmp/sieg-pos-s6/final-*` como histórico, sem substituir os manifestos novos.
