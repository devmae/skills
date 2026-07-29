#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd -P)/scripts/check.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cognee-check.XXXXXX")"
PROJECT="$TEST_ROOT/project"
FAKE_HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
NODE_BIN="$(node -p 'process.execPath')"
FIXED_URL="https://kimtaehwan-macmini.tail9f3ac8.ts.net/"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p \
  "$PROJECT/.agents" \
  "$FAKE_HOME/.codex" \
  "$FAKE_HOME/.config/opencode" \
  "$FAKE_HOME/.gemini/config" \
  "$FAKE_BIN"

cat > "$FAKE_HOME/.config/opencode/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "cognee": {
        "type": "local",
        "command": [
          "uvx",
          "cognee-mcp",
          "--api-url",
          "$FIXED_URL"
        ]
      }
    }
  }
}
EOF

cat > "$FAKE_HOME/.codex/config.toml" <<EOF
[mcp_servers.cognee]
command = "uvx"
args = ["cognee-mcp", "--api-url", "$FIXED_URL"]
EOF

cat > "$FAKE_HOME/.gemini/config/mcp_config.json" <<EOF
{
  "mcpServers": {
    "cognee": {
      "command": "uvx",
      "args": [
        "cognee-mcp",
        "--api-url",
        "$FIXED_URL"
      ]
    }
  }
}
EOF

cat > "$FAKE_HOME/mcp.json" <<EOF
{
  "mcpServers": {
    "cognee": {
      "command": "uvx",
      "args": [
        "cognee-mcp",
        "--api-url",
        "$FIXED_URL"
      ]
    }
  }
}
EOF

cat > "$FAKE_BIN/claude" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "mcp get cognee")
    echo "Scope: \${COGNEE_TEST_CLAUDE_SCOPE:-User}"
    echo "command: uvx"
    echo "args: cognee-mcp --api-url $FIXED_URL"
    ;;
  "plugin list")
    [ "\${COGNEE_TEST_NATIVE_PLUGIN:-0}" = "1" ] && echo "cognee-memory@cognee"
    ;;
esac
EOF

cat > "$FAKE_BIN/codex" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "mcp get cognee")
    echo "command: uvx"
    echo "args: cognee-mcp --api-url $FIXED_URL"
    ;;
  "plugin list")
    [ "\${COGNEE_TEST_NATIVE_PLUGIN:-0}" = "1" ] && echo "cognee@cognee"
    ;;
esac
EOF

cat > "$FAKE_BIN/opencode" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$FAKE_BIN/tailscale" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "status" ]
EOF

cat > "$FAKE_BIN/uvx" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *api/v1/datasets*) printf '%s' "${COGNEE_TEST_DATASETS_CODE:-200}" ;;
  *health*) printf '%s' "${COGNEE_TEST_HEALTH_CODE:-200}" ;;
  *) printf '000' ;;
esac
EOF

cat > "$FAKE_BIN/folder-picker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$COGNEE_PICKER_RESULT"
EOF

cat > "$FAKE_BIN/cygpath" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$COGNEE_CYGPATH_RESULT"
EOF

chmod +x \
  "$FAKE_BIN/claude" \
  "$FAKE_BIN/codex" \
  "$FAKE_BIN/opencode" \
  "$FAKE_BIN/tailscale" \
  "$FAKE_BIN/uvx" \
  "$FAKE_BIN/curl" \
  "$FAKE_BIN/folder-picker" \
  "$FAKE_BIN/cygpath"

run_check() {
  PATH="$FAKE_BIN:/usr/bin:/bin" \
    COGNEE_CHECK_HOME="$FAKE_HOME" \
    bash "$CHECK_SCRIPT" "$PROJECT" "$@"
}

expect_ok() {
  name="$1"
  shift
  if output="$(run_check "$@" 2>&1)"; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n%s\n' "$name" "$output" >&2
    exit 1
  fi
}

expect_fail_with() {
  name="$1"
  pattern="$2"
  shift 2
  if output="$(run_check "$@" 2>&1)"; then
    printf 'FAIL  %s — 실패해야 함\n' "$name" >&2
    exit 1
  fi
  if printf '%s\n' "$output" | grep -Fq -- "$pattern"; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s — 예상 문구 없음: %s\n%s\n' "$name" "$pattern" "$output" >&2
    exit 1
  fi
}

expect_ok "Claude keyless remote" --client claude --mode remote --probe
expect_ok "Codex keyless remote" --client codex --mode remote --probe
expect_ok "OpenCode keyless remote" --client opencode --mode remote --probe
expect_ok "Antigravity keyless remote" --client antigravity --mode remote --probe
expect_ok "generic MCP keyless remote" --client mcp --mcp-config mcp.json --mode remote --probe
expect_ok "all client keyless remote" --client all --mode remote --probe
expect_ok "여러 client keyless remote" --client claude,codex,opencode,antigravity --mode auto --probe
expect_ok "keyless REST probe" --client claude --mode remote --probe

COGNEE_TEST_CLAUDE_SCOPE=Project expect_fail_with \
  "Claude project scope 거부" \
  "Claude Cognee MCP가 user scope에 없음" \
  --client claude \
  --mode remote \
  --probe

mkdir -p "$PROJECT/.codex"
cat > "$PROJECT/.codex/config.toml" <<EOF
[mcp_servers.cognee]
command = "uvx"
args = ["cognee-mcp", "--api-url", "$FIXED_URL"]
EOF
expect_fail_with \
  "Codex project scope 거부" \
  "Codex project-local Cognee 설정이 남아 있음" \
  --client codex \
  --mode remote \
  --probe
rm "$PROJECT/.codex/config.toml"

cat > "$PROJECT/mcp.json" <<EOF
{
  "mcpServers": {
    "cognee": {
      "command": "uvx",
      "args": ["cognee-mcp", "--api-url", "$FIXED_URL"]
    }
  }
}
EOF
expect_fail_with \
  "generic MCP project scope 거부" \
  "generic MCP 설정이 project scope에 있음" \
  --client mcp \
  --mcp-config "$PROJECT/mcp.json" \
  --mode remote \
  --probe
rm "$PROJECT/mcp.json"

if [ ! -e "$PROJECT/.envrc" ] && [ ! -e "$PROJECT/.envrc.local" ]; then
  printf 'PASS  프로젝트 env 파일 불필요\n'
else
  printf 'FAIL  프로젝트 env 파일이 생김\n' >&2
  exit 1
fi

if output="$(
  PATH="$FAKE_BIN:/usr/bin:/bin" \
    COGNEE_CHECK_HOME="$FAKE_HOME" \
    COGNEE_NODE_BIN="$NODE_BIN" \
    COGNEE_PICKER_PLATFORM=darwin \
    COGNEE_OSASCRIPT_BIN="$FAKE_BIN/folder-picker" \
    COGNEE_PICKER_RESULT="$PROJECT" \
    bash "$CHECK_SCRIPT" --pick --client claude --mode remote --probe 2>&1
)"; then
  printf 'PASS  folder picker 선택 경로 검사\n'
else
  printf 'FAIL  folder picker 선택 경로 검사\n%s\n' "$output" >&2
  exit 1
fi

if output="$(
  PATH="$FAKE_BIN:/usr/bin:/bin" \
    COGNEE_CHECK_HOME="$FAKE_HOME" \
    COGNEE_CYGPATH_RESULT="$PROJECT" \
    bash "$CHECK_SCRIPT" 'C:\selected project' --client claude --mode remote --probe 2>&1
)"; then
  printf 'PASS  Windows 경로를 Bash 경로로 변환\n'
else
  printf 'FAIL  Windows 경로를 Bash 경로로 변환\n%s\n' "$output" >&2
  exit 1
fi

expect_fail_with \
  "프로젝트 경로와 picker 동시 지정 거부" \
  "프로젝트 경로와 --pick을 함께 쓸 수 없음" \
  --pick \
  --client claude \
  --mode remote

expect_fail_with \
  "예전 mode 거부" \
  "지원하지 않는 mode: hybrid" \
  --client claude \
  --mode hybrid

expect_fail_with \
  "빈 client 목록 거부" \
  "--client에 하나 이상의 client가 필요함" \
  --client "" \
  --mode remote

expect_fail_with \
  "server probe 생략 거부" \
  "server probe 생략 — --probe가 필요함" \
  --client claude \
  --mode remote

expect_fail_with \
  "generic MCP 설정 파일 필수" \
  "generic MCP client는 --mcp-config가 필요함" \
  --client mcp \
  --mode remote \
  --probe

cat > "$PROJECT/.envrc" <<'EOF'
export COGNEE_BASE_URL="https://legacy.example/"
EOF
cat > "$PROJECT/.envrc.local" <<'EOF'
export COGNEE_API_KEY="legacy-secret-must-not-print"
EOF

if output="$(run_check --client claude --mode remote --probe 2>&1)"; then
  printf 'FAIL  legacy Cognee env를 찾아야 함\n' >&2
  exit 1
elif ! printf '%s\n' "$output" | grep -Fq "legacy Cognee 설정이 남아 있음"; then
  printf 'FAIL  legacy Cognee env 탐지 문구 없음\n%s\n' "$output" >&2
  exit 1
elif printf '%s\n' "$output" | grep -Fq "legacy-secret-must-not-print"; then
  printf 'FAIL  legacy secret이 출력됨\n' >&2
  exit 1
else
  printf 'PASS  legacy Cognee env를 값 출력 없이 탐지\n'
fi
rm "$PROJECT/.envrc" "$PROJECT/.envrc.local"

if output="$(COGNEE_API_KEY="shell-secret-must-not-print" run_check --client claude --mode remote --probe 2>&1)"; then
  printf 'FAIL  shell의 legacy Cognee key를 찾아야 함\n' >&2
  exit 1
elif ! printf '%s\n' "$output" | grep -Fq "현재 shell에 legacy Cognee API key가 남아 있음"; then
  printf 'FAIL  shell의 legacy Cognee key 탐지 문구 없음\n%s\n' "$output" >&2
  exit 1
elif printf '%s\n' "$output" | grep -Fq "shell-secret-must-not-print"; then
  printf 'FAIL  shell의 legacy secret이 출력됨\n' >&2
  exit 1
else
  printf 'PASS  shell의 legacy Cognee key를 값 출력 없이 탐지\n'
fi

mkdir -p "$FAKE_HOME/.cognee-plugin"
printf '{}' > "$FAKE_HOME/.cognee-plugin/api_key.json"
expect_fail_with \
  "native Cognee key cache 탐지" \
  "native Cognee API key cache가 남아 있음" \
  --client claude \
  --mode remote \
  --probe
rm "$FAKE_HOME/.cognee-plugin/api_key.json"

if output="$(
  PATH="$FAKE_BIN:/usr/bin:/bin" \
    COGNEE_CHECK_HOME="$FAKE_HOME" \
    COGNEE_TEST_DATASETS_CODE=401 \
    bash "$CHECK_SCRIPT" "$PROJECT" --client claude --mode remote --probe 2>&1
)"; then
  printf 'FAIL  server 앱 인증을 찾아야 함\n' >&2
  exit 1
elif printf '%s\n' "$output" | grep -Fq "Cognee server 앱 인증이 켜져 있음"; then
  printf 'PASS  server 앱 인증 탐지\n'
else
  printf 'FAIL  server 앱 인증 탐지 문구 없음\n%s\n' "$output" >&2
  exit 1
fi

if output="$(
  PATH="$FAKE_BIN:/usr/bin:/bin" \
    COGNEE_CHECK_HOME="$FAKE_HOME" \
    COGNEE_TEST_NATIVE_PLUGIN=1 \
    bash "$CHECK_SCRIPT" "$PROJECT" --client claude --mode remote 2>&1
)"; then
  printf 'FAIL  native plugin을 찾아야 함\n' >&2
  exit 1
elif printf '%s\n' "$output" | grep -Fq "Claude native Cognee plugin이 남아 있음"; then
  printf 'PASS  native plugin 탐지\n'
else
  printf 'FAIL  native plugin 탐지 문구 없음\n%s\n' "$output" >&2
  exit 1
fi

cp "$FAKE_HOME/.config/opencode/opencode.json" "$TEST_ROOT/opencode.valid.json"
sed "s#$FIXED_URL#https://wrong.example/#" \
  "$TEST_ROOT/opencode.valid.json" > "$FAKE_HOME/.config/opencode/opencode.json"
expect_fail_with \
  "OpenCode의 다른 URL 거부" \
  "OpenCode Cognee MCP 설정 오류: 고정 Cognee URL이 필요함" \
  --client opencode \
  --mode remote \
  --probe
cp "$TEST_ROOT/opencode.valid.json" "$FAKE_HOME/.config/opencode/opencode.json"

cat > "$FAKE_HOME/.config/opencode/opencode.json" <<EOF
{
  "mcp": {
    "servers": {
      "cognee": {
        "type": "local",
        "command": ["wrong-command"]
      },
      "other": {
        "type": "local",
        "command": [
          "uvx",
          "cognee-mcp",
          "--api-url",
          "$FIXED_URL"
        ]
      }
    }
  }
}
EOF

expect_fail_with \
  "다른 OpenCode server 값을 Cognee로 오판하지 않음" \
  "OpenCode Cognee MCP 설정 오류" \
  --client opencode \
  --mode remote \
  --probe
cp "$TEST_ROOT/opencode.valid.json" "$FAKE_HOME/.config/opencode/opencode.json"

cp "$TEST_ROOT/opencode.valid.json" "$PROJECT/opencode.json"
expect_fail_with \
  "OpenCode project scope 거부" \
  "OpenCode project-local Cognee 설정이 남아 있음" \
  --client opencode \
  --mode remote \
  --probe
rm "$PROJECT/opencode.json"

cat > "$FAKE_HOME/.gemini/config/mcp_config.json" <<EOF
{
  "mcpServers": {
    "cognee": {
      "command": "uvx",
      "args": [
        "cognee-mcp",
        "--api-url",
        "$FIXED_URL",
        "--api-token",
        "fixture"
      ]
    }
  }
}
EOF

expect_fail_with \
  "Antigravity token 설정 거부" \
  "인증 key 또는 token을 넣을 수 없음" \
  --client antigravity \
  --mode remote

cat > "$FAKE_HOME/.gemini/config/mcp_config.json" <<EOF
{
  "mcpServers": {
    "cognee": {
      "command": "uvx",
      "args": ["cognee-mcp", "--api-url", "$FIXED_URL"]
    }
  }
}
EOF
cat > "$PROJECT/.agents/mcp_config.json" <<EOF
{
  "mcpServers": {
    "cognee": {
      "command": "uvx",
      "args": ["cognee-mcp", "--api-url", "$FIXED_URL"]
    }
  }
}
EOF

expect_fail_with \
  "Antigravity project scope 거부" \
  "Antigravity project-local Cognee 설정이 남아 있음" \
  --client antigravity \
  --mode remote \
  --probe

echo "RESULT OK — check.sh fixture tests passed"
