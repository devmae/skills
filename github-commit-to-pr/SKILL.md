---
name: github-commit-to-pr
description: "현재 대화의 변경이나 이미 commit된 로컬 branch를 mattpocock:code-review로 local 리뷰한 뒤 exact reviewed SHA만 push하고 Pull Request를 생성하거나 기존 PR을 갱신한다. 사용자가 \"PR 올려줘\", \"푸시해줘\", \"브랜치 따서 PR 만들어줘\", \"변경사항 올려줘\"라고 요청할 때 사용한다."
---

# Review → Push → PR

로컬 변경을 commit으로 고정하고 `mattpocock:code-review`를 통과한 exact SHA만 GitHub에 push한다.

## 사전 조건

| 조건 | 요구 사항 |
|---|---|
| 저장소 | 로컬 clone과 쓰기 가능한 작업 branch |
| 도구 | 인증된 `gh` CLI와 `git` |
| 범위 | 현재 요청에서 바꾼 파일과 대상 base |

## 실행 환경

GitHub 서버에 접속하는 `gh`, `git fetch`, `git push`, `git ls-remote`는 격리 환경 밖의 host CLI에서 실행한다. `git status`, `git add`, `git commit` 같은 local 명령은 격리 환경 안에서 실행해도 된다.

첫 원격 명령 전에 host CLI에서 `gh auth status`를 실행한다. 격리 환경 안의 인증 실패만으로 token 만료를 판단하지 않는다. host CLI에서도 실패할 때만 로그인을 안내하고 중단한다.

## 1. 입력과 base 확정

대화와 저장소에서 다음 값을 찾는다.

| 값 | 결정 규칙 |
|---|---|
| 변경 파일 | 현재 요청에서 작성하거나 수정한 파일만 |
| 저장소 | 현재 remote와 대화 맥락에서 확인 |
| base | 사용자 지정값, 없으면 GitHub default branch |
| branch | 현재 작업 branch 또는 변경 성격을 담은 새 영어 slug |

저장소를 찾을 수 없을 때만 사용자에게 묻는다. 원격 base를 fetch하고 `base_sha`를 기록한다.

```bash
git fetch origin <base_ref>
git rev-parse origin/<base_ref>
```

## 2. local commit snapshot

detached HEAD이거나 base에서 작업 중이면 `codex/` prefix의 새 branch를 만든다. branch 이름이 겹치면 짧은 숫자 suffix를 붙인다.

```bash
git branch --all --list '*<branch_slug>*'
git switch -c codex/<branch_slug>
```

working tree가 dirty하면 현재 요청의 파일만 stage해 첫 commit을 만든다. 아직 push하지 않는다.

```bash
git status --short
git add <허용한 파일>
git commit -m "<type>: <간결한 영어 요약>"
```

working tree가 이미 clean이면 empty commit을 만들지 않는다. `base_sha`보다 앞선 local commit을 review 대상으로 쓴다.

```bash
git status --short
git merge-base --is-ancestor <base_sha> HEAD
git rev-list --count <base_sha>..HEAD
git rev-parse HEAD
```

변경과 local commit이 모두 없으면 중단한다. review 전에 working tree가 clean이어야 한다. 현재 `HEAD`를 `head_sha`로 기록한다. 관련 없는 사용자 변경을 stage, stash, amend, reset하지 않는다.

## 3. local code review gate

push 전에 `mattpocock:code-review`로 `base_sha...head_sha`를 리뷰한다. issue, acceptance criteria, 저장소 Standard를 함께 제공한다.

상위 orchestrator가 아래 clean 증거를 넘겼다면 현재 SHA와 대조한 뒤 재사용할 수 있다. 호출자가 exact SHA를 기록하므로 하위 리뷰 skill이 같은 형식으로 출력할 필요는 없다.

```text
reviewer: mattpocock:code-review
verdict: clean
reviewed_base_sha: <base_sha>
reviewed_head_sha: <head_sha>
```

증거가 없거나 SHA가 다르면 review를 다시 실행한다. finding이 있으면 가장 작은 수정을 구현·검증한 뒤 commit한다.

```bash
git add <수정한 파일>
git commit -m "fix(review): <간결한 영어 요약>"
```

새 commit은 이전 증거를 무효화한다. 최신 전체 diff를 `mattpocock:code-review`로 다시 본다. 제품 결정이나 범위 확대가 필요할 때만 사용자에게 묻는다.

## 4. push 직전 SHA 확인

```bash
git fetch origin <base_ref>
git rev-parse origin/<base_ref>
git rev-parse HEAD
git status --short
```

| 불일치 | 처리 |
|---|---|
| 원격 base ≠ `reviewed_base_sha` | 최신 base를 안전하게 반영하고 검증·`mattpocock:code-review`를 다시 실행 |
| `HEAD` ≠ `reviewed_head_sha` | push 중단 후 최신 SHA를 다시 리뷰 |
| working tree dirty | push 중단 후 변경 범위 확인 |

## 5. exact reviewed SHA push와 PR 생성·갱신

검증된 branch만 push한다.

```bash
git push -u origin <branch>
```

현재 branch의 OPEN PR을 찾는다.

```bash
gh pr view --json number,url,state,headRefOid
```

OPEN PR이 없으면 `gh pr create`로 만든다. 있으면 새 PR을 만들지 않고 같은 PR의 제목과 본문을 갱신한다.

```bash
gh pr create --base <base_ref> --head <branch> --title "<PR 제목>" --body "<PR 본문>"
gh pr edit <번호> --title "<PR 제목>" --body "<PR 본문>"
```

PR 본문은 다음 정보를 담는다.

```markdown
## 개요
[변경 이유를 1~2문장으로]

## 변경 내용
- [핵심 변경]

## 검증
- Matt Pocock code review: `<reviewed_head_sha>`
```

생성·갱신 뒤 GitHub SHA를 대조한다.

```bash
gh pr view <번호> --json headRefOid,url,state
```

`headRefOid`가 `reviewed_head_sha`와 다르면 clean review 완료로 보지 않고 중단한다.

## 6. 결과

PR URL, `reviewed_base_sha`, `reviewed_head_sha`, local 검증 결과를 보고한다.

## 안전 규칙

| 규칙 | 처리 |
|---|---|
| 관련 없는 변경 | stage·commit하지 않음 |
| PR 뒤 새 commit | 기존 증거를 버리고 local code review부터 반복 |
| 상위 clean 증거 | base, head, working tree를 직접 대조한 뒤 재사용 |
| 범위 불명확 | 대상 파일만 사용자에게 확인 |
