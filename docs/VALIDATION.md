## Atualização 02/11/2026 — build 9, entrada Bluetooth

Correção opt-in HFP compilada no simulador iPhone 17 Pro/iOS 26.5: **22 XCTest, zero falhas**. Projeto regenerado e `verify_project.py` passou. Fonte em build 9; não instalada no Diego Phone durante a investigação para preservar o teste físico em andamento da build 8. Descoberta/captura Bluetooth real pendente. Detalhes e roteiro em [BLUETOOTH_AUDIO.md](BLUETOOTH_AUDIO.md).

# Validação

## Estado atual — 02/11/2026, Rodopio 0.5.0 build 8

Mac com Xcode 26.6 disponível. Build nativo e XCTest foram executados no iPhone 17 Pro simulado, iOS 26.5: build final com ícone, PCM, instrumento e os dois backends passou com 22 testes e zero falhas. O núcleo C, incluindo ring PCM concorrente, passou. A estrutura do projeto passou no verificador. Inclui roundtrip PCM/metadata, inválidos, ring, descarte de áudio antigo após UI ocupada e métricas/reinício de stream. Log local: `/tmp/rodopio-verified-tests.log`; xcresult em `build/DerivedData/Logs/Test/`.

Isso não valida captura USB física, áudio entre dois iPhones nem latência acústica. O teste prioritário está em [AUDIO_STREAMING.md](AUDIO_STREAMING.md); comparação instrumentada em [NETWORK_COMPARISON.md](NETWORK_COMPARISON.md). O nome exibido é Rodopio; projeto/scheme/bundle permanecem tecnicamente Ciranda.

As seções seguintes conservam o histórico anterior de geração em Linux e sua matriz de testes. Alegações sobre ferramentas ausentes referem-se àquele ambiente anterior.

## Histórico anterior — executado no ambiente Linux

- Núcleo C compilado com `cc -Wall -Wextra -Werror -std=c11`.
- Offset e RTT testados com uma troca simétrica conhecida.
- Prazos imediatamente antes, no instante e após fechamento.
- Quantização com wrap de compasso e tempo anterior ao início.
- 100.000 instantes: cada ação é atribuída a um compasso ainda aberto e ao primeiro disponível.
- Estrutura dos arquivos, plist e referências do projeto verificadas por script.

## Histórico anterior — não executado no ambiente Linux

Na etapa anterior não havia Xcode, Swift compiler, iOS SDK, simulador iOS ou Godot. Naquela etapa não foi declarado sucesso de compilação Swift, XCTest, teste de som, conexão física, FPS ou captura nativa.

## No Mac

Execute `bash scripts/test_core.sh` e `bash scripts/build_and_test_ios.sh`.
O segundo comando compila o app, executa XCTest, instala e abre no simulador, salva uma captura em `docs/snapshots/01-teclado.png` e imprime o caminho do xcresult. A primeira captura é uma inspeção da tela, não uma prova de sincronização.

XCTest cobre: ação duplicada, sessão incorreta, limite do prazo, compasso imutável, nota inválida, timestamp NaN/antigo, serialização/hash e repetição fora de ordem.

## Matriz em dois iPhones

| Cenário | Procedimento | Aprovação |
|---|---|---|
| Livre | Tocar as 13 teclas | 13 alturas crescentes, etiquetas e sustenidos corretos |
| Início | Esperar relógio pronto, iniciar pelo host | Mesma contagem, sem tocar antes da época combinada |
| Contribuição | Toques alternados nos dois aparelhos | Mesmo hash por compasso recebido no prazo |
| Atraso | 0/500/1500/3000 ms no controle | Sem pausa do metrônomo; nota atribuída a compasso aberto |
| Retransmissão | Atraso >1,5 s provoca retries | Uma contribuição por UUID, sem coleta duplicada |
| Mensagem tardia | Introduzir atraso de downlink via condicionador de rede | Incremento no contador de atrasos, sem rajada de notas antigas |
| Perda | Perfis de 1% e 5% de perda | Continuidade da base; recuperação quando snapshots chegam |
| Desconexão | Desligar rede ou sair da sala | Mensagem explícita; retorno requer entrar/sincronizar |
| Segundo plano | Minimizar anfitrião | Sessão encerrada; sem pressupor host ativo no fundo |
| Rota de áudio | Conectar/remover fone durante sessão | Sessão interrompida e reinício explícito |
| Longa duração | 30 minutos em primeiro plano | Registrar deriva, carga, atrasos e falhas |

Os perfis de perda/downlink NÃO estão implementados pelo slider: usar condicionador de rede externo/roteador de teste. Uma mudança de rede pode encerrar o MultipeerConnectivity.

## Medição acústica

Gravar cliques de dois dispositivos em canais separados da mesma interface, ou com geometria de microfones controlada. Medir a diferença dos onsets e informar mediana, p95 e máximo. Meta inicial: p95 <=10 ms em rede local controlada, sem Bluetooth; meta ainda não comprovada. Logs de `offset` não provam sincronização acústica.

Os buffers são agendados descontando `outputLatency + ioBufferDuration` como estimativa, não como calibração certificada. Rotas reais podem exigir outro ajuste. Não subtrair atrasos adicionais sem medir e evitar dupla compensação.

## Falha esperada

Uma rede sem prazo máximo não permite garantir novos dados idênticos e tempo de reprodução fixo simultaneamente. Ao perder um compasso, o cliente toca apenas o metrônomo compartilhado, registra a ocorrência e usa o próximo compasso que chegar com antecedência. O protótipo prioriza continuidade temporal.

## Demonstração na conversa

Uma demonstração separada usa Web Audio para explorar as 13 notas e experimentar ações atrasadas num único dispositivo. Seu JavaScript foi executado em Node com DOM e relógio de áudio simulados: altura de Dó♯, ação imediata, destino de ação atrasada, continuidade do metrônomo e limpeza ao parar passaram. Isso não é execução do aplicativo Swift.

Tentativa de teste de interface com Playwright não pôde iniciar: o ambiente tem a biblioteca, mas não tem Chromium instalado. Não foi feita alegação de teste visual em navegador ou audição real. A demonstração será executada no navegador do usuário ao interagir.


## Atualização 0.2 — entrada de baixo

Executado em Linux:
- Sinais sintéticos de Si0, Mi1, Lá1, Ré2, Sol2 e notas até Lá4, em 44,1/48/96 kHz: erro <20 cents nos casos de teste e MIDI correto.
- Fundamental de Mi1 com segundo harmônico de amplitude maior: fundamental identificada no sinal de teste.
- Silêncio, clipping, leitura de canal intercalado estéreo, overflow limitado e transposição de oitava.
- Produtor e consumidor em threads concorrentes: 2.560.000 amostras contabilizadas como consumidas ou descartadas, sem fila ilimitada. É um teste de estresse, não uma medida da taxa de perdas real no iPhone.
- AddressSanitizer e UndefinedBehaviorSanitizer passaram para os testes de áudio com `ASAN_OPTIONS=detect_leaks=0`. LeakSanitizer não pode inspecionar processos neste ambiente e não foi validado.
- Projeto e plist incluem os novos fontes e NSMicrophoneUsageDescription.

Novos XCTest (não executados neste ambiente): nota estável única, silêncio rearma nota, baixa confiança/baixo nível rejeitados e troca de nota.

Validação física pendente:
1. Permitir/negar permissão; verificar mensagem e teclado ainda funcional após negação.
2. Capturar baixo real por USB; conferir a rota exibida e canais 1/2, incluindo interface 44,1 kHz.
3. Medir ruído, clipping, fundamental, oitavas e notas distorcidas. Não generalizar acertos sintéticos para instrumentos reais.
4. Verificar monitoração desligada inicialmente, habilitada com fones/USB, bloqueada em alto-falante/receptor.
5. Verificar volume; conferir que direct monitoring + app não estejam duplicando o caminho.
6. Tocar teclado e metrônomo enquanto captura e monitora baixo; observar carga, estalos e descontinuidade.
7. Desconectar USB, interromper áudio e ir para segundo plano: captura desligada e sessão encerrada explicitamente.
8. Reativar e verificar ausência de taps duplicados; repetir ativar/desativar 20 vezes.
9. Dois iPhones: nota do baixo gera apenas um UUID por identificação estável, com hash de compasso igual.
10. Usar microfone com fones: impedir que som sintetizado do próprio aparelho vire uma nova contribuição por realimentação acústica.

Nenhum teste com microfone real, interface USB, simulador ou iPhone foi executado aqui. A demonstração anterior na conversa continua sendo teclado Web Audio; não está conectada à captura nativa.


## Correção 0.2.1 — seleção USB

Evidência: vídeo do usuário com `USB-Audio` disponível no menu e como saída, e `iPhone Microphone` selecionado como entrada. Não foi possível observar logs da instalação do usuário, portanto não se afirma reprodução conclusiva da causa no hardware.

Executado aqui:
- Testes do código C usado pela transição: seleção atrasada, formato atrasado, indisponibilidade transitória, desconexão, timeout e rota oscilante.
- Mesmos testes com UndefinedBehaviorSanitizer.
- Regressão dos testes de temporização, detector de baixo e ring concorrente.
- Parse/referências do Xcode project.

Pendente no Mac/iPhone:
- Compilar e executar o build 0.2.1 (3), incluindo XCTest.
- Abrir a lista durante atualização do medidor e selecionar USB-Audio; confirmar log INPUT_SELECT.
- Confirmar ROUTE request → confirmed e que a indicação de entrada acompanha o UID real, não apenas a saída.
- Atrasar confirmação de rota e testar até o limite de 3 segundos.
- Desconectar USB durante a espera; confirmar erro visível e ausência de captura residual.
- Cancelar uma tentativa saindo do app; confirmar que polls antigos não reiniciam o engine.
- Trocar microfone ↔ USB repetidamente, incluindo canais/taxas diferentes.
- Entrar como convidado durante configuração da entrada; o snapshot seguinte deve iniciar playback só depois da configuração.

Não foram executados Xcode, simulador ou interface USB neste ambiente. Os testes de política de transição não validam os drivers nem o comportamento de AVAudioSession no aparelho.
