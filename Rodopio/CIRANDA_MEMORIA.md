# Ciranda — memória e guia de continuidade

Atualizado em **02/11/2026, America/Recife**. Estado de código: **0.5.0 build 10; build 10 instalada** (Rodopio). Este arquivo é um handoff; não significa memória automática instalada nem configuração de agentes aplicada.

## 1. Retomada atual — Rodopio 0.5.0, build 8

Nome escolhido pelo usuário nesta sessão: **Rodopio**. Workspace ativo: `/Users/dmh/Documents/ChatGPT/music-app`, copiado de `~/Downloads/Ciranda 5` quando o workspace estava vazio. Originais preservados. Bundle ID `org.ciranda.prototype`, scheme/projeto Ciranda mantidos para continuidade de instalação. Sem commit/PR criado.

Pedido vigente: testar primeiro **áudio real da entrada selecionada no outro iPhone**, sem depender de interpretação de notas nem de iniciar composição. Implementados PCM16 mono, captura com ring SPSC limitado, envio sem retransmissão, reprodução por participante com mute/volume/nível e fila limitada. MultipeerConnectivity é padrão. Network.framework UDP disponível como alternativa LAN, com métricas comparáveis e seleção antes de criar/entrar na sala; ambos devem escolher o mesmo modo. UDP experimental não tem autenticação/criptografia. Ver `docs/NETWORK_COMPARISON.md` e README atual.

Braço de baixo vertical implementado com alternância Baixo/Teclado, quatro cordas E1 A1 D2 G2, 12/24 casas e todas as posições possíveis da nota original estabilizada. Áudio monofônico não identifica corda/casa.

Ícone atual: `App/Rodopio.icon`, composição nativa com seis faces vetoriais azul/roxo e quatro traços sonoros separados, material/iluminação aplicados pelo renderizador Apple. Reconstrução vetorial do conceito, não idêntica ao raster. `ictool` aceitou o pacote e build iOS genérica sem assinatura passou. Aberto no Icon Composer por `open`; automação CUA não respondeu. Fonte selecionada no projeto: Rodopio. Script `scripts/make_icon_layers.py` recria composição (sobrescreve edições manuais). PNGs conceituais e catálogo legado preservados. Prévia `assets/branding/rodopio-native-preview.png`; detalhes `docs/LOGO.md`. Build10 inclui HFP da9 e ícone nativo, instalada e aberta no Diego Phone; devicectl confirmou versão0.5.0/build10.

**Evidência:** Xcode 26.6 e simuladores disponíveis no Mac. Build integrado (áudio PCM, Network/MC, braço e ícone) passou 22 XCTest/0 falhas no simulador iPhone17Pro iOS26.5; testes C existentes e ring novo passaram. Build físico assinado passou; Rodopio 0.5.0 build8 instalado e aberto no Diego Phone (iPhone Air, iOS26.6.1), confirmado por devicectl. CFBundleDisplayName e CFBundleName são Rodopio. Equipe de assinatura usada FS5N5ZG4WY por override local; generator não fixa equipe. Não há medição física de latência, benchmark real MC versus Network nem confirmação de áudio entre dois aparelhos ainda. Não chamar RTT/2 de latência acústica.

A memória abaixo inclui histórico 0.4.2; estado atual desta seção prevalece sobre descrições antigas de streaming ausente ou Xcode indisponível. Próximo passo imediato: testar no Diego Phone captura → recepção real com dois aparelhos/fones; registrar rota, taxa, falhas e resultado. Depois ensaios alternados dos dois transportes.

## 2. Estado técnico e decisões que não devem se perder

| Área | Implementação / limite |
|---|---|
| Tempo musical | 4/4, 16 semicolcheias; a 120 BPM: 125 ms por posição e 2 s por compasso. Áudio agendado em relógio monotônico, independente da atualização visual de aproximadamente 60 Hz. |
| Cooperação | Ações entram em compassos futuros ainda abertos; atraso da rede não pausa o metrônomo. Conteúdo novo idêntico não é garantido durante partição da rede. |
| Transporte | MultipeerConnectivity, proximidade/rede local, eventos de notas; não transmite PCM/timbre real. Sem internet ou servidor implementado. |
| USB | Espera assíncrona pela rota efetiva e formato estável, até 3 s. Separa entrada solicitada de ativa; selecionar USB não pode ser interpretado como desconexão. Preservar essa correção. |
| Baixo | Detector monofônico. 1024 amostras após decimação; ~85,3 ms em 48/96 kHz, ~69,7 ms em 44,1 kHz. FFT 2048 com zero padding → autocorrelação → diferenças normalizadas → interpolação do período. Não é seleção do pico FFT mais alto. |
| Análise | Consulta a cada 10 ms, limitada pela entrega real dos buffers. Timestamp representa centro da janela capturada, não ataque físico medido. Votos por posição em grade de 16. |
| Nota exibida | Filtro visual separado: confiança 90%, confirmação inicial 40 ms/mudança 80 ms, retenção até 350 ms, publicação até 10 Hz. Não usar esse atraso para comandar o relógio musical. |
| Teclado | Dó4–Dó5, 8 naturais + 5 sustenidos. Baixo transposto por classe de altura; etiqueta de detecção mantém a oitava original. |
| Pauta 0.4.1 | Histórico local independente de ACK/reprodução coletiva; até 32 compassos com notas; preservado ao parar e entre trechos; Limpar explícito. Só em memória. Baixo atualiza pauta/teclado mesmo com contribuição desligada. |
| Notação | Posições de gestos; não transcreve duração, ligaduras, pausas completas, polifonia nem reataques sem silêncio. Compassos vazios e pré-roll não são registrados. |
| Gravação | Até 120 s; WAV mono de entrada selecionada + WAV mono de saída do app canal 1 + JSON de sincronização. Origem temporal comum; picos de waveform a cada 20 ms. Saída renderizada não é captura acústica. |
| Exportação 0.4.2 | Task.detached prepara cópias temporárias; loading, bloqueio de reentrância e erro visível; folha UIKit recebe URLs/metadados leves. Sua apresentação continua na thread principal. Congelamento reportado ainda exige reteste físico. |
| Ciclo de vida | Interrupções/rotas/segundo plano encerram captura/participação conforme fluxo atual. Sem host migration e sem captura alternativa silenciosa. |

144 segmentos sintéticos de semicolcheias passaram: três taxas, semitons graves, Si0, ruído/DC e distribuições de harmônicos incluindo fundamental ausente. Maior tempo para primeira identificação correta: 90 ms nesse conjunto. Não é garantia para qualquer baixo/timbre nem medida de latência iOS. ASan/UBSan passaram no teste sintético com detecção de vazamentos desativada; LeakSanitizer não funcionou no ambiente.

## 3. Mapa mínimo para localizar código

| Arquivos | Responsabilidade |
|---|---|
| `App/MusicEngine.swift`, `App/LiveInput.swift` | Grafo, taps, rota, análise e filtro de eventos do baixo |
| `Core/LiveInputCore.c`, `Core/NoteDisplay.c` | DSP, FFT, mailbox e estabilização visual |
| `Core/TimingCore.c`, `App/Models.swift` | Quantização, prazo, autoridade, protocolo, hashes |
| `App/SessionModel.swift` | Coordenação, estado observável, input, ACKs e histórico |
| `App/ScoreHistory.swift`, `App/ScoreHistoryView.swift`, `App/ContentView.swift` | Pauta progressiva, teclado, UI |
| `App/DebugRecorder.swift`, `Core/DebugCapture.c` | Escrita assíncrona de WAV e timestamps |
| `App/RecordingPanel.swift`, `App/RecordingExport.swift` | Waveform, loading e compartilhamento |
| `App/NearbyTransport.swift` | Transporte atual de eventos |
| `Tests/`, `scripts/` | C, XCTest, geração e verificação do projeto |

Comandos: `bash scripts/test_core.sh`; após novos fontes, `python3 scripts/make_project.py`; `python3 scripts/verify_project.py`. No Mac: `bash scripts/build_and_test_ios.sh`, revisar seu destino/simulador antes de executar. Preferência histórica do usuário: XcodeBuildMCP para build/test e screenshots em `docs/snapshots`; usar quando disponível, sem fingir que está instalado.

**Dívida documental encontrada:** o README mistura descrição antiga de janela 170–186 ms, ausência de gravação e pauta apenas do compasso atual com changelog novo. Essas descrições antigas não são o estado 0.4.2. Consolidar documentação numa próxima mudança; conferir código e testes antes de resolver divergências.

## 4. Fila de trabalho e critérios de aceite

1. **Validar o que já existe:** build/XCTest, input USB, nota estável, teclado com contribuição desligada, pauta atravessando dois compassos/parada, exportação de 120 s com spinner, cancelar/repetir/salvar os três arquivos. Registrar versão, aparelho, iOS, interface, sample rate, passos e resultado. Não chamar análise estática de build.
2. **Refinar detecção com áudio real:** guardar WAVs consentidos como fixtures e marcações esperadas; medir erros de oitava, confusão entre semitons, omissões, timestamps e CPU. Não ajustar limiares só para passar nos sinais sintéticos.
3. **Áudio por participante:** dois iPhones, mesma rede, mono; cada faixa com identidade, nível, waveform, mute e volume. Capturar somente input local, nunca retransmitir o mix recebido. Buffer limitado por participante, timestamps, perdas/atraso visíveis. Escolher explicitamente escuta com atraso curto ou reprodução em compasso futuro; não prometer simultaneidade física perfeita. Medir com captura externa/loopback.
4. **Depois:** partitura persistente/exportável, notação de duração, Godot integrado, gameplay/movimentos e transporte online.

Não iniciar toda a fila em uma única tarefa. Streaming foi discutido e adiado para corrigir os defeitos de base; confirmar a prioridade vigente pelo último pedido do usuário.

## 5. Padrões observados e fluxo adaptado

- O usuário dá instruções curtas enquanto testa hardware. Tratar novas mensagens como ajustes/fila da tarefa ativa. Respeitar ordens explícitas como “continue esta antes daquela”.
- Prefere implementação concreta e autonomia, sem sucessivos pedidos de confirmação. Perguntar só quando falta uma escolha que muda escopo ou bloqueia execução.
- Relatos como “pisca”, “fraca” e “congela” devem virar comportamento reproduzível e critério verificável: frequência de atualização, janela/erro, tempo bloqueado e feedback ao toque.
- Observabilidade vem junto da feature: rota efetiva, timestamps, waveform, logs e indicador de carregamento. Não esconder incerteza com nota fictícia ou estado de sucesso prematuro.
- Comunicação em português, breve: causa → mudança → evidência → limitação. Não anunciar correção física sem reteste.
- Novo bug: reproduzir/inspecionar → isolar causa → corrigir pouco → teste relevante → build nativo quando acessível → feedback do aparelho → atualizar memória. Evitar várias versões não compiladas acumuladas.
- Uma tarefa/branch por objetivo e patch revisável; PR descreve comportamento final e validação. Não criar PR/commit nem presumir repositório remoto quando inexistente. Prompts de tarefa em `docs/prompts/` quando necessários.
- Ao encerrar, atualizar apenas estado, decisão, evidência, risco e próximo passo; manter a retomada curta. Documento de processo é proposta operacional, não instalação de skill nem autorização para disparar agentes recorrentes.

## 6. Modelos por função — proposta econômica

Papéis abaixo podem ser desempenhados sequencialmente pelo mesmo agente. **Padrão: um implementador; revisão independente apenas em mudança de risco.** Não abrir todos os agentes para cada bug. Seleção depende da disponibilidade real da sessão. As recomendações por tarefa são julgamento para este projeto, não benchmark de Swift/DSP.

| Papel | Modelo sugerido | Esforço inicial | Escopo e escalonamento |
|---|---|---|---|
| Triagem/documentação | `gpt-6-luna` | low | Resumir evidências fornecidas, changelog, checklist; não diagnosticar sozinho sincronização/concorrência |
| Implementador de UI/fluxos delimitados | `gpt-6.1-terra` | medium | Alterações locais e reproduzíveis; migrar a Sol se falha persistir após uma tentativa fundamentada ou atravessar áudio/rede |
| Integrador / implementação complexa | `gpt-6.1-sol` | medium | Swift/C, estado entre filas, build e integração de transporte |
| Especialista DSP / revisor crítico | `gpt-6.1-sol` | high | Janela/FFT, timestamp, thread de áudio, ownership e buffers; receber só contratos, diff e evidências |
| Escalação excepcional | `gpt-6-astra` | high | Ambiguidade técnica não resolvida após experimento/reprodução; pedido pequeno, não o histórico inteiro |
| Runner de testes | Scripts/XcodeBuildMCP; Luna para resumir | low | Compilação deve ser feita pela ferramenta; LLM não substitui resultado do teste |

Standard como preferência de custo, quando selecionável. Não foi alterado modelo/modo desta sessão. Não inferir preço de execução a partir de nomes internos ou de modelos listados por ferramentas. Não foi delegada tarefa a subagentes para produzir este documento.

Economia de contexto: enviar a cada especialista objetivo, arquivos pertinentes, invariantes, reprodução, aceite e orçamento; evitar fork do histórico completo. Reusar testes já aprovados até uma mudança justificar repetição. Buscar trechos com `rg`, evitar imprimir arquivos enormes. Orçamento inicial proposto por tarefa delimitada: 8–15 mil tokens de entrada e 2–5 mil de saída; revisão 4–8 mil/1–2 mil. São metas de planejamento por interação, não limites garantidos de uma execução com múltiplas ferramentas.

## 7. Preço da sessão de hoje: o que é e não é calculável

**Custo efetivamente cobrado em 02/11/2026: indeterminado.** Não há telemetria completa de tokens, modelo por chamada, cache, raciocínio, modo de velocidade, créditos nem cobrança. A conversa teve continuidades/resumos; contar apenas o texto final ou o código não recupera os tokens faturados. Não atribuir um número de dólares como conta real do ChatGPT.

Assinatura/uso incluído e API são formas distintas de cobrança. Sem o painel de uso, não é possível dizer quanto esta sessão consumiu da franquia nem se usou créditos adicionais. Se só usou franquia incluída, não há uma cobrança API por esta conversa; isso não demonstra consumo zero de franquia.

Referência pública consultada em 02/11/2026: **USD por 1 milhão de tokens, API Standard/contexto curto**, não Fast/Ultrafast ou preço da assinatura [1].

| Modelo | Entrada normal | Entrada em cache | Saída |
|---|---:|---:|---:|
| GPT-6 Luna | 0,10 | 0,01 | 0,50 |
| GPT-6.1 Terra | 1,00 | 0,05 | 5,00 |
| GPT-6.1 Sol | 2,00 | 0,10 | 10,00 |
| GPT-6 Astra | 10,00 | 1,00 | 50,00 |

**Simulação de orçamento para reproduzir uma sessão longa como esta via API.** Volumes abaixo são hipóteses de sensibilidade, não estimativas medidas da sessão. Entrada é soma de todas as chamadas, incluindo contexto reenviado; saída deve incluir raciocínio faturável quando aplicável.

| Hipótese de volume agregado | Tudo Terra | Tudo Sol | Tudo Astra |
|---|---:|---:|---:|
| 500 mil entrada + 50 mil saída | US$ 0,75 | US$ 1,50 | US$ 7,50 |
| 1,5 milhão entrada + 100 mil saída | US$ 2,00 | US$ 4,00 | US$ 20,00 |
| 3 milhões entrada + 200 mil saída | US$ 4,00 | US$ 8,00 | US$ 40,00 |

Contas sem cache, escritas de cache, ferramentas, impostos, infraestrutura ou sobretaxas de contexto/velocidade. Não há base para escolher qual linha descreve hoje. **US$ 4,00 é somente o cenário central hipotético em Sol, não o valor gasto.** Não converter para reais com câmbio inventado.

Exemplo separado de roteamento, com trabalho fixo de 1 milhão de tokens de entrada e 100 mil de saída: 200k/15k Luna + 600k/60k Terra + 200k/25k Sol = **US$ 1,5775**, contra US$ 3,00 tudo Sol, cerca de 47,4% menor. É aritmética mantendo volumes iguais, não promessa: delegação, retrabalho e revisão podem anular a economia.

Fórmula para auditar quando houver dados:

`USD = soma((entrada_nao_cache × tarifa_entrada + entrada_cache × tarifa_cache + saida_faturavel × tarifa_saida) / 1_000_000) + demais_custos`

Não contar tokens em cache novamente como entrada normal. Incluir eventuais escritas de cache, ferramentas e modo real. Na próxima sessão, registrar por chamada: data, tarefa, modelo, modo, entrada total, entrada cache, saída, tarifa e custo; usar Usage API/dashboard para API ou painel de créditos/uso do produto para ChatGPT. Não presumir que um fornece a fatura do outro.

## 8. Prompt para a próxima sessão

> Leia primeiro a seção 1 de CIRANDA_MEMORIA.md e só aprofunde as seções relacionadas à tarefa. Localize a versão 0.4.2 ou a mais recente, preserve alterações locais e confira ambiente/ferramentas. Priorize compilar e validar pauta progressiva e exportação no iPhone antes de streaming. Trabalhe com um agente por padrão, seguindo a matriz econômica quando houver seleção de modelo. Não declare testes nativos ou validação física sem executá-los. Ao terminar, registre mudança, evidência, limitações e próximo passo neste arquivo. Pedido atual do usuário: [inserir objetivo].

## Fontes oficiais para modelos e preços

1. https://developers.openai.com/api/docs/pricing — tarifas API; consultada em 02/11/2026.
2. https://learn.chatgpt.com/docs/pricing — uso/assinatura/créditos e distinção de preços API; consultada em 02/11/2026.
3. https://developers.openai.com/api/docs/guides/latest-model — características das famílias; consultada em 02/11/2026. A alocação de papéis acima é recomendação específica deste documento.

Manutenção: preservar fatos confirmados, substituir estados superados e não acumular descrições contraditórias como se todas ainda fossem atuais.

## Investigação em andamento — entrada Bluetooth

Usuário pediu agente dedicado. Encontrada sessão playAndRecord com options vazias, que não habilita entradas Bluetooth HFP. Correção aplicada em fonte build9: allowBluetoothHFP, identificação de entradas Bluetooth e diagnóstico expandido; compilou com deployment iOS17 e passou 22 XCTest/0 falhas no simulador iPhone17Pro iOS26.5. USB/rota efetiva preservados. Ver docs/BLUETOOTH_AUDIO.md. Build8 permanece no iPhone enquanto usuário testa; não confundir teste no simulador com confirmação física HFP.

## Resultado build 10 — ícone nativo

Documento `.icon` validado com renderizador Icon Composer e `xcodebuild` para iOS genérico sem assinatura; build passou. Não repetidos XCTest pois mudança desta etapa é ícone/projeto e metadado de build; build9 passou22. Diego Phone atualizado para build10 nesta sessão.

Novo estudo do ícone em `assets/branding/Rodopio-fluid.icon` e prévia `rodopio-fluid-preview.png`: curvas fluidas e silhueta de pião com corpo superior largo/ponta. Renderizado com ictool; estudo separado, não instalado. Ver docs/LOGO.md.

Revisão visual mais recente: `assets/branding/Rodopio-fluid-v2.icon` (prévia `rodopio-fluid-v2-preview.png`), barriga arredondada e ponta dividida em faixa azul + vazio + triângulo roxo menor, conforme pedido. Validada no ictool; estudo ainda não instalado.
