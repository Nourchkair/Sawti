# The canonical paths used by the Sawti app and its development E2E drivers.
#
# AppPaths resolves normal app data under the current user's Application Support
# and Downloads directories. When SAWTI_TEST_HOME is supplied to a dev app, its
# owner-only data and output paths are redirected under that isolated test home.
# The bundle's UserDefaults remain managed by macOS and are handled separately
# by the E2E drivers' snapshot/restore helpers.
#
# Source this file after setting HOME. No directories are created here.

if [ -n "${SAWTI_TEST_HOME:-}" ]; then
    # AppPaths standardizes file-URL syntax but preserves the caller's logical
    # `/var/folders` spelling rather than resolving it to `/private/var/folders`.
    # Match the app path while collapsing a possible `//` from TMPDIR.
    _SAWTI_PATHS_HOME="$(cd "$SAWTI_TEST_HOME" 2>/dev/null && pwd -L)" \
        || _SAWTI_PATHS_HOME="$SAWTI_TEST_HOME"
else
    _SAWTI_PATHS_HOME="$HOME"
fi
SAWTI_APP_SUPPORT_DIR="$_SAWTI_PATHS_HOME/Library/Application Support/Sawti"
SAWTI_RECORDINGS_DIR="$SAWTI_APP_SUPPORT_DIR/recordings"
SAWTI_RPC_TOKEN_FILE="$SAWTI_APP_SUPPORT_DIR/.rpc-token"
SAWTI_OUTPUT_DIR="$_SAWTI_PATHS_HOME/Downloads/Sawti"
SAWTI_OUTPUT_RECORDINGS_DIR="$SAWTI_OUTPUT_DIR/recordings"
SAWTI_OUTPUT_PROTOCOLS_DIR="$SAWTI_OUTPUT_DIR/protocols"

# Launch the dev app through LaunchServices with the same test home the shell
# driver uses for token and output paths. A shell-only export is not reliably
# inherited by GUI apps launched through `open`; without this explicit env,
# the app writes its token to the real user profile while the test polls the
# disposable one. Additional `open` flags may be passed after the bundle path
# to this helper.
sawti_open_app() {
    local app_path="$1"
    shift

    if [ -n "${SAWTI_TEST_HOME:-}" ]; then
        open -n --env "SAWTI_TEST_HOME=$SAWTI_TEST_HOME" "$@" "$app_path"
    else
        # Preserve each caller's pre-existing LaunchServices behavior when no
        # isolated home is requested (notably run_app.sh's wait-for-exit mode).
        open "$@" "$app_path"
    fi
}
