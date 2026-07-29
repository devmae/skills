---
name: github-issue-to-pr
description: "GitHub 이슈를 받아서 브랜치 생성, 작업 수행, Pull Request 생성까지 전체 워크플로우를 자동화한다. 사용자가 GitHub 이슈 링크를 언급하거나, \"이슈 해결해줘\", \"이슈 작업해줘\", \"PR 만들어줘\", \"브랜치 따줘\" 같은 말을 할 때 반드시 이 스킬을 사용한다. GitHub 이슈 URL이 대화에 등장하면 즉시 이 스킬을 트리거한다."
---
 
# GitHub Issue → PR 자동화 스킬
 
GitHub 이슈를 읽고, 작업을 수행하고, Pull Request를 생성하는 전체 워크플로우.
 
---
 
## 사전 조건

- 로컬에 git 저장소가 클론되어 있어야 한다.
- `gh` CLI가 설치되어 있고 인증돼 있어야 한다.

## 실행 환경

GitHub 서버에 접속하는 CLI 명령은 Codex sandbox 밖에서 실행한다. `gh` 전체와 `git clone`, `git fetch`, `git pull`, `git push`, `git ls-remote` 등이 이에 속한다. `git status`, `git add`, `git commit` 같은 로컬 명령은 sandbox 안에서 실행해도 된다.

시작 전에 sandbox 밖에서 `gh auth status` 를 실행한다. sandbox 안의 인증 실패만으로 token 만료를 판단하거나 `gh auth login` 을 안내하지 않는다. sandbox 밖에서도 실패할 때만 사용자에게 로그인을 안내하고 중단한다.

---
 
## 워크플로우
 
### 1단계: 이슈 링크 확인
 
대화에 GitHub 이슈 URL이 있으면 바로 2단계로 진행한다.
 
없으면 사용자에게 요청:
> "작업할 GitHub 이슈 링크를 알려주세요."
 
이슈 URL에서 `owner`, `repo`, `issue_number` 를 파싱한다.
예: `https://github.com/owner/repo/issues/42` → owner=owner, repo=repo, issue_number=42
 
### 2단계: 이슈 내용 파악
 
`gh issue view` 로 이슈 본문, 제목, 댓글을 읽는다:

```bash
gh issue view <이슈번호> --repo <owner>/<repo> --json number,title,body,state,url,comments
```
 
이슈 내용을 바탕으로:
- **브랜치명 결정**: 이슈 내용을 반영한 간결한 영어 slug. 예: `fix-login-redirect`, `add-dark-mode`, `update-readme-korean`
- **작업 범위 파악**: 코드 수정인지, 문서 업데이트인지, 또는 둘 다인지 판단
- **worktree 생성**: worktree를 생성하여 해당 worktree에서 작업 진행
### 3단계: 작업 수행
 
`rg --files` 와 `rg` 로 관련 파일과 현재 코드·문서 상태를 확인한다. 필요하면 파일을 직접 연다.
 
이슈 해결에 필요한 변경사항을 직접 작성한다:
- 코드 버그 수정, 기능 추가, 리팩토링
- README, 문서, 주석 업데이트
- 설정 파일 변경
변경할 파일 목록과 내용을 준비한다.
 
### 4단계: PR 생성
 
이슈 내용을 반영한 브랜치를 만들고, 변경한 파일만 커밋한 뒤 push한다:

```bash
git branch --all --list '*<브랜치명>*'
git switch -c <브랜치명>
git status --short
git add <변경한 파일들>
git commit -m "<commitMessage>"
git push -u origin <브랜치명>
```
 
**PR 제목**: 이슈 핵심을 담은 간결한 한국어 제목. 제목의 prefix로 amannn/action-semantic-pull-request를 참고해서 적용한다.
**PR 본문 형식**:
 
```markdown
## 개요
[이슈에서 해결하려는 문제를 1-2문장으로]
 
## 변경 내용
- [핵심 변경사항 bullet]
- [핵심 변경사항 bullet]
 
## 관련 이슈
Issues #[이슈번호]
```
 
> PR 본문은 사람이 빠르게 읽을 수 있도록 핵심만 담는다. 긴 설명보다 명확한 bullet이 낫다.
 
**commitMessage**: 영어로 간결하게. 예: `fix: resolve login redirect issue (#42)`
 
`gh pr create` 로 PR을 만든다:

```bash
gh pr create --base <베이스 브랜치> --head <브랜치명> --title "<PR 제목>" --body "<PR 본문>"
```

### 5단계: PR 링크 제공
 
PR 생성 후 반드시 클릭 가능한 링크를 컨텍스트에 남긴다:
 
```
✅ PR이 생성되었습니다: https://github.com/{owner}/{repo}/pull/{pr_number}
```
 
---
 
## 주의사항
 
- 새 브랜치명은 로컬과 원격에 없어야 한다. `git branch --all` 로 미리 확인한다.
- 관련 없는 변경사항을 stage하거나 커밋하지 않는다.
- PR 생성 후 추가 파일이 필요하면 같은 브랜치에 커밋하고 push한다.
- 이슈 내용이 불분명하거나 작업 범위가 크면 사용자에게 먼저 확인한다.
