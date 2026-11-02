# Rodopio — ícone nativo em camadas (build 10)

A imagem gerada anteriormente era um conceito raster com acabamento de vidro incorporado. Após leitura do artigo indicado pelo usuário, o desenho foi reconstruído em vetores separados e empacotado no formato `.icon` compatível com Icon Composer.

## Arquivo editável

`App/Rodopio.icon` contém `icon.json` e dez SVGs em `Assets/`: seis faces alternadas azul/roxo da fita, com separação física entre trechos, e quatro traços amarelos de vibração. O fundo é configurado na composição. Não há PNG achatado dentro desse documento. As formas são preenchimentos simples; o renderizador da Apple aplica iluminação, especular, sombra e translucidez.

A reconstrução vetorial é uma nova interpretação do conceito, não uma vetorização idêntica da imagem gerada. A prévia nativa está em `assets/branding/rodopio-native-preview.png`. Os conceitos raster v1/v2 e o catálogo legado continuam preservados, mas o app seleciona `Rodopio.icon` como fonte principal.

## Verificação e edição

O documento foi criado programaticamente e aceito pelo `ictool` incluído no Icon Composer e pelo compilador de ícones do Xcode. Não se afirma exportação pela interface gráfica: a automação da interface não respondeu nesta sessão. É possível abrir o pacote no Icon Composer e editar as camadas. O formato interno não é uma API pública; alterações de versão do Composer podem exigir atualização.

Geometria reproduzível: `python3 scripts/make_icon_layers.py`. Esse comando recria os SVGs e a composição; salvar ajustes manuais no Composer antes de executá-lo novamente, pois ele substitui os arquivos gerados.

Renderização nativa:

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" "$PWD/App/Rodopio.icon" --export-image --output-file "$PWD/assets/branding/rodopio-native-preview.png" --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

## Referências

- [Artigo indicado: transformar conceito de IA em composição](https://www.avanderlee.com/workflow/icon-composer-transforming-an-ai-generated-icon/)
- [Apple: criar o ícone com Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Referência empírica do formato e amostras reais](https://github.com/peterpoliwoda/icon-composer-template)

## Estudo fluido de pião — após instalação da build 10

Usuário apontou que a primeira geometria nativa perdeu a silhueta do pião. Nova alternativa em `assets/branding/Rodopio-fluid.icon`: curvas Bézier com ombros largos, três faixas afuniladas, coroa e ponta inferior. Sete formas da fita e quatro traços sonoros, todos SVGs independentes. Prévia nativa `assets/branding/rodopio-fluid-preview.png`; reprodução `python3 scripts/make_fluid_icon.py`. Validado pelo ictool. É estudo separado para revisão visual; ainda não substitui `App/Rodopio.icon` nem o ícone da build10 instalada.

## Estudo fluido v2

Pedido: dividir a antiga ponta azul em faixa azul + espaço vazio + triângulo roxo menor e suavizar a barriga, reduzindo o perfil triangular. Revisão em `assets/branding/Rodopio-fluid-v2.icon`, com oito formas da fita e quatro traços sonoros independentes. Curvas centrais e inferiores mais largas/arredondadas; ponta roxa separada. Prévia `assets/branding/rodopio-fluid-v2-preview.png`, renderizada/validada com ictool. O script `scripts/make_fluid_icon.py` agora gera v2, preservando o estudo anterior. Não instalado no iPhone; build10 mantida.

## Estudo fluido v3

Corpo central/inferior alargado para reduzir o contorno triangular, com barriga mais cheia e afunilamento concentrado na ponta roxa menor. `assets/branding/Rodopio-fluid-v3.icon`, prévia `rodopio-fluid-v3-preview.png`. Validado/renderizado no ictool. Versões anteriores preservadas; app instalado permanece build10. Script make_fluid_icon.py agora gera v3.

## Estudo fluido v4

Volta superior e coroa reduzidas em 10%; profundidade aparente das elipses ampliada em 18–20% e inclinação lateral de −8° para −10°, mantendo camadas separadas e ponta roxa. `assets/branding/Rodopio-fluid-v4.icon`, prévia `rodopio-fluid-v4-preview.png`, renderização ictool validada. Script make_fluid_icon.py gera v4. Não instalado; build10 permanece no iPhone.
