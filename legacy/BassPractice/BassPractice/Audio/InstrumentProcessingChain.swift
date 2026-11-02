import AVFoundation

/// A future processor supplies its node without changing downstream recording or mixer code.
protocol NativeInstrumentProcessor: AnyObject {
    var audioNode: AVAudioNode { get }
}

/// Owned by the serialized audio backend; processors retain their explicit signal order.
final class InstrumentProcessingChain {
    let processors: [any NativeInstrumentProcessor]

    init(processors: [any NativeInstrumentProcessor]) { self.processors = processors }

    func attach(to engine: AVAudioEngine) {
        for processor in processors { engine.attach(processor.audioNode) }
    }

    func detach(from engine: AVAudioEngine) {
        for processor in processors where processor.audioNode.engine != nil {
            engine.disconnectNodeInput(processor.audioNode)
            engine.disconnectNodeOutput(processor.audioNode)
            engine.detach(processor.audioNode)
        }
    }

    func connect(in engine: AVAudioEngine, input: AVAudioNode, output: AVAudioNode, format: AVAudioFormat) {
        var previous = input
        for processor in processors {
            engine.connect(previous, to: processor.audioNode, format: format)
            previous = processor.audioNode
        }
        engine.connect(previous, to: output, format: format)
    }
}
