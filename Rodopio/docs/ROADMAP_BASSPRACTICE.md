# Rodopio × BassPractice — inventário e mapa de roadmap

Data do levantamento: 2026-11-02. Este documento é um mapa de produto; não incorpora código nem altera o roadmap aprovado de Rodopio.

## Projetos separados no workspace

- **Rodopio** — app colaborativo de criação musical em tempo real. Checkout local `music-app`; este é o produto principal.
- **BassPractice** — app de prática e gravação individual de baixo/guitarra. Checkout local `ios-bass-app`; o remoto indicado `diegomhamilton/rodopio-app` tem a branch padrão `develop` e contém este produto/histórico.

Os dois continuam independentes. Rodopio é o produto principal e prevalece em decisões de integração. Qualquer reutilização futura deve ser avaliada por feature e adaptada ao domínio colaborativo de Rodopio.

## Rodopio atual — features presentes no checkout

### Composição colaborativa

- Salas locais: criar sala e entrar em sala próxima; até quatro participantes.
- Relógio musical sincronizado, andamento ajustável, compasso 4/4 e grade de 16 semicolcheias.
- Contribuições de notas agendadas para compassos futuros; o relógio local não espera a rede.
- Teclado e visualização em pauta; reprodução coletiva do compasso atual.
- Histórico local de notas por compasso, com opção de acompanhar e limpar.
- Entrada de baixo opcional para analisar notas e contribuir para a composição; detector monofônico experimental.

### Áudio e instrumentos

- Seleção de entrada/canal iOS, monitoramento local, volume e medidor.
- Transmissão bidirecional de PCM mono entre aparelhos, independente da composição, com MultipeerConnectivity e transporte Network UDP experimental.
- Controles de volume/silêncio por faixa remota e métricas de pacotes, lacunas, descartes, jitter e fila.
- Gravação local de entrada e saída, visualização temporal e exportação de WAVs mais timestamps/diagnóstico.
- Instrumentos visuais e saída sintetizada, além de análise ao vivo do baixo.

### Diagnóstico e limitações conhecidas

- Painel de laboratório com atraso artificial de contribuições, RTT, diferença estimada de relógio, compassos atrasados e exportação de logs.
- Latência acústica entre iPhones ainda precisa de medição física; Network UDP é experimental e sem criptografia/autenticação.
- O README do checkout chama esta versão de protótipo 0.5.0; isso é uma identificação interna, não declaração de release validado.

## Inventário de features do BassPractice

Com base no README, plano de releases, backlog e módulos Swift do checkout local:

- **Prática simplificada:** abas Practice e Recordings, ações para gravar/parar/repetir loop e fluxo dedicado de sessão.
- **Áudio em tempo real:** gerenciamento de sessão/rota, seleção de entrada, monitoramento e processamento de ganho e EQ paramétrico; controles de rota/ganho e diagnósticos de formato.
- **Perfis e timbre:** perfis Bass/Guitar/Custom, presets de efeito, presets de tom e editor de cadeia de efeitos.
- **Gravação e reprodução:** captura do sinal processado, reprodução, mixer separado para instrumento e playback, medidores, exportação/compartilhamento e recuperação de áudio após interrupção/rota.
- **Biblioteca de sessões:** criar, nomear/renomear, salvar automaticamente, restaurar e excluir sessões com gravações persistentes.
- **Backing tracks:** importação e reprodução planejadas no plano (V0.4); os módulos atuais e a UI inspecionada não mostram essa capacidade. Tratar como planejada, não entregue.
- **Looper:** repetição de takes confirmada em fluxo básico; o plano ainda marca múltiplas pistas, overdub, alinhamento, persistência dedicada e UI como pendentes/parciais. O README diz que o release completo não está concluído.
- **Metrônomo e prática guiada:** BPM, compasso, acentos, count-in e modos de prática planejados, ainda não confirmados como entrega implementada no README.
- **Confiabilidade e diagnósticos:** recuperação de erros de áudio e instrumentação de desempenho estão no plano; exportação de gravação é funcionalidade implementada/documentada.
- **Edição avançada de loops:** histórico de revisões, ferramentas de edição e sincronização avançada constam no backlog.

## Mapa para o roadmap do Rodopio

| Capacidade de BassPractice | Valor possível para Rodopio | Recomendação inicial |
|---|---|---|
| Seleção de entrada, rota e recuperação de áudio | Reduz falhas para músicos em salas | **Alta prioridade**; comparar com LiveInput/MusicEngine e portar só lacunas verificadas |
| Medição e diagnóstico de gravação de entrada/saída | Ajuda a reproduzir problemas de latência e sincronização | **Alta prioridade**; integrar evidências ao laboratório existente, preservando timestamps e ressalvas acústicas |
| Perfis de instrumento e ganho/EQ | Personaliza o timbre de cada participante | **Candidata**; avaliar controles por pessoa e impacto no áudio transmitido, sem impor presets individuais como padrão global |
| Cadeia de efeitos e presets | Dá expressão ao tocar em grupo | **Candidata posterior**; primeiro definir se efeitos são locais, transmitidos ou ambos |
| Mixer e medidores por faixa | Melhora equilíbrio entre participantes | **Alta prioridade**; Rodopio já tem volume/silêncio remoto; ampliar após feedback de sessão real |
| Gravação, reprodução e exportação | Permite registrar e compartilhar a composição coletiva | **Candidata de roadmap**; definir mix final, trilhas separadas, consentimento e sincronização antes de implementar |
| Backing tracks importadas | Praticar/criar sobre uma base comum | **Candidata de roadmap**; requer relógio compartilhado e política de transporte de mídia |
| Metrônomo/count-in/modos de prática | Facilita ensaio e entrada conjunta | **Candidata**; reaproveitar conceitos, mas acoplar ao relógio de sala e à grade Rodopio |
| Looper multi-track/overdub/alinhamento | Criação colaborativa por camadas | **Exploração de produto**; projetar semântica colaborativa, dono da faixa e sincronização antes de portar implementação solo |
| Biblioteca de sessões locais | Retomar composições/sessões | **Candidata**; modelar sala, participantes e assets primeiro; não copiar o domínio de sessão individual |
| Interface simplificada de Practice | Reduz atrito durante performance | **Referência de UX** para rever os fluxos de entrada, sala e transmissão de Rodopio |

## Ordem sugerida para avaliação

1. Concluir validação física e instrumentação de áudio de Rodopio.
2. Fechar lacunas de seleção/recuperação de rota e controles por participante.
3. Definir gravação/exportação de uma sessão coletiva e política de consentimento.
4. Avaliar backing tracks e metrônomo sincronizados à sala.
5. Explorar perfis/efeitos e gravação em camadas conforme feedback dos testes.
6. Só então decidir se o looper colaborativo pertence ao produto e especificar seu modelo de autoria/sincronização.

O mapa é uma proposta para discussão. Nenhum item acima foi movido para um release ou assumido como compromisso de implementação.

## Proveniência e limite da comparação

O remoto `diegomhamilton/rodopio-app` foi consultado via conector GitHub na branch padrão `develop` (2 nov. 2026). O README remoto descreve o app nativo de prática individual BassPractice e o plano V0.1–V0.5; a branch `develop` termina no baseline consolidado de 11 out. 2026. Não há `App/ContentView.swift` nessa branch e a busca de branches não encontrou uma linha do Rodopio colaborativo. O README remoto de `main` também descreve BassPractice. Assim, esse repositório ainda não é a fonte do código do Rodopio colaborativo; não foi feito merge nem alteração remota.

A lista de Rodopio atual neste documento foi extraída do checkout local `music-app`, cuja origem remota ainda não está configurada neste workspace e que contém arquivos não commitados. O mapeamento de features de BassPractice foi conferido contra a branch remota `develop` e o checkout local; o README e plano remoto confirmam Practice/Recordings, fluxo básico de loop validado, áudio, perfis, releases e backlog. Capacidades do plano continuam identificadas como planejadas/parciais, não como entregues.
