# Bassy: prática, gravação e reprodução simples

Exploração de 5 de outubro de 2026. Base: HEAD `e5a2532fcf38e9f45872f639078cba03192056d2`, fontes da app de `3d7319a`. Checkout em HEAD destacado; a branch de origem informada é `codex/session-library`. PR #22 é contexto. Nenhuma alteração de produção, assinatura, projeto, merge ou nova feature nesta exploração.

Seguimento autorizado pelo usuário: [F0.2 — Simplified Practice UI](../../plan/features/f0-2-simplified-practice-ui.md). As observações e capturas deste documento descrevem a base anterior à implementação de F0.2.

## Decisão proposta

Usar **Praticar + Gravações** como navegação principal. A tela Praticar mostra sessão atual, saída, Gravar, Ouvir ao vivo e última gravação com Ouvir/Parar. Timbre abre os controles já existentes; Entrada e saída abre ajustes de áudio e leva ao diagnóstico. Remover o passo explícito Start Audio do caminho cotidiano: o modelo inicia o motor quando uma ação o exige, com autorização de microfone quando necessária. Encerrar áudio permanece disponível como ação secundária distinta de finalizar gravação e parar reprodução.

Alternativa revisável: **Gravação em foco**, com o transporte dominando a tela e a escuta ao vivo abaixo dele. Recomendo Praticar porque atende tanto quem toca com fones quanto quem grava pelo microfone para ouvir depois. O protótipo usa os controles existentes como base; os comportamentos simplificados descritos aqui ainda dependem de implementação posterior.

O protótipo interativo foi entregue na conversa, com duas variantes. É uma simulação sem áudio real, sem captura de microfone e sem persistência. Duração, nomes e rota são exemplos. O guia local preexistente em `docs/guides/gravacao/GUIA.md` serviu como referência e foi preservado fora deste commit; não comprova captura ou reprodução física.

## Problemas observados no código e na tela atual

| Fluxo | Implementação atual | Consequência |
|---|---|---|
| Começar a tocar | Start Audio e Live Monitoring são ações independentes; monitoramento fica muito abaixo | Running pode ser interpretado como “já ouvindo”, embora monitoring comece desligado |
| Gravar | Exige Running; botão abaixo de sessão, áudio e perfil | A próxima ação fica fora da área inicial visível |
| Parar | Stop Audio, Stop Recording e Stop Playback em lugares diferentes | É difícil prever se o botão termina uma faixa ou encerra tudo |
| Ouvir | Play na linha; Stop Playback aparece separado; mixer e ganho de saída em outras seções/aba | Reprodução ativa pode estar silenciosa por configuração legítima |
| Encontrar | Library lista sessões; Open muda workspace, mas não muda a aba | Usuário volta a Session e procura Recording rolando |
| Escolher entrada | Texto pede iniciar, parar, selecionar e iniciar novamente | Fluxo técnico de descoberta entra no caminho comum |
| Salvar | Autosave existe, mas Save Session ocupa a parte superior | A interface sugere trabalho manual obrigatório e ainda não distingue arquivo finalizado de metadados persistidos |

Referências: `BassPractice/UI/AppShellView.swift`, `Features/Session/SessionView.swift`, `SessionModel.swift`, `Features/Library/LibraryView.swift`.

## Fluxos e número de toques

Contagens excluem autorização inicial do iOS e conexão física. A promessa de um ou dois toques vale para a próxima ação a partir da tela principal, não para todas as operações de manutenção.

| Objetivo | Proposta | Toques |
|---|---|---:|
| Ouvir ao vivo | Ouvir ao vivo → modelo solicita permissão, inicia motor e liga monitoring | 1 com fones; 2 se precisar confirmar uso de microfone/alto-falante |
| Gravar | Gravar → modelo inicia motor se necessário e depois captura | 1 |
| Finalizar | Mesmo botão muda para Finalizar gravação; finaliza CAF e oferece Ouvir | 1 |
| Ouvir última faixa | Ouvir na última gravação; inicia motor se necessário | 1 |
| Interromper faixa | Ouvir muda para Parar na mesma linha | 1 |
| Outra faixa da sessão | Gravações → Ouvir na linha | 2 |
| Faixa de outra sessão | Gravações → Sessões → abrir → Ouvir | 4; melhoria futura de lista conjunta pode reduzir, mas não é requisito desta exploração |
| Timbre | Timbre → perfil/ajuste | 1–2 até o controle |
| Volume/saída | Saída visível → ajustes | 1 até os controles |
| Diagnóstico | Saída → Diagnóstico | 2 |

Na primeira abertura, Gravações usa a sessão atual. Abrir outra sessão deve levar diretamente às suas faixas e mostrar seu nome. Não juntar gravações de todas as sessões sem explicitar a origem e o efeito sobre o workspace. Renomear, nova sessão e excluir ficam no menu de Sessões; exclusão mantém confirmação já existente.

## Contrato dos estados

- **Pronto:** Gravar e Ouvir ao vivo acionáveis; última faixa mostra Ouvir. Nenhum estado “Running” sem explicação funcional.
- **Iniciando:** ação selecionada mostra preparação; bloquear toques duplicados, não ocultar erros nem navegação desnecessariamente.
- **Gravando:** tempo decorrido, indicação textual e Finalizar gravação no mesmo lugar. Não permitir troca de sessão; feedback contextual explica o motivo. Na proposta simples, parar playback antes de começar a gravar. O motor atual permite ambos; essa é uma decisão de interação a validar, não uma limitação técnica.
- **Finalizando:** aguardar fechamento do arquivo; só oferecer Ouvir depois do sucesso. “Salvando…” dura até `repository.save` concluir. `finishRecording` bem-sucedido não autoriza mostrar “Salva automaticamente” antes do autosave.
- **Reproduzindo:** linha ativa identificada; Parar permanece na mesma posição; conclusão volta a Ouvir. Não prometer pausa, seek, repetição ou loop.
- **Som bloqueado:** mute/volume zero aparece perto da reprodução com ação explícita de restaurar som; preservar o valor salvo até a ação do usuário. Não restaurar mute silenciosamente.
- **Interrompido/erro:** mensagem perto do transporte com ação pertinente; gravações válidas permanecem acessíveis. Não afirmar “gravado” após falha de finalização.

“Ouvir gravação” pode manter a escolha de monitoring, mas deve mostrar “Escuta ao vivo ligada” quando houver mistura. Para o teste isolado de playback, desligar monitoring. Com microfone interno e saída interna, não ligar monitoring automaticamente: solicitar escolha contextual de fones ou continuidade com volume baixo. O modo measurement não fornece, por si só, um contrato de cancelamento de realimentação.

## Organização da informação

**Principal:** transporte, estado humano, sessão atual, última faixa e saída efetiva. Identificar alto-falante versus receptor usando `portType`; o nome de dispositivo sozinho pode ser ambíguo. Antes da ativação, mostrar saída ainda não confirmada, sem inventar uma rota.

**Entrada e saída:** seleção de entrada, volume de escuta, volume/mute de gravação e rota. Explicar que a entrada só muda com motor parado; descobrir entradas no início do fluxo sem exigir que o usuário memorize iniciar/parar/iniciar. Como mudança de rota pode finalizar captura no código atual, não oferecer troca sem feedback durante gravação.

**Timbre:** perfil, ganho de entrada/saída, EQ e efeitos. Reutilizar o controller e o modelo existentes; SwiftUI continua sem conhecer a topologia de AVAudioEngine.

**Diagnóstico:** taxa e buffer reais, canais/formato, medidores, rota técnica, erro e atualização. Medidores atuais são anteriores ao volume/mute; manter essa explicação aqui. Um único indicador de entrada na principal só ajuda se disser claramente “sinal de entrada”, sem sugerir saída audível.

## Investigação do relato: microfone interno → alto-falante interno

### Comprovado por inspeção

1. `SystemAudioSessionBackend.configureForMeasurement()` configura `.playAndRecord`, modo `.measurement`, `options: []`. Não há `defaultToSpeaker`, `overrideOutputAudioPort`, consulta de `outputVolume` do sistema ou política específica para playback. O mesmo motor/sessão é usado para captura e reprodução.
2. A Apple documenta que `defaultToSpeaker` muda a rota padrão de receiver para speaker quando não há acessório; portanto **a saída pelo receptor é uma hipótese prioritária**, não a causa comprovada do relato. [Apple QA1754](https://developer.apple.com/library/archive/qa/qa1754/_index.html). Um override temporário pode mudar também a entrada e é resetado por mudanças de rota/interrupções; não o aplicar indiscriminadamente a interfaces/fones.
3. Playback abre AVAudioFile, rejeita arquivo sem frames/formato inválido, reconecta player e mixer com `file.processingFormat`, agenda uma reprodução com `.dataPlayedBack` e chama `play()`. Completion usa geração para não parar uma nova reprodução por callback antigo. Não existe loop.
4. Playback mixer usa `muted ? 0 : volume`; a configuração persiste por sessão e é reaplicada ao reconstruir o grafo. Ganho de saída global pode atenuar até −96 dB. Medidor de playback antes desses controles pode indicar sinal mesmo sem saída útil.
5. Captura sai de `processedInstrument`, antes do mute/volume de monitoring. Sink salva CAF e rejeita zero frames; **não rejeita buffers cheios de zeros ou sinal extremamente baixo**. Duração e registro na lista não comprovam conteúdo audível.
6. `playRecording` inicia o motor se parado, inclusive pedindo permissão de microfone. Isso pode impedir ouvir um arquivo quando microfone está negado, porque a arquitetura atual acopla playback ao motor com entrada.
7. Mudança de rota que reconstrói o motor finaliza gravação e para playback; background/interrupção também encerram mídia. A UI precisa representar essa transição sem levar o usuário a acreditar que a faixa continua.

### O que ainda não foi observado

Não há neste trabalho o arquivo da gravação relatada, sua amplitude/RMS, a rota real durante Play, volume físico, configuração salva da sessão ou confirmação auditiva. Não é possível concluir se o arquivo está silencioso, se tocou no receptor ou se estava silenciado. O simulador não reproduz a topologia física do iPhone.

O modo measurement prioriza medição e reduz processamento do sistema; manter ou trocar esse modo requer comparação de captura/latência no equipamento. [Documentação Apple](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement). Não declarar que `.defaultToSpeaker` sozinho resolve a combinação no aparelho alvo.

### Experimento físico para fechar a causa

| Etapa | Evidência necessária | Interpretação |
|---|---|---|
| Baseline | iPhone/modelo/iOS/build; sem USB/fones/Bluetooth; monitoring off; playback unmuted/100%; ganho saída 0 dB; volume sistema audível | Elimina configuração conhecida sem alterar arquivo |
| Reproduzir a faixa relatada | Estado playing, mensagem de erro, currentRoute outputs com `portType`, outputVolume do sistema | builtInReceiver confirma rota inadequada à expectativa; playing sozinho não confirma som |
| Analisar o CAF preservado | frames, formato, peak/RMS por canal e trecho reconhecível, sem sobrescrever | Zero/quase zero aponta para captura; sinal significativo exige investigar saída |
| Referência conhecida | CAF de sinal audível conhecido pelo mesmo player, monitoring off | Se referência também falha, foco em saída/grafo/mix; não na captura original |
| Comparar rota | Mesma faixa/configuração em receptor, speaker e fones; anotar entrada efetiva após cada mudança | Audição só em fones/speaker com PCM válido sustenta hipótese de roteamento |
| Candidato de correção | Testar playAndRecord + measurement + defaultToSpeaker, verificar rota efetiva; se necessário comparar modo default/estratégia específica de playback | Escolher mudança com evidência, mantendo captura e interfaces funcionais |
| Recuperação | Desconectar fones/USB; interrupção; voltar do background; reabrir sessão | Não regressar para receptor inesperado, mute invisível ou UI stale |

Registrar resultados antes/depois e uma conclusão por variável. Um arquivo gerado em teste não substitui a faixa relatada. Não coletar/exportar áudio pessoal sem necessidade; análise local pode bastar. Sem aparelho desbloqueado e observação auditiva, essa matriz permanece pendente.

## Critérios de revisão e implementação posterior

1. No tamanho de iPhone da referência, gravar/finalizar/ouvir última faixa não exige scroll; alvos de toque de pelo menos 44 pt e Dynamic Type sem esconder transporte.
2. Separar comandos de captura, playback e encerramento; ação e erro atualizam no lugar.
3. Gravações da sessão corrente em dois toques; abrir outra sessão apresenta as faixas diretamente.
4. Autosave só declara sucesso confirmado; falha oferece retry sem perder o CAF.
5. Rota e silêncio por mute/volume são visíveis durante playback; avançado a no máximo dois toques.
6. Antes de próximas features V0.1, validar microfone interno → speaker e interface → fones com som físico, reabertura e troca de rota.

Esta exploração não implementa transporte compartilhado, looper, importação, exportação ou busca global. Loop segue F9.1/V0.2. As futuras alterações podem reutilizar AppShellView, SessionModel, LibraryView, AudioControlActor e os repositórios; manter `UI → Feature Model → Audio API → Graph` conforme o acordo de arquitetura.

## Validação desta exploração

Skill usada: [ios-feature-validation](../../../.agents/skills/ios-feature-validation/SKILL.md). XcodeBuildMCP disponível. Uma execução completa do scheme BassPractice está registrada em VALIDACAO.md. Nenhum teste novo para documentação/protótipo; testes existentes verificam CAF, rendering offline, mixer, lifecycle e persistência.

Protótipo: conferido no navegador local pelo fluxo Gravar → Finalizar → Ouvir; transições são de apresentação. Não são taps da app iOS. Capturas do guia foram examinadas como referência visual, sem promover evidência antiga a validação física.
