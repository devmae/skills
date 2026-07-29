#!/usr/bin/env bash
# API key와 프로젝트 env 파일 없이 쓰는 Cognee MCP bridge를 검사한다.
# 사용법: check.sh [project-root|--pick] [--client NAME[,NAME...]] [--mode auto|remote] [--probe]
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT=""
PICK_PROJECT_ROOT=0
CLIENT_SPEC="auto"
MODE="auto"
PROBE=0
FAILED=0
PROBED=0

FIXED_COGNEE_BASE_URL="https://kimtaehwan-macmini.tail9f3ac8.ts.net/"

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=1; }
info() { printf 'INFO  %s\n' "$1"; }

usage() {
  cat <<'EOF'
Usage: check.sh [project-root|--pick] [options]

Options:
  --pick                    OS folder picker로 프로젝트 루트 선택
  --client NAME[,NAME...]  auto, all, claude, codex, opencode, antigravity, mcp
  --mode MODE              auto, remote
  --probe                   key 없이 원격 REST endpoint 검사
  -h, --help               도움말 출력
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pick)
      PICK_PROJECT_ROOT=1
      shift
      ;;
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
    --probe)
      PROBE=1
      shift
      ;;
    --require-tailscale)
      # 예전 호출과 호환한다. remote mode는 늘 Tailscale을 검사한다.
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

if [ "$PICK_PROJECT_ROOT" -eq 1 ]; then
  if [ -n "$PROJECT_ROOT" ]; then
    printf 'ERROR 프로젝트 경로와 --pick을 함께 쓸 수 없음\n' >&2
    exit 2
  fi

  NODE_BIN="${COGNEE_NODE_BIN:-node}"
  if ! command -v "$NODE_BIN" >/dev/null 2>&1; then
    printf 'ERROR folder picker 실행에 Node.js가 필요함\n' >&2
    exit 2
  fi
  if PROJECT_ROOT="$("$NODE_BIN" "$SCRIPT_DIR/pick-project-folder.mjs")"; then
    :
  else
    picker_status=$?
    exit "$picker_status"
  fi
fi

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
case "$PROJECT_ROOT" in
  [A-Za-z]:[\\/]*)
    if command -v cygpath >/dev/null 2>&1; then
      if PROJECT_ROOT="$(cygpath -u "$PROJECT_ROOT")"; then
        :
      else
        printf 'ERROR Windows 프로젝트 경로를 Bash 경로로 바꿀 수 없음\n' >&2
        exit 2
      fi
    fi
    ;;
esac

if [ ! -d "$PROJECT_ROOT" ]; then
  printf 'ERROR 프로젝트 폴더가 없음: %s\n' "$PROJECT_ROOT" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)"
PROJECT_DATASET="$(basename "$PROJECT_ROOT")"
CHECK_HOME="${COGNEE_CHECK_HOME:-$HOME}"

case "$MODE" in
  auto) MODE="remote" ;;
  remote) ;;
  *)
    printf 'ERROR 지원하지 않는 mode: %s\n' "$MODE" >&2
    exit 2
    ;;
esac

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

info "프로젝트: $PROJECT_ROOT"
info "client: $CLIENTS"
info "mode: $MODE"
info "Cognee URL: $FIXED_COGNEE_BASE_URL"
info "dataset: $PROJECT_DATASET"

check_tailscale() {
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
  else
    fail "tailscale 실행 또는 로그인 필요"
  fi
}

check_uvx() {
  if command -v uvx >/dev/null 2>&1; then
    pass "uvx 설치됨"
  else
    fail "uvx 미설치"
  fi
}

has_forbidden_auth() {
  printf '%s\n' "$1" | grep -Eqi -- \
    'api-token|serve-api-key|bearer-token|authorization[[:space:]]*[:=]|api[_-]?key'
}

check_bridge_text() {
  output="$1"
  label="$2"

  if ! printf '%s\n' "$output" | grep -Fq 'uvx'; then
    fail "$label command에 uvx가 없음"
  elif ! printf '%s\n' "$output" | grep -Fq 'cognee-mcp'; then
    fail "$label command에 cognee-mcp가 없음"
  elif ! printf '%s\n' "$output" | grep -Fq -- '--api-url'; then
    fail "$label command에 --api-url이 없음"
  elif ! printf '%s\n' "$output" | grep -Fq "$FIXED_COGNEE_BASE_URL"; then
    fail "$label Cognee URL이 고정값과 다름"
  elif has_forbidden_auth "$output"; then
    fail "$label 설정에 인증 key 또는 token이 있음"
  else
    pass "$label keyless MCP bridge 설정됨"
  fi
}

check_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    fail "Claude Code CLI 미설치"
    return
  fi
  pass "Claude Code CLI 설치됨"

  mcp_output="$(claude mcp get cognee 2>/dev/null || true)"
  check_bridge_text "$mcp_output" "Claude"

  plugin_output="$(claude plugin list 2>/dev/null || true)"
  if printf '%s\n' "$plugin_output" | grep -Eqi 'cognee-memory(@cognee)?'; then
    fail "Claude native Cognee plugin이 남아 있음"
  else
    pass "Claude native Cognee plugin 없음"
  fi
}

check_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    fail "Codex CLI 미설치"
    return
  fi
  pass "Codex CLI 설치됨"

  mcp_output="$(codex mcp get cognee 2>/dev/null || true)"
  check_bridge_text "$mcp_output" "Codex"

  plugin_output="$(codex plugin list 2>/dev/null || true)"
  if printf '%s\n' "$plugin_output" | grep -Eqi 'cognee@cognee'; then
    fail "Codex native Cognee plugin이 남아 있음"
  else
    pass "Codex native Cognee plugin 없음"
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
    [ -f "$config_path" ] || continue
    if grep -Eq '"mcp"[[:space:]]*:' "$config_path" \
      && grep -Eqi '"cognee"[[:space:]]*:' "$config_path" \
      && grep -Fq '"uvx"' "$config_path" \
      && grep -Fq '"cognee-mcp"' "$config_path" \
      && grep -Fq '"--api-url"' "$config_path" \
      && grep -Fq "$FIXED_COGNEE_BASE_URL" "$config_path"; then
      if has_forbidden_auth "$(sed -n '/"cognee"[[:space:]]*:/,/^[[:space:]]*}[,]*/p' "$config_path")"; then
        fail "OpenCode Cognee 설정에 인증 key 또는 token이 있음 ($config_path)"
      elif grep -Fq '@cognee/cognee-opencode' "$config_path"; then
        fail "OpenCode native Cognee plugin이 남아 있음 ($config_path)"
      else
        pass "OpenCode keyless MCP bridge 설정됨 ($config_path)"
        config_found=1
      fi
      break
    fi
  done
  [ "$config_found" -eq 1 ] || fail "OpenCode keyless Cognee MCP 설정 없음"
}

validate_antigravity_config() {
  config_path="$1"

  if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3가 없어 JSON을 검사할 수 없음'
    return 1
  fi

  python3 - "$config_path" "$FIXED_COGNEE_BASE_URL" <<'PY'
import json
import sys

path, expected_url = sys.argv[1:3]
try:
    with open(path, encoding="utf-8") as file:
        config = json.load(file)
except (OSError, json.JSONDecodeError):
    print("JSON 형식 오류")
    raise SystemExit(1)

servers = config.get("mcpServers") if isinstance(config, dict) else None
server = servers.get("cognee") if isinstance(servers, dict) else None
if not isinstance(server, dict):
    print("mcpServers.cognee 객체가 필요함")
    raise SystemExit(1)

if server.get("command") != "uvx":
    print("command는 uvx여야 함")
    raise SystemExit(1)

args = server.get("args")
if not isinstance(args, list) or not all(isinstance(value, str) for value in args):
    print("args 문자열 배열이 필요함")
    raise SystemExit(1)

required = ["cognee-mcp", "--api-url", expected_url]
if any(value not in args for value in required):
    print("cognee-mcp, --api-url, 고정 URL이 필요함")
    raise SystemExit(1)

serialized = json.dumps(server).lower()
for forbidden in ("api-token", "serve-api-key", "bearer-token", "authorization", "api_key", "api-key"):
    if forbidden in serialized:
        print("인증 key 또는 token을 넣을 수 없음")
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
    pass "Antigravity keyless MCP bridge 설정됨 ($config_path)"
  else
    fail "Antigravity Cognee MCP 설정 오류 ($config_path): $validation_error"
  fi
}

check_server() {
  if ! command -v curl >/dev/null 2>&1; then
    fail "server probe에 curl이 필요함"
    return
  fi

  health_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 15 \
    "${FIXED_COGNEE_BASE_URL}health" 2>/dev/null || true)"
  case "$health_code" in
    2??) pass "Cognee health 응답 정상" ;;
    *) fail "Cognee health 실패 (HTTP ${health_code:-000})" ;;
  esac

  datasets_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 15 \
    "${FIXED_COGNEE_BASE_URL}api/v1/datasets" 2>/dev/null || true)"
  case "$datasets_code" in
    2??) pass "Cognee REST가 key 없이 응답함" ;;
    401|403) fail "Cognee server 앱 인증이 켜져 있음 (HTTP $datasets_code)" ;;
    *) fail "Cognee datasets probe 실패 (HTTP ${datasets_code:-000})" ;;
  esac
}

check_tailscale
check_uvx

for client in $CLIENTS; do
  case "$client" in
    claude) check_claude ;;
    codex) check_codex ;;
    opencode) check_opencode ;;
    antigravity) check_antigravity ;;
    mcp) info "generic MCP client는 같은 uvx command 등록을 직접 확인해야 함" ;;
  esac
done

if [ "$PROBE" -eq 1 ]; then
  PROBED=1
  check_server
else
  info "server probe 생략 — 전체 검증에는 --probe 필요"
fi

printf '%s\n' "----------------------------------------------------------"
if [ "$FAILED" -eq 0 ]; then
  if [ "$PROBED" -eq 1 ]; then
    echo "RESULT OK — Cognee keyless 설정과 server probe 통과"
  else
    echo "RESULT OK — Cognee keyless 로컬 설정 통과, server probe 생략"
  fi
  exit 0
fi

echo "RESULT INCOMPLETE — 위 FAIL 항목을 해결해야 함"
exit 1
