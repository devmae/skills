---
name: github-issue-to-pr
description: "GitHub 이슈를 읽고 격리 branch에서 구현·검증한 뒤, commit된 변경을 mattpocock:code-review로 local 리뷰하고 exact reviewed SHA로 Pull Request를 생성한다. GitHub 이슈 URL이나 \"이슈 해결해줘\", \"이슈 작업해줘\" 같은 요청에 사용한다."
---

# GitHub Issue → Review → PR

GitHub 이슈를 구현한 뒤 `github-commit-to-pr`의 공통 local review gate로 PR을 만든다.

## 사전 조건

| 조건 | 요구 사항 |
|---|---|
| 저장소 | 로컬 clone과 GitHub remote |
| 도구 | 인증된 `gh` CLI와 `git` |
| 입력 | issue URL 또는 repo와 issue 번호 |

## 실행 환경

GitHub 서버에 접속하는 `gh`, `git fetch`, `git push`는 격리 환경 밖의 host CLI에서 실행한다. 첫 원격 명령 전에 host CLI에서 `gh auth status`를 확인한다. host CLI에서도 인증이 실패할 때만 로그인을 안내하고 중단한다.

## 1. issue와 작업 공간 확정

대화에서 issue URL을 찾는다. 없으면 대상 issue만 사용자에게 묻는다.

```bash
gh issue view <번호> --repo <owner>/<repo> --json number,title,body,state,url,comments
```

| 값 | 결정 규칙 |
|---|---|
| branch | issue 내용을 담은 간결한 영어 slug와 `codex/` prefix |
| 범위 | 코드, 테스트, 문서 중 issue 해결에 필요한 최소 범위 |
| base | 사용자 지정값, 없으면 저장소 default branch |
| 작업 공간 | 최신 원격 base에서 만든 clean worktree |

branch와 worktree를 구현 전에 만든다. PR gate가 끝나기 전에는 push하지 않는다.

## 2. 구현과 local 검증

`rg --files`와 `rg`로 관련 코드와 저장소 규칙을 찾는다. issue 해결에 필요한 파일만 수정하고 위험에 맞는 test, typecheck, lint를 실행한다.

변경 파일, 핵심 판단, 실행한 검증과 결과를 기록한다. 관련 없는 사용자 변경을 stage, stash, 삭제하지 않는다.

## 3. 공통 PR 경로 호출

`github-commit-to-pr`을 호출해 다음 값을 전달한다.

| 값 | 내용 |
|---|---|
| repo와 base | 1단계에서 확정한 값 |
| branch | 구현 worktree의 local branch |
| 허용 파일 | 현재 issue를 위해 바꾼 파일만 |
| spec | issue 제목, 본문, 댓글, acceptance criteria |
| commit message | 예: `fix: resolve login redirect issue (#42)` |
| PR 본문 | 아래 형식과 `Issues #<번호>` |

`github-commit-to-pr`은 첫 local commit을 만들거나 기존 clean commit을 사용한다. 두 경우 모두 push 전에 `mattpocock:code-review`의 clean 결과와 exact reviewed SHA가 필요하다.

finding 수정 commit은 `fix(review): <간결한 영어 요약>`을 쓴다. 새 commit이 생기면 기존 review 증거를 버리고 최신 전체 diff를 `mattpocock:code-review`로 다시 리뷰한다.

이 스킬은 직접 push하거나 `gh pr create`를 실행하지 않는다. `github-commit-to-pr`이 exact reviewed SHA를 push하고 PR을 생성·갱신한다.

## 4. PR 본문

```markdown
## 개요
[issue에서 풀 문제를 1~2문장으로]

## 변경 내용
- [핵심 변경]

## 관련 이슈
Issues #<번호>

## 검증
- Matt Pocock code review: `<reviewed_head_sha>`
```

## 5. 결과

PR URL, `reviewed_base_sha`, `reviewed_head_sha`, PR `headRefOid`, local 검증 결과를 보고한다. 세 SHA가 맞아야 완료로 판정한다.

## 안전 규칙

| 사건 | 처리 |
|---|---|
| 관련 없는 변경 | stage·commit하지 않음 |
| PR 뒤 새 commit | local Matt Pocock review부터 다시 실행 |
| issue 범위가 불명확 | 구현 범위를 사용자에게 확인 |
| SHA 불일치 | push·완료 판정 중단 후 최신 snapshot 재검증 |
