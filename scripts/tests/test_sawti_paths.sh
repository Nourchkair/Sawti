#!/usr/bin/env bash
# Verify that live E2E drivers follow Sawti's app-owned data namespace and can
# be redirected into an isolated home without touching Meeting Transcriber.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PATHS_FILE="$REPO_ROOT/scripts/lib/sawti-paths.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sawti-paths-test.XXXXXX")"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

FAILED=0
run_test() {
    local name="$1"
    printf '%s ... ' "$name"
    if "$name"; then printf 'PASS\n'; else printf 'FAIL\n'; FAILED=1; fi
}

resolved_paths() {
    local home="$1" test_home="${2:-}"
    if [ -n "$test_home" ]; then
        HOME="$home" SAWTI_TEST_HOME="$test_home" bash -c '
            source "$1"
            printf "%s\n" "$SAWTI_APP_SUPPORT_DIR" "$SAWTI_RECORDINGS_DIR" \
                "$SAWTI_RPC_TOKEN_FILE" "$SAWTI_OUTPUT_DIR" \
                "$SAWTI_OUTPUT_RECORDINGS_DIR" "$SAWTI_OUTPUT_PROTOCOLS_DIR"
        ' _ "$PATHS_FILE"
    else
        HOME="$home" env -u SAWTI_TEST_HOME bash -c '
            source "$1"
            printf "%s\n" "$SAWTI_APP_SUPPORT_DIR" "$SAWTI_RECORDINGS_DIR" \
                "$SAWTI_RPC_TOKEN_FILE" "$SAWTI_OUTPUT_DIR" \
                "$SAWTI_OUTPUT_RECORDINGS_DIR" "$SAWTI_OUTPUT_PROTOCOLS_DIR"
        ' _ "$PATHS_FILE"
    fi
}

test_default_paths_use_sawti_namespace() {
    local home="$TMP_ROOT/user home" got expected
    got="$(resolved_paths "$home")"
    expected="$home/Library/Application Support/Sawti
$home/Library/Application Support/Sawti/recordings
$home/Library/Application Support/Sawti/.rpc-token
$home/Downloads/Sawti
$home/Downloads/Sawti/recordings
$home/Downloads/Sawti/protocols"
    [ "$got" = "$expected" ]
}

test_test_home_redirects_all_app_owned_paths() {
    local home="$TMP_ROOT/user home" test_home="$TMP_ROOT/isolated home" canonical_test_home got expected
    mkdir -p "$test_home"
    canonical_test_home="$(cd "$test_home" && pwd -L)"
    got="$(resolved_paths "$home" "$test_home")"
    expected="$canonical_test_home/Library/Application Support/Sawti
$canonical_test_home/Library/Application Support/Sawti/recordings
$canonical_test_home/Library/Application Support/Sawti/.rpc-token
$canonical_test_home/Downloads/Sawti
$canonical_test_home/Downloads/Sawti/recordings
$canonical_test_home/Downloads/Sawti/protocols"
    [ "$got" = "$expected" ]
}

test_launch_passes_test_home_through_launchservices() {
    local fake_bin="$TMP_ROOT/fake-bin" capture="$TMP_ROOT/open-args" got expected
    mkdir -p "$fake_bin"
    mkdir -p "$TMP_ROOT/isolated home"
    cat > "$fake_bin/open" <<'OPEN_STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$OPEN_CAPTURE"
OPEN_STUB
    chmod +x "$fake_bin/open"
    OPEN_CAPTURE="$capture" PATH="$fake_bin:$PATH" \
        HOME="$TMP_ROOT/user home" SAWTI_TEST_HOME="$TMP_ROOT/isolated home" \
        bash -c 'source "$1"; sawti_open_app "/Applications/Sawti Dev.app" -g --env EXTRA_FLAG=1' _ "$PATHS_FILE"
    got="$(cat "$capture")"
    expected="-n
--env
SAWTI_TEST_HOME=$TMP_ROOT/isolated home
-g
--env
EXTRA_FLAG=1
/Applications/Sawti Dev.app"
    [ "$got" = "$expected" ]
}

test_launch_preserves_caller_flags_without_test_home() {
    local fake_bin="$TMP_ROOT/fake-bin-plain" capture="$TMP_ROOT/open-args-plain" got expected
    mkdir -p "$fake_bin"
    cat > "$fake_bin/open" <<'OPEN_STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$OPEN_CAPTURE"
OPEN_STUB
    chmod +x "$fake_bin/open"
    OPEN_CAPTURE="$capture" PATH="$fake_bin:$PATH" \
        HOME="$TMP_ROOT/user home" env -u SAWTI_TEST_HOME \
        bash -c 'source "$1"; sawti_open_app "/Applications/Sawti.app" -W' _ "$PATHS_FILE"
    got="$(cat "$capture")"
    expected="-W
/Applications/Sawti.app"
    [ "$got" = "$expected" ]
}

run_test test_default_paths_use_sawti_namespace
run_test test_test_home_redirects_all_app_owned_paths
run_test test_launch_passes_test_home_through_launchservices
run_test test_launch_preserves_caller_flags_without_test_home

exit "$FAILED"
