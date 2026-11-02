# Entradas de áudio Bluetooth — Rodopio 0.5.0 build 9

## Causa encontrada no código

A captura configurava `AVAudioSession` como `playAndRecord`, modo `measurement`, com `options: []`. Bluetooth HFP é opt-in nessa categoria: sem `allowBluetoothHFP`, microfones HFP pareados não são disponibilizados como entradas. Não era uma falha na interpretação da nota nem no envio PCM.

A correção habilita `allowBluetoothHFP` antes de ativar a sessão e consultar `availableInputs`. No SDK atual, esse nome tem disponibilidade iOS 1.0 e usa o mesmo bit da opção anteriormente chamada `allowBluetooth`; é compatível com o deployment iOS 17 do projeto. Mantidos modo `measurement`, preferência inicial por USB, seleção explícita por UID, espera de rota/formato estável e indicação da entrada realmente ativa.

A seleção marca as portas Bluetooth reportadas pelo iOS. O diagnóstico de rota passa a registrar categoria, modo, opções, portas disponíveis e tipos de entrada/saída, permitindo distinguir um acessório não exposto pelo sistema de uma seleção não confirmada. Não há descoberta Bluetooth própria no app.

## O que pode aparecer como entrada

- **Fone com microfone HFP:** pode ser entrada depois de conectado nos Ajustes, autorizada a captura e ativada a sessão no app. O iOS decide as rotas efetivas; a seleção de microfone HFP pode também alterar a saída. A taxa de amostra preferida de 48 kHz não é uma garantia: o app usa o formato efetivo.
- **Dispositivo A2DP apenas:** oferece saída Bluetooth, não uma entrada de microfone. `allowBluetoothA2DP` habilita saída e não resolve captura. Não foi adicionado como correção de entrada.
- **Interface anunciada como Bluetooth:** só poderá fornecer PCM se o iOS a expuser como porta de áudio de entrada compatível. Alguns acessórios usam Bluetooth apenas para controle ou MIDI; nesses casos, o instrumento precisa chegar por USB/áudio ou por uma API específica do fabricante.
- **BLE MIDI:** transporta eventos musicais, não o som/timbre PCM. O app não implementa CoreMIDI; habilitar HFP não transforma MIDI em áudio.

O app lista `availableInputs` reais, sem inventar um acessório ausente nessa lista. A etiqueta Bluetooth LE só aparece se o próprio iOS reportar uma porta de áudio LE disponível; não indica suporte genérico a qualquer dispositivo BLE.

## Qualidade e atraso

HFP pode mudar qualidade, taxa e latência. Não prometer desempenho equivalente a interface USB/fone com fio. `bluetoothHighQualityRecording` (iOS 26) exige modo `default`, depende do acessório e a Apple alerta que pode elevar latência; não foi habilitado nesta correção, preservando o caminho `measurement` existente. Monitoramento local Bluetooth continua bloqueado pela política atual de monitoramento: habilitar captura Bluetooth não habilita automaticamente “Ouvir o baixo”. O áudio remoto continua usando a rota de saída efetiva do sistema.

## Teste físico pendente

1. Pare a composição. Conecte nos Ajustes do iOS um fone com microfone HFP conhecido.
2. No app, ative a entrada; abra “Escolher entrada”, atualize e selecione o fone.
3. Confirme o nome em “Entrada ativa no iOS”, a saída e a taxa efetiva no diagnóstico. Fale perto do microfone do fone mantendo o iPhone afastado; observe o nível e grave para confirmar a origem.
4. Transmita áudio real a um segundo aparelho; o receptor deve ouvir o microfone do fone. Registrar modelo do acessório, iOS, rota, taxa, quedas e atraso observado, sem chamar RTT/2 de latência física.
5. Repita com USB, escolha USB explicitamente e confirme que a rota estável continua funcionando. Desconecte/reconecte Bluetooth; captura deve parar se a rota mudar e pedir reativação, sem indicar entrada fictícia.
6. Um acessório A2DP-only/MIDI-only não deve ser apresentado como entrada PCM. Para uma interface específica ausente, coletar modelo e o diagnóstico `available=` antes de afirmar incompatibilidade.

## Fontes primárias

- [Apple — allowBluetoothHFP](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetoothhfp)
- [Apple — availableInputs](https://developer.apple.com/documentation/avfaudio/avaudiosession/availableinputs)
- [Apple — allowBluetoothA2DP](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetootha2dp)
- [Apple — Enhance your app’s audio recording capabilities, WWDC25](https://developer.apple.com/videos/play/wwdc2025/251/)
- Headers oficiais do SDK iOS 26.5 local: `AVAudioSessionTypes.h` (HFP, measurement e high-quality recording).

Validação: projeto regenerado/verificado; build + 22 XCTest passaram no simulador iPhone 17 Pro iOS 26.5, zero falhas. Resultado: `build/DerivedData/Logs/Test/Test-Ciranda-2026.11.02_04-05-53--0300.xcresult`; log `/tmp/rodopio-bluetooth-tests.log`. O simulador valida compilação/regressão, não descoberta ou captura Bluetooth física. Build 9 fonte não foi instalado no Diego Phone durante esta investigação; o aparelho permanecia na build 8 para teste do usuário.
