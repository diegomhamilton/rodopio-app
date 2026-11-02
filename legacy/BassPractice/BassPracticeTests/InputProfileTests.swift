import Foundation
import Testing
@testable import BassPractice

@Suite("Input profile domain")
struct InputProfileTests {
    @Test("Domain values accept finite gains and positive finite EQ values without imposing DSP backend limits", arguments: Fixtures.validMagnitudes)
    func domainDoesNotInventBackendLimits(magnitude: Float) throws {
        // Arrange
        let gain = -magnitude

        // Act
        let band = try EQBand(frequencyHertz: magnitude, gainDecibels: gain, q: magnitude)
        let profile = try InputProfile(name: "Custom", instrument: .custom, inputGainDecibels: gain, eq: EQConfiguration(bands: [band]))

        // Assert
        #expect(profile.inputGainDecibels == gain)
        #expect(profile.eq.bands == [band])
    }

    @Test("Profiles round-trip instrument, stable identifier, decibel gain, and EQ values", arguments: InstrumentType.allCases)
    func profileCodableRoundTrip(instrument: InstrumentType) throws {
        // Arrange
        let band = try EQBand(frequencyHertz: 350, gainDecibels: -1.5, q: 0.7, enabled: false)
        let profile = try InputProfile(id: Fixtures.profileID, name: "My Instrument", instrument: instrument, inputGainDecibels: -6, eq: EQConfiguration(bands: [band]))

        // Act
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(InputProfile.self, from: data)

        // Assert
        #expect(decoded == profile)
        #expect(decoded.id == Fixtures.profileID)
        #expect(decoded.eq.bands.first?.enabled == false)
    }

    @Test("Default profile describes unity input gain and a flat EQ")
    func defaultsDescribeUnityAndFlatEQ() throws {
        // Arrange
        let name = "Custom"

        // Act
        let profile = try InputProfile(name: name, instrument: .custom)

        // Assert
        #expect(profile.inputGainDecibels == 0)
        #expect(profile.eq == .flat)
    }

    @Test("Replacing a profile preserves its identity while retaining the original value")
    func replacementPreservesIdentity() throws {
        // Arrange
        let original = try InputProfile(id: Fixtures.profileID, name: "Bass", instrument: .bass)

        // Act
        let replacement = try InputProfile(id: original.id, name: "My Bass", instrument: original.instrument, inputGainDecibels: -3, eq: original.eq)

        // Assert
        #expect(replacement.id == original.id)
        #expect(replacement.name == "My Bass")
        #expect(original.name == "Bass")
        #expect(original.inputGainDecibels == 0)
    }

    @Test("Profile initialization rejects blank names and nonfinite gain", arguments: Fixtures.invalidProfiles)
    fileprivate func invalidProfileRejected(testCase: Fixtures.InvalidProfile) {
        // Arrange
        var failure: InputProfileValidationError?

        // Act
        do { _ = try InputProfile(name: testCase.name, instrument: .custom, inputGainDecibels: testCase.gain) }
        catch { failure = error }

        // Assert
        #expect(failure == testCase.expected)
    }

    @Test("EQ initialization rejects nonpositive or nonfinite frequency and Q and nonfinite gain", arguments: Fixtures.invalidBands)
    fileprivate func invalidEQBandRejected(testCase: Fixtures.InvalidBand) {
        // Arrange
        var failure: EQBandValidationError?

        // Act
        do { _ = try EQBand(frequencyHertz: testCase.frequency, gainDecibels: testCase.gain, q: testCase.q, enabled: false) }
        catch { failure = error }

        // Assert
        #expect(failure == testCase.expected)
    }

    @Test("Codable decoding validates EQ bands even when disabled", arguments: Fixtures.invalidBands)
    fileprivate func decodedInvalidEQBandRejected(testCase: Fixtures.InvalidBand) throws {
        // Arrange
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let data = try encoder.encode(Fixtures.BandPayload(frequencyHertz: testCase.frequency, gainDecibels: testCase.gain, q: testCase.q, enabled: false))
        var failure: EQBandValidationError?

        // Act
        do { _ = try decoder.decode(EQBand.self, from: data) }
        catch let error as EQBandValidationError { failure = error }

        // Assert
        #expect(failure == testCase.expected)
    }

    @Test("Codable decoding validates profile names and gains", arguments: Fixtures.invalidProfiles)
    fileprivate func decodedInvalidProfileRejected(testCase: Fixtures.InvalidProfile) throws {
        // Arrange
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let data = try encoder.encode(Fixtures.ProfilePayload(id: Fixtures.profileID, name: testCase.name, instrument: .custom, inputGainDecibels: testCase.gain, eq: .flat))
        var failure: InputProfileValidationError?

        // Act
        do { _ = try decoder.decode(InputProfile.self, from: data) }
        catch let error as InputProfileValidationError { failure = error }

        // Assert
        #expect(failure == testCase.expected)
    }
}

private enum Fixtures {
    static let validMagnitudes: [Float] = [.leastNormalMagnitude, 1, .greatestFiniteMagnitude]
    static let profileID = UUID(uuidString: "C25E3BF2-0C8D-4EBF-AEF1-0AB2F91E3B6D")!
    struct InvalidProfile: Sendable {
        let name: String
        let gain: Float
        let expected: InputProfileValidationError
    }
    struct InvalidBand: Sendable {
        let frequency: Float
        let gain: Float
        let q: Float
        let expected: EQBandValidationError
    }
    struct BandPayload: Encodable {
        let frequencyHertz: Float
        let gainDecibels: Float
        let q: Float
        let enabled: Bool
    }
    struct ProfilePayload: Encodable {
        let id: UUID
        let name: String
        let instrument: InstrumentType
        let inputGainDecibels: Float
        let eq: EQConfiguration
    }
    static let invalidProfiles = [
        InvalidProfile(name: "", gain: 0, expected: .emptyName),
        InvalidProfile(name: " \n\t", gain: 0, expected: .emptyName),
        InvalidProfile(name: "Custom", gain: .nan, expected: .nonFiniteInputGain),
        InvalidProfile(name: "Custom", gain: .infinity, expected: .nonFiniteInputGain),
        InvalidProfile(name: "Custom", gain: -.infinity, expected: .nonFiniteInputGain)
    ]
    static let invalidBands: [InvalidBand] = [Float(0), -1, .nan, .infinity, -.infinity].flatMap { value in
        [InvalidBand(frequency: value, gain: 0, q: 1, expected: .invalidFrequency),
         InvalidBand(frequency: 80, gain: 0, q: value, expected: .invalidQ)]
    } + [Float.nan, .infinity, -.infinity].map {
        InvalidBand(frequency: 80, gain: $0, q: 1, expected: .nonFiniteGain)
    }
}
