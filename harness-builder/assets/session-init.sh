#!/usr/bin/env bash
# 하네스 세션 부팅 — 매번 동일한 7단계.
set -euo pipefail

echo "== STEP 1: 작업 디렉터리 =="
pwd

echo "== STEP 2: 최근 히스토리 + 진행 상황 =="
git --no-pager log --oneline -10 || true
echo "--- features.json (실패 항목, 우선순위순) ---"
if [ -f harness/features.json ]; then
  jq -r '.features | map(select(.status=="fail")) | sort_by(.priority) | .[] | "[\(.priority)] \(.id): \(.description)"' harness/features.json 2>/dev/null || cat harness/features.json
fi

echo "== STEP 3: 우선순위가 가장 높은 실패 기능 =="
echo "(에이전트: 위 목록에서 최상단 항목을 고른다. 그 하나만 구현한다.)"

echo "== STEP 4: 개발 서버 시작 (스택에 맞게 수정) =="
echo "예: npm run dev &   # 이후 계속"

echo "== STEP 5: 스모크 / e2e 검증 =="
echo "예: npm run test:smoke"

echo "== STEP 6: 기능 하나 구현 =="
echo "(Generator 역할이 선택된 단일 기능을 구현.)"

echo "== STEP 7: 커밋 + 진행 상황 업데이트 =="
echo "git commit -m \"<설명>\"  &&  harness/features.json에서 해당 기능 status=pass로 표시"
