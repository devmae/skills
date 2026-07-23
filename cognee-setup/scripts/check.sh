#!/usr/bin/env bash
# cognee 사용 전 환경 체크 스크립트.
# 사용법: check.sh [repo-root]   (기본값: 현재 디렉토리)
# 출력: 각 항목별 PASS/FAIL/INFO 라인 + 마지막 RESULT 라인. 모두 통과 시 exit 0.
set -u

REPO_ROOT="${1:-$(pwd)}"
ENVRC="$REPO_ROOT/.envrc"
FAILED=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=1; }
info() { printf 'INFO  %s\n' "$1"; }

# ---------------------------------------------------------------
# 1. Tailscale 설치/실행 여부
# ---------------------------------------------------------------
TS_BIN=""
if command -v tailscale >/dev/null 2>&1; then
  TS_BIN="tailscale"
elif [ -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then
  TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi

if [ -n "$TS_BIN" ]; then
  pass "tailscale 설치됨 ($TS_BIN)"
  if "$TS_BIN" status >/dev/null 2>&1; then
    info "tailscale 실행 중 (tailnet 연결됨)"
    # base URL 후보로 쓸 수 있도록 tailnet 머신 이름 목록 출력
    PEERS=$("$TS_BIN" status 2>/dev/null | awk '$2 != "" {print $2}' | head -10 | tr '\n' ' ')
    [ -n "$PEERS" ] && info "tailnet 머신 목록: $PEERS"
  else
    info "tailscale이 설치되어 있으나 실행/로그인 상태가 아님 — Tailscale 앱을 실행하고 로그인 필요"
  fi
else
  fail "tailscale 미설치 — 설치: brew install --cask tailscale"
fi

# ---------------------------------------------------------------
# 2. cognee claude-code 플러그인 설치 여부
#    (topoteretes/cognee-integrations 의 cognee-memory 플러그인)
# ---------------------------------------------------------------
PLUGIN_OK=0

if command -v claude >/dev/null 2>&1; then
  if claude plugin list 2>/dev/null | grep -qi "cognee"; then
    PLUGIN_OK=1
    pass "cognee-memory 플러그인 설치됨 (claude plugin list)"
  fi
fi

if [ "$PLUGIN_OK" -eq 0 ] && [ -d "$HOME/.claude/plugins" ]; then
  if grep -rqli "cognee" "$HOME/.claude/plugins" 2>/dev/null; then
    PLUGIN_OK=1
    pass "cognee-memory 플러그인 설치됨 (~/.claude/plugins 에서 확인)"
  fi
fi

if [ "$PLUGIN_OK" -eq 0 ]; then
  fail "cognee-memory 플러그인 미설치 — 설치: claude plugin marketplace add topoteretes/cognee-integrations && claude plugin install cognee-memory@cognee"
else
  if [ -d "$HOME/.cognee-plugin" ]; then
    info "플러그인 실행 이력 있음 (~/.cognee-plugin 존재)"
  else
    info "~/.cognee-plugin 이 아직 없음 — 플러그인이 아직 한 번도 실행되지 않았을 수 있음 (Claude Code 재시작 필요할 수 있음)"
  fi
fi

# ---------------------------------------------------------------
# 3. 환경변수 3종 체크 (현재 셸 또는 .envrc 정의 기준)
# ---------------------------------------------------------------
check_var() {
  VAR="$1"
  # 현재 셸에 이미 설정되어 있으면 통과
  CUR="$(printenv "$VAR" 2>/dev/null || true)"
  if [ -n "$CUR" ]; then
    pass "$VAR 현재 셸에 설정됨"
    return
  fi
  # .envrc 에 비어있지 않은 값으로 정의되어 있으면 통과
  if [ -f "$ENVRC" ]; then
    LINE=$(grep -E "^[[:space:]]*export[[:space:]]+$VAR=" "$ENVRC" | tail -1)
    if [ -n "$LINE" ]; then
      VALUE=$(printf '%s' "$LINE" | sed -E "s/^[[:space:]]*export[[:space:]]+$VAR=//" | sed -E "s/^[\"']//; s/[\"']\$//" | sed -E 's/[[:space:]]*#.*$//')
      if [ -n "$VALUE" ]; then
        pass "$VAR .envrc에 정의됨"
        return
      fi
      fail "$VAR .envrc에 있으나 값이 비어 있음"
      return
    fi
  fi
  fail "$VAR 미설정 (현재 셸에도 없고 .envrc에도 없음)"
}

check_var COGNEE_BASE_URL
check_var COGNEE_API_KEY
check_var COGNEE_PLUGIN_DATASET

# ---------------------------------------------------------------
# 4. 부가 점검 (.envrc 사용 시)
# ---------------------------------------------------------------
if [ -f "$ENVRC" ]; then
  if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$REPO_ROOT" check-ignore -q .envrc 2>/dev/null; then
      info ".envrc 는 git ignore 됨 (API key 커밋 방지 OK)"
    else
      info "경고: .envrc 가 git ignore 되지 않음 — COGNEE_API_KEY가 커밋될 수 있음. .gitignore에 .envrc 추가 권장"
    fi
  fi
  if command -v direnv >/dev/null 2>&1; then
    info "direnv 설치됨 — .envrc 수정 후 'direnv allow' 필요"
  else
    info "direnv 미설치 — .envrc 가 자동 로드되지 않음. 설치: brew install direnv (또는 매번 'source .envrc')"
  fi
fi

# ---------------------------------------------------------------
echo "----------------------------------------------------------"
if [ "$FAILED" -eq 0 ]; then
  echo "RESULT OK — cognee 사용 준비 완료"
  exit 0
else
  echo "RESULT INCOMPLETE — 위 FAIL 항목을 해결해야 cognee를 사용할 수 있음"
  exit 1
fi
