import Foundation
import Testing
@testable import BassPractice

@Suite("Built-in input profiles")
struct BuiltInInputProfileTests {
    @Test("Built-in profiles retain their deterministic identities, names, and instrument kinds", arguments: Fixtures.expectedProfiles)
    fileprivate func catalogMatchesExpectedDefaults(testCase: Fixtures.ExpectedProfile) throws {
        // Arrange
        let catalog = BuiltInInputProfiles.profiles

        // Act
        let profile = try #require(catalog.first { $0.id.uuidString == testCase.id })

        // Assert
        #expect(profile.name == testCase.name)
        #expect(profile.instrument == testCase.instrument)
        #expect(profile.inputGainDecibels == 0)
        #expect(profile.eq.bands.map(\.frequencyHertz) == testCase.frequencies)
        #expect(profile.eq.bands.map(\.gainDecibels) == testCase.gains)
        try NativeEQLimits.validate(profile.eq, sampleRate: 48_000)
    }

    @Test("The catalog exposes exactly three distinct profiles in Bass, Guitar, Custom order")
    func catalogHasStableOrderAndUniqueIDs() {
        // Arrange
        let catalog = BuiltInInputProfiles.profiles

        // Act
        let instruments = catalog.map(\.instrument)
        let ids = Set(catalog.map(\.id))

        // Assert
        #expect(instruments == [.bass, .guitar, .custom])
        #expect(ids.count == 3)
        #expect(catalog.map(\.id) == [BuiltInInputProfiles.bassID, BuiltInInputProfiles.guitarID, BuiltInInputProfiles.customID])
    }

    @Test("A custom replacement copied from a built-in remains independent of the catalog", arguments: Fixtures.expectedProfiles)
    fileprivate func customCopyDoesNotChangeBuiltIn(testCase: Fixtures.ExpectedProfile) throws {
        // Arrange
        let source = try #require(BuiltInInputProfiles.profiles.first { $0.id.uuidString == testCase.id })
        let band = try EQBand(frequencyHertz: 120, gainDecibels: 2, q: 1)

        // Act
        let copy = try InputProfile(name: "My \(source.name)", instrument: source.instrument, inputGainDecibels: -3, eq: EQConfiguration(bands: [band]))
        let unchangedSource = try #require(BuiltInInputProfiles.profiles.first { $0.id == source.id })

        // Assert
        #expect(copy.id != source.id)
        #expect(copy.inputGainDecibels == -3)
        #expect(copy.eq.bands == [band])
        #expect(unchangedSource == source)
        #expect(unchangedSource.inputGainDecibels == 0)
        #expect(unchangedSource.eq == source.eq)
    }
}

private enum Fixtures {
    struct ExpectedProfile: Sendable {
        let id: String
        let name: String
        let instrument: InstrumentType
        let frequencies: [Float]
        let gains: [Float]
    }
    static let expectedProfiles = [
        ExpectedProfile(id: "00000000-0000-0000-0000-000000000001", name: "Bass", instrument: .bass, frequencies: [80, 350, 1600], gains: [2, -1, 1]),
        ExpectedProfile(id: "00000000-0000-0000-0000-000000000002", name: "Guitar", instrument: .guitar, frequencies: [120, 800, 3200], gains: [-2, 1, 2]),
        ExpectedProfile(id: "00000000-0000-0000-0000-000000000003", name: "Flat / Custom", instrument: .custom, frequencies: [], gains: [])
    ]
}
