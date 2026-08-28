---
name: issue-loop-mattpocock
description: "GitHub 이슈 묶음(예: to-tickets 산출물)을 1개씩 순차 처리한다 — 구현 → github-commit-to-pr(PR 생성) → mattpocock code-review(Spec/Standards) → github-pr-review-merge(correctness 리뷰·머지·정리) → 다음 이슈. 이슈는 1개든 여러 개든 처리하며, 번호를 인자로 받는다 (예: \"/issue-loop-mattpocock 605 606\"). 사용자가 \"이슈 루프 돌려줘\", \"티켓 순차 처리해줘\", \"이슈들 전부 처리해줘\", \"이 이슈 파이프라인으로 처리해줘\", \"/issue-loop-mattpocock\" 같은 말을 할 때 사용한다."
---

# Issue Loop — 이슈 묶음 순차 처리

여러 GitHub 이슈를 **한 번에 1개씩** "구현 → PR → 2단 리뷰 → 머지"로 끝내고 다음 이슈로 넘어가는 루프. 스택형 티켓(앞 티켓 위에 다음 티켓이 쌓이는 구조)을 전제로 하므로, **이전 이슈의 PR이 머지되기 전에는 다음 이슈를 시작하지 않는다.**

파이프라인 (이슈 1개당):

```
구현(uncommitted) → github-commit-to-pr → mattpocock code-review → github-pr-review-merge → 다음 이슈
                     (브랜치·커밋·PR)      (Spec/Standards 축)      (Correctness 축·머지·정리)
```

리뷰 게이트는 축이 다른 2개다 — mattpocock code-review는 "티켓/표준이 요구한 대로 만들었나"(스펙 누락·scope creep·코딩 표준), github-pr-review-merge의 자체 리뷰는 "코드가 실제로 옳게 동작하나"(로직 버그·엣지 케이스·보안·호환성)를 본다. 같은 리뷰의 중복이 아니므로 어느 쪽도 생략하지 않는다.

---

## 사전 조건 (Fail Fast — 하나라도 어긋나면 즉시 중단하고 보고)

- `gh auth status` 통과.
- 워킹 트리가 깨끗해야 한다 (`git status --short` 비어 있음). 남은 변경이 있으면 처리 방법(stash / commit / 중단)을 사용자에게 확인한다.
- 처리할 이슈 집합과 base 브랜치가 확정돼야 한다 (아래 0단계). 추측으로 채우지 않는다.

## 0단계: 입력 확정

**이슈 집합**: 호출 인자로 받는다 — 이슈 번호 **1개 이상**(공백/쉼표 구분), 또는 label·milestone.

- 호출 예: `/issue-loop-mattpocock 605 606 607` (여러 개), `/issue-loop-mattpocock 605` (1개), `/issue-loop-mattpocock label:dialogue-system`
- 이슈가 1개면 루프를 1회만 돌고 종료한다 — 파이프라인은 동일하다.
- 인자가 없으면 반드시 사용자에게 질문하고 답을 받을 때까지 진행하지 않는다:
  > "처리할 이슈들을 알려주세요 (번호 1개 이상, label, 또는 milestone)."

**base 브랜치**: 이 루프의 모든 PR이 향하는 브랜치. 브랜치명을 이 스킬에 하드코딩하지 않는다.
1. 사용자가 명시했으면 그것을 쓴다.
2. 명시하지 않았으면 현재 체크아웃된 브랜치를 후보로 제시하고 **반드시 1회 확인받는다**:
   > "base 브랜치를 `<현재 브랜치>`로 진행할까요?"

확정되면 처리 순서(이슈 번호 오름차순, 단 이슈 본문에 의존성이 명시돼 있으면 의존성 우선)를 요약해 보고하고 루프를 시작한다.

## 1단계: 다음 이슈 선택

- 이슈 집합에서 `state=OPEN`인 것 중 처리 순서상 첫 번째를 고른다.
- `gh issue view <번호> --json title,body,state,comments` 로 내용을 읽는다.
- 남은 이슈가 없으면 루프를 종료하고 최종 보고로 간다 (6단계).

## 2단계: 구현

- base 브랜치를 최신화한다: `git checkout <base>` 후 `git pull --ff-only origin <base>`. ff 불가면 중단하고 보고한다.
- **base 브랜치 위에서 uncommitted 상태로 구현한다.** 브랜치 생성과 커밋은 3단계의 github-commit-to-pr가 담당하므로 여기서 하지 않는다.
- 이슈 본문·연결된 스펙 문서를 구현의 기준으로 삼는다. 이슈에 없는 것을 추가하지 않는다 (scope creep은 4단계 리뷰에서 걸린다).
- 테스트 가능한 변경이면 테스트를 함께 작성하고, 타입체크를 수시로, 마지막에 관련 테스트 스위트를 돌린다.

## 3단계: PR 생성 — `github-commit-to-pr` 스킬 호출

- base 브랜치를 명시해서 호출한다 (스킬이 main을 기본값으로 잡지 않도록).
- PR 본문의 관련 이슈 표기는 `Issues #<번호>` 형식을 쓴다 (5단계의 이슈 종료가 이 패턴을 읽는다).

## 4단계: Spec/Standards 리뷰 — mattpocock `code-review` 스킬 호출

- 이 스킬은 fixed point(diff 기준점)를 **호출 인자로 요구한다**. 인자 없이 호출하면 사용자에게 기준점을 물으며 루프가 멈추므로, 반드시 인자에 담아 호출한다:
  - fixed point = **base 브랜치** (0단계에서 확정한 값)
  - spec = 이번 이슈 (번호 또는 URL)
  - 호출 예 (Claude Code 기준): `/mattpocock-skills:code-review <base브랜치> — spec: issue #<번호>`
- mattpocock 스킬은 Claude Code 외의 에이전트 환경(codex 등)에도 설치해 쓸 수 있다. **설치돼 있지 않으면 대체 수행하지 말고 중단한 뒤 사용자에게 설치를 안내한다**:
  > "mattpocock skills가 설치돼 있지 않습니다. https://github.com/mattpocock/skills 에서 설치한 뒤 다시 실행해 주세요."
- finding 처리:
  - 스펙 누락·표준 위반 등 실질 결함 → 수정하고 같은 브랜치에 커밋·push.
  - 판단이 필요한 finding(스펙 해석 차이 등) → 사용자에게 보고하고 지시를 받는다.
- 수정 push 후 리뷰를 재수행하지는 않는다 — 다음 단계의 correctness 리뷰가 최신 diff를 다시 본다.

## 5단계: Correctness 리뷰·머지·정리 — `github-pr-review-merge` 스킬 호출

스킬을 그대로 따르되, **다음 오버라이드가 스킬 본문보다 우선한다**:

1. **머지 승인 게이트**: 리뷰·CI가 모두 통과해도 머지 직전에 사용자 승인을 **이슈당 1회** 받는다. 승인 없이는 머지하지 않는다.
2. **머지 명령**: `gh pr merge <번호> --auto` 를 사용한다. `--squash`/`--merge`/`--rebase` 직접 머지는 하지 않는다 (repo가 merge queue를 쓰므로 큐를 우회하게 된다).
3. **머지 완료 대기**: `--auto`는 비동기다. `gh pr view <번호> --json state,mergedAt` 으로 `MERGED`가 확인될 때까지 기다린 뒤에만 정리 단계로 간다. 큐에서 튕기면(CI 실패 등) 스킬의 문제 해결 루프로 돌아간다.
4. **정리 기준 브랜치**: 스킬 본문의 "main" 가정 대신 **0단계에서 확정한 base 브랜치**를 기준으로 로컬을 정리한다.
5. **이슈 종료**: PR이 `MERGED` 확인된 후 이슈를 close한다 (스킬 6단계 그대로 — base가 default 브랜치가 아니면 GitHub이 자동 close하지 않으므로 이 명시적 close가 필요하다).

## 6단계: 반복 및 종료

- 1단계로 돌아가 다음 이슈를 처리한다.
- 한 이슈에서 문제 해결 루프가 3회를 넘도록 해소되지 않으면, 그 이슈는 중단하고 상황을 보고한 뒤 사용자 지시를 기다린다 — 임의로 skip하고 다음 이슈로 넘어가지 않는다 (스택형 티켓은 앞 이슈에 의존한다).
- 모든 이슈가 끝나면 최종 보고: 이슈별 PR 링크, 리뷰에서 발견·수정한 문제 요약, 머지·close 상태.

---

## 승인 모델

- 사용자의 루프 시작 지시가 각 이슈의 **commit / push / PR 생성**에 대한 승인이다 (git 승인 tier의 "명시적 명령" 예외).
- **머지**는 비가역이므로 위 오버라이드 1에 따라 이슈당 1회 별도 승인을 받는다.
- `push --force`, `reset --hard` 등 Tier 3 명령은 이 루프 안에서 절대 쓰지 않는다.

## 환경 이식성

- 이 스킬은 특정 에이전트 전용이 아니다. 필수 요구는 `git`과 GitHub CLI(`gh`)뿐이며, 어떤 CLI 에이전트에서도 동일하게 동작해야 한다.
- 하위 스킬 중 **mattpocock code-review는 필수 의존성이다** — 없으면 4단계의 안내대로 설치를 요청하고 중단한다 (mattpocock skills는 Claude Code 외 에이전트 환경에도 설치 가능).
- 나머지 하위 스킬(github-commit-to-pr, github-pr-review-merge)은 설치된 환경에서는 호출하고, 없는 환경에서는 **해당 단계에 적힌 목적과 오버라이드를 동일한 절차로 직접 수행한다** (3단계: 브랜치 생성→커밋→push→base 브랜치 대상 PR 생성 / 5단계: correctness 리뷰→CI 확인→승인→`--auto` 머지→base 기준 정리→이슈 close).
- 특정 에이전트의 도구명·명령어를 이 문서에 추가하지 않는다.

## 주의사항

- 이 스킬은 오케스트레이터다 — 하위 스킬이 있으면 절차를 복제하지 말고 호출해서 쓴다. 하위 스킬과 이 문서가 충돌하면 이 문서의 오버라이드가 우선한다.
- 이슈 내용이 불분명하거나 구현 범위가 예상보다 크면, 구현을 시작하기 전에 사용자에게 확인한다.
- 루프 중간에 사용자가 개입하면(리뷰 finding 판단, 머지 보류 등) 그 지시가 이 문서보다 우선한다.
