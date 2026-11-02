import AVFoundation
import Foundation
import Testing
@testable import BassPractice

@Suite("Native parametric EQ", .serialized)
struct NativeEQProcessorTests {
    @Test("Offline EQ changes center-frequency amplitude and honors band/global bypass", arguments: Fixtures.scenarios)
    fileprivate func measuredEQ(scenario: Fixtures.Scenario) throws {
        // Arrange
        let unity = try Fixtures.render(.flat)

        // Act
        let processed = try Fixtures.render(scenario.eq)

        // Assert
        #expect(unity > 0.01)
        #expect(abs(processed / unity - scenario.ratio) < 0.015)
    }

    @Test("Unsupported configuration preserves already-applied native band parameters")
    func invalidNativeEQKeepsPrevious() throws {
        // Arrange
        let processor = NativeEQProcessor()
        try processor.apply(Fixtures.scenarios[0].eq, sampleRate: 48_000)
        let invalid = EQConfiguration(bands: [try EQBand(frequencyHertz: 19, gainDecibels: -12, q: 1)])
        var rejected = false

        // Act
        do { try processor.apply(invalid, sampleRate: 48_000) }
        catch { rejected = true }

        // Assert
        #expect(rejected)
        #expect(processor.node.bands[0].frequency == 1000)
        #expect(processor.node.bands[0].gain == 6)
        #expect(!processor.node.bands[0].bypass)
    }
}

private enum Fixtures {
    struct Scenario: Sendable {
        let eq: EQConfiguration
        let ratio: Double
    }
    static let scenarios: [Scenario] = {
        do {
            let boost = try EQBand(frequencyHertz: 1000, gainDecibels: 6, q: 1)
            return [
                Scenario(eq: EQConfiguration(bands: [boost]), ratio: pow(10, 6.0 / 20)),
                Scenario(eq: EQConfiguration(bands: [try EQBand(frequencyHertz: 1000, gainDecibels: -6, q: 1)]), ratio: pow(10, -6.0 / 20)),
                Scenario(eq: EQConfiguration(bands: [try EQBand(frequencyHertz: 1000, gainDecibels: 6, q: 1, enabled: false)]), ratio: 1),
                Scenario(eq: EQConfiguration(bands: [boost], bypassed: true), ratio: 1),
                Scenario(eq: .flat, ratio: 1)
            ]
        } catch { preconditionFailure("Invalid EQ test fixtures") }
    }()

    static func render(_ configuration: EQConfiguration) throws -> Double {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let processor = NativeEQProcessor()
        // Applying a boosted tone first catches stale bands after switching to Flat.
        try processor.apply(scenarios[0].eq, sampleRate: 48_000)
        try processor.apply(configuration, sampleRate: 48_000)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        engine.attach(player)
        engine.attach(processor.node)
        engine.connect(player, to: processor.node, format: format)
        engine.connect(processor.node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384))
        source.frameLength = source.frameCapacity
        let values = try #require(source.floatChannelData?[0])
        for index in 0..<Int(source.frameLength) { values[index] = Float(0.125 * sin(2 * Double.pi * 1000 * Double(index) / 48_000)) }
        player.scheduleBuffer(source)
        try engine.start()
        player.play()
        defer { engine.stop() }
        let output = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        var squares = 0.0
        var samples = 0
        for _ in 0..<64 {
            let status = try engine.renderOffline(1024, to: output)
            if status == .success {
                if engine.manualRenderingSampleTime > 4096 && engine.manualRenderingSampleTime <= 12_288 {
                    let rendered = try #require(output.floatChannelData?[0])
                    for index in 0..<Int(output.frameLength) { squares += Double(rendered[index]) * Double(rendered[index]); samples += 1 }
                }
                if engine.manualRenderingSampleTime >= 12_288 { break }
            }
        }
        try #require(samples >= 4096, "EQ render must provide a settled measurement window")
        return sqrt(squares / Double(samples))
    }
}
