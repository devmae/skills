---
name: issue-loop-mattpocock
description: "오케스트레이터가 GitHub 이슈를 하나씩 구현하고 local mattpocock:code-review, exact SHA PR, 사람이 승인하는 HITL merge skill을 조합해 정리까지 끝낸다. 사용자가 issue 번호·label·milestone과 함께 이슈 루프나 순차 처리를 요청할 때 사용한다."
---

## 먼저 서브에이전트 모델 확인

이 스킬을 불러오면 조사나 실행 전에 다음 문장만 묻고 답을 기다린다.

> 각 서브에이전트는 어떤 모델을 사용할까요?

사용자는 모든 역할에 같은 모델을 주거나 역할별 모델을 정할 수 있다. 지정한 모델을 쓸 수 없으면 대체 모델을 고르지 말고 다시 묻는다.

# Issue Loop — Matt Review + HITL Merge

대상 issue를 하나씩 끝낸다. PR마다 HITL comment를 남기고 사용자가 같은 세션에서 승인할 때까지 merge를 멈춘다.

```text
issue 확인 → local 구현·commit → mattpocock:code-review → exact SHA push·PR → HITL comment → 사용자 승인 → merge·정리 → 다음 issue
```

## 조합하는 skill

| Skill | 이 loop에서 맡는 일 |
|---|---|
| `mattpocock:code-review` | local commit 전체를 저장소 Standard와 issue spec 기준으로 리뷰 |
| `github-commit-to-pr` | clean review SHA를 대조하고 push·PR 생성·갱신 |
| `github-pr-hitl-merge` | PR 전체 요약 comment, 사용자 승인 대기, 승인된 SHA merge·정리 |

오케스트레이터는 하위 skill의 내부 단계를 복제하지 않는다. 입력과 증거를 넘기고 완료 결과를 받는다.

## 에이전트 역할

| 역할 | 책임 |
|---|---|
| 오케스트레이터 | issue 순서, 단계 상태, exact SHA, HITL 승인 상태 관리 |
| 구현 에이전트 | issue 구현, review·CI·사용자 요청 수정, local 검증 |
| 리뷰 에이전트 | `mattpocock:code-review`로 local 전체 diff 리뷰 |
| GitHub 에이전트 | branch·commit, PR 생성·갱신, HITL·merge skill 실행과 증거 수집 |

구현자는 자기 변경을 clean으로 승인하지 않는다. 리뷰는 새 에이전트가 맡는다. 같은 저장소를 쓰는 에이전트는 동시에 파일을 바꾸지 않는다.

## 시작 범위와 승인

사용자의 loop 시작 요청은 구현, local commit, review 수정, push, PR 생성·갱신, HITL comment 작성을 승인한다. **각 PR merge는 HITL comment를 본 사용자의 별도 승인이 필요하다.**

| 사용자 결정이 필요한 경우 | 처리 |
|---|---|
| 대상 issue를 찾을 수 없음 | 번호, label, milestone 중 필요한 값만 요청 |
| HITL comment 작성 완료 | comment URL을 보여주고 merge 승인까지 대기 |
| 인증·권한·필수 secret·도구가 없음 | 확인한 증거와 필요한 조치를 보고 |
| 파괴 작업만 남음 | 대상, 영향, 복구법을 알리고 승인 전 중단 |
| issue 밖의 제품 결정이 필요함 | 가능한 범위까지 끝낸 뒤 선택 요청 |

force push, `reset --hard`, 사용자 변경 폐기, 강제 worktree 삭제는 자동 승인 범위가 아니다.

## 0. 대상 확정

GitHub 조사 에이전트가 인증, 저장소, default branch, issue 본문·댓글·상태를 확인한다.

| 항목 | 규칙 |
|---|---|
| 대상 | 사용자가 준 번호, label, milestone의 OPEN issue |
| 순서 | 번호 오름차순, 명시된 의존성이 있으면 선행 issue 우선 |
| base | 사용자 지정값, 없으면 GitHub default branch |
| 작업 공간 | 최신 base의 clean worktree와 `codex/` branch |

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

### 4. HITL comment와 승인 대기

GitHub 에이전트가 `github-pr-hitl-merge`를 전체 실행한다. 이 skill은 PR 전체를 주요 사실별로 요약해 `## HITL` comment를 남긴다.

오케스트레이터는 다음 상태를 기록하고 **현재 turn을 끝낸다**.

```text
status: waiting_for_hitl_approval
pr_url: <url>
hitl_comment_url: <url>
hitl_base_sha: <base_sha>
hitl_head_sha: <head_sha>
```

사용자가 같은 세션에서 승인하면 `github-pr-hitl-merge`를 재개한다. skill은 PR base/head SHA를 다시 확인하고, 같을 때만 `github-pr-review-merge`의 merge 단계부터 이어서 CI·merge·정리를 수행한다.

| 승인 뒤 상태 | 처리 |
|---|---|
| snapshot 같음 | 승인된 head SHA merge와 정리 진행 |
| base 또는 head 변경 | 새 HITL comment 작성 후 다시 승인 대기 |
| 사용자 수정 요청 | 구현 수정 → local 검증 → 2단계부터 반복 |
| CI·충돌 수정에 새 commit 필요 | 승인 폐기 → 수정 → 2단계부터 반복 |

### 5. 다음 issue

다음 조건이 모두 맞을 때만 현재 issue를 완료로 표시한다.

| 증거 | 완료 조건 |
|---|---|
| Review | final head SHA의 Matt Pocock clean 결과 |
| HITL | 같은 base/head SHA의 comment와 세션 승인 |
| Merge | PR `state=MERGED`와 merge SHA 확인 |
| Issue | `state=CLOSED` 확인 |

그 뒤 다음 OPEN issue를 같은 순서로 처리한다.

## 실패 처리

명확한 finding과 CI 실패는 원인을 좁혀 수정 loop로 돌린다. 내용이 바뀌면 이전 HITL 승인을 재사용하지 않는다. 사용자 권한이나 제품 결정이 꼭 필요할 때만 오케스트레이터가 묻는다.

## 종료 보고

모든 대상 issue가 CLOSED이고 각 PR이 MERGED일 때만 완료로 판정한다. issue별 PR·HITL comment 링크, approved head SHA, merge SHA, 고친 핵심 finding, 검증 결과를 보고한다.
