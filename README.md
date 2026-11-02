# Rodopio · protótipo musical iOS 0.5.0 (build 10)

Esta raiz contém o projeto Rodopio. O app anterior de prática e gravação foi preservado em [`legacy/BassPractice/`](legacy/BassPractice/), incluindo fontes, projeto Xcode, testes, documentação e configuração de desenvolvimento.

Um laboratório para construir música em conjunto. Cada gesto oferece uma nota a um compasso futuro; o tempo musical continua sem esperar a rede.

## Teste prioritário: som real entre dois iPhones

O painel **Áudio real entre aparelhos** envia PCM mono da entrada selecionada, preservando o timbre. É independente dos eventos de nota e não requer iniciar composição. Passos e limitações: [docs/AUDIO_STREAMING.md](docs/AUDIO_STREAMING.md).

1. Instale esta versão nos dois aparelhos, conecte-os à mesma rede e use fones com fio ou interface USB em ambos.
2. Deixe **Multipeer** selecionado nos dois para o primeiro teste. No primeiro, **Criar sala**; no segundo, **Entrar perto**. Aguarde aparecer a conexão.
3. No aparelho com o instrumento, **Ativar entrada de áudio**, escolha a entrada/canal e confira o medidor local.
4. Ligue **Transmitir áudio real**. O outro aparelho começa a reproduzir; use o medidor remoto, volume e Silenciar para conferir o caminho.
5. Para o sentido inverso, ative entrada/transmissão também no segundo aparelho. Desligar a transmissão deixa de enviar o som local; **Sair da sala** encerra os caminhos de áudio.

Os targets, scheme e bundle identifier continuam com o nome técnico Ciranda para preservar a instalação. O nome exibido é Rodopio. Esta etapa não comprova latência física: o teste acústico em dois iPhones continua necessário.

## Correção USB — 0.2.1

A versão anterior verificava a rota imediatamente após `setPreferredInput`, podendo rejeitar uma troca ainda em andamento. Agora o app espera pela rota e pelo formato estáveis, com prazo de 3 segundos, e separa entrada solicitada de entrada efetiva. A seleção usa uma lista com botões explícitos; a própria troca não dispara um encerramento indevido da sessão.

Para aplicar a correção, abra este projeto atualizado no Xcode e instale novamente no iPhone. O rodapé mostra **PROTÓTIPO 0.5.0**. O arquivo ZIP não atualiza automaticamente uma instalação anterior.

1. Encerre a composição, caso esteja tocando.
2. Em **Baixo ao vivo**, ative a entrada; depois abra **Escolher entrada**.
3. Toque **USB-Audio**. Confira **Entrada ativa no iOS: USB-Audio** e o movimento do medidor ao tocar o baixo.
4. Se a interface tiver vários canais, selecione o canal conectado ao instrumento.
5. Se a troca falhar, a mensagem fica no painel da entrada. **Laboratório → Preparar diagnóstico → Compartilhar diagnóstico** inclui `INPUT_SELECT`, `ROUTE request`, `confirmed` ou `failed`.

A gravação enviada mostra USB-Audio disponível e como saída, com iPhone Microphone ainda selecionado. Isso confirma reconhecimento do dispositivo, mas não prova qual ponto da troca falhou. O defeito de validação prematura foi encontrado no código; a correção ainda requer confirmação com a interface física.

## Abrir e executar

1. Extraia o ZIP num Mac com Xcode (SDK iOS 17 ou posterior).
2. Abra **Ciranda.xcodeproj**. Não requer CocoaPods, XcodeGen nem pacotes externos.
3. Selecione o scheme **Ciranda** e um simulador iPhone. Execute com ⌘R.
4. Para instalar num iPhone: em **Signing & Capabilities**, selecione sua equipe Apple e um Bundle Identifier disponível. Conecte o iPhone, habilite o modo de desenvolvedor quando solicitado e execute.
5. Para executar testes e capturar a primeira tela no simulador: `bash scripts/build_and_test_ios.sh`.

**Estado de validação atual:** build e XCTest executados no Mac com Xcode 26.6/iOS Simulator 26.5. O build final passou em 22 testes Swift e na regressão C, incluindo ring concorrente. Áudio físico entre dois iPhones e latência acústica seguem pendentes. Resultado final e histórico em `docs/VALIDATION.md`.

## Baixo / entrada de áudio ao vivo (0.2)

1. Conecte o baixo a uma interface que o iOS reconheça como entrada de áudio USB (por exemplo, a interface do seu setup de baixo, quando compatível). Conecte os fones à saída da interface.
2. No painel **Baixo ao vivo**, toque **Ativar entrada de áudio** e conceda a permissão do iOS. A permissão de microfone também é necessária para capturar pela interface USB.
3. USB tem preferência inicial; para trocar, toque em **Escolher entrada** e depois em **USB-Audio**. Aguarde até 3 segundos e confira **Entrada ativa no iOS: USB-Audio**. A saída USB, sozinha, não confirma que a entrada também é USB. Em interfaces multicanal, selecione o **canal analisado** que recebe o baixo.
4. Toque e observe o medidor em dBFS, indicação de clipping, frequência e nota reconhecida.
5. Ative **Ouvir o baixo** para monitoração pelo app. O som percorre o grafo de áudio nativo; não espera pelo detector de notas nem pela rede. A monitoração começa desligada e é permitida apenas com saída com fio/USB/line-out. Se usar direct monitoring da interface, mantenha a monitoração do app desligada para evitar ouvir o sinal duas vezes.
6. Para jogar, ative **Usar notas do baixo na composição**, inicie a sessão e mantenha **Compor juntos** selecionado. Toque uma nota por vez. O evento reconhecido entra num compasso futuro.

O baixo pode ser monitorado localmente com seu timbre original. A composição troca eventos de nota; **Transmitir áudio real** envia separadamente PCM da entrada. Os eventos são transpostos para Dó4–Si4: Mi1 → Mi4, Lá1 → Lá4. A etiqueta do detector mostra a nota real antes da transposição. O teclado virtual continua com Dó4–Dó5.

A detecção é experimental e monofônica, com janela de aproximadamente 85,3 ms em 48/96 kHz e 69,7 ms em 44,1 kHz. O filtro visual confirma a nota inicial em 40 ms e mudanças em 80 ms. Ela acrescenta atraso à identificação, não ao caminho de monitoração. O timestamp da análise representa o centro da janela capturada; não serve ainda para avaliar precisão rítmica do ataque. Notas sustentadas produzem um evento; silêncio rearma a mesma nota. Repetições sem silêncio, acordes, ruído e timbres muito distorcidos podem ser interpretados incorretamente.

O canal selecionado afeta medição/detecção. A monitoração reproduz os canais da interface (mixados para até dois canais); não oferece roteamento individual por canal nesta versão. O volume do app é monitoração, não ganho físico do pré-amplificador.

Para mudar a entrada/canal, encerre a composição. Desconectar hardware, interromper áudio ou ir para segundo plano desativa a captura. É necessário reativar explicitamente; não se mantém um microfone alternativo capturando silenciosamente. Há gravação diagnóstica persistente, limitada a 120 s, e transmissão opcional do PCM aos aparelhos conectados; não há serviço de áudio na internet.

O projeto anterior do app de baixo foi consultado como referência arquitetural (AVAudioEngine, playAndRecord, USB, mudanças de rota). Nenhum código-fonte anterior foi localizado nas fontes disponíveis, portanto esta implementação não é apresentada como cópia de um módulo já validado.

## Usar sozinho

- **Explorar sons:** toque nas teclas para ouvir imediatamente. Dó4–Dó5: oito naturais e cinco sustenidos (13 alturas cromáticas).
- **Começar em 3 segundos:** inicia uma sessão em 4/4 no andamento selecionado (60–160 BPM).
- **Compor juntos:** cada toque registra uma contribuição. O ritmo do gesto determina uma posição de semicolcheia; a chegada da mensagem determina o primeiro compasso ainda aberto.
- A pauta local preserva até 32 compassos com gestos; a reprodução coletiva do compasso atual aparece separadamente. É uma visualização inicial: não é um editor completo de partituras (vozes, colisões, acidentes válidos por compasso, pausas e agrupamentos ainda precisam de desenvolvimento).
- Não há E♯ ou B♯ como teclas adicionais: nesta oitava equivalem enarmonicamente a Fá e Dó. O teclado cromático padrão tem cinco teclas pretas.
- As notas têm envelope curto, não sustentação por pressão. O teclado é de toques; controle multitoque contínuo de acordes é uma evolução.

## Usar em dois iPhones

1. Instale o app nos dois. Mantenha Wi-Fi ligado, mesma rede local e ambos em primeiro plano.
2. A: **Criar sala**. B: **Entrar perto**. Autorize o acesso à rede local.
3. B entra automaticamente na primeira sala anunciada e estima seu relógio com oito amostras. Aguarde **Relógio pronto**.
4. A inicia. Ambos recebem a mesma referência musical e os mesmos compassos confirmados.
5. Toque em **Compor juntos** nos dois. Em **Laboratório**, altere o atraso de contribuição para 0, 500, 1500 e 3000 ms. As notas mudam de compasso de destino; o metrônomo continua.
6. Compartilhe os diagnósticos dos dois e compare os hashes `BAR` para os mesmos índices.

A sala aceita até quatro participantes incluindo o anfitrião. A descoberta usa MultipeerConnectivity com criptografia exigida. Este protótipo aceita convites de proximidade automaticamente: use uma única sala de teste por ambiente; seleção de sala e confirmação de participantes devem preceder um piloto com crianças. Não há contas, anúncios nem coleta remota de dados.

## Limites desta versão

- **Rede local/proximidade implementada no código; internet ainda não implementada.** MultipeerConnectivity não é o transporte multiplataforma final.
- **SwiftUI é a interface executável do app. Godot ainda não está embutido.** `Godot/` contém um estudo 3D separado com 13 plataformas e entrada por toque/clique. Leia `docs/GODOT.md` para o contrato de conexão.
- O app encerra sua participação ao ir para segundo plano. O anfitrião saindo encerra a sessão. Não há migração de anfitrião nem execução em segundo plano.
- Troca de saída e interrupção de áudio exigem reinício da sessão e reativação da captura. Bluetooth e latência física ainda não validados.
- Notas chegam a compassos futuros; isto não é transmissão de áudio ao vivo nem jam remota de latência zero.
- Atraso artificial afeta apenas ações. Perda de pacotes, atraso de commits e reconexão precisam dos testes descritos em `docs/VALIDATION.md`.
- Não existe garantia de conteúdo novo idêntico durante uma partição da rede: o metrônomo local continua, e compassos que chegam tarde são ignorados.

## Estrutura

- `App/Models.swift`: protocolo, notas, autoridade, IDs e hash dos compassos.
- `App/LiveInput.swift` e `Core/LiveInputCore.c`: entrada, análise monofônica e mailbox SPSC sem bloqueio no tap.
- `Core/TimingCore.c`: cálculo do relógio, prazo de fechamento e quantização, acessado por bridging header.
- `App/MusicEngine.swift`: AVAudioEngine, timbres sintéticos próprios e agendamento em host time.
- `App/NearbyTransport.swift`: salas próximas.
- `App/SessionModel.swift`: coordenação, confirmação, repetição idempotente, diagnósticos.
- `App/ContentView.swift`: teclado, pauta, controles e laboratório.
- `Tests/`: testes C executáveis em Linux/Mac e XCTest para Xcode.
- `Godot/`: estudo visual 3D independente, sem plugin nativo compilado.
- `scripts/make_project.py`: regenera o Xcode project se acrescentar arquivos fonte.

## Parâmetros iniciais

4/4; passos visuais de aproximadamente 60 Hz; áudio sintetizado em 48 kHz (o hardware pode negociar outra taxa); buffer solicitado de 256 amostras; fechamento 500 ms antes do compasso; metrônomo programado com 200 ms de antecedência. Nenhum desses valores é uma medição de desempenho no iPhone.

O áudio roda em fila própria. O timer da interface não é um relógio de áudio nem uma garantia de física determinística a 60 Hz. Ao integrar movimento/física no Godot, usar passo fixo e derivar os visuais da posição musical.

## Próximas entregas

- [ ] Compilar no Xcode, resolver avisos/erros encontrados e executar XCTest.
- [ ] Medir cliques de dois dispositivos na mesma gravação.
- [ ] Seleção explícita de sala/participantes.
- [ ] Ponte Godot iOS compilada, cena 3D conectada e simulação fixa.
- [ ] Movimento corporal/toque gestual e avaliação pedagógica de ritmo.
- [ ] Transporte online e servidor dedicado, mantendo o protocolo musical.
- [ ] Partitura completa, vozes/instrumentos e missões cooperativas.


## Versão 0.3.0

Grade/playback de 16 semicolcheias por compasso. Todas as pessoas precisam instalar esta versão para encontrar a mesma sala. Pauta horizontal com bandeirolas duplas.

A nota exibida exige confiança de 90%, confirma a primeira nota por 40 ms e mudanças por 80 ms. Mantém a nota durante falhas de até 350 ms, tolera oscilação de afinação e atualiza a interface no máximo 10 vezes/s. Esse filtro não interfere nos eventos do jogo. O detector de baixo continua experimental: a janela de análise e a articulação limitam passagens rápidas; a grade em semicolcheias não garante transcrição de cada ataque nessa velocidade.

Ative a entrada e toque em Gravar áudio. Dois WAVs mono capturam a entrada selecionada e a saída do app (canal 1), com origem temporal comum. Limite de 120 segundos; mudar/desativar a rota finaliza a gravação. Visualização em janelas de 1, 4 ou 8 segundos, ao vivo ou com navegação manual; picos agregados a cada 20 ms. Para inspeção em resolução de amostras, use os WAVs.

Exportar WAVs + timestamps compartilha os WAVs e sincronizacao.json, com BPM, marcadores, relógio, taxas de amostragem, lacunas, perdas de buffer e indicação de timestamps estimados. Arquivos ficam em Documents/Gravacoes no app e não são enviados aos participantes. Exporte antes de iniciar outra gravação para manter acesso pelo botão.

A saída é áudio renderizado, não medição acústica. Marcadores são referências agendadas; para medir latência física, use captura externa/loopback. Lacunas são preenchidas com silêncio e declaradas no JSON.

Validação: testes C de temporização, análise, concorrência, transição USB, captura e estabilização passaram; estrutura do projeto Xcode validada. Compilação Swift e gravação real ainda precisam de Mac/iPhone.

Teste no aparelho: sustente Mi grave, abafe por mais de 350 ms, alterne Mi/Lá. Grave junto ao metrônomo, pare, exporte os três arquivos e confira as pistas em uma DAW e os timestamps/lacunas no JSON.


## 0.4.0 — análise do baixo para semicolcheias

No Mac, extraia o ZIP e execute `bash /caminho/para/Ciranda/Instalar-no-Mac.command` no Terminal. O script cria `~/Documents/Personal/Ciranda`, copia o projeto e abre o Xcode. Se já existir um projeto nesse destino, cria uma pasta com data/hora sem sobrescrevê-lo. A criação no Mac não foi executada pelo ambiente remoto.

O analisador usa 1024 amostras após decimação: 85,3 ms a 48/96 kHz, 69,7 ms a 44,1 kHz. FFT de 2048 pontos com zero padding calcula autocorrelação linear; energias acumuladas produzem diferenças normalizadas de periodicidade e interpolação parabólica estima frequência. Zero padding não cria resolução física adicional. Não escolhemos simplesmente o pico espectral mais alto, que pode ser um harmônico. A leitura é solicitada a cada 10 ms, limitada pelos buffers efetivamente entregues pelo iOS. Não há alocação/FFT no callback de captura.

A grade de entrada acumula votos ponderados por confiança em cada intervalo de 125 ms, usando o centro temporal da janela capturada. Leituras ambíguas ficam sem nota; a apresentação principal mantém seu filtro visual. Contribuições detectadas usam esse timestamp em vez do horário de atualização da UI. A grade exibe estimativas provisórias com atraso; não conhece a nota no instante inicial do ataque. Notas sustentadas aparecem em múltiplas posições, mas o filtro de contribuição continua enviando mudanças de nota (ou reataques após silêncio).

Escopo monofônico: distingue notas sucessivas, incluindo semitons graves. Não separa duas cordas simultâneas nem garante detecção de todos os reataques da mesma nota sem silêncio. Timbres distorcidos, ruído, vazamento e ataques reais ainda precisam de validação. Não há evidência de áudio real do instrumento incluída no conjunto de testes.

Teste reproduzível: `bash scripts/test_core.sh`. O teste sixteenth_input_tests.c usa 144 segmentos de 125 ms a 120 BPM, taxas 44,1/48/96 kHz, Si0, semitons adjacentes, três distribuições de harmônicos (inclusive fundamental ausente), ruído e DC. Verifica identificação dentro de cada segmento e a nota vencedora na posição atribuída pelo timestamp. Pior tempo para primeira estimativa correta: 90 ms nessa simulação; não é latência medida no iPhone. Testes C anteriores e validação estrutural do Xcode passam. Swift/Xcode e custo de CPU no aparelho continuam pendentes.

Referência do método de periodicidade: https://librosa.org/doc/main/api/generated/librosa.yin.html . Para limites de estimadores de baixa latência: https://www.dafx14.fau.de/papers/dafx14_olivier_derrien_a_very_low_latency_pitch_.pdf .


## 0.4.1 — registro visual progressivo

Corrigido: a pauta usava somente eventos do compasso coletivo atual, apagava ao parar e inventava uma nota de exemplo quando vazia. A detecção do baixo só atualizava o teclado quando a contribuição estava ligada.

Agora O que você tocou registra os gestos locais de teclado e baixo em até 32 compassos com notas, em rolagem horizontal. Acompanhar novos compassos segue a pauta mais recente; desligue para consultar anteriores. Parar ou iniciar outro trecho preserva as pautas anteriores; Limpar apaga explicitamente. O histórico é em memória e não persiste ao encerrar o processo. Compassos totalmente silenciosos não ganham uma pauta. Notas no pré-roll da composição não entram no histórico quantizado.

O baixo atualiza o teclado e o histórico independentemente de Usar notas do baixo na composição. Essa opção controla somente o envio musical. A pauta representa gestos detectados, transpostos ao teclado Dó4–Dó5; não transcreve duração, ligaduras ou reataques sem silêncio. A reprodução coletiva e suas confirmações continuam separadas em uma seção própria. Repetições da mesma nota dentro da mesma posição são consolidadas.

Validação: testes C de regressão e estrutura do projeto passaram. Adicionados ScoreHistoryTests.swift para preservação entre compassos/trechos, slots, duplicação, limite e entradas inválidas. Esses testes Swift ainda não foram executados: ambiente sem Xcode/SDK iOS. No iPhone, ative o baixo com contribuição desligada, toque Mi/Lá e observe teclado/pauta; atravesse dois compassos, pare, confira histórico, navegue de volta e teste Limpar.


## 0.4.2 — exportação assíncrona

Exportar WAVs + timestamps agora inicia uma Task. Verificação/cópia dos arquivos acontece em Task.detached, fora da thread principal e do áudio; o botão exibe Preparando exportação e bloqueia múltiplos cliques. A folha nativa recebe URLs de cópias temporárias prontas e metadados leves sem geração própria de previews. A mesma gravação reutiliza suas cópias. Os WAVs originais não são alterados. A tela mostra erros e permite tentar novamente. Cópias de exportação ficam no diretório temporário do app.

A criação/apresentação do UIActivityViewController permanece na thread principal, como exigido pelo UIKit. Essa mudança retira o I/O de preparação da UI; o tempo interno da folha do iOS não foi medido. Testar gravação de 120 s, exportar, conferir spinner e ausência de reentrância, cancelar, tentar novamente e salvar os três arquivos no app Arquivos. Confirmar que áudio/metrônomo continuam.

RecordingExportTests.swift cobre cópias idênticas, cache e arquivo ausente. Testes Swift e interface ainda não executados por falta de Xcode/SDK iOS. Projeto estruturalmente validado; testes C de regressão passaram na etapa anterior de pauta.

### Build 9 — entradas Bluetooth

Captura agora habilita entradas Bluetooth HFP (`allowBluetoothHFP`), preservando a preferência USB e a confirmação assíncrona da rota real. A seleção identifica portas Bluetooth e os diagnósticos incluem tipos/portas disponíveis. Dispositivos só de saída A2DP e acessórios BLE MIDI não viram entradas PCM. Ver [notas Bluetooth](docs/BLUETOOTH_AUDIO.md). Validação física ainda pendente.

### Build 10 — ícone nativo em camadas

`App/Rodopio.icon` substitui o PNG como fonte principal. Fitas e traços sonoros são SVGs independentes, com material/iluminação nativos. Ver [documentação do ícone](docs/LOGO.md). Build10 inclui a correção HFP da build9; instalada e aberta no Diego Phone (iPhone Air, iOS26.6.1). Captura Bluetooth e transmissão física entre aparelhos ainda exigem teste.
