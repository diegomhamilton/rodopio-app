---
title: iOS Bass App — Implementation Plan through V0.4
aliases:
  - Implementation Plan
tags:
  - ios
  - audio
  - product-plan
  - scope
status: proposed
---

# iOS Bass App — Implementation Plan through V0.4

> [!tip] Scope review
> Each release starts with a feature checklist. Uncheck any feature you want to question, defer, or remove. Keep the detailed feature section until the scope decision is final so its rationale and dependencies remain available.

## Delivery model

Development is organized at three levels:

```text
Version
└── Implementation Phase
    └── Feature PR
        ├── Task PR
        ├── Task PR
        └── Task PR
```

A Task PR should ideally:

- change one architectural concept or user-visible behavior;
- remain reviewable in roughly 10–30 minutes;
- include tests where practical;
- avoid unrelated refactors;
- leave the project compiling and tests passing.

A Feature PR is the integration point for a complete capability.

Example:

```text
feature/audio-input
├── task/audio-session
├── task/audio-device-discovery
├── task/audio-engine-input
└── task/input-device-ui
```

During development, task PRs can be stacked:

```text
main
  ↓
feature/audio-input
  ↓
task/audio-session
  ↓
task/audio-routing
  ↓
task/audio-input-ui
```

Once all task PRs are reviewed, the complete feature branch is merged into `main`.

---

# V0.1 — Play, Process, Record

## Feature scope checklist

- [x] [[#Feature PR F0.1 — Application Skeleton|F0.1 — Application Skeleton]]
- [x] [[#Feature PR F1.1 — Audio Session Management|F1.1 — Audio Session Management]]
- [x] [[#Feature PR F1.2 — Audio Engine Core|F1.2 — Audio Engine Core]]
- [x] [[#Feature PR F2.1 — Input Profiles|F2.1 — Input Profiles]]
- [x] [[#Feature PR F3.1 — Gain Processing|F3.1 — Gain Processing]]
- [x] [[#Feature PR F3.2 — Parametric EQ|F3.2 — Parametric EQ]]
- [x] [[#Feature PR F3.3 — Effect Chain Architecture|F3.3 — Effect Chain Architecture]]
- [x] [[#Feature PR F4.1 — Recording Engine|F4.1 — Recording Engine]]
- [x] [[#Feature PR F5.1 — Track Import|F5.1 — Track Import]]
- [x] [[#Feature PR F5.2 — Backing Track Playback|F5.2 — Backing Track Playback]]
- [x] [[#Feature PR F6.1 — Main Mixer|F6.1 — Main Mixer]]
- [x] [[#Feature PR F7.1 — Session Domain|F7.1 — Session Domain]]
- [x] [[#Feature PR F7.2 — Library Screen|F7.2 — Library Screen]]

## Product milestone

The user can:

1. connect an audio interface;
2. select an input;
3. identify the instrument as Bass, Guitar, or Custom;
4. monitor the instrument;
5. apply gain and EQ;
6. load a backing track;
7. play along with it;
8. record the processed instrument;
9. listen to the resulting recording;
10. save and reopen the session.

The objective is not yet to create a DAW.

The goal is a reliable musical practice and recording tool.

---

# Phase 0 — Project Foundation

## Feature PR F0.1 — Application Skeleton

### Task PR F0.1.1 — Create project structure

Create the initial native iOS application.

Suggested modules:

```text
App
Core
Audio
DSP
Sessions
Library
Features
    Session
    Tone
    Looper
    Library
UI
Tests
```

Initial dependency direction:

```text
UI
 ↓
Features
 ↓
Domain / Sessions
 ↓
Audio / DSP
 ↓
AVFoundation
```

Avoid allowing UI code to directly manipulate `AVAudioEngine`.

### Task PR F0.1.2 — Dependency container

Introduce explicit dependency injection.

Example:

```swift
struct AppDependencies {
    let audioEngine: AudioEngineProtocol
    let sessionRepository: SessionRepository
    let fileStore: AudioFileStore
}
```

No service locator or global audio singleton.

### Task PR F0.1.3 — Navigation shell

Implement the primary destinations:

```text
Session
Tone
Library
```

The Looper destination is introduced in V0.2.

### Task PR F0.1.4 — Logging infrastructure

Add structured logging for:

- audio route changes;
- audio session state;
- engine start/stop;
- recording;
- file errors;
- session loading.

Use `Logger` / `os.Logger`.

### Acceptance criteria

- App launches.
- Navigation works.
- Core components can be mocked.
- No actual audio processing yet.
- Unit-test target exists.
- CI can build and run tests.

---

# Phase 1 — Audio Hardware Foundation

This phase should happen before significant UI work.

Its purpose is to validate iOS and Cube Baby behavior.

---

# Feature PR F1.1 — Audio Session Management

## Task PR F1.1.1 — AVAudioSession abstraction

Create:

```swift
protocol AudioSessionManaging {
    func activate() async throws
    func deactivate() async
}
```

Configure the app for simultaneous:

```text
input
processing
recording
playback
monitoring
```

Likely category:

```swift
.playAndRecord
```

with appropriate options determined during hardware testing.

## Task PR F1.1.2 — Route change observation

Observe:

```swift
AVAudioSession.routeChangeNotification
```

Represent routes internally:

```swift
struct AudioRoute {
    let inputs: [AudioDevice]
    let outputs: [AudioDevice]
}
```

## Task PR F1.1.3 — Input device discovery

Expose available inputs.

Example:

```swift
enum AudioInputKind {
    case builtInMicrophone
    case usb
    case bluetooth
    case unknown
}
```

Do not encode Cube Baby-specific behavior into the domain layer.

## Task PR F1.1.4 — Preferred input selection

Allow selecting an available input where iOS permits it.

Handle:

- disconnected device;
- route becoming unavailable;
- app background/foreground;
- audio interruption.

## Feature acceptance criteria

Connecting or disconnecting an interface updates the app without restarting it.

---

# Feature PR F1.2 — Audio Engine Core

## Task PR F1.2.1 — Engine lifecycle

Create an `AudioEngine`.

Responsibilities:

```text
configure graph
start
stop
restart after route change
report engine state
```

Suggested state:

```swift
enum AudioEngineState {
    case stopped
    case starting
    case running
    case interrupted
    case failed(Error)
}
```

## Task PR F1.2.2 — Input node integration

Connect:

```text
AVAudioInputNode
        ↓
instrument processing
        ↓
main mixer
        ↓
output
```

Initially processing can simply pass the signal through.

## Task PR F1.2.3 — Monitoring

Add live monitoring:

```text
Input → Engine → Output
```

Expose:

```swift
monitoringEnabled
monitoringGain
```

## Task PR F1.2.4 — Audio format diagnostics

Record and display/debug:

- sample rate;
- channel count;
- input format;
- output format;
- IO buffer duration.

This PR is especially useful for testing Cube Baby compatibility.

## Task PR F1.2.5 — Interruption recovery

Handle:

- phone interruption;
- audio session interruption;
- device disconnect;
- route changes.

## Feature acceptance criteria

Bass connected through the interface can be heard through the configured output continuously.

---

# Phase 2 — Instrument Profiles

# Feature PR F2.1 — Input Profiles

## Task PR F2.1.1 — Domain model

Introduce:

```swift
enum InstrumentType {
    case bass
    case guitar
    case custom
}
```

And:

```swift
struct InputProfile {
    let id: UUID
    var name: String
    var instrument: InstrumentType
    var inputGain: Float
    var eq: EQConfiguration
}
```

## Task PR F2.1.2 — Built-in profiles

Provide sensible starting profiles:

```text
Bass
Guitar
Flat / Custom
```

These are defaults, not hard-coded processing modes.

## Task PR F2.1.3 — Profile persistence

Persist custom profiles.

## Task PR F2.1.4 — Profile selector UI

On the Session screen:

```text
INPUT
Cube Baby USB

INSTRUMENT
Bass ▼
```

Changing profile updates processing immediately.

## Feature acceptance criteria

User can switch Bass → Guitar → Custom while monitoring.

---

# Phase 3 — DSP V1

The purpose here is to establish the processing pipeline that future amp modeling will plug into.

---

# Feature PR F3.1 — Gain Processing

## Task PR F3.1.1 — Processing node abstraction

Define a reusable processing concept.

```swift
protocol AudioProcessor {
    var id: UUID { get }
    var bypassed: Bool { get set }
}
```

The implementation may wrap Audio Units internally.

## Task PR F3.1.2 — Input gain processor

Signal path:

```text
Input
 ↓
Gain
 ↓
EQ
 ↓
Effects
```

## Task PR F3.1.3 — Gain UI

Expose:

```text
Input Gain
Output Gain
Bypass
```

---

# Feature PR F3.2 — Parametric EQ

## Task PR F3.2.1 — EQ model

Example:

```swift
struct EQBand {
    var frequency: Float
    var gain: Float
    var q: Float
    var enabled: Bool
}
```

## Task PR F3.2.2 — EQ audio node

Use native audio processing initially.

Likely:

```text
AVAudioUnitEQ
```

## Task PR F3.2.3 — Bass EQ preset

Initial bass-oriented frequency ranges.

## Task PR F3.2.4 — Guitar EQ preset

Separate defaults from Bass.

## Task PR F3.2.5 — EQ editor UI

First version can be controls rather than a graphical frequency curve.

Example:

```text
LOW
80 Hz
+2.5 dB

LOW MID
350 Hz
-1.0 dB

HIGH MID
1.6 kHz
+3.0 dB
```

A graphical EQ can be added later.

## Feature acceptance criteria

Changing EQ is audible in real time without restarting the engine.

---

# Feature PR F3.3 — Effect Chain Architecture

This is primarily an architectural PR.

## Task PR F3.3.1 — Effect model

```swift
struct EffectChain {
    var effects: [EffectConfiguration]
}
```

## Task PR F3.3.2 — Effect ordering

Support:

```text
Gain
 ↓
EQ
 ↓
Effect A
 ↓
Effect B
 ↓
Output
```

## Task PR F3.3.3 — Bypass

Every processor supports bypass.

## Task PR F3.3.4 — Effect preset persistence

Create:

```swift
struct EffectPreset {
    let id: UUID
    var name: String
    var inputProfile: UUID?
    var effects: [EffectConfiguration]
}
```

## Feature acceptance criteria

Architecture supports adding future processors without modifying the recorder or mixer.

---

# Phase 4 — Recording

# Feature PR F4.1 — Recording Engine

## Task PR F4.1.1 — Recorder abstraction

```swift
protocol AudioRecording {
    func start() throws
    func stop() async throws -> Recording
}
```

## Task PR F4.1.2 — Engine tap recording

Install an audio tap at the correct point.

Recommended default:

```text
Input
 ↓
Effects
 ↓
┌──────────────┐
│ recording tap│
└──────────────┘
 ↓
Mixer
```

This means recordings contain the selected tone.

Later we could optionally record dry + wet simultaneously.

## Task PR F4.1.3 — Audio file storage

Define file layout:

```text
Sessions/
    <session-id>/
        session.json
        recordings/
            <recording-id>.caf
```

Prefer a lossless internal format.

## Task PR F4.1.4 — Recording state

```swift
enum RecordingState {
    case idle
    case recording(startedAt: Date)
    case stopping
}
```

## Task PR F4.1.5 — Record controls UI

Session screen:

```text
● Record
■ Stop
▶ Playback
```

## Feature acceptance criteria

User can:

```text
connect bass
→ select tone
→ record
→ stop
→ play recording
```

---

# Phase 5 — Backing Tracks

# Feature PR F5.1 — Track Import

## Task PR F5.1.1 — Document picker

Import common audio formats.

## Task PR F5.1.2 — Backing track model

```swift
struct BackingTrack {
    let id: UUID
    let fileURL: URL
    var name: String
}
```

## Task PR F5.1.3 — File management

Imported audio becomes owned by the app rather than relying permanently on an external URL.

---

# Feature PR F5.2 — Backing Track Playback

## Task PR F5.2.1 — Player node

Add:

```text
AVAudioPlayerNode
```

to the audio graph.

## Task PR F5.2.2 — Transport

Implement:

```text
play
pause
stop
seek
```

## Task PR F5.2.3 — Track gain

Backing-track gain is independent from instrument gain.

## Task PR F5.2.4 — Session UI

Example:

```text
BACKING TRACK

Come Together.mp3

00:42 ━━━━━━━●━━━━━━━━ 04:18

      ◀︎    ▶︎    ■

Volume ━━━━━━━━━●━━
```

## Feature acceptance criteria

Backing track and live bass play simultaneously.

Bass remains independently recordable.

---

# Phase 6 — Mixer

# Feature PR F6.1 — Main Mixer

## Task PR F6.1.1 — Mixer domain model

Channels:

```text
Instrument
Backing Track
Playback
```

Loop channels are added in V0.2.

## Task PR F6.1.2 — Channel volume

Independent volume controls.

## Task PR F6.1.3 — Mute

Each source can be muted.

## Task PR F6.1.4 — Metering

Add basic level metering.

Important for identifying:

```text
no signal
signal
clipping
```

## Feature acceptance criteria

User can balance live bass and backing music without modifying recorded signal levels.

---

# Phase 7 — Session Persistence

# Feature PR F7.1 — Session Domain

## Task PR F7.1.1 — Session model

```swift
struct MusicSession {
    let id: UUID

    var name: String

    var inputProfileID: UUID?
    var effectPresetID: UUID?

    var backingTrack: BackingTrack?

    var recordings: [Recording]
    var loops: [Loop]

    var createdAt: Date
    var updatedAt: Date
}
```

## Task PR F7.1.2 — Repository

```swift
protocol SessionRepository {
    func create() throws -> MusicSession
    func save(_ session: MusicSession) throws
    func load(id: UUID) throws -> MusicSession
    func list() throws -> [MusicSession]
    func delete(id: UUID) throws
}
```

## Task PR F7.1.3 — Serialization

Persist session metadata independently of audio files.

## Task PR F7.1.4 — Autosave

Important changes trigger debounced saving.

---

# Feature PR F7.2 — Library Screen

## Task PR F7.2.1 — Session list

Show:

```text
Name
Date
Backing track
Number of recordings
```

## Task PR F7.2.2 — Open session

Restore:

```text
instrument profile
effect preset
backing track
recordings
mixer levels
```

## Task PR F7.2.3 — Rename/delete session

## Feature acceptance criteria

Closing and reopening the app preserves the complete working session.

---

# V0.1 RELEASE GATE

Before calling V0.1 complete:

### Hardware

- Cube Baby input works reliably.
- Built-in mic works.
- Wired/USB output works.
- Route changes do not crash the app.

### Monitoring

- Live monitoring works.
- Latency is measured.
- No obvious glitches during normal use.

### Tone

- Bass profile.
- Guitar profile.
- Custom profile.
- Gain.
- EQ.
- Effect-chain abstraction.

### Recording

- Start/stop recording.
- Playback.
- Audio survives relaunch.

### Backing tracks

- Import.
- Play/pause/seek.
- Independent volume.

### Sessions

- Save.
- Load.
- Delete.

---

# V0.2 — Basic Looper

## Feature scope checklist

- [x] [[#Feature PR F8.1 — Shared Transport|F8.1 — Shared Transport]]
- [x] [[#Feature PR F9.1 — Single Loop Recording|F9.1 — Single Loop Recording]]
- [x] [[#Feature PR F9.2 — Multiple Loop Tracks|F9.2 — Multiple Loop Tracks]]
- [x] [[#Feature PR F9.3 — Basic Overdub|F9.3 — Basic Overdub]]
- [x] [[#Feature PR F10.1 — Basic Loop Alignment|F10.1 — Basic Loop Alignment]]
- [x] [[#Feature PR F11.1 — Loop Persistence|F11.1 — Loop Persistence]]
- [x] [[#Feature PR F12.1 — Looper Screen|F12.1 — Looper Screen]]

## Product milestone

V0.2 adds the minimum looping functionality required for a useful practice workflow.

The user can:

1. create a loop from the processed instrument input;
2. stop recording and immediately hear the loop repeat;
3. play live over the loop;
4. create additional loop tracks;
5. mute and unmute loop tracks;
6. adjust loop volume;
7. clear a loop;
8. save and restore loops as part of a session.

V0.2 is intentionally limited.

It does not include a metronome, tempo-aware quantization, advanced overdub history, a full tone preset library, a generic effect-chain editor, or performance diagnostics beyond what is required for reliable looping.

The core goal is:

```text
record → repeat → play over it → add another loop → mute/clear → save
```

---

# Phase 8 — Shared Transport Foundation

Implement only the transport capabilities required for reliable loop playback.

# Feature PR F8.1 — Shared Transport

## Task PR F8.1.1 — Transport clock

Introduce an engine-level timeline.

```swift
struct TransportPosition {
    let sampleTime: AVAudioFramePosition
    let seconds: TimeInterval
}
```

Avoid relying on wall-clock time for loop scheduling.

## Task PR F8.1.2 — Transport states

```swift
enum TransportState {
    case stopped
    case playing
    case paused
}
```

## Task PR F8.1.3 — Scheduled playback

Enable sample-accurate scheduling where practical.

## Task PR F8.1.4 — Backing-track integration

Use the shared transport for backing-track playback where this can be done without destabilizing V0.1 behavior.

## Feature acceptance criteria

Backing tracks and loops can use one timing system without audible scheduling gaps.

---

# Phase 9 — Basic Looper

# Feature PR F9.1 — Single Loop Recording

## Task PR F9.1.1 — Loop model

```swift
struct Loop {
    let id: UUID

    var name: String

    let fileURL: URL
    let frameCount: AVAudioFrameCount

    var volume: Float
    var muted: Bool
}
```

## Task PR F9.1.2 — First-pass recording

Workflow:

```text
Record Loop
    ↓
play bass
    ↓
Stop
    ↓
loop length established
    ↓
loop begins repeating
```

## Task PR F9.1.3 — Seamless playback

Loop playback must repeat without audible scheduling gaps or clicks.

## Task PR F9.1.4 — Loop state machine

```swift
enum LoopState {
    case empty
    case recording
    case playing
    case muted
}
```

## Task PR F9.1.5 — Basic looper UI

Before recording:

```text
┌───────────────────────┐

       LOOP 1

       ● RECORD

└───────────────────────┘
```

After recording:

```text
┌───────────────────────┐

       LOOP 1

       ▶ PLAYING

    MUTE      CLEAR

└───────────────────────┘
```

## Feature acceptance criteria

User can create one loop and play bass over it indefinitely.

---

# Feature PR F9.2 — Multiple Loop Tracks

## Task PR F9.2.1 — Loop collection

Session contains:

```swift
var loops: [Loop]
```

## Task PR F9.2.2 — Independent players

Each loop has an independently controllable playback node.

## Task PR F9.2.3 — Mute and volume

Support:

```text
mute
unmute
volume
clear
```

Solo is deferred unless it is trivial to add without complicating the basic loop workflow.

## Task PR F9.2.4 — Loop list UI

Example:

```text
LOOPS

1  Bass Groove       ▶   M
2  Harmonics         ▶   M
3  Chords            ▶   M

+ Add Loop
```

## Feature acceptance criteria

User can create multiple loops, hear them together, mute individual loops, adjust their levels, and clear them.

---

# Feature PR F9.3 — Basic Overdub

Overdub is included in V0.2 only in its simplest form: recording a new loop while existing loops continue playing.

## Task PR F9.3.1 — Record against existing loops

Existing loops continue playing while a new loop is captured.

## Task PR F9.3.2 — Independent loop creation

The new recording becomes a separate loop track rather than destructively replacing an existing loop.

## Task PR F9.3.3 — Basic cancel behavior

Allow the user to cancel a loop recording before committing it.

## Feature acceptance criteria

User can:

```text
record groove
→ hear it repeat
→ record another part over it
→ keep both loops independently
```

Advanced overdub merging and revision history are deferred.

---

# Phase 10 — Loop Synchronization

# Feature PR F10.1 — Basic Loop Alignment

## Task PR F10.1.1 — Shared loop start

All loops start from the same transport origin.

## Task PR F10.1.2 — Loop boundary scheduling

Provide a reliable concept of the current loop boundary for starting and stopping loop playback.

This is timing infrastructure, not tempo-aware quantization.

## Task PR F10.1.3 — Synchronized mute and unmute

Mute and unmute operations should not restart a loop at an arbitrary position.

Unmuting rejoins at the current transport position.

## Feature acceptance criteria

Multiple loops remain phase-aligned after mute and unmute.

---

# Phase 11 — Looper Session Integration

# Feature PR F11.1 — Loop Persistence

## Task PR F11.1.1 — Store loop files

Use a session-specific directory:

```text
Sessions/
    <session-id>/
        session.json
        recordings/
            <recording-id>.caf
        loops/
            <loop-id>.caf
```

## Task PR F11.1.2 — Persist loop metadata

Save:

```text
loop name
loop file
frame count
volume
mute state
order
```

## Task PR F11.1.3 — Restore loop playback

Opening a session restores the loop list and makes each loop available for playback.

## Feature acceptance criteria

Closing and reopening the app preserves the loops and their basic mixer state.

---

# Phase 12 — Basic Looper UI

# Feature PR F12.1 — Looper Screen

## Task PR F12.1.1 — Looper navigation

Add the Looper destination to the application shell.

## Task PR F12.1.2 — Large performance controls

Prioritize controls that can be used while playing:

```text
Record
Stop
Play
Mute
Clear
```

## Task PR F12.1.3 — Loop status

Show:

```text
empty
recording
playing
muted
```

## Task PR F12.1.4 — Loop volume

Provide a simple per-loop volume control.

## Task PR F12.1.5 — Add-loop flow

Allow the user to create a new loop without navigating through complex configuration.

## Feature acceptance criteria

The looper can be operated from a single screen with clear state feedback and controls large enough for performance use.

---

# V0.2 RELEASE GATE

A session must support this complete workflow:

```text
Connect Cube Baby
       ↓
Select Bass
       ↓
Choose tone
       ↓
Load optional backing track
       ↓
Record first bass loop
       ↓
Loop repeats
       ↓
Record second loop
       ↓
Hear both loops together
       ↓
Mute or unmute a loop
       ↓
Adjust loop volume
       ↓
Clear a loop
       ↓
Play live bass on top
       ↓
Save session
       ↓
Close app
       ↓
Reopen session
       ↓
Loops restore correctly
```

---

# V0.3 — Metronome and Practice Timing

## Feature scope checklist

- [x] [[#Feature PR F13.1 — Metronome Clock|F13.1 — Metronome Clock]]
- [x] [[#Feature PR F13.2 — Metronome Audio Path|F13.2 — Metronome Audio Path]]
- [x] [[#Feature PR F13.3 — Metronome Controls|F13.3 — Metronome Controls]]
- [x] [[#Feature PR F13.4 — Metronome-Aware Looping|F13.4 — Metronome-Aware Looping]]

## Product milestone

V0.3 adds a metronome that can be heard during playback and practice but is never captured in instrument recordings or loop recordings.

The user can:

1. enable or disable the metronome;
2. set BPM;
3. choose a time signature;
4. choose an audible accent pattern;
5. hear the metronome alongside backing tracks, loops, and live monitoring;
6. record instrument audio without the metronome in the recorded file;
7. use the metronome as a timing reference for loop creation.

The key audio rule is:

```text
Metronome → playback/output mix only
Metronome ↛ recording tap
```

---

# Phase 13 — Metronome Timing

# Feature PR F13.1 — Metronome Clock

## Task PR F13.1.1 — BPM model

```swift
struct Tempo {
    var bpm: Double
}
```

## Task PR F13.1.2 — Time-signature model

```swift
struct TimeSignature {
    var beatsPerBar: Int
    var beatUnit: Int
}
```

## Task PR F13.1.3 — Sample-based click scheduling

Schedule clicks against the shared transport rather than using UI timers.

## Task PR F13.1.4 — Start and stop behavior

Metronome follows transport state:

```text
transport stopped → metronome stopped
transport playing → metronome playing
transport paused → metronome paused
```

---

# Feature PR F13.2 — Metronome Audio Path

## Task PR F13.2.1 — Click source

Create a lightweight click source using bundled samples or generated audio.

## Task PR F13.2.2 — Playback-only routing

Route the metronome into the playback mixer after the recording tap.

```text
Instrument
    ↓
Effects
    ↓
Recording tap
    ↓
Instrument mixer ─────┐
                      ├── Output
Backing track ────────┤
Loops ────────────────┤
Metronome ────────────┘
```

## Task PR F13.2.3 — Recording exclusion tests

Verify that:

- instrument recordings contain no metronome;
- loop recordings contain no metronome;
- playback still contains the metronome.

## Feature acceptance criteria

The metronome is audible during practice but absent from all captured instrument and loop audio.

---

# Feature PR F13.3 — Metronome Controls

## Task PR F13.3.1 — Enable/disable

## Task PR F13.3.2 — BPM control

## Task PR F13.3.3 — Time signature control

## Task PR F13.3.4 — Accent control

Support at least:

```text
accent first beat
no accent
```

## Task PR F13.3.5 — Metronome volume

Metronome volume is independent from instrument, backing-track, and loop volume.

## Feature acceptance criteria

The user can configure and control the metronome without leaving the active practice workflow.

---

# Feature PR F13.4 — Metronome-Aware Looping

## Task PR F13.4.1 — Beat and bar boundaries

Expose beat and bar boundaries from the shared transport.

## Task PR F13.4.2 — Optional count-in

Provide an optional one-bar count-in before recording.

## Task PR F13.4.3 — Loop boundary assistance

Allow loop recording to begin and end on a selected beat or bar boundary where practical.

## Task PR F13.4.4 — Preserve free-form looping

The user can still record loops without quantization or a count-in.

## Feature acceptance criteria

The metronome improves timing without forcing tempo-aware behavior on users who want free-form looping.

---

# V0.3 RELEASE GATE

The following workflow must work:

```text
Set BPM
       ↓
Enable metronome
       ↓
Start playback
       ↓
Hear click with live instrument and backing track
       ↓
Record instrument
       ↓
Stop recording
       ↓
Play recording
       ↓
Confirm metronome is not in recording
       ↓
Record loop with optional count-in
       ↓
Play loop with metronome
       ↓
Confirm metronome is not in loop
```

---

# V0.4 — Advanced Practice and Workflow

## Feature scope checklist

- [x] [[#Feature PR F14.1 — Tone Preset Library|F14.1 — Tone Preset Library]]
- [x] [[#Feature PR F14.2 — Effect Chain Editor|F14.2 — Effect Chain Editor]]
- [x] [[#Feature PR F15.1 — Loop Revision History|F15.1 — Loop Revision History]]
- [x] [[#Feature PR F15.2 — Loop Editing Tools|F15.2 — Loop Editing Tools]]
- [x] [[#Feature PR F15.3 — Advanced Loop Synchronization|F15.3 — Advanced Loop Synchronization]]
- [x] [[#Feature PR F16.1 — Count-In and Practice Modes|F16.1 — Count-In and Practice Modes]]
- [x] [[#Feature PR F16.2 — Solo and Routing Controls|F16.2 — Solo and Routing Controls]]
- [x] [[#Feature PR F17.1 — Audio Error Recovery|F17.1 — Audio Error Recovery]]
- [x] [[#Feature PR F17.2 — Performance Instrumentation|F17.2 — Performance Instrumentation]]
- [x] [[#Feature PR F18.1 — Audio Export|F18.1 — Audio Export]]

The following items are intentionally deferred from V0.2 and V0.3. They are valuable, but they are not required to prove the core product loop.

V0.4 should focus on refinement, flexibility, and advanced practice workflows rather than basic audio viability.

---

# Phase 14 — Advanced Tone Preset UX

# Feature PR F14.1 — Tone Preset Library

## Task PR F14.1.1 — Create preset

## Task PR F14.1.2 — Duplicate preset

## Task PR F14.1.3 — Rename preset

## Task PR F14.1.4 — Delete preset

## Task PR F14.1.5 — Favorite preset

## Task PR F14.1.6 — Search and filter presets

---

# Feature PR F14.2 — Effect Chain Editor

## Task PR F14.2.1 — Reordering

Allow processors such as:

```text
EQ
Compressor
Amp
Drive
Modulation
```

to be reordered.

## Task PR F14.2.2 — Enable/bypass

## Task PR F14.2.3 — Processor parameter editor

Build a generic parameter editing system where reasonable.

## Task PR F14.2.4 — Preset comparison

Allow users to compare the current tone with the saved preset.

## Feature acceptance criteria

Users can build, organize, and edit reusable tone chains without changing the underlying audio architecture.

---

# Phase 15 — Advanced Loop Editing

# Feature PR F15.1 — Loop Revision History

## Task PR F15.1.1 — Loop revisions

```text
LoopRevision 1
LoopRevision 2
LoopRevision 3
```

## Task PR F15.1.2 — Undo last overdub

Move backward one revision without deleting the entire loop.

## Task PR F15.1.3 — Redo overdub

Restore a previously removed revision.

---

# Feature PR F15.2 — Loop Editing Tools

## Task PR F15.2.1 — Trim loop

## Task PR F15.2.2 — Crop loop

## Task PR F15.2.3 — Duplicate loop

## Task PR F15.2.4 — Rename loop

## Task PR F15.2.5 — Export loop

## Task PR F15.2.6 — Replace loop audio

---

# Feature PR F15.3 — Advanced Loop Synchronization

## Task PR F15.3.1 — Quantized recording

Quantize loop start and end to beats or bars.

## Task PR F15.3.2 — Loop length selection

Support one-bar, two-bar, four-bar, and free-form loop lengths.

## Task PR F15.3.3 — Tempo changes

Define behavior when BPM changes after loops have been recorded.

## Task PR F15.3.4 — Time stretching

Evaluate whether loops should follow tempo changes without changing pitch.

## Feature acceptance criteria

Users can create rhythmically consistent loops and modify tempo without losing musical alignment.

---

# Phase 16 — Advanced Practice Features

# Feature PR F16.1 — Count-In and Practice Modes

## Task PR F16.1.1 — Configurable count-in

Support one-, two-, and four-bar count-ins.

## Task PR F16.1.2 — Pre-roll

Play a configurable amount of backing material before recording begins.

## Task PR F16.1.3 — Practice sections

Mark and repeat a selected section of a backing track.

## Task PR F16.1.4 — Speed control

Allow backing tracks to play slower or faster where technically practical.

---

# Feature PR F16.2 — Solo and Routing Controls

## Task PR F16.2.1 — Solo loops

## Task PR F16.2.2 — Solo backing track

## Task PR F16.2.3 — Monitor-only controls

Allow a source to be heard without being included in a selected recording path.

## Task PR F16.2.4 — Dry/wet recording options

Support optional dry and processed recordings.

---

# Phase 17 — Reliability and Diagnostics

These items are useful throughout development but can be exposed as a complete user-facing feature in V0.4.

# Feature PR F17.1 — Audio Error Recovery

Task PRs:

```text
F17.1.1 USB disconnect recovery
F17.1.2 route change recovery
F17.1.3 interruption recovery
F17.1.4 media services reset recovery
F17.1.5 invalid audio format recovery
```

---

# Feature PR F17.2 — Performance Instrumentation

## Task PR F17.2.1 — Render performance counters

Watch for audio render failures.

## Task PR F17.2.2 — CPU measurements

Measure processing load during:

```text
monitoring
recording
backing playback
metronome playback
multiple loops
```

## Task PR F17.2.3 — Latency diagnostics

Provide a debug screen showing:

```text
Sample rate
IO buffer
Input latency
Output latency
Reported total latency
Input channels
Output channels
```

## Task PR F17.2.4 — Glitch reporting

Record and surface audio underruns or render failures for debugging.

---

# Phase 18 — Export and Sharing

# Feature PR F18.1 — Audio Export

## Task PR F18.1.1 — Export recording

## Task PR F18.1.2 — Export loop

## Task PR F18.1.3 — Export mixed session

## Task PR F18.1.4 — Share sheet integration

## Task PR F18.1.5 — Export format selection

Support a small set of practical formats.

---

# V0.4 RELEASE GATE

V0.4 is complete when the app supports a polished advanced practice workflow:

```text
Open session
       ↓
Choose tone preset
       ↓
Load backing track
       ↓
Set tempo and count-in
       ↓
Create synchronized loops
       ↓
Overdub with undo
       ↓
Edit, mute, solo, and reorder loops
       ↓
Practice a selected backing-track section
       ↓
Adjust playback speed
       ↓
Export a recording or loop
       ↓
Recover gracefully from common audio-route failures
```

---

# Deferred Work Summary

The following items are intentionally moved out of V0.2:

## Moved to V0.3

- metronome;
- BPM;
- time signature;
- click scheduling;
- count-in;
- beat and bar boundaries;
- metronome exclusion from recordings;
- metronome-aware loop assistance.

## Moved to V0.4

- tone preset library management;
- generic effect-chain editor;
- advanced processor parameter editing;
- solo controls;
- loop revision history;
- undo and redo for overdubs;
- loop trimming and cropping;
- loop duplication and export;
- quantized loop recording;
- selectable loop lengths;
- tempo changes;
- time stretching;
- advanced count-in and pre-roll;
- practice sections;
- playback speed control;
- dry/wet recording options;
- advanced routing;
- user-facing diagnostics;
- audio export and sharing.

## Kept as ongoing engineering work

These should not wait for V0.4 if they are needed for stability:

- USB disconnect recovery;
- route-change recovery;
- interruption recovery;
- media-services reset recovery;
- basic performance monitoring;
- basic latency diagnostics;
- automated tests for recording-path separation.

---

# Recommended Merge Order

The critical path is:

```text
F0.1 Project Foundation
 │
 ▼
F1.1 Audio Session
 │
 ▼
F1.2 Audio Engine
 │
 ├──────────────┐
 ▼              ▼
F2.1 Profiles   F3.1 Gain
                │
                ▼
              F3.2 EQ
                │
                ▼
              F3.3 Effect Chain
                │
 ┌──────────────┴───────────────┐
 ▼                              ▼
F4.1 Recording               F5.1 Import
                                │
                                ▼
                             F5.2 Playback
 └──────────────┬───────────────┘
                ▼
             F6.1 Mixer
                │
                ▼
             F7.1 Sessions
                │
                ▼
             F7.2 Library
                │
             V0.1
                │
                ▼
             F8.1 Transport
                │
                ▼
             F9.1 Single Loop
                │
                ▼
             F9.2 Multi-loop
                │
                ▼
             F9.3 Basic Overdub
                │
                ▼
             F10.1 Loop Alignment
                │
                ▼
             F11.1 Loop Persistence
                │
                ▼
             F12.1 Looper UI
                │
             V0.2
                │
                ▼
             F13.1 Metronome Clock
                │
                ▼
             F13.2 Playback-only Routing
                │
                ▼
             F13.3 Metronome Controls
                │
                ▼
             F13.4 Metronome-aware Looping
                │
             V0.3
                │
       ┌────────┼─────────┬─────────┐
       ▼        ▼         ▼         ▼
   F14 Tone  F15 Loops  F16 Practice F17 Reliability
       │        │         │         │
       └────────┴─────────┴─────────┘
                    │
                    ▼
                 F18 Export
                    │
                 V0.4
```

---

# Parallelizable Work

Once the audio engine is stable, these streams can proceed independently:

```text
STREAM A — DSP
Gain
EQ
Effect chain
Basic presets

STREAM B — Recording
Recorder
File storage
Recording playback

STREAM C — Backing Tracks
Import
Playback
Transport UI

STREAM D — Persistence
Session model
Repository
Library

STREAM E — UI
Session
Tone
Library
```

For V0.2:

```text
STREAM A
Shared transport
Loop engine

STREAM B
Loop file storage
Loop persistence

STREAM C
Looper UI

STREAM D
Basic loop synchronization
```

For V0.3:

```text
STREAM A
Metronome clock

STREAM B
Playback-only metronome routing

STREAM C
Metronome controls

STREAM D
Count-in and loop timing assistance
```

For V0.4:

```text
STREAM A
Advanced tone UX

STREAM B
Advanced loop editing

STREAM C
Practice features

STREAM D
Diagnostics and export
```

Avoid parallelizing changes to the actual `AVAudioEngine` graph until its topology is stable.

---

# PR Naming Convention

Feature branch:

```text
feature/F3-effect-chain
```

Task branches:

```text
task/F3.1-audio-processor-protocol
task/F3.2-gain-node
task/F3.3-eq-node
task/F3.4-chain-routing
```

PR title:

```text
[F3.2] Add parametric EQ processor
```

Commit examples:

```text
audio: add AVAudioUnitEQ wrapper
audio: map EQ configuration to audio unit
test: cover EQ configuration mapping
```

---

# Task PR Template

Every task PR should explicitly contain:

## Goal

One or two sentences describing the change.

## Why

The architectural or product reason.

## Changes

Concrete implementation changes.

## Out of scope

Important things intentionally excluded.

## Test plan

For example:

```text
[ ] Unit tests pass
[ ] App builds
[ ] Tested with built-in mic
[ ] Tested with Cube Baby
[ ] Tested reconnecting the interface
```

## Follow-up

Reference the next task PR.

This makes stacked PR review significantly easier.

---

# Architecture Rule for V0.1–V0.4

One principle should remain strict:

```text
UI
does NOT know
about AVAudioEngine topology.
```

Instead:

```text
SwiftUI
   ↓
Feature Model
   ↓
Audio Engine API
   ↓
Audio Graph
```

For example:

```swift
audioEngine.selectInput(...)
audioEngine.setInputProfile(...)
audioEngine.applyPreset(...)
audioEngine.startRecording(...)
audioEngine.playBackingTrack(...)
audioEngine.createLoop(...)
audioEngine.setMetronome(...)
```

rather than:

```swift
view.audioEngine.attach(...)
view.audioEngine.connect(...)
```

The recording path must remain explicitly separate from playback-only sources:

```text
Instrument
    ↓
Effects
    ↓
Recording tap
    ↓
Instrument recording
    ↓
Playback mixer
```

Playback-only sources such as the metronome must be connected after the recording tap:

```text
Instrument recording ─────┐
Backing track ────────────┤
Loops ────────────────────┤
Metronome ────────────────┤
                          ▼
                        Output
```

This boundary will become particularly valuable when future versions introduce custom DSP, amp transfer functions, cabinet simulation, and more advanced routing.

---

# Expected state at the end of V0.2

The application is a reliable basic looping practice tool:

```text
               BASS / GUITAR
                     │
                     ▼
              INPUT PROFILE
                     │
                     ▼
                TONE CHAIN
                     │
          ┌──────────┴───────────┐
          │                      │
          ▼                      ▼
       RECORDER                LOOPER
                                 │
                     ┌───────────┼───────────┐
                     ▼           ▼           ▼
                   Loop 1      Loop 2      Loop N
                     │           │           │
                     └───────────┼───────────┘
                                 │
BACKING TRACK ───────────────────┤
                                 ▼
                              MIXER
                                 │
                                 ▼
                              OUTPUT
```

The user can record, repeat, layer, mute, clear, save, and restore loops.

---

# Expected state at the end of V0.3

The playback system includes a metronome while the recording system remains isolated from it:

```text
Instrument ────────┐
                   ▼
                Effects
                   │
                   ├── Recording tap ── Instrument recording
                   │
                   ▼
             Playback mixer ◄── Backing track
                   ▲
                   ├── Loops
                   └── Metronome
                   │
                   ▼
                 Output
```

The metronome is available during playback and practice but is never captured in instrument or loop recordings.

---

# Expected state at the end of V0.4

The application is a more complete practice workstation:

```text
               BASS / GUITAR
                     │
                     ▼
              INPUT PROFILE
                     │
                     ▼
              EDITABLE TONE CHAIN
                     │
          ┌──────────┴───────────┐
          │                      │
          ▼                      ▼
       RECORDER                LOOPER
                                 │
                     ┌───────────┼───────────┐
                     ▼           ▼           ▼
              EDITABLE LOOP  EDITABLE LOOP  EDITABLE LOOP
                     │           │           │
                     └───────────┼───────────┘
                                 │
BACKING TRACK ───────────────────┤
METRONOME ───────────────────────┤
                                 ▼
                              MIXER
                                 │
                                 ▼
                              OUTPUT
                                 │
                                 ▼
                         EXPORT / SHARE
```

V0.4 improves control and workflow without changing the core separation between live input, recording, playback, looping, and metronome routing.

One thing I’d strongly preserve from this plan is **F8.1 Shared Transport before implementing the looper**. It may seem like extra infrastructure, but it prevents the classic situation where backing tracks, recordings, and loops each develop their own notion of time and synchronization becomes a rewrite later.

For actual implementation, I’d start with **F0 → F1.1 → F1.2 and make the first hardware milestone “hear the Cube Baby through the app reliably.”** Everything after that can build on a known-good audio foundation.
