#!/usr/bin/env bash
# Run MeetingTranscriber XCTest workers with a disposable home and verify that
# known real-user data locations were not changed. No file contents are read.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_dir="$repo_root/app/MeetingTranscriber"
temp_root="${TMPDIR:-/tmp}"
if [[ "$temp_root" == "/" ]]; then
    temp_root="/tmp"
else
    temp_root="${temp_root%/}"
fi
real_home="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
test_home="$(mktemp -d "$temp_root/sawti-test-home.XXXXXX")"
guard_dir="$(mktemp -d "$temp_root/sawti-test-guard.XXXXXX")"

cleanup() {
    case "$test_home" in
        "$temp_root"/sawti-test-home.*) rm -rf -- "$test_home" ;;
        *) echo "Refusing to remove unexpected test-home path" >&2 ;;
    esac
    case "$guard_dir" in
        "$temp_root"/sawti-test-guard.*) rm -rf -- "$guard_dir" ;;
        *) echo "Refusing to remove unexpected guard path" >&2 ;;
    esac
}
trap cleanup EXIT

snapshot_real_user_paths() {
    python3 - "$real_home" <<'PY'
import json
import os
import sys

home = sys.argv[1]
records = {}

def metadata(path):
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return None
    return [info.st_mode, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns]

def record_tree(label, relative, recursive):
    root = os.path.join(home, relative)
    records[label] = metadata(root)
    if not os.path.isdir(root):
        return
    if recursive:
        for current, directories, files in os.walk(root, followlinks=False):
            directories.sort()
            files.sort()
            for name in directories + files:
                path = os.path.join(current, name)
                rel = os.path.relpath(path, root)
                records[label + "/" + rel] = metadata(path)
    else:
        try:
            names = sorted(os.listdir(root))
        except OSError:
            records[label + "/<unreadable>"] = None
            return
        for name in names:
            records[label + "/" + name] = metadata(os.path.join(root, name))

record_tree("sawti-app-ipc", "Library/Application Support/Sawti/ipc", True)
record_tree("legacy-sawti-ipc", ".sawti", True)
record_tree("meeting-transcriber-app-ipc", "Library/Application Support/MeetingTranscriber/ipc", True)
record_tree("legacy-meeting-transcriber-ipc", ".meeting-transcriber", True)

print(json.dumps(records, sort_keys=True, separators=(",", ":")))
PY
}

snapshot_real_user_paths > "$guard_dir/before.json"

test_args=("$@")
if [[ "${SAWTI_RUN_MODEL_PRELOAD_TESTS:-0}" != "1" ]]; then
    # These tests download ASR/VAD models from Hugging Face on a cold cache.
    test_args+=(--skip ModelPreloadTests)
fi

test_status=0
(
    cd "$package_dir"
    # Avoid running a user-selected ffmpeg executable from the host environment.
    HOME="$test_home" \
        CFFIXED_USER_HOME="$test_home" \
        SAWTI_TEST_HOME="$test_home" \
        FFMPEG_BINARY="" \
        swift test --parallel "${test_args[@]}"
) || test_status=$?

snapshot_real_user_paths > "$guard_dir/after.json"
if ! cmp -s "$guard_dir/before.json" "$guard_dir/after.json"; then
    changed_categories="$(python3 - "$guard_dir/before.json" "$guard_dir/after.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as before_file:
    before = json.load(before_file)
with open(sys.argv[2], encoding="utf-8") as after_file:
    after = json.load(after_file)
changed = [key for key in set(before) | set(after) if before.get(key) != after.get(key)]
print(", ".join(sorted({key.split("/", 1)[0] for key in changed})))
PY
)"
    echo "Test isolation guard failed: protected real-user IPC metadata changed ($changed_categories)." >&2
    exit 1
fi

exit "$test_status"
