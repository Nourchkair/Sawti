#!/usr/bin/env bash
# The capture-onset lane must refuse to run unless it can isolate app audio and
# verify a record-only capture before the delayed fixture begins.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DRIVER="$REPO_ROOT/scripts/e2e-app.sh"
FAILED=0

expect_refusal() {
    local name="$1" expected="$2"
    shift 2
    printf '%s ... ' "$name"
    local output status
    output="$(bash "$DRIVER" "$@" 2>&1)"
    status=$?
    if [ "$status" -eq 2 ] && [[ "$output" == *"$expected"* ]]; then
        printf 'PASS\n'
    else
        printf 'FAIL (status=%s, output=%s)\n' "$status" "$output"
        FAILED=1
    fi
}

expect_refusal 'playback delay requires record-only and no-mic' \
    'requires --no-mic plus --record-only or --reimport-recorded' --playback-delay 10
expect_refusal 'playback delay requires a whole number' \
    'requires a non-negative whole number' --record-only --no-mic --playback-delay 1.5
expect_refusal 'playback delay requires an argument' \
    'requires a non-negative whole number' --record-only --no-mic --playback-delay
expect_refusal 'playback delay leaves time to observe capture first' \
    'must be at least 2 seconds' --record-only --no-mic --playback-delay 1
expect_refusal 'playback delay is bounded' \
    'must be at most 120 seconds' --record-only --no-mic --playback-delay 121
expect_refusal 'playback delay is incompatible with reimport-latest' \
    'requires --no-mic plus --record-only or --reimport-recorded' \
    --record-only --no-mic --reimport-latest --playback-delay 10
expect_refusal 'completeness floor is bound to the measured default fixture' \
    'calibrated only for the default two_speakers_de fixture' \
    --record-only --no-mic --playback-delay 10 \
    --fixture "$REPO_ROOT/app/MeetingTranscriber/Tests/Fixtures/quality/two_speakers_de.wav"

exit "$FAILED"
