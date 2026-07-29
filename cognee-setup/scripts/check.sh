#!/usr/bin/env bash
# user scope에서 API key와 프로젝트 env 파일 없이 쓰는 Cognee MCP bridge를 검사한다.
# 사용법: check.sh [project-root|--pick] [--client NAME[,NAME...]] [--mcp-config FILE] [--mode auto|remote] [--probe]
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT=""
PICK_PROJECT_ROOT=0
CLIENT_SPEC="auto"
MODE="auto"
GENERIC_MCP_CONFIG=""
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
  --mcp-config FILE        generic MCP client의 user scope JSON 설정 파일
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
    --mcp-config)
      [ "$#" -ge 2 ] || { printf 'ERROR --mcp-config 값이 필요함\n' >&2; exit 2; }
      GENERIC_MCP_CONFIG="$2"
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
if [ -d "$CHECK_HOME" ]; then
  CHECK_HOME="$(cd "$CHECK_HOME" 2>/dev/null && pwd -P)"
fi
if [ -n "$GENERIC_MCP_CONFIG" ]; then
  case "$GENERIC_MCP_CONFIG" in
    /*) ;;
    *) GENERIC_MCP_CONFIG="$CHECK_HOME/$GENERIC_MCP_CONFIG" ;;
  esac
fi

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
  CLIENTS="claude codex opencode antigravity"
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
info "MCP scope: user"
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

check_legacy_env() {
  for env_path in "$PROJECT_ROOT/.envrc" "$PROJECT_ROOT/.envrc.local"; do
    if [ -f "$env_path" ] && grep -Eq '(^|[^[:alnum:]_])COGNEE_[[:alnum:]_]+' "$env_path"; then
      fail "legacy Cognee 설정이 남아 있음 ($env_path)"
    fi
  done
  if [ -n "${COGNEE_API_KEY:-}" ]; then
    fail "현재 shell에 legacy Cognee API key가 남아 있음"
  fi
  if [ -f "$CHECK_HOME/.cognee-plugin/api_key.json" ]; then
    fail "native Cognee API key cache가 남아 있음 ($CHECK_HOME/.cognee-plugin/api_key.json)"
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

file_has_json_cognee() {
  [ -f "$1" ] && grep -Eq '"cognee"[[:space:]]*:' "$1"
}

file_has_codex_cognee() {
  [ -f "$1" ] && grep -Eq \
    '^[[:space:]]*\[mcp_servers\.cognee([.][^]]+)?\][[:space:]]*$' "$1"
}

check_project_json_override() {
  local label config_path
  label="$1"
  shift
  for config_path in "$@"; do
    if file_has_json_cognee "$config_path"; then
      fail "$label project-local Cognee 설정이 남아 있음 ($config_path)"
    fi
  done
}

canonical_file_path() {
  local config_path config_dir config_name
  config_path="$1"
  config_dir="$(dirname "$config_path")"
  config_name="$(basename "$config_path")"
  config_dir="$(cd "$config_dir" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$config_dir" "$config_name"
}

check_user_config_path() {
  local label config_path
  label="$1"
  config_path="$(canonical_file_path "$2")" || {
    fail "$label 설정 경로를 확인할 수 없음 ($2)"
    return 1
  }

  case "$config_path" in
    "$PROJECT_ROOT"|"$PROJECT_ROOT"/*)
      fail "$label 설정이 project scope에 있음 ($config_path)"
      return 1
      ;;
  esac
  case "$config_path" in
    "$CHECK_HOME"/*) return 0 ;;
    *)
      fail "$label 설정이 user scope 경로 밖에 있음 ($config_path)"
      return 1
      ;;
  esac
}

check_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    fail "Claude Code CLI 미설치"
    return
  fi
  pass "Claude Code CLI 설치됨"

  mcp_output="$(claude mcp get cognee 2>/dev/null || true)"
  check_bridge_text "$mcp_output" "Claude"
  if printf '%s\n' "$mcp_output" | grep -Eqi \
    'scope[[:space:]]*:[[:space:]]*user([[:space:]]|$)'; then
    pass "Claude Cognee MCP가 user scope에 있음"
  else
    fail "Claude Cognee MCP가 user scope에 없음"
  fi
  check_project_json_override "Claude" "$PROJECT_ROOT/.mcp.json"

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
  user_config="$CHECK_HOME/.codex/config.toml"
  if file_has_codex_cognee "$user_config"; then
    pass "Codex Cognee MCP가 user scope에 있음 ($user_config)"
  else
    fail "Codex user scope Cognee MCP 설정 없음 ($user_config)"
  fi
  project_config="$PROJECT_ROOT/.codex/config.toml"
  if file_has_codex_cognee "$project_config"; then
    fail "Codex project-local Cognee 설정이 남아 있음 ($project_config)"
  fi

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

  check_project_json_override \
    "OpenCode" \
    "$PROJECT_ROOT/opencode.json" \
    "$PROJECT_ROOT/opencode.jsonc" \
    "$PROJECT_ROOT/.opencode/opencode.json" \
    "$PROJECT_ROOT/.opencode/opencode.jsonc"

  config_found=0
  config_seen=0
  native_plugin_found=0
  validation_error="Cognee MCP 설정이 없음"
  for config_path in \
    "$CHECK_HOME/.config/opencode/opencode.json" \
    "$CHECK_HOME/.config/opencode/opencode.jsonc"; do
    [ -f "$config_path" ] || continue
    config_seen=1
    if grep -Fq '@cognee/cognee-opencode' "$config_path"; then
      native_plugin_found=1
    fi
    if validation_error="$(validate_opencode_config "$config_path" 2>&1)"; then
      pass "OpenCode keyless MCP bridge 설정됨 ($config_path)"
      config_found=1
    fi
  done
  if [ "$native_plugin_found" -eq 1 ]; then
    fail "OpenCode native Cognee plugin이 남아 있음"
  fi
  if [ "$config_found" -ne 1 ]; then
    if [ "$config_seen" -eq 1 ]; then
      fail "OpenCode Cognee MCP 설정 오류: $validation_error"
    else
      fail "OpenCode keyless Cognee MCP 설정 없음"
    fi
  fi
}

validate_opencode_config() {
  config_path="$1"

  if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3가 없어 JSON을 검사할 수 없음'
    return 1
  fi

  python3 - "$config_path" "$FIXED_COGNEE_BASE_URL" <<'PY'
import json
import sys

path, expected_url = sys.argv[1:3]

def strip_jsonc(text):
    output = []
    index = 0
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            output.append(char)
            index += 1
            continue
        if char == "/" and next_char == "/":
            index += 2
            while index < len(text) and text[index] not in "\r\n":
                index += 1
            continue
        if char == "/" and next_char == "*":
            end = text.find("*/", index + 2)
            if end == -1:
                raise ValueError("닫히지 않은 block comment")
            index = end + 2
            continue
        output.append(char)
        index += 1

    text = "".join(output)
    output = []
    index = 0
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            output.append(char)
            index += 1
            continue
        if char == ",":
            lookahead = index + 1
            while lookahead < len(text) and text[lookahead].isspace():
                lookahead += 1
            if lookahead < len(text) and text[lookahead] in "}]":
                index += 1
                continue
        output.append(char)
        index += 1
    return "".join(output)

try:
    with open(path, encoding="utf-8") as file:
        config = json.loads(strip_jsonc(file.read()))
except (OSError, ValueError, json.JSONDecodeError):
    print("JSON 형식 오류")
    raise SystemExit(1)

servers_root = config.get("mcp") if isinstance(config, dict) else None
servers = servers_root.get("servers") if isinstance(servers_root, dict) else None
server = servers.get("cognee") if isinstance(servers, dict) else None
if not isinstance(server, dict):
    print("mcp.servers.cognee 객체가 필요함")
    raise SystemExit(1)

if server.get("type") != "local":
    print("type은 local이어야 함")
    raise SystemExit(1)

command = server.get("command")
if not isinstance(command, list) or not all(isinstance(value, str) for value in command):
    print("command 문자열 배열이 필요함")
    raise SystemExit(1)

if not command or command[0] != "uvx" or "cognee-mcp" not in command:
    print("uvx cognee-mcp command가 필요함")
    raise SystemExit(1)

try:
    url_index = command.index("--api-url")
except ValueError:
    print("--api-url이 필요함")
    raise SystemExit(1)
if url_index + 1 >= len(command) or command[url_index + 1] != expected_url:
    print("고정 Cognee URL이 필요함")
    raise SystemExit(1)

serialized = json.dumps(server).lower()
for forbidden in ("api-token", "serve-api-key", "bearer-token", "authorization", "api_key", "api-key"):
    if forbidden in serialized:
        print("인증 key 또는 token을 넣을 수 없음")
        raise SystemExit(1)
PY
}

validate_standard_mcp_config() {
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

if "cognee-mcp" not in args:
    print("cognee-mcp가 필요함")
    raise SystemExit(1)
try:
    url_index = args.index("--api-url")
except ValueError:
    print("--api-url이 필요함")
    raise SystemExit(1)
if url_index + 1 >= len(args) or args[url_index + 1] != expected_url:
    print("고정 Cognee URL이 필요함")
    raise SystemExit(1)

serialized = json.dumps(server).lower()
for forbidden in ("api-token", "serve-api-key", "bearer-token", "authorization", "api_key", "api-key"):
    if forbidden in serialized:
        print("인증 key 또는 token을 넣을 수 없음")
        raise SystemExit(1)
PY
}

check_antigravity() {
  local config_path validation_error
  if command -v antigravity >/dev/null 2>&1; then
    pass "Antigravity CLI 설치됨"
  else
    info "Antigravity CLI는 찾지 못함 — IDE만 쓸 수 있음"
  fi

  config_path="$CHECK_HOME/.gemini/config/mcp_config.json"
  check_project_json_override \
    "Antigravity" \
    "$PROJECT_ROOT/.agents/mcp_config.json" \
    "$PROJECT_ROOT/.gemini/config/mcp_config.json"
  if [ ! -f "$config_path" ]; then
    fail "Antigravity Cognee MCP 설정 없음 ($config_path)"
    return
  fi

  if validation_error="$(validate_standard_mcp_config "$config_path" 2>&1)"; then
    pass "Antigravity keyless MCP bridge 설정됨 ($config_path)"
  else
    fail "Antigravity Cognee MCP 설정 오류 ($config_path): $validation_error"
  fi
}

check_generic_mcp() {
  if [ -z "$GENERIC_MCP_CONFIG" ]; then
    fail "generic MCP client는 --mcp-config가 필요함"
    return
  fi
  if [ ! -f "$GENERIC_MCP_CONFIG" ]; then
    fail "generic MCP 설정 파일이 없음 ($GENERIC_MCP_CONFIG)"
    return
  fi
  if ! check_user_config_path "generic MCP" "$GENERIC_MCP_CONFIG"; then
    return
  fi

  if validation_error="$(validate_standard_mcp_config "$GENERIC_MCP_CONFIG" 2>&1)"; then
    pass "generic keyless MCP bridge 설정됨 ($GENERIC_MCP_CONFIG)"
  else
    fail "generic Cognee MCP 설정 오류 ($GENERIC_MCP_CONFIG): $validation_error"
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
check_legacy_env

for client in $CLIENTS; do
  case "$client" in
    claude) check_claude ;;
    codex) check_codex ;;
    opencode) check_opencode ;;
    antigravity) check_antigravity ;;
    mcp) check_generic_mcp ;;
  esac
done

if [ "$PROBE" -eq 1 ]; then
  PROBED=1
  check_server
else
  fail "server probe 생략 — --probe가 필요함"
fi

printf '%s\n' "----------------------------------------------------------"
if [ "$FAILED" -eq 0 ]; then
  if [ "$PROBED" -eq 1 ]; then
    echo "RESULT OK — Cognee user scope keyless 설정과 server probe 통과"
  else
    echo "RESULT OK — Cognee user scope keyless 설정 통과, server probe 생략"
  fi
  exit 0
fi

echo "RESULT INCOMPLETE — 위 FAIL 항목을 해결해야 함"
exit 1
