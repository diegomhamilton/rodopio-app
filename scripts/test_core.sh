#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
binary="$(mktemp -t ciranda-tests.XXXXXX)"
trap 'rm -f "$binary"' EXIT
cc -Wall -Wextra -Werror -std=c11 Core/TimingCore.c Tests/timing_tests.c -lm -o "$binary"
"$binary"

cc -Wall -Wextra -Werror -std=c11 Core/LiveInputCore.c Tests/live_input_tests.c -lm -o "$binary"
"$binary"
cc -Wall -Wextra -Werror -std=c11 Core/LiveInputCore.c Tests/input_concurrency_tests.c -lm -pthread -o "$binary"
"$binary"

cc -Wall -Wextra -Werror -std=c11 Core/RouteTransition.c Tests/route_transition_tests.c -lm -o "$binary"
"$binary"

cc -Wall -Wextra -Werror -std=c11 Core/DebugCapture.c Core/NoteDisplay.c Tests/debug_capture_tests.c -lm -o "$binary"
"$binary"

cc -O2 -Wall -Wextra -Werror -std=c11 Core/LiveInputCore.c Tests/sixteenth_input_tests.c -lm -o "$binary"
"$binary"

cc -O2 -Wall -Wextra -Werror -std=c11 Core/AudioStreamCore.c Tests/audio_stream_tests.c -lm -pthread -o "$binary"
"$binary"
