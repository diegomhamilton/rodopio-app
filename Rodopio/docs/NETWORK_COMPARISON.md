# Comparação de transporte — etapa experimental

O primeiro teste do usuário continua sendo o áudio PCM sobre MultipeerConnectivity. `NetworkLANTransport.swift` é selecionado pela fachada `NearbyTransport`, preservando o mesmo caminho PCM. O seletor e os snapshots foram integrados ao painel de transmissão. O modo inicial continua Multipeer; ambos os aparelhos precisam escolher o mesmo backend antes de hospedar/entrar. A seleção só muda no modo solo, fora da composição e da troca de entrada. O diagnóstico exporta os snapshots em JSON.

## Contrato

O backend espelha `NearbyTransport`: `host`, `join`, `stop`, `send(WireMessage,to:)`, `sendAudio(Data)`, callbacks `onMessage`, `onAudio`, `onPeers`, `onError`, propriedades `peers` e `hostPeer`. Usa `MCPeerID` somente para compatibilidade com a identidade do aplicativo; não cria `MCSession`. `onMetrics` recebe snapshots por participante uma vez por segundo.

Descoberta Bonjour `_ciranda-sixteen._udp` com `NWBrowser`/`NWListener`, seguida de `NWConnection` UDP. O plist existente já declara esse serviço. O modo usa a rede Wi-Fi de infraestrutura (`includePeerToPeer = false`). Isso permite controlar a rede da comparação e evita confundir uma troca de caminho AWDL com mudança do protocolo.

Áudio CRPA recebe um envelope de nove bytes (tipo + sequência UInt64 big endian). Payload limitado a 1.200 bytes; pacotes PCM atuais de até 1.001 bytes ficam abaixo desse limite. Não há retransmissão de áudio. No máximo quatro envios de áudio por conexão podem estar pendentes; excedentes são descartados. Controles JSON têm ACK, janela de 128 mensagens, entrega ordenada e até 20 tentativas em intervalos de pelo menos 150 ms. Falta de confirmação encerra o link e exibe erro. O protótipo não implementa remontagem de datagramas: controles JSON grandes podem sofrer fragmentação IP.

**Diferença de segurança:** o backend UDP é experimental, sem autenticação e sem criptografia. MultipeerConnectivity existente exige criptografia. Usar UDP somente em LAN confiável com conteúdo de teste; não apresentar os dois como equivalentes em privacidade. O hello identifica pares por UUID aleatório de execução, com sufixo no nome para distinguir iPhones de nomes iguais.

## O que medir

`TransportMetricAccumulator` pode ser usado nos dois backends. Os dois backends usam o mesmo acumulador e probes ping/pong a cada 500 ms quando não há probe pendente (timeout de 2 s):

- RTT mediana e p95 dos últimos 120 pings respondidos; ping/pong usa o relógio monotônico de um só aparelho.
- Variação média absoluta entre RTTs consecutivos. Essa é variação de RTT, não jitter de reprodução nem jitter de ida isolada.
- Pacotes de áudio recebidos, bytes recebidos, duplicados, fora de ordem e lacunas de sequência. Lacunas são provisórias e diminuem quando chega um pacote atrasado dentro da janela de 4.096 sequências. Não inclui perdas anteriores ao primeiro pacote recebido nem depois do último.
- Retransmissões de controles.

RTT inclui as filas/callbacks do aplicativo (delegate MC entregue na main e callback Network na fila serial de rede), portanto compara o caminho implementado, não apenas o protocolo isolado. **RTT/2 não é medição de latência de áudio de ponta a ponta**, e relógios monotônicos de dois aparelhos não podem ser subtraídos sem estimar offset. Pings não respondidos não entram na distribuição de RTT; acompanhar desconexões e lacunas juntamente com a distribuição evita selecionar somente respostas boas.

## Protocolo de ensaio nos dois iPhones

1. Escolher o backend nos dois aparelhos, mantendo a mesma captura, packetização, buffer e reprodução PCM. Desconectar a sessão antes de mudar o transporte.
2. Registrar versão/build, modelos, iOS, roteador/AP, distância, faixa Wi-Fi, rota USB/fone, taxa de amostra efetiva, tamanho do pacote, alvo do buffer e volume.
3. Rodar 60 s de aquecimento e três ensaios de 120 s por backend, alternando a ordem MC/Network e o aparelho que hospeda. Não mudar a rota de áudio entre ensaios.
4. Exportar os snapshots por participante em JSON/CSV e o número de desconexões. Comparar p50/p95 RTT, variação de RTT, lacunas/recebidos, bytes/s e retries. Registrar também CPU/energia no Instruments quando disponível.
5. Para latência física, enviar impulsos de uma fonte comum à entrada local e a um canal de referência de um gravador externo. Gravar a saída do iPhone remoto no outro canal. Medir distância entre ataques e repetir pelo menos 30 vezes por configuração. O resultado inclui captura, empacotamento, rede, buffer e reprodução.
6. Repetir com tráfego concorrente na LAN e interrupções breves. Áudio antigo deve ser descartado, sem crescimento ilimitado da fila.

Não há resultado de benchmark entre aparelhos ainda, nem evidência de ganho percentual do Network. Typecheck iOS e teste sintético das métricas verificam código/contagem, sem validar descoberta Bonjour, transporte físico ou latência acústica.

## Fontes primárias

- [Apple — Moving from Multipeer Connectivity to Network framework](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework)
- [Apple — NWBrowser](https://developer.apple.com/documentation/network/nwbrowser)
- [Apple — NWListener](https://developer.apple.com/documentation/network/nwlistener)
- [Apple — receiveMessage](https://developer.apple.com/documentation/network/nwconnection/receivemessage(completion:))
