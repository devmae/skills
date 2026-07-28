#!/usr/bin/env bash
# Cognee client와 프로젝트별 환경 설정을 검사한다.
# 사용법: check.sh [project-root] [--client NAME[,NAME...]] [--mode auto|remote|local|mcp|hybrid] [--require-tailscale]
set -u

PROJECT_ROOT=""
CLIENT_SPEC="auto"
MODE="auto"
REQUIRE_TAILSCALE=0
FAILED=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=1; }
info() { printf 'INFO  %s\n' "$1"; }

usage() {
  cat <<'EOF'
Usage: check.sh [project-root] [options]

Options:
  --client NAME[,NAME...]  auto, all, claude, codex, opencode, antigravity, mcp
  --mode MODE              auto, remote, local, mcp, hybrid
  --require-tailscale      Tailscale 설치와 연결을 필수로 검사
  -h, --help               도움말 출력
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --client)
      [ "$#" -ge 2 ] || { printf 'ERROR --client 값이 필요함\n' >&2; exit 2; }
      CLIENT_SPEC="$2"
      shift 2
      ;;
    --mode)
      [ "$#" -ge 2 ] || { printf 'ERROR --mode 값이 필요함\n' >&2; exit 2; }
      MODE="$2"
      shift 2
      ;;
    --require-tailscale)
      REQUIRE_TAILSCALE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      printf 'ERROR 알 수 없는 옵션: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$PROJECT_ROOT" ]; then
        printf 'ERROR 프로젝트 루트는 하나만 지정할 수 있음\n' >&2
        exit 2
      fi
      PROJECT_ROOT="$1"
      shift
      ;;
  esac
done

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
if [ ! -d "$PROJECT_ROOT" ]; then
  printf 'ERROR 프로젝트 폴더가 없음: %s\n' "$PROJECT_ROOT" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)"
ENVRC="$PROJECT_ROOT/.envrc"
ENVRC_LOCAL="$PROJECT_ROOT/.envrc.local"
CHECK_HOME="${COGNEE_CHECK_HOME:-$HOME}"
FIXED_COGNEE_BASE_URL="https://kimtaehwan-macmini.tail9f3ac8.ts.net/"
PROJECT_DATASET="$(basename "$PROJECT_ROOT")"

case "$MODE" in
  auto|remote|local|mcp|hybrid) ;;
  *)
    printf 'ERROR 지원하지 않는 mode: %s\n' "$MODE" >&2
    exit 2
    ;;
esac

file_var_value() {
  var_name="$1"
  file_path="$2"
  [ -f "$file_path" ] || return 1

  line="$(grep -E "^[[:space:]]*export[[:space:]]+$var_name=" "$file_path" 2>/dev/null | tail -1)"
  [ -n "$line" ] || return 1

  value="$(printf '%s' "$line" \
    | sed -E "s/^[[:space:]]*export[[:space:]]+$var_name=//" \
    | sed -E 's/[[:space:]]*#.*$//' \
    | sed -E "s/^[\"']//; s/[\"']$//")"
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

check_var_in_file() {
  var_name="$1"
  file_path="$2"
  label="$3"

  if value="$(file_var_value "$var_name" "$file_path")"; then
    pass "$var_name ${label}에 정의됨"
    return 0
  fi

  fail "$var_name 미설정 (${label}에 필요)"
  return 1
}

check_var_equals() {
  var_name="$1"
  file_path="$2"
  label="$3"
  expected="$4"

  if ! value="$(file_var_value "$var_name" "$file_path")"; then
    fail "$var_name 미설정 (${label}에 필요)"
    return 1
  fi

  if [ "$value" = "$expected" ]; then
    pass "$var_name ${label} 값 확인됨"
    return 0
  fi

  fail "$var_name 값이 맞지 않음 (${label}에서 $expected 필요)"
  return 1
}

contains_client() {
  case " $CLIENTS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

add_client() {
  candidate="$1"
  contains_client "$candidate" || CLIENTS="${CLIENTS}${CLIENTS:+ }$candidate"
}

detect_clients() {
  command -v claude >/dev/null 2>&1 && add_client claude
  command -v codex >/dev/null 2>&1 && add_client codex
  if command -v opencode >/dev/null 2>&1 || command -v opencode2 >/dev/null 2>&1; then
    add_client opencode
  fi
  if command -v antigravity >/dev/null 2>&1 \
    || [ -f "$CHECK_HOME/.gemini/config/mcp_config.json" ]; then
    add_client antigravity
  fi
  [ -n "$CLIENTS" ] || add_client mcp
}

has_native_client() {
  contains_client claude || contains_client codex || contains_client opencode
}

has_mcp_client() {
  contains_client antigravity || contains_client mcp
}

CLIENTS=""
if [ "$CLIENT_SPEC" = "auto" ]; then
  detect_clients
elif [ "$CLIENT_SPEC" = "all" ]; then
  CLIENTS="claude codex opencode antigravity mcp"
else
  old_ifs="$IFS"
  IFS=','
  for client in $CLIENT_SPEC; do
    case "$client" in
      claude|codex|opencode|antigravity|mcp) add_client "$client" ;;
      *)
        printf 'ERROR 지원하지 않는 client: %s\n' "$client" >&2
        exit 2
        ;;
    esac
  done
  IFS="$old_ifs"
fi

if [ -z "$CLIENTS" ]; then
  printf 'ERROR --client에 하나 이상의 client가 필요함\n' >&2
  exit 2
fi

if [ "$MODE" = "auto" ]; then
  if has_native_client && has_mcp_client; then
    MODE="hybrid"
  elif file_var_value COGNEE_BASE_URL "$ENVRC" >/dev/null 2>&1 \
    && file_var_value COGNEE_MCP_URL "$ENVRC" >/dev/null 2>&1; then
    MODE="hybrid"
  elif file_var_value COGNEE_BASE_URL "$ENVRC" >/dev/null 2>&1; then
    MODE="remote"
  elif file_var_value COGNEE_MCP_URL "$ENVRC" >/dev/null 2>&1; then
    MODE="mcp"
  elif file_var_value LLM_API_KEY "$ENVRC_LOCAL" >/dev/null 2>&1; then
    MODE="local"
  elif contains_client antigravity || { contains_client mcp && [ "$CLIENTS" = "mcp" ]; }; then
    MODE="mcp"
  else
    MODE="remote"
  fi
  info "mode 자동 선택: $MODE"
fi

info "프로젝트: $PROJECT_ROOT"
info "client: $CLIENTS"
info "mode: $MODE"

if [ "$MODE" = "remote" ] && has_mcp_client; then
  fail "Antigravity와 generic MCP client는 --mode mcp 또는 hybrid가 필요함"
fi

if [ "$MODE" = "hybrid" ] && { ! has_native_client || ! has_mcp_client; }; then
  fail "hybrid mode는 native client와 MCP client가 모두 필요함"
fi

# Tailscale은 private tailnet을 쓸 때만 필수다.
if [ "$REQUIRE_TAILSCALE" -eq 1 ]; then
  TS_BIN=""
  if command -v tailscale >/dev/null 2>&1; then
    TS_BIN="tailscale"
  elif [ -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then
    TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  fi

  if [ -z "$TS_BIN" ]; then
    fail "tailscale 미설치"
  elif "$TS_BIN" status >/dev/null 2>&1; then
    pass "tailscale 연결됨"
    peers="$("$TS_BIN" status 2>/dev/null | awk '$1 ~ /^[0-9]/ && $2 != "" {print $2}' | head -10 | tr '\n' ' ')"
    [ -n "$peers" ] && info "tailnet 머신: $peers"
  else
    fail "tailscale 실행 또는 로그인 필요"
  fi
fi

check_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    fail "Claude Code CLI 미설치"
    return
  fi
  pass "Claude Code CLI 설치됨"

  plugin_output="$(claude plugin list 2>/dev/null || true)"
  if printf '%s\n' "$plugin_output" | grep -Eqi 'cognee-memory(@cognee)?'; then
    pass "Claude cognee-memory plugin 설치됨"
  else
    fail "Claude cognee-memory plugin 미설치"
  fi
}

check_claude_mcp() {
  if ! command -v claude >/dev/null 2>&1; then
    fail "Claude Code CLI 미설치"
    return
  fi
  pass "Claude Code CLI 설치됨"

  mcp_output="$(claude mcp list 2>/dev/null || true)"
  if printf '%s\n' "$mcp_output" | grep -Eqi '(^|[[:space:]])cognee([: ]|$)'; then
    pass "Claude Cognee MCP 설정됨"
  else
    fail "Claude Cognee MCP 설정 없음"
  fi
}

check_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    fail "Codex CLI 미설치"
    return
  fi
  pass "Codex CLI 설치됨"

  plugin_output="$(codex plugin list 2>/dev/null || true)"
  if printf '%s\n' "$plugin_output" | grep -Eqi 'cognee@cognee[[:space:]]+installed,[[:space:]]*enabled'; then
    pass "Codex cognee plugin 설치되고 활성화됨"
  else
    fail "Codex cognee plugin 미설치 또는 비활성"
  fi

  feature_output="$(codex features list 2>/dev/null || true)"
  if printf '%s\n' "$feature_output" | grep -Eq '^hooks[[:space:]].*[[:space:]]true[[:space:]]*$'; then
    pass "Codex hooks 활성화됨"
  else
    fail "Codex hooks 비활성"
  fi
}

check_codex_mcp() {
  if ! command -v codex >/dev/null 2>&1; then
    fail "Codex CLI 미설치"
    return
  fi
  pass "Codex CLI 설치됨"

  mcp_output="$(codex mcp list 2>/dev/null || true)"
  if printf '%s\n' "$mcp_output" | grep -Eqi '^cognee([[:space:]]|$)'; then
    pass "Codex Cognee MCP 설정됨"
  else
    fail "Codex Cognee MCP 설정 없음"
  fi
}

check_opencode() {
  if command -v opencode >/dev/null 2>&1; then
    pass "OpenCode CLI 설치됨 (opencode)"
  elif command -v opencode2 >/dev/null 2>&1; then
    pass "OpenCode CLI 설치됨 (opencode2)"
  else
    fail "OpenCode CLI 미설치"
  fi

  config_found=0
  for config_path in \
    "$PROJECT_ROOT/opencode.json" \
    "$PROJECT_ROOT/opencode.jsonc" \
    "$PROJECT_ROOT/.opencode/opencode.json" \
    "$CHECK_HOME/.config/opencode/opencode.json"; do
    if [ -f "$config_path" ] && grep -Fq '@cognee/cognee-opencode' "$config_path"; then
      pass "OpenCode Cognee plugin 설정됨 ($config_path)"
      config_found=1
      break
    fi
  done
  [ "$config_found" -eq 1 ] || fail "OpenCode Cognee plugin 설정 없음"
}

check_opencode_mcp() {
  if command -v opencode >/dev/null 2>&1; then
    pass "OpenCode CLI 설치됨 (opencode)"
  elif command -v opencode2 >/dev/null 2>&1; then
    pass "OpenCode CLI 설치됨 (opencode2)"
  else
    fail "OpenCode CLI 미설치"
  fi

  config_found=0
  for config_path in \
    "$PROJECT_ROOT/opencode.json" \
    "$PROJECT_ROOT/opencode.jsonc" \
    "$PROJECT_ROOT/.opencode/opencode.json" \
    "$CHECK_HOME/.config/opencode/opencode.json"; do
    if [ -f "$config_path" ] \
      && grep -Eq '"mcp"[[:space:]]*:' "$config_path" \
      && grep -Eqi '"cognee"[[:space:]]*:' "$config_path"; then
      pass "OpenCode Cognee MCP 설정됨 ($config_path)"
      config_found=1
      break
    fi
  done
  [ "$config_found" -eq 1 ] || fail "OpenCode Cognee MCP 설정 없음"
}

validate_antigravity_config() {
  config_path="$1"

  if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3가 없어 JSON을 검사할 수 없음'
    return 1
  fi

  python3 - "$config_path" <<'PY'
import json
import sys
from urllib.parse import urlparse

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as file:
        config = json.load(file)
except (OSError, json.JSONDecodeError):
    print("JSON 형식 오류")
    raise SystemExit(1)

if not isinstance(config, dict):
    print("최상위 JSON 객체가 필요함")
    raise SystemExit(1)

servers = config.get("mcpServers")
server = servers.get("cognee") if isinstance(servers, dict) else None
if not isinstance(server, dict):
    print("mcpServers.cognee 객체가 필요함")
    raise SystemExit(1)

server_url = server.get("serverUrl")
command = server.get("command")
has_command = isinstance(command, str) and bool(command.strip())
has_url = isinstance(server_url, str) and bool(server_url.strip())

if has_url:
    parsed = urlparse(server_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        print("serverUrl은 http 또는 https 절대 URL이어야 함")
        raise SystemExit(1)

if not has_url and not has_command:
    print("serverUrl 또는 command가 필요함")
    raise SystemExit(1)
PY
}

check_antigravity() {
  if command -v antigravity >/dev/null 2>&1; then
    pass "Antigravity CLI 설치됨"
  else
    info "Antigravity CLI는 찾지 못함 — IDE만 쓸 수 있음"
  fi

  config_path="$CHECK_HOME/.gemini/config/mcp_config.json"
  if [ ! -f "$config_path" ]; then
    fail "Antigravity Cognee MCP 설정 없음 ($config_path)"
    return
  fi

  if validation_error="$(validate_antigravity_config "$config_path" 2>&1)"; then
    pass "Antigravity Cognee MCP 설정됨 ($config_path)"
  else
    fail "Antigravity Cognee MCP 설정 오류 ($config_path): $validation_error"
  fi
}

for client in $CLIENTS; do
  case "$client" in
    claude)
      if [ "$MODE" = "mcp" ]; then check_claude_mcp; else check_claude; fi
      ;;
    codex)
      if [ "$MODE" = "mcp" ]; then check_codex_mcp; else check_codex; fi
      ;;
    opencode)
      if [ "$MODE" = "mcp" ]; then check_opencode_mcp; else check_opencode; fi
      ;;
    antigravity) check_antigravity ;;
    mcp) info "generic MCP client는 client별 설정과 연결 상태를 따로 확인해야 함" ;;
  esac
done

for var_name in COGNEE_BASE_URL COGNEE_MCP_URL COGNEE_API_KEY COGNEE_MCP_BEARER_TOKEN COGNEE_PLUGIN_DATASET LLM_API_KEY; do
  if [ -n "$(printenv "$var_name" 2>/dev/null || true)" ]; then
    info "현재 shell의 $var_name 값은 판정에서 제외함"
  fi
done

case "$MODE" in
  remote)
    check_var_equals COGNEE_BASE_URL "$ENVRC" ".envrc" "$FIXED_COGNEE_BASE_URL"
    check_var_equals COGNEE_PLUGIN_DATASET "$ENVRC" ".envrc" "$PROJECT_DATASET"
    check_var_in_file COGNEE_API_KEY "$ENVRC_LOCAL" ".envrc.local"
    if contains_client opencode; then
      check_var_in_file COGNEE_SERVICE_URL "$ENVRC" ".envrc"
    fi
    ;;
  hybrid)
    check_var_equals COGNEE_BASE_URL "$ENVRC" ".envrc" "$FIXED_COGNEE_BASE_URL"
    check_var_in_file COGNEE_MCP_URL "$ENVRC" ".envrc"
    check_var_equals COGNEE_PLUGIN_DATASET "$ENVRC" ".envrc" "$PROJECT_DATASET"
    check_var_in_file COGNEE_API_KEY "$ENVRC_LOCAL" ".envrc.local"
    if contains_client opencode; then
      check_var_in_file COGNEE_SERVICE_URL "$ENVRC" ".envrc"
    fi
    ;;
  local)
    check_var_equals COGNEE_PLUGIN_DATASET "$ENVRC" ".envrc" "$PROJECT_DATASET"
    if contains_client claude \
      || contains_client codex \
      || contains_client antigravity \
      || contains_client mcp; then
      check_var_in_file LLM_API_KEY "$ENVRC_LOCAL" ".envrc.local"
    fi
    if contains_client opencode; then
      check_var_in_file COGNEE_SERVICE_URL "$ENVRC" ".envrc"
    fi
    ;;
  mcp)
    check_var_in_file COGNEE_MCP_URL "$ENVRC" ".envrc"
    check_var_equals COGNEE_PLUGIN_DATASET "$ENVRC" ".envrc" "$PROJECT_DATASET"
    if ! contains_client antigravity && ! contains_client mcp; then
      info "native client에 MCP를 선택함 — 자동 capture는 native plugin보다 적을 수 있음"
    fi
    ;;
esac

if [ -f "$ENVRC" ]; then
  if grep -Eq '^[[:space:]]*export[[:space:]]+(COGNEE_API_KEY|COGNEE_MCP_BEARER_TOKEN|LLM_API_KEY)=' "$ENVRC"; then
    fail "secret이 .envrc에 있음 — .envrc.local로 옮겨야 함"
  fi
  if grep -Eq "^[[:space:]]*(source|\\.)[[:space:]]+.*\\.envrc\\.local" "$ENVRC"; then
    pass ".envrc가 .envrc.local을 불러옴"
  else
    fail ".envrc가 .envrc.local을 불러오지 않음"
  fi
fi

if [ -f "$ENVRC" ]; then
  if command -v git >/dev/null 2>&1 \
    && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$PROJECT_ROOT" check-ignore -q .envrc 2>/dev/null; then
      fail ".envrc가 git ignore됨"
    elif git -C "$PROJECT_ROOT" ls-files --error-unmatch -- .envrc >/dev/null 2>&1; then
      pass ".envrc가 git에 추적됨"
    else
      fail ".envrc가 git에 추적되지 않음"
    fi

    if git -C "$PROJECT_ROOT" check-ignore -q .envrc.local 2>/dev/null; then
      pass ".envrc.local이 git ignore됨"
    else
      fail ".envrc.local이 git ignore되지 않음"
    fi
  else
    info "Git worktree가 아님"
  fi

  if command -v direnv >/dev/null 2>&1; then
    info "direnv 설치됨 — 변경 후 direnv allow 필요"
  else
    info "direnv 미설치 — client 실행 전 source .envrc 필요"
  fi
fi

printf '%s\n' "----------------------------------------------------------"
if [ "$FAILED" -eq 0 ]; then
  echo "RESULT OK — Cognee 로컬 설정 검사 통과"
  exit 0
fi

echo "RESULT INCOMPLETE — 위 FAIL 항목을 해결해야 함"
exit 1
