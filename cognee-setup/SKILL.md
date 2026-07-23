---
name: cognee-setup
description: 현재 repo에서 cognee(claude-code용 cognee-memory 플러그인)를 쓸 수 있는지 점검하고, 부족한 부분을 세팅한다. Tailscale 설치 여부, cognee-memory 플러그인 설치 여부, COGNEE_BASE_URL / COGNEE_API_KEY / COGNEE_PLUGIN_DATASET 환경변수(.envrc) 세팅 여부를 체크하고, 환경변수가 없으면 사용자에게 값을 물어 .envrc에 세팅한다. 사용자가 "cognee 셋업", "cognee 체크", "cognee 환경 확인", "cognee 되는지 봐줘", "기억/메모리 서버 연결 확인" 등을 말하거나, cognee를 처음 쓰려는 repo에서 환경 준비가 필요해 보일 때 반드시 사용한다.
---

# Cognee Setup

repo에서 cognee-memory 플러그인([topoteretes/cognee-integrations](https://github.com/topoteretes/cognee-integrations/tree/main/integrations/claude-code))을 사용하기 위한 환경을 점검하고 세팅하는 스킬. cognee는 Tailscale로 연결된 원격 서버(Mac mini 등)에 기억을 저장하므로, 세 가지가 모두 갖춰져야 동작한다: (1) Tailscale, (2) 플러그인, (3) 환경변수 3종.

## 1단계: 체크 스크립트 실행

repo 루트에서 실행한다:

```bash
bash <이 스킬 경로>/scripts/check.sh <repo 루트>
```

스크립트는 항목별로 `PASS` / `FAIL` / `INFO` 라인을 출력하고, 모두 통과하면 `RESULT OK`(exit 0), 하나라도 실패하면 `RESULT INCOMPLETE`(exit 1)를 낸다. 체크 항목:

1. **Tailscale** — CLI 또는 macOS 앱 설치 여부, 실행(tailnet 연결) 여부. 연결 중이면 tailnet 머신 이름 목록도 출력한다 (COGNEE_BASE_URL 후보로 활용).
2. **cognee-memory 플러그인** — `claude plugin list` 및 `~/.claude/plugins`에서 확인.
3. **환경변수 3종** — 현재 셸 또는 repo의 `.envrc`에 비어있지 않은 값으로 정의되어 있는지: `COGNEE_BASE_URL`, `COGNEE_API_KEY`, `COGNEE_PLUGIN_DATASET`.
4. **부가 점검** — `.envrc`가 git ignore 되는지(API key 커밋 방지), direnv 설치 여부.

## 2단계: FAIL 항목 해결

### Tailscale 미설치

사용자에게 설치가 필요함을 알린다. 설치 자체는 시스템 변경이므로 사용자 동의 후 진행:

```bash
brew install --cask tailscale
```

설치 후 Tailscale 앱을 실행해 로그인해야 tailnet에 연결된다. cognee 서버(Mac mini)와 같은 tailnet에 있어야 함을 설명한다.

### 플러그인 미설치

```bash
claude plugin marketplace add topoteretes/cognee-integrations
claude plugin install cognee-memory@cognee
```

설치 후 Claude Code 재시작이 필요함을 안내한다.

### 환경변수 미설정

**AskUserQuestion 도구로 사용자에게 값을 직접 물어본다.** 추측하거나 더미 값을 넣지 않는다. 세 값의 의미를 질문에 함께 설명한다:

- `COGNEE_BASE_URL` — 어느 서버에 붙을지 (Mac mini의 Tailscale 주소, 예: `http://<tailnet-머신명>:8000`). 체크 스크립트가 출력한 tailnet 머신 목록이 있으면 그 이름들로 URL 후보 선택지를 만들어 제시한다.
- `COGNEE_API_KEY` — 그 서버에 인증할 key. 선택지로 제시할 수 없으므로 사용자가 "Other"에 직접 입력하도록 안내한다.
- `COGNEE_PLUGIN_DATASET` — 기억을 저장할 dataset 이름 (프로젝트별 구분). repo 디렉토리 이름을 추천 선택지로 제시한다. 같은 프로젝트를 여러 기기에서 쓸 때 이 값을 동일하게 맞추면 기억이 공유된다는 점을 설명한다.

**사용자가 값을 제공하지 않으면(모른다고 하거나 건너뛰면) 세팅을 진행하지 말고 미완료로 종료한다.** 빈 값이나 placeholder를 `.envrc`에 쓰는 것은 금지 — 체크는 통과한 것처럼 보이지만 실제로는 동작하지 않는 상태를 만들기 때문이다.

값을 받으면 repo 루트의 `.envrc`에 기록한다 (기존 `.envrc`가 있으면 해당 export 라인만 추가/수정하고 나머지 내용은 보존):

```bash
export COGNEE_BASE_URL="..."
export COGNEE_API_KEY="..."
export COGNEE_PLUGIN_DATASET="..."
```

그리고 반드시 함께 처리한다:

1. **`.gitignore`에 `.envrc` 추가** (이미 ignore되어 있지 않다면) — API key가 커밋되면 안 된다.
2. **direnv 처리** — direnv가 설치되어 있으면 `direnv allow <repo 루트>` 실행. 미설치라면 사용자에게 알린다: `brew install direnv` 후 셸 훅 설정(`eval "$(direnv hook zsh)"` in `~/.zshrc`)을 하거나, 매번 `source .envrc`를 직접 실행해야 한다고 안내.
3. 현재 실행 중인 Claude Code 세션에는 새 환경변수가 적용되지 않으므로, **터미널/Claude Code 재시작 후 플러그인이 원격 서버 모드로 붙는다**는 점을 안내한다.

## 3단계: 재검증 및 완료 판정

FAIL 항목을 해결한 뒤 체크 스크립트를 다시 실행한다.

**완료 조건: `RESULT OK` (exit 0).** 다음 중 하나라도 해당하면 "완료"라고 보고하지 않는다:

- 스크립트가 `RESULT INCOMPLETE`를 반환
- 환경변수 값을 사용자로부터 받지 못함
- Tailscale 또는 플러그인 설치를 사용자가 보류함

미완료로 끝날 때는 무엇이 남았고 사용자가 무엇을 준비하면 되는지(예: "Mac mini의 API key를 확인해서 다시 요청해 주세요")를 명확히 정리해서 보고한다.

완료 시에는 체크 결과 요약과 함께, 재시작 후 Claude Code 상태줄에 `cognee: <dataset> · <mode>`가 표시되면 정상 연결된 것이라고 안내한다.
