#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PICKER="$(cd "$SCRIPT_DIR/.." && pwd -P)/scripts/pick-project-folder.mjs"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cognee-picker.XXXXXX")"
PROJECT="$TEST_ROOT/project with spaces"
FAKE_PICKER="$TEST_ROOT/fake-picker"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$PROJECT"
PROJECT="$(cd "$PROJECT" && pwd -P)"

cat > "$FAKE_PICKER" <<'EOF'
#!/usr/bin/env bash
if [ "${PICKER_CANCEL:-0}" -eq 1 ]; then
  exit 130
fi
printf '%s\r\n' "$PICKER_RESULT"
EOF
chmod +x "$FAKE_PICKER"

expect_path() {
  name="$1"
  platform="$2"
  command_var="$3"
  output="$(
    env \
      COGNEE_PICKER_PLATFORM="$platform" \
      "$command_var=$FAKE_PICKER" \
      PICKER_RESULT="$PROJECT" \
      node "$PICKER"
  )"

  if [ "$output" = "$PROJECT" ]; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s — 잘못된 경로: %s\n' "$name" "$output" >&2
    exit 1
  fi
}

expect_path "macOS picker 경로" darwin COGNEE_OSASCRIPT_BIN
expect_path "Windows picker 경로" win32 COGNEE_POWERSHELL_BIN

if env \
  COGNEE_PICKER_PLATFORM=darwin \
  COGNEE_OSASCRIPT_BIN="$FAKE_PICKER" \
  PICKER_CANCEL=1 \
  node "$PICKER" >/dev/null 2>&1; then
  printf 'FAIL  picker 취소 — 성공하면 안 됨\n' >&2
  exit 1
else
  status=$?
  if [ "$status" -ne 130 ]; then
    printf 'FAIL  picker 취소 — exit 130이 아님: %s\n' "$status" >&2
    exit 1
  fi
  printf 'PASS  picker 취소\n'
fi

if env \
  COGNEE_PICKER_PLATFORM=linux \
  node "$PICKER" >/dev/null 2>&1; then
  printf 'FAIL  미지원 OS — 성공하면 안 됨\n' >&2
  exit 1
else
  status=$?
  if [ "$status" -ne 2 ]; then
    printf 'FAIL  미지원 OS — exit 2가 아님: %s\n' "$status" >&2
    exit 1
  fi
  printf 'PASS  미지원 OS\n'
fi

echo "RESULT OK — folder picker tests passed"
