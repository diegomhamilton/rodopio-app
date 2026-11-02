---
name: ios-swift-testing
description: Create or update unit tests for native iOS implementation steps with the Swift Testing framework. Use whenever app production code is added or changed and focused automated coverage is required; do not use it for UI screenshots, simulator validation, or physical audio-hardware validation.
---

# iOS Swift Testing

Add the smallest deterministic test set that proves the current implementation step and its acceptance behavior.

## Workflow

1. Read the task acceptance criteria, production diff, existing test target, and nearby test conventions.
2. Identify observable behavior at the public or internal module boundary. Introduce a narrow injected seam when Apple framework state would otherwise make the test nondeterministic.
3. Write focused tests with Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, and `#require`). Do not add new XCTest cases. When modifying an XCTest-only suite, migrate the touched suite rather than mixing frameworks within it.
4. Structure every test body with `// Arrange`, `// Act`, and `// Assert` sections. Keep actions separate from expectations even when the code is short.
5. Give every test a human-readable behavior description with `@Test("…")`. Name the Swift function for navigation and diagnostics; do not rely on it as the only description.
6. Namespace immutable fixture values and test doubles with caseless enums. Prefer `Fixtures` for static values and `TestDoubles` for spies, stubs, fakes, and their nested support types. Do not use global mutable test state.
7. Use `@Test(arguments:)` when the same behavior is verified with different inputs or expected values. Keep separate tests when setup, action, or the reason for failure differs materially.
8. Run only the affected suite while iterating. Report the exact tests and result. The feature-validation workflow owns the final complete-scheme and simulator gates.

## Shape

```swift
import Testing
@testable import BassPractice

@Suite("Audio route mapping")
struct AudioRouteMappingTests {
    @Test(
        "Maps supported input kinds",
        arguments: Fixtures.inputKinds
    )
    func mapsSupportedInputKinds(testCase: Fixtures.InputKindCase) {
        // Arrange
        let mapper = AudioRouteMapper()

        // Act
        let result = mapper.inputKind(for: testCase.portType)

        // Assert
        #expect(result == testCase.expectedKind)
    }
}

private enum Fixtures {
    struct InputKindCase: Sendable {
        let portType: String
        let expectedKind: AudioInputKind
    }

    static let inputKinds: [InputKindCase] = [/* task cases */]
}

private enum TestDoubles {
    final class AudioSession: AudioSessionProtocol, @unchecked Sendable {
        // Synchronize mutable observations or isolate the double to an actor.
    }
}
```

Adapt names and isolation to the feature. Do not copy placeholder cases.

## AVFoundation boundaries

- Do not depend on the process-wide `AVAudioSession.sharedInstance()` or real `AVAudioEngine` hardware state in deterministic unit tests.
- Inject narrow session, engine, notification, or clock interfaces and test commands, mappings, state transitions, and error propagation through them.
- Model mutable spies safely under Swift 6 concurrency using actor isolation, a lock, or an otherwise justified synchronization strategy. Use `@unchecked Sendable` only when the implementation supplies that safety.
- Avoid sleeps and polling. Drive async behavior through injected event sources, streams, or continuations.
- Keep actual routes, microphones, output devices, latency, interruptions, reconnection, and continuous monitoring in simulator or hardware validation evidence.

## Completion gate

An implementation step is not test-complete until its focused Swift Testing suite passes. Stop and report when behavior or failure policy is ambiguous, coverage would require widening the approved production API, a deterministic seam is missing, a real-device claim cannot be made deterministically, or the failure belongs to an earlier task or unrelated code. Do not weaken assertions, add timing delays, or suppress a known failure merely to obtain a pass.
