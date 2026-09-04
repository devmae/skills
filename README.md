# Skills

반복 작업을 더 빠르고 일관되게 처리하는 Agent Skill 모음입니다. Agent Skills를 지원하는 여러 client에서 쓸 수 있습니다. 각 폴더의 `SKILL.md`에 사용 조건과 작업 절차를 담았습니다.

| 스킬 | 소개 |
| --- | --- |
| `cognee-setup` | Claude Code, Codex, OpenCode, Antigravity와 MCP client의 Cognee memory를 점검하고 설정합니다. |
| `explain-simply` | 직전 설명·리뷰 결과·작업 내용을 쉬운 말로 다시 설명합니다. |
| `game-audio-organizer` | 게임 오디오를 실제 음원 기준으로 분석해 MUSIC, VOICE, SFX 폴더로 분류합니다. |
| `github-commit-to-pr` | 로컬 commit을 Matt Pocock review한 뒤 exact SHA로 Pull Request를 생성·갱신합니다. |
| `github-issue-to-pr` | GitHub 이슈를 구현하고 Matt Pocock review를 거쳐 Pull Request를 생성합니다. |
| `github-pr-hitl-merge` | Pull Request 전체를 HITL comment로 요약한 뒤 같은 SHA를 merge합니다. |
| `github-merge-clean` | 검증된 Pull Request를 merge하고 branch·linked issue를 정리합니다. |
| `github-pr-review-merge` | Pull Request를 리뷰·수정한 뒤 `github-merge-clean`으로 넘깁니다. |
| `harness-builder` | 코드베이스에 문서, 진행 추적, 검증 절차를 갖춘 Agent harness를 만듭니다. |
| `issue-loop-mattpocock` | GitHub 이슈를 구현하고 Matt Pocock review, HITL 기록, merge까지 순차 처리합니다. |
| `project-discovery-architecture` | 초기 아이디어를 제품 목표, 기술 결정, 단계별 개발 계획으로 구체화합니다. |
| `vat-filing` | 국내 1인 모바일 게임 사업자의 부가가치세 자료 수집, 계산, 신고 검증을 돕습니다. |

## 설치 없이 한 번 사용

[`skills`](https://github.com/vercel-labs/skills) CLI의 `use` 명령으로 스킬을 설치하지 않고 한 세션에서 쓸 수 있습니다. 이 명령은 선택한 스킬을 임시 폴더에 받고 `SKILL.md`와 지원 파일 경로를 Agent prompt에 넣습니다. 프로젝트나 사용자 스킬 폴더에는 파일을 만들지 않습니다.

Node.js와 사용할 Agent CLI를 먼저 준비해야 합니다.

### Codex

작업할 프로젝트에서 다음 명령을 실행합니다.

```bash
npx -y skills use devmae/skills \
  --skill project-discovery-architecture \
  --agent codex
```

Codex가 열리면 작업 내용을 입력합니다.

### Claude Code

```bash
npx -y skills use devmae/skills \
  --skill project-discovery-architecture \
  --agent claude-code
```

Claude Code가 열리면 작업 내용을 입력합니다.

### 로컬 clone 사용

GitHub에서 다시 받지 않고 현재 clone을 쓸 수도 있습니다.

```bash
npx -y skills use /path/to/skills \
  --skill game-audio-organizer \
  --agent codex
```

`/path/to/skills`를 이 repo의 절대 경로로 바꿉니다.

### 비대화형 한 번 실행

스킬과 작업 내용을 한 prompt로 만들어 Codex를 실행합니다.

```bash
(
  npx -y skills use devmae/skills \
    --skill project-discovery-architecture
  printf '\n\nUser request: 새 프로젝트 기획을 도와줘\n'
) | codex exec -C /path/to/project -
```

Claude Code에서는 다음 명령을 실행합니다.

```bash
(
  npx -y skills use devmae/skills \
    --skill project-discovery-architecture
  printf '\n\nUser request: 새 프로젝트 기획을 도와줘\n'
) | claude -p
```

`npx`는 `skills` CLI를 전역 설치하지 않지만 npm cache는 남길 수 있습니다. 기본 명령은 최신 `skills` 버전을 사용합니다. CI처럼 같은 실행 결과가 중요할 때만 `skills@1.5.20`처럼 버전을 고정합니다.
