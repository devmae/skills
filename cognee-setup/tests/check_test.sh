#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd -P)/scripts/check.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cognee-check.XXXXXX")"
PROJECT="$TEST_ROOT/project"
FAKE_HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p \
  "$PROJECT/.agents" \
  "$FAKE_HOME/.claude/plugins/marketplaces/cognee" \
  "$FAKE_HOME/.gemini/config" \
  "$FAKE_BIN"

cat > "$PROJECT/.envrc" <<'EOF'
export COGNEE_BASE_URL="https://kimtaehwan-macmini.tail9f3ac8.ts.net/"
export COGNEE_MCP_URL="https://cognee.example/mcp"
export COGNEE_SERVICE_URL="${COGNEE_BASE_URL}"
export COGNEE_PLUGIN_DATASET="project"
export COGNEE_API_KEY="fixture-secret"

if [ -f .envrc.local ]; then
  source .envrc.local
fi
EOF

cat > "$PROJECT/.envrc.local" <<'EOF'
export LLM_API_KEY="fixture-llm-secret"
EOF

cat > "$PROJECT/opencode.json" <<'EOF'
{
  "plugin": ["@cognee/cognee-opencode"],
  "mcp": {
    "servers": {
      "cognee": {
        "type": "remote",
        "url": "{env:COGNEE_MCP_URL}"
      }
    }
  }
}
EOF

cat > "$FAKE_HOME/.gemini/config/mcp_config.json" <<'EOF'
{
  "mcpServers": {
    "cognee": {
      "serverUrl": "https://cognee.example/mcp"
    }
  }
}
EOF

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "plugin list") echo "cognee-memory@cognee" ;;
  "mcp list") echo "cognee: connected" ;;
esac
EOF

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "plugin list") echo "cognee@cognee  installed, enabled  1.1.0" ;;
  "features list") echo "hooks stable true" ;;
  "mcp list") echo "cognee  https://cognee.example/mcp  enabled" ;;
esac
EOF

cat > "$FAKE_BIN/opencode" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$FAKE_BIN/claude" "$FAKE_BIN/codex" "$FAKE_BIN/opencode"

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

expect_ok "Claude native remote" --client claude --mode remote
expect_ok "Codex native remote" --client codex --mode remote
expect_ok "OpenCode native remote" --client opencode --mode remote
expect_ok "Claude MCP" --client claude --mode mcp
expect_ok "Codex MCP" --client codex --mode mcp
expect_ok "OpenCode MCP" --client opencode --mode mcp
expect_ok "Antigravity MCP" --client antigravity --mode mcp
expect_ok "native와 MCP hybrid" --client claude,antigravity --mode auto

cp "$PROJECT/.envrc" "$TEST_ROOT/.envrc.valid"
sed 's#https://kimtaehwan-macmini.tail9f3ac8.ts.net/#https://wrong.example/#' \
  "$TEST_ROOT/.envrc.valid" > "$PROJECT/.envrc"
expect_fail_with \
  "고정 Cognee URL과 다른 값 거부" \
  "COGNEE_BASE_URL 값이 맞지 않음" \
  --client claude \
  --mode remote

sed 's/COGNEE_PLUGIN_DATASET="project"/COGNEE_PLUGIN_DATASET="wrong"/' \
  "$TEST_ROOT/.envrc.valid" > "$PROJECT/.envrc"
expect_fail_with \
  "프로젝트 폴더명과 다른 dataset 거부" \
  "COGNEE_PLUGIN_DATASET 값이 맞지 않음" \
  --client claude \
  --mode remote
cp "$TEST_ROOT/.envrc.valid" "$PROJECT/.envrc"

expect_fail_with \
  "MCP client의 remote mode 거부" \
  "Antigravity와 generic MCP client는 --mode mcp 또는 hybrid가 필요함" \
  --client antigravity \
  --mode remote

expect_fail_with \
  "native client만 둔 hybrid 거부" \
  "hybrid mode는 native client와 MCP client가 모두 필요함" \
  --client claude,codex \
  --mode hybrid

expect_fail_with \
  "빈 client 목록 거부" \
  "--client에 하나 이상의 client가 필요함" \
  --client "" \
  --mode remote

cat > "$FAKE_HOME/.gemini/config/mcp_config.json" <<'EOF'
{
  "mcpServers": {
    "cognee": {}
  }
}
EOF

expect_fail_with \
  "Antigravity transport 누락 거부" \
  "serverUrl 또는 command가 필요함" \
  --client antigravity \
  --mode mcp

cat > "$FAKE_HOME/.gemini/config/mcp_config.json" <<'EOF'
{
  "mcpServers": {
    "cognee": {
      "serverUrl": "not-a-url"
    }
  }
}
EOF

expect_fail_with \
  "Antigravity 잘못된 URL 거부" \
  "serverUrl은 http 또는 https 절대 URL이어야 함" \
  --client antigravity \
  --mode mcp

rm "$FAKE_HOME/.gemini/config/mcp_config.json"
cat > "$PROJECT/.agents/mcp_config.json" <<'EOF'
{
  "mcpServers": {
    "cognee": {
      "serverUrl": "https://cognee.example/mcp"
    }
  }
}
EOF

expect_fail_with \
  "Antigravity project-local 비지원" \
  "Antigravity Cognee MCP 설정 없음" \
  --client antigravity \
  --mode mcp

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_BIN/claude"

expect_fail_with \
  "marketplace source를 설치로 오판하지 않음" \
  "Claude cognee-memory plugin 미설치" \
  --client claude \
  --mode remote

echo "RESULT OK — check.sh fixture tests passed"
