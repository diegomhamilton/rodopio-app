# Effect-chain architecture

Reviewed source `3347214`, branch `codex/effect-chain`, based on EQ/profile PR #18.

Native processors expose their audio node to an ordered chain. Attachment, connection and detachment iterate the declared order; recording/mixer consumers attach to a stable processed-instrument mixer after the chain and before monitoring volume. The production chain remains Gain → EQ. Future processors can be added to this boundary without altering downstream recording or mixer code.

Validated immutable effect chains retain effect IDs, ordering, gain/EQ bypass and optional profile association. A versioned actor-owned preset repository performs atomic file replacement and preserves malformed/unsupported stores. Preset ordering/application UI is not implemented or claimed by this architecture-only checkpoint.

XcodeBuildMCP focused EffectChainTests: 4 logical /7 expanded cases passed, zero failures/skips, 222.0 seconds. Tests inspect actual native connection order in both arrangements and verify preset reopen/rename/delete, malformed-file byte preservation and duplicate identity rejection.

Full scheme at the reviewed source passed **100 logical /210 expanded cases**, zero failures/skips, 240.9 seconds. Retained iPhone 17 Pro simulator, iOS 26.2, DerivedData `/tmp/BassPracticeF12Validation`. Result `/Users/dmh/Library/Developer/XcodeBuildMCP/workspaces/ios-bass-app-791fac75e19c/result-bundles/test_sim_2026-10-05T13-55-01-352Z_pid30850_9e7778d0.xcresult`.

No visual product controls changed, so no new UI gesture or screenshot result is claimed. Physical audio/latency remain pending. User-owned signing/project formatting, the newly observed untracked BassPracticeTests.xcscheme and pre-existing .orig files are untouched and excluded. Recording follows this stable boundary; V0.1 remains incomplete.
