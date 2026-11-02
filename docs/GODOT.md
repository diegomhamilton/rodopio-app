# Integração Godot: estado e contrato

O app deste ZIP executa a prova musical em SwiftUI. A engine Godot NÃO está ligada ao target iOS. A cena `Godot/project.godot` é um estudo independente em Godot 4: câmera, luz, 13 plataformas, labels e seleção por raycast; clicar anima a plataforma e emite `note_requested(midi)`.

Para visualizar o estudo, importe `Godot/project.godot` no editor Godot 4 e execute. O estudo não toca áudio nem participa de salas; não mascara a ausência de integração com um som local diferente.

## Contrato a conectar

- Godot → Swift: `note_requested(midi)` deve chamar `SessionModel.play(midi)` na thread principal. O timestamp do gesto deve ser capturado no evento, não depois de trabalho pesado.
- Swift → Godot: posição musical (compasso, beat, fase) para animação; confirmação com ID/compasso; eventos de compasso para recursos compartilhados.
- O áudio permanece sob autoridade do `MusicEngine` nativo. Godot não deve disparar `AudioStreamPlayer.play()` a cada beat nem criar um segundo relógio de música.
- Passo da física Godot: 60 Hz inicialmente. A interpolação visual consulta o tempo da sessão; o horário de áudio nunca espera a física.

## Build futuro

Selecionar uma versão estável específica do Godot, gerar um plugin iOS com interface Objective-C++ e uma biblioteca Swift estática, conforme a documentação oficial. Compilar a `.a`/`.xcframework`, criar `.gdip`, exportar o projeto Godot para Xcode e ligar AVFoundation e MultipeerConnectivity. Não há binário vendorizado nem versão de engine falsamente fixada neste protótipo.

Fonte: https://docs.godotengine.org/en/stable/tutorials/platform/ios/ios_plugin.html

Validar primeiro uma única chamada Swift–Godot e o ciclo de vida do áudio; em seguida conectar os 13 pads e a sessão. A interface SwiftUI pode permanecer como laboratório nativo.
