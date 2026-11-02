import Foundation

/// Editable starting points, applied through the same processing path as custom profiles.
enum BuiltInInputProfiles {
    // These identifiers are persisted identity, so retain them when changing display names.
    static let bassID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let guitarID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    static let customID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))

    static let profiles: [InputProfile] = {
        do {
            return [
                try InputProfile(id: bassID, name: "Bass", instrument: .bass, eq: EQConfiguration(bands: [
                    try EQBand(frequencyHertz: 80, gainDecibels: 2, q: 0.7),
                    try EQBand(frequencyHertz: 350, gainDecibels: -1, q: 1),
                    try EQBand(frequencyHertz: 1600, gainDecibels: 1, q: 0.8)
                ])),
                try InputProfile(id: guitarID, name: "Guitar", instrument: .guitar, eq: EQConfiguration(bands: [
                    try EQBand(frequencyHertz: 120, gainDecibels: -2, q: 0.7),
                    try EQBand(frequencyHertz: 800, gainDecibels: 1, q: 1),
                    try EQBand(frequencyHertz: 3200, gainDecibels: 2, q: 0.8)
                ])),
                try InputProfile(id: customID, name: "Flat / Custom", instrument: .custom)
            ]
        } catch {
            // Literal names and domain defaults must satisfy the validated model.
            // A failure here is a programming error, never malformed user data.
            preconditionFailure("Invalid built-in input profile constants: \(error)")
        }
    }()
}
