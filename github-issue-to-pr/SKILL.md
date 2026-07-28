---
name: github-issue-to-pr
description: "GitHub 이슈를 받아서 브랜치 생성, 작업 수행, Pull Request 생성까지 전체 워크플로우를 자동화한다. 사용자가 GitHub 이슈 링크를 언급하거나, \"이슈 해결해줘\", \"이슈 작업해줘\", \"PR 만들어줘\", \"브랜치 따줘\" 같은 말을 할 때 반드시 이 스킬을 사용한다. GitHub 이슈 URL이 대화에 등장하면 즉시 이 스킬을 트리거한다."
---
 
# GitHub Issue → PR 자동화 스킬
 
GitHub 이슈를 읽고, 작업을 수행하고, Pull Request를 생성하는 전체 워크플로우.
 
---
 
## 도구 정보
 
Mermaid Chart MCP를 통해 GitHub에 접근한다. 모든 도구 호출에 `clientName: "github-issue-to-pr-skill"` 을 포함한다.
 
사용 가능한 도구:
- `list_issues` — 이슈 목록 조회
- `get_issue_comments` — 이슈 댓글 조회
- `list_branches` — 브랜치 목록 조회
- `read_mermaid_file` — 파일 내용 읽기
- `list_mermaid_files` — 파일 목록 조회
- `create_pr` — 브랜치 생성 + 파일 커밋 + PR 오픈 (한 번에)
- `push_file` — 기존 브랜치에 파일 추가/수정
---
 
## 워크플로우
 
### 1단계: 이슈 링크 확인
 
대화에 GitHub 이슈 URL이 있으면 바로 2단계로 진행한다.
 
없으면 사용자에게 요청:
> "작업할 GitHub 이슈 링크를 알려주세요."
 
이슈 URL에서 `owner`, `repo`, `issue_number` 를 파싱한다.
예: `https://github.com/owner/repo/issues/42` → owner=owner, repo=repo, issue_number=42
 
### 2단계: 이슈 내용 파악
 
`list_issues` 로 해당 이슈를 조회한다 (state: "all", 이슈 번호로 필터). 이슈 본문과 제목을 읽는다.
필요하면 `get_issue_comments` 로 댓글도 확인한다.
 
이슈 내용을 바탕으로:
- **브랜치명 결정**: 이슈 내용을 반영한 간결한 영어 slug. 예: `fix-login-redirect`, `add-dark-mode`, `update-readme-korean`
- **작업 범위 파악**: 코드 수정인지, 문서 업데이트인지, 또는 둘 다인지 판단
- **worktree 생성**: worktree를 생성하여 해당 worktree에서 작업 진행
### 3단계: 작업 수행
 
저장소의 관련 파일을 파악하기 위해 `list_mermaid_files` 와 `read_mermaid_file` 을 활용해 현재 코드/문서 상태를 확인한다.
 
이슈 해결에 필요한 변경사항을 직접 작성한다:
- 코드 버그 수정, 기능 추가, 리팩토링
- README, 문서, 주석 업데이트
- 설정 파일 변경
변경할 파일 목록과 내용을 준비한다.
 
### 4단계: PR 생성
 
`create_pr` 로 브랜치 생성 + 커밋 + PR을 한 번에 만든다.
 
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
 
### 5단계: PR 링크 제공
 
PR 생성 후 반드시 클릭 가능한 링크를 컨텍스트에 남긴다:
 
```
✅ PR이 생성되었습니다: https://github.com/{owner}/{repo}/pull/{pr_number}
```
 
---
 
## 주의사항
 
- `create_pr` 의 `headBranch` 는 **존재하지 않는** 새 브랜치명이어야 한다. `list_branches` 로 중복 여부를 미리 확인한다.
- 파일 수정이 여러 개인 경우 `create_pr` 의 `files` 배열에 모두 담아 한 번에 커밋한다.
- PR 생성 후 추가 파일을 더 올려야 한다면 `push_file` 로 같은 브랜치에 커밋을 추가한다.
- 이슈 내용이 불분명하거나 작업 범위가 크면 사용자에게 먼저 확인한다.