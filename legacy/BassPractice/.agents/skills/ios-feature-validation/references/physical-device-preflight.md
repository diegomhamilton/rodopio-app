# Physical device checkpoint

Use the existing signing configuration. Discover once with `xcrun devicectl list devices` and Xcode destinations; record the identifiers separately. CoreDevice identifiers used by devicectl can differ from Xcode destination UDIDs. Do not copy one into the other tool's argument without checking its discovery output.

Inspect build settings for the intended device configuration (`DEVELOPMENT_TEAM`, signing style, bundle ID and provisioning settings), then build the reviewed commit. A successful generic iOS build proves compilation/signing for that configuration; it does not prove installation on the selected device. Do not invent an Apple team, replace signing configuration, or add Bluetooth options to solve deployment.

For microphone features, verify the built app's `NSMicrophoneUsageDescription` and the runtime permission request path before physical review. Simulator unit success does not prove these device prerequisites. Report missing prerequisites to the implementation owner rather than editing app code during validation.

Keep build, install and launch as separate commands with checked results. Record the installed source commit, app path, target device and launch result. If installation fails, do not label the commit installed. A Developer Disk Image mount failure can persist with Developer Mode enabled; preserve the concrete error and readiness evidence instead of repeating unlock requests or assuming signing is its cause. Missing team/provisioning is a separate build blocker.

Report what the checkpoint UI actually exposes. Working audio APIs do not establish that hardware-review controls exist. Simulator evidence cannot prove physical input/output routing, latency, hardware monitoring, interruption or reconnection behavior.
