import AVFoundation
import Foundation
import Testing
@testable import BassPractice

@Suite("Native gain amplitude", .serialized)
struct NativeGainProcessorTests {
    @Test("Offline audio renders the expected gain and independent bypass", arguments: Fixtures.scenarios)
    fileprivate func renderedAmplitude(scenario: Fixtures.Scenario) throws {
        // Arrange
        let unity = try Fixtures.render(input: .unity, output: .unity)

        // Act
        let actual = try Fixtures.render(input: scenario.input, output: scenario.output)

        // Assert
        #expect(unity > 0.01)
        #expect(abs(actual / unity - scenario.ratio) < 0.002)
    }
}

private enum Fixtures {
    struct Scenario: Sendable {
        let input: GainConfiguration
        let output: GainConfiguration
        let ratio: Double
    }
    static let scenarios = [
        Scenario(input: .unity, output: .unity, ratio: 1),
        Scenario(input: GainConfiguration(decibels: -6, bypassed: false), output: .unity, ratio: pow(10, -6.0 / 20)),
        Scenario(input: .unity, output: GainConfiguration(decibels: -6, bypassed: false), ratio: pow(10, -6.0 / 20)),
        Scenario(input: GainConfiguration(decibels: -6, bypassed: false), output: GainConfiguration(decibels: -6, bypassed: false), ratio: pow(10, -12.0 / 20)),
        Scenario(input: GainConfiguration(decibels: -6, bypassed: true), output: GainConfiguration(decibels: -6, bypassed: false), ratio: pow(10, -6.0 / 20)),
        Scenario(input: GainConfiguration(decibels: -6, bypassed: false), output: GainConfiguration(decibels: -6, bypassed: true), ratio: pow(10, -6.0 / 20)),
        Scenario(input: GainConfiguration(decibels: -6, bypassed: true), output: GainConfiguration(decibels: -6, bypassed: true), ratio: 1)
    ]

    static func render(input: GainConfiguration, output: GainConfiguration) throws -> Double {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let inputProcessor = NativeGainProcessor(stage: .input)
        let outputProcessor = NativeGainProcessor(stage: .output)
        try inputProcessor.apply(input)
        try outputProcessor.apply(output)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        for node in [player, inputProcessor.node, outputProcessor.node] as [AVAudioNode] { engine.attach(node) }
        engine.connect(player, to: inputProcessor.node, format: format)
        engine.connect(inputProcessor.node, to: outputProcessor.node, format: format)
        engine.connect(outputProcessor.node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384))
        source.frameLength = source.frameCapacity
        let sourceSamples = try #require(source.floatChannelData?[0])
        for index in 0..<Int(source.frameLength) { sourceSamples[index] = 0.125 }
        player.scheduleBuffer(source)
        try engine.start()
        player.play()
        defer { engine.stop() }
        let rendered = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        var sum = 0.0
        var samples = 0
        for _ in 0..<64 {
            let status = try engine.renderOffline(1024, to: rendered)
            if status == .success {
                if engine.manualRenderingSampleTime > 4096 && engine.manualRenderingSampleTime <= 12_288 {
                    let values = try #require(rendered.floatChannelData?[0])
                    for index in 0..<Int(rendered.frameLength) { sum += Double(values[index]); samples += 1 }
                }
                if engine.manualRenderingSampleTime >= 12_288 { break }
            }
        }
        try #require(samples >= 4096, "Offline render must supply a settled measurement window")
        return sum / Double(samples)
    }
}
