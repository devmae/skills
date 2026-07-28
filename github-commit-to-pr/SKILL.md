---
name: github-commit-to-pr
description: "현재 대화에서 작업한 파일 변경사항을 새 브랜치에 push하고 Pull Request를 자동으로 생성한다. 사용자가 \"PR 올려줘\", \"푸시해줘\", \"브랜치 따서 PR 만들어줘\", \"변경사항 올려줘\" 같은 말을 하거나, 이 스킬을 직접 호출할 때 반드시 사용한다. 코드/문서 작업이 끝난 후 GitHub에 결과물을 올리고 싶을 때 이 스킬을 사용한다."
---
 
# Push & PR 자동화 스킬
 
현재 대화에서 작업한 변경사항을 GitHub에 push하고 Pull Request를 생성하는 워크플로우.
 
---
 
## 사전 조건
 
- 로컬에 git 저장소가 클론되어 있어야 한다.
- `gh` CLI가 설치되어 있고 인증돼 있어야 한다. 시작 전에 `gh auth status` 로 확인하고, 실패하면 사용자에게 `gh auth login` 을 안내하고 중단한다.
---
 
## 워크플로우
 
### 1단계: 컨텍스트 파악
 
대화 맥락에서 다음을 자동으로 파악한다:
 
**변경된 파일 목록**: 현재 대화에서 작성하거나 수정한 파일들. 파일 경로와 최종 내용을 수집한다.
 
**저장소 정보**: owner, repo를 대화 맥락에서 찾는다. 없으면 사용자에게 질문:
> "어떤 저장소에 올릴까요? (예: owner/repo)"
 
**베이스 브랜치**: 대화 맥락에서 기준 브랜치를 파악한다. 명시되지 않았으면 `main` 을 기본으로 사용한다.
 
### 2단계: 브랜치명 결정
 
변경사항의 성격을 파악해 간결한 영어 slug로 브랜치명을 자동 생성한다.
 
패턴 예시:
- 버그 수정 → `fix-{무엇을}`
- 기능 추가 → `add-{무엇을}` 또는 `feat-{무엇을}`
- 문서 업데이트 → `docs-{무엇을}`
- 리팩토링 → `refactor-{무엇을}`

로컬과 원격 브랜치의 중복 여부를 확인한다:

```bash
git branch --all --list '*<브랜치명>*'
```

중복이면 뒤에 `-2`, `-3` 을 붙인다. 중복이 없으면 새 브랜치를 만든다:

```bash
git switch -c <브랜치명>
```
 
### 3단계: PR 생성
 
현재 대화에서 바꾼 파일만 커밋하고 push한다:
 
```bash
git status --short
git add <변경한 파일들>
git commit -m "<commitMessage>"
git push -u origin <브랜치명>
```
 
**`commitMessage`**: 영어로 간결하게.
예: `feat: add dark mode toggle`, `fix: resolve null pointer in auth`
 
**PR 제목**: 변경사항 핵심을 담은 간결한 한국어 제목. 제목의 prefix로 amannn/action-semantic-pull-request를 참고해서 적용한다.
 
**PR 본문 형식**:
```markdown
## 개요
[변경 이유 또는 해결한 문제를 1-2문장으로]
 
## 변경 내용
- [핵심 변경사항 bullet]
- [핵심 변경사항 bullet]
```
 
> PR 본문은 핵심만 담는다. 변경된 모든 것을 나열하기보다, 리뷰어가 맥락을 빠르게 파악할 수 있도록 작성한다.
 
`gh pr create` 로 PR을 만든다:

```bash
gh pr create --base <베이스 브랜치> --head <브랜치명> --title "<PR 제목>" --body "<PR 본문>"
```

### 4단계: PR 링크 제공
 
PR 생성 후 반드시 클릭 가능한 링크를 컨텍스트에 남긴다:
 
```
✅ PR이 생성되었습니다: https://github.com/{owner}/{repo}/pull/{pr_number}
```
 
---
 
## 주의사항
 
- 새 브랜치명은 로컬과 원격에 없어야 한다. 반드시 `git branch --all` 로 확인한다.
- 관련 없는 변경사항을 stage하거나 커밋하지 않는다.
- PR 생성 후 추가 파일이 필요하면 같은 브랜치에 커밋하고 push한다.
- 변경사항이 불분명하면 사용자에게 "어떤 파일을 올릴까요?" 라고 확인한다.
