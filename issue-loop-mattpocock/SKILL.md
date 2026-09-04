---
name: issue-loop-mattpocock
description: "grill-with-docs, to-spec, to-ticket 뒤 남은 ADR·spec·ticket 문서를 먼저 독립 PR로 merge한 다음 GitHub 이슈를 하나씩 구현하고 local mattpocock:code-review, exact SHA PR, HITL 기록과 merge skill을 조합해 정리까지 끝낸다. 사용자가 issue 번호·label·milestone과 함께 이슈 루프나 순차 처리를 요청할 때 사용한다."
---

## 먼저 서브에이전트 모델 확인

이 스킬을 불러오면 최초 1회 다음 세 질문을 묻고 사용자의 답변을 기다린다.

| 질문 | 내용 |
|---|---|
| 질문 1 | 전체 오케스트레이션, 문서 범위·issue 순서 결정, Standards·Spec 리뷰, HITL 요약, 최종 증거 감사에 어떤 모델을 사용할까요? |
| 질문 2 | 구현·검증, commit, exact SHA push·PR, review·CI 수정, merge·branch·issue 정리에 어떤 모델을 사용할까요? |
| 질문 3 | 읽기 전용 issue·PR·저장소 조사에 어떤 모델을 사용할까요? |

사용자는 모든 역할에 같은 모델을 주거나 역할별 모델을 정할 수 있다. 지정한 모델을 쓸 수 없으면 대체 모델을 고르지 말고 다시 묻는다. 이 질문에 답변이 완료되면 다음 단계부터는 사용자의 승인없이 자동으로 진행한다.

# Issue Loop — Matt Review + HITL Merge

대상 issue를 하나씩 끝낸다. PR마다 HITL comment를 남긴 뒤 같은 snapshot의 merge·정리까지 바로 진행한다.

```text
문서 baseline PR·merge → issue 확인 → local 구현·commit → mattpocock:code-review → exact SHA push·PR → HITL comment → merge·정리 → 다음 issue
```

## 조합하는 skill

| Skill | 이 loop에서 맡는 일 |
|---|---|
| `mattpocock:code-review` | local commit 전체를 저장소 Standard와 issue spec 기준으로 리뷰 |
| `github-commit-to-pr` | clean review SHA를 대조하고 push·PR 생성·갱신 |
| `github-pr-hitl-merge` | PR 전체 요약 HITL comment와 snapshot 검증 |
| `github-merge-clean` | 기록된 SHA의 CI 확인, merge, branch·issue 정리 |

오케스트레이터는 하위 skill의 내부 단계를 복제하지 않는다. 입력과 증거를 넘기고 완료 결과를 받는다.

## 에이전트 역할

| 역할 | 책임 |
|---|---|
| 오케스트레이터 | issue 순서, 단계 상태, exact SHA, HITL 기록 상태 관리 |
| 구현 에이전트 | issue 구현, review·CI·사용자 요청 수정, local 검증 |
| 리뷰 에이전트 | `mattpocock:code-review`로 local 전체 diff 리뷰 |
| GitHub 에이전트 | branch·commit, PR 생성·갱신, HITL·merge skill 실행과 증거 수집 |

구현자는 자기 변경을 clean으로 승인하지 않는다. 리뷰는 새 에이전트가 맡는다. 같은 저장소를 쓰는 에이전트는 동시에 파일을 바꾸지 않는다.

## 시작 범위와 중단 조건

사용자의 loop 시작 요청은 구현, local commit, review 수정, push, PR 생성·갱신, HITL comment, `github-merge-clean`의 merge·정리를 승인한다. HITL comment는 기록이며 별도 사용자 승인을 기다리지 않는다.

| 사용자 결정이 필요한 경우 | 처리 |
|---|---|
| 대상 issue를 찾을 수 없음 | 번호, label, milestone 중 필요한 값만 요청 |
| HITL comment 작성 완료 | 같은 snapshot을 확인하고 `github-merge-clean`으로 바로 handoff |
| 인증·권한·필수 secret·도구가 없음 | 확인한 증거와 필요한 조치를 보고 |
| 파괴 작업만 남음 | 대상, 영향, 복구법을 알리고 승인 전 중단 |
| issue 밖의 제품 결정이 필요함 | 가능한 범위까지 끝낸 뒤 선택 요청 |

force push, `reset --hard`, 사용자 변경 폐기, 강제 worktree 삭제는 자동 승인 범위가 아니다.

기본 작업 공간은 현재 폴더다. 사용자가 별도로 지시하지 않으면 worktree를 만들거나 전환하지 않는다.

## 사전 단계: 문서 baseline PR

이 loop가 `grill-with-docs`, `to-spec`, `to-ticket` 뒤 시작되어 ADR·spec·ticket 문서가 local working tree에 남아 있으면, issue를 찾거나 구현하기 전에 문서만 독립 PR로 merge한다. 문서와 issue 구현은 같은 branch, commit, PR에 섞지 않는다.

### 1. 문서 범위 확정

오케스트레이터가 `git status --short`와 대화의 upstream 산출물을 대조한다. 대화에서 확인된 ADR, spec, ticket 문서만 허용 파일로 기록한다. 문서 범위를 정할 수 없으면 필요한 경로만 사용자에게 확인한다. 문서 밖의 dirty file은 stage, stash, 이동, 삭제하지 않는다.

문서 밖의 dirty file이 있어도 현재 폴더에서 작업한다. 확인한 문서만 stage·commit하고, 문서 밖 파일은 지우거나 되돌리지 않는다. worktree는 사용자가 별도로 지시할 때만 만든다.

문서 변경이 없으면 다음 상태를 기록하고 `0. 대상 확정`으로 간다.

```text
docs_baseline_status: skipped
```

### 2. 문서 PR 생성

문서 변경이 있으면 최신 base에서 `codex/docs-baseline` branch를 사용한다. 이름이 겹치면 짧은 숫자 suffix를 붙인다. GitHub 에이전트가 `github-commit-to-pr`을 호출하고 다음을 넘긴다.

| 값 | 내용 |
|---|---|
| 허용 파일 | 1단계에서 확정한 ADR·spec·ticket 문서만 |
| branch | `codex/docs-baseline` 또는 suffix branch |
| base | 사용자 지정값, 없으면 GitHub default branch |
| spec | upstream 산출물의 목적과 문서 간 연결 |
| commit message | `docs: add planning baseline` 등 간결한 영어 요약 |

`github-commit-to-pr`은 문서 파일만 local commit하고, `mattpocock:code-review`의 clean exact SHA를 확인한 뒤 push·PR 생성 또는 갱신을 수행한다. 문서 PR 본문에는 문서 목적, 핵심 파일, local 검증, reviewed head SHA를 넣는다.

### 3. 문서 HITL 기록과 merge

GitHub 에이전트가 문서 PR에 `github-pr-hitl-merge`를 실행한다. 이 skill은 HITL comment를 기록하고 같은 snapshot을 확인한 뒤 `github-merge-clean`으로 바로 handoff한다. 문서 PR이 merge되기 전에는 `0. 대상 확정`과 issue 구현을 시작하지 않는다.

```text
status: docs_hitl_recorded
docs_pr_url: <url>
docs_hitl_comment_url: <url>
docs_base_sha: <base_sha>
docs_head_sha: <head_sha>
```

`github-pr-hitl-merge`가 snapshot을 다시 확인한다. 같으면 `github-merge-clean`이 CI 확인, merge commit, local·remote docs branch 정리를 수행한다.

| 기록 뒤 상태 | 처리 |
|---|---|
| snapshot 같음 | 문서 PR merge와 정리 진행 |
| base 또는 head 변경 | 새 문서 HITL comment를 기록하고 다시 handoff |
| 문서 수정 요청·CI 실패·충돌 | 문서 수정 → local 검증 → Matt 리뷰 → PR 갱신 → 새 HITL 기록 |

### 4. issue loop 시작 조건

문서 PR의 `state=MERGED`, merge SHA, local·remote docs branch 정리 상태를 확인한다. `git fetch origin <base>` 뒤 현재 폴더의 base가 이 merge SHA를 포함하는지 확인한다. 그 뒤에만 `0. 대상 확정`으로 진행한다. worktree는 사용자가 별도로 지시할 때만 만든다.

## 0. 대상 확정

GitHub 조사 에이전트가 인증, 저장소, default branch, issue 본문·댓글·상태를 확인한다.

| 항목 | 규칙 |
|---|---|
| 대상 | 사용자가 준 번호, label, milestone의 OPEN issue |
| 순서 | 번호 오름차순, 명시된 의존성이 있으면 선행 issue 우선 |
| base | 사용자 지정값, 없으면 GitHub default branch |
| 작업 공간 | 현재 폴더의 최신 base와 `codex/` branch. 별도 지시가 있을 때만 worktree 사용 |

오케스트레이터는 issue별 상태, PR URL, HITL comment URL을 기록한다.

## 이슈별 loop

### 1. local 구현과 첫 commit

구현 에이전트가 issue와 저장소 규칙에 맞는 최소 변경을 만든다. 관련 test, typecheck, lint를 실행한다.

GitHub 에이전트가 issue 범위 파일만 stage하고 첫 local commit을 만든다. 아직 push하지 않는다.

```bash
git status --short
git add <issue 범위 파일>
git commit -m "<type>: <간결한 영어 요약>"
git status --short
git rev-parse HEAD
```

오케스트레이터는 `base_sha`, `head_sha`, clean working tree, 변경 파일, 검증 결과를 기록한다.

### 2. local Matt Pocock review

새 리뷰 에이전트가 exact `base_sha...head_sha`를 `mattpocock:code-review`로 확인한다. issue 본문, acceptance criteria, 저장소 Standard를 함께 준다.

finding이 있으면 구현 에이전트가 고치고 검증한다. GitHub 에이전트는 review 수정만 담은 local commit을 만든다.

```bash
git add <수정한 파일>
git commit -m "fix(review): <간결한 영어 요약>"
```

새 commit은 clean 증거를 무효화한다. 새 리뷰 에이전트가 최신 전체 diff를 다시 본다. clean 결과 뒤 오케스트레이터가 `reviewed_base_sha`와 `reviewed_head_sha`를 기록한다.

### 3. exact SHA push와 PR

GitHub 에이전트가 `github-commit-to-pr`을 전체 실행한다.

| 증거 | 필수 값 |
|---|---|
| Review | `reviewer=mattpocock:code-review`, `verdict=clean` |
| SHA | `reviewed_base_sha`, `reviewed_head_sha` |
| Local 상태 | clean working tree, validation 결과, 허용 파일 |

`github-commit-to-pr`은 원격 base와 현재 HEAD를 다시 확인한다. SHA가 바뀌면 push하지 않고 2단계부터 반복한다. PR 본문에는 `Issues #<번호>`와 reviewed head SHA를 넣는다.

### 4. HITL comment 기록과 merge

GitHub 에이전트가 `github-pr-hitl-merge`를 전체 실행한다. 이 skill은 PR 전체를 주요 사실별로 요약해 `## HITL` comment를 남기고 같은 snapshot을 확인한 뒤 `github-merge-clean`으로 handoff한다.

오케스트레이터는 다음 상태를 기록한 뒤 `github-merge-clean` 결과를 기다린다.

```text
status: hitl_recorded
pr_url: <url>
hitl_comment_url: <url>
hitl_base_sha: <base_sha>
hitl_head_sha: <head_sha>
```

`github-merge-clean`은 기록한 PR base/head SHA를 다시 확인하고, 같을 때만 CI·merge·정리를 수행한다.

| 기록 뒤 상태 | 처리 |
|---|---|
| snapshot 같음 | 기록된 head SHA merge와 정리 진행 |
| base 또는 head 변경 | 새 HITL comment 기록 후 다시 handoff |
| 사용자 수정 요청 | 구현 수정 → local 검증 → 2단계부터 반복 |
| CI·충돌 수정에 새 commit 필요 | HITL 기록 폐기 → 수정 → 2단계부터 반복 |

### 5. 다음 issue

다음 조건이 모두 맞을 때만 현재 issue를 완료로 표시한다.

| 증거 | 완료 조건 |
|---|---|
| Review | final head SHA의 Matt Pocock clean 결과 |
| HITL | 같은 base/head SHA의 comment 기록 |
| Merge | PR `state=MERGED`와 merge SHA 확인 |
| Issue | `state=CLOSED` 확인 |

그 뒤 다음 OPEN issue를 같은 순서로 처리한다.

## 실패 처리

명확한 finding과 CI 실패는 원인을 좁혀 수정 loop로 돌린다. 내용이 바뀌면 이전 HITL 기록을 재사용하지 않는다. 사용자 권한이나 제품 결정이 꼭 필요할 때만 오케스트레이터가 묻는다.

## 종료 보고

모든 대상 issue가 CLOSED이고 각 PR이 MERGED일 때만 완료로 판정한다. 최종 답변에는 issue별 결과를 다음 표로 넣는다. 각 행의 `HITL comment`는 GitHub comment의 직접 링크여야 하며 생략하지 않는다.

| Issue | PR | HITL comment | Recorded head SHA | Merge SHA | 검증·핵심 finding |
|---|---|---|---|---|---|
| #<번호> | <PR URL> | <HITL comment URL> | `<sha>` | `<sha>` | <결과> |
