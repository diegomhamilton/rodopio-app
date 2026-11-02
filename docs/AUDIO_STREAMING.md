# Rodopio 0.5.0 — transmissão PCM experimental

## Primeiro teste físico

Use dois iPhones na mesma rede, com esta versão instalada. Conecte fones com fio/USB nos dois. Crie uma sala no primeiro e entre no segundo. Não é necessário iniciar a composição. Ative a entrada no aparelho transmissor, escolha o canal conectado ao instrumento e confira seu nível local. Ligue **Transmitir áudio real**. Confira se o timbre original aparece no receptor, se o medidor remoto acompanha os ataques e se Silenciar/Volume alteram somente essa faixa. Grave versão, iPhone/iOS, interface, rota, taxa e resultado.

Transmissão é desligada por padrão. O receptor não precisa conceder permissão de microfone ou ativar entrada. Para transmitir nos dois sentidos, cada pessoa ativa sua própria entrada e transmissão. O áudio recebido e o mix de saída nunca são enviados de volta. **Sair da sala**, interrupção de áudio ou encerramento da captura desligam o envio. Ao trocar entrada/canal, encerre a composição conforme o fluxo existente e confira novamente a entrada ativa.

O primeiro marco atende o par anfitrião/participante. O transporte MC existente forma uma estrela: cada participante ouve os peers diretamente conectados; não há retransmissão do áudio de um convidado aos outros convidados. A sala de quatro pessoas ainda não implica mix de áudio completo entre quatro pessoas.

## Caminho implementado

- O tap da entrada copia somente o canal escolhido para um ring SPSC C com capacidade de 16.384 amostras. Não serializa, aloca ou envia pela rede no callback de áudio.
- Uma fila dedicada drena a cada 5 ms e cria pacotes de até 480 amostras, descartando captura que já tem 60 ms. PCM mono signed Int16 LE na taxa original da entrada. A 48 kHz, cada pacote cheio cobre 10 ms; a entrega real depende do tap/iOS.
- Cabeçalho CRPA, versão 1, taxa UInt32 BE, sequência UInt64 BE, timestamp monotônico Double/UInt64 BE, UUID de captura (16 bytes), seguido do PCM. Tamanho máximo 1001 bytes. O receptor valida versão, tamanho e taxa antes de alocar buffers de reprodução.
- A ponte para a fila principal mantém no máximo 12 pacotes pendentes e revalida idade inferior a 60 ms antes de enviar. UI ocupada descarta som antigo em vez de criar backlog.
- MultipeerConnectivity usa `.unreliable` para PCM e mantém `.reliable` para eventos. Áudio perdido não é retransmitido.
- Um player por peer pré-carrega 20 ms e limita sua fila reportada a 60 ms. Estourar o limite descarta a fila e retoma a partir de áudio novo. Mudança do UUID/taxa substitui o player. Ausência de pacotes por 250 ms limpa a fila e zera o medidor.
- O mix principal conserva o headroom existente de 0,4; o volume remoto é adicional. O medidor exibe o pico PCM recebido, antes de mute/volume.

Não há codec/compressão, PLC, preenchimento de lacunas com silêncio, compensação de deriva ou sincronização acústica entre aparelhos. Pacotes fora de ordem são descartados. Perdas podem produzir cortes; as filas são deliberadamente curtas. Bluetooth e rotas com latência alta podem exceder o limite e não são o alvo deste teste. A gravação da saída do app inclui o áudio remoto renderizado, mas nunca é a fonte da transmissão.

## Medição honesta

O painel mostra pacotes recebidos, lacunas de sequência, pacotes atrasados/duplicados ou estouros da fila, jitter suavizado (variação da diferença chegada/captura) e duração agendada. Lacunas podem refletir perda/reordenação; não contam amostras descartadas antes do envio pelo ring. Esses números não são latência ponta a ponta. Os relógios de captura remotos não são subtraídos diretamente do relógio local para anunciar atraso.

Para medir latência acústica, capture externamente, na mesma gravação, um pulso do sinal de origem e a saída do receptor. Use ligação elétrica segura/loopback com dois canais ou microfone externo capturando ambos. Meça a diferença entre ataques para pelo menos 30 pulsos. Registre mediana/p95, falhas e configuração. Repita com os mesmos aparelhos, rota, intensidade e rede para cada backend; não compare uma rota Bluetooth com outra USB. RTT de rede é outra grandeza.

## Verificação automatizada

`bash scripts/test_core.sh` inclui teste concorrente producer/consumer do ring e contabilização do overflow. `AudioStreamingTests` cobre PCM/metadata roundtrip, descarte de captura antiga após bloqueio da UI, datagramas inválidos/limite e canal selecionado/timestamp/overflow/desativação. Testes sintéticos não demonstram captura ou escuta física em dois iPhones.
