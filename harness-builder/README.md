# harness-builder (Claude Code Skill)

Harness Engineering(Agent = Model + Harness) 기반의 에이전트 하네스를 코드베이스에 구축하는 Claude Code 스킬입니다.

## 설치
이 폴더를 다음 위치에 넣으세요:
- 프로젝트 전용: `<repo>/.claude/skills/harness-builder/`
- 전역 사용: `~/.claude/skills/harness-builder/`

## 사용
어떤 레포에서든 다음과 같이 말하세요:
> "이 프로젝트에 에이전트 하네스를 세팅해줘"

Claude Code가 스킬을 호출해 실제 코드베이스를 조사하고 CLAUDE.md, features.json, 세션 부팅 스크립트, 스프린트 계약/작업 템플릿을 생성합니다.

## 구조
- SKILL.md — 스킬 정의 및 절차
- assets/ — 생성에 쓰이는 템플릿
- references/ — 역할(Planner/Generator/Evaluator) 프롬프트
- harness/ — build-to-delete 감사 체크리스트
