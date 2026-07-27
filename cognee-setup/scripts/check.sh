#!/usr/bin/env bash
# cognee 사용 전 환경 체크 스크립트.
# 사용법: check.sh [project-root]   (기본값: 현재 디렉토리)
# 출력: 각 항목별 PASS/FAIL/INFO 라인 + 마지막 RESULT 라인. 모두 통과 시 exit 0.
set -u

PROJECT_ROOT="${1:-$(pwd)}"
ENVRC="$PROJECT_ROOT/.envrc"
ENVRC_LOCAL="$PROJECT_ROOT/.envrc.local"
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
# 3. 프로젝트별 환경변수 체크
# ---------------------------------------------------------------
check_var_in_file() {
  VAR="$1"
  FILE="$2"
  LABEL="$3"

  if [ -f "$FILE" ]; then
    LINE=$(grep -E "^[[:space:]]*export[[:space:]]+$VAR=" "$FILE" 2>/dev/null | tail -1)
    if [ -n "$LINE" ]; then
      VALUE=$(printf '%s' "$LINE" | sed -E "s/^[[:space:]]*export[[:space:]]+$VAR=//" | sed -E "s/^[\"']//; s/[\"']\$//" | sed -E 's/[[:space:]]*#.*$//')
      if [ -n "$VALUE" ]; then
        pass "$VAR ${LABEL}에 정의됨"
        return
      fi
      fail "$VAR ${LABEL}에 있으나 값이 비어 있음"
      return
    fi
  fi
  fail "$VAR 미설정 (${LABEL}에 필요)"
}

for VAR in COGNEE_BASE_URL COGNEE_API_KEY COGNEE_PLUGIN_DATASET; do
  if [ -n "$(printenv "$VAR" 2>/dev/null || true)" ]; then
    info "현재 셸의 $VAR 값은 판정에서 제외함 — 프로젝트 파일로 설정 필요"
  fi
done

check_var_in_file COGNEE_BASE_URL "$ENVRC" ".envrc"
check_var_in_file COGNEE_PLUGIN_DATASET "$ENVRC" ".envrc"
check_var_in_file COGNEE_API_KEY "$ENVRC_LOCAL" ".envrc.local"

if [ -f "$ENVRC" ]; then
  if grep -Eq "^[[:space:]]*export[[:space:]]+COGNEE_API_KEY=" "$ENVRC"; then
    fail "COGNEE_API_KEY가 .envrc에 있음 — .envrc.local로 옮겨야 함"
  fi
  if grep -Eq "^[[:space:]]*(source|\\.)[[:space:]]+.*\\.envrc\\.local" "$ENVRC"; then
    pass ".envrc가 .envrc.local을 불러옴"
  else
    fail ".envrc가 .envrc.local을 불러오지 않음"
  fi
fi

# ---------------------------------------------------------------
# 4. Git 추적과 direnv 점검
# ---------------------------------------------------------------
if [ -f "$ENVRC" ]; then
  if command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$PROJECT_ROOT" check-ignore -q .envrc 2>/dev/null; then
      fail ".envrc가 git ignore됨 — ignore 규칙을 제거하고 추적해야 함"
    elif git -C "$PROJECT_ROOT" ls-files --error-unmatch -- .envrc >/dev/null 2>&1; then
      pass ".envrc가 git에 추적됨"
    else
      fail ".envrc가 git에 추적되지 않음 — git add -f -- .envrc 필요"
    fi

    if git -C "$PROJECT_ROOT" check-ignore -q .envrc.local 2>/dev/null; then
      pass ".envrc.local이 git ignore됨"
    else
      fail ".envrc.local이 git ignore되지 않음 — API key가 commit될 수 있음"
    fi
  else
    info "Git worktree가 아님 — 프로젝트 루트의 .envrc/.envrc.local만 사용"
  fi

  if command -v direnv >/dev/null 2>&1; then
    info "direnv 설치됨 — .envrc 수정 후 'direnv allow' 필요"
  else
    info "direnv 미설치 — 프로젝트 루트에서 매번 'source .envrc' 필요"
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
