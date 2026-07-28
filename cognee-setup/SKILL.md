---
name: cognee-setup
description: 지정한 프로젝트에서 Claude Code, Codex, OpenCode, Antigravity와 그 밖의 MCP client가 Cognee memory를 쓰도록 점검하고 설정한다. Git 저장소가 아닌 폴더도 지원한다. native Cognee plugin, MCP 연결, Tailscale, 프로젝트별 COGNEE_BASE_URL / COGNEE_MCP_URL / COGNEE_API_KEY / COGNEE_PLUGIN_DATASET 설정을 검사한다. 사용자가 "cognee 셋업", "cognee 체크", "cognee 환경 확인", "cognee 되는지 봐줘", "기억 서버 연결", "여러 agent에서 기억 공유" 등을 요청할 때 사용한다.
---

# Cognee Setup

프로젝트별 Cognee 연결을 만든다. model 이름이 아니라 Cognee를 실행할 client를 기준으로 설정한다.

## 1. 범위 확정

사용자가 지정한 폴더를 프로젝트 루트로 쓴다. Git 정보로 다른 경로를 고르지 않는다. 경로가 없으면 현재 폴더를 쓴다.

현재 client를 우선 설정한다. 사용자가 여러 client를 말하면 모두 설정한다. client가 불명확하면 설치된 CLI를 검사한다.

환경변수와 secret은 프로젝트 안에만 둔다. user shell의 전역 rc 파일에는 쓰지 않는다. client가 프로젝트별 MCP server 설정을 지원하지 않으면 공식 user 설정에 Cognee 항목만 합친다.

| 연결 | 쓸 때 | 특징 |
| --- | --- | --- |
| `remote` | 원격 Cognee REST API 사용 | Claude, Codex, OpenCode native plugin에 권장 |
| `local` | client 또는 로컬 서비스가 Cognee 실행 | client별 시작 방식이 다름 |
| `mcp` | Antigravity 또는 generic MCP client 사용 | Cognee MCP endpoint가 따로 필요 |
| `hybrid` | native client와 MCP client를 함께 사용 | REST API와 MCP endpoint를 모두 설정 |

Claude, Codex, OpenCode에는 native plugin을 우선 쓴다. native plugin은 session과 tool 사용을 자동 저장한다. Antigravity와 그 밖의 client에는 MCP를 쓴다.

선택한 client의 명령과 설정 파일만 [references/clients.md](references/clients.md)에서 읽는다.

## 2. 검사

`--client`에는 쉼표로 여러 값을 줄 수 있다. 값은 `auto`, `all`, `claude`, `codex`, `opencode`, `antigravity`, `mcp`다.

```bash
bash <이 스킬 경로>/scripts/check.sh <프로젝트 루트> \
  --client <현재 client> \
  --mode remote
```

현재 client를 알면 이름을 명시한다. `auto`는 설치된 client를 모두 검사하므로 client를 모를 때만 쓴다. Tailscale 주소를 쓸 때만 `--require-tailscale`을 붙인다. `--mode auto`는 선택한 client와 프로젝트 env를 보고 mode를 고른다. native client와 MCP client가 함께 있으면 `hybrid`를 쓴다. 아무 값도 없으면 기존 동작과 맞게 `remote`를 쓴다.

스크립트는 현재 shell의 `COGNEE_*` 값을 통과 근거로 쓰지 않는다. 프로젝트 파일과 client 설정만 검사한다.

## 3. 공통 설정

값을 추측하지 않는다. 필요한 값을 사용자가 주지 않으면 파일을 만들지 말고 미완료로 끝낸다.

| 파일 | 내용 |
| --- | --- |
| `.envrc` | 공개 URL, dataset, OpenCode alias, `.envrc.local` load |
| `.envrc.local` | API key, LLM key 같은 secret |
| `.gitignore` | `.envrc.local`과 secret이 든 client 설정 |

`remote` mode의 기본값은 다음과 같다.

```bash
export COGNEE_BASE_URL="..."
export COGNEE_SERVICE_URL="${COGNEE_BASE_URL}"
export COGNEE_PLUGIN_DATASET="..."

if [ -f .envrc.local ]; then
  source .envrc.local
fi
```

```bash
export COGNEE_API_KEY="..."
```

`COGNEE_SERVICE_URL`은 OpenCode가 필요할 때만 넣는다.

`mcp` mode에서는 `.envrc`에 `COGNEE_MCP_URL`과 `COGNEE_PLUGIN_DATASET`을 넣는다. REST API URL에 `/mcp`를 임의로 붙이지 않는다. Cognee MCP server가 실제로 제공하는 endpoint를 받는다. MCP endpoint 인증이 필요하면 `.envrc.local`에 `COGNEE_MCP_BEARER_TOKEN`을 두고 client의 secret 참조로 연결한다.

`hybrid` mode에서는 `remote`와 `mcp`의 공개 설정을 모두 넣는다. 두 경로가 같은 Cognee backend, principal, dataset을 쓰게 맞춘다. REST API key와 MCP bearer token이 같다고 가정하지 않는다.

`local` mode에서는 선택한 client 문서를 따른다. Claude와 Codex plugin은 로컬 runtime을 시작할 수 있다. OpenCode는 기본적으로 `http://localhost:8000`의 Cognee service가 따로 필요하다. generic MCP stdio는 `LLM_API_KEY`와 `cognee-mcp` 경로가 필요하다.

Git worktree에서는 `.envrc`를 추적하고 `.envrc.local`을 ignore한다. Git이 아니면 두 파일을 프로젝트 루트에만 둔다.

`--require-tailscale` 검사에 실패하면 동의를 받은 뒤 `brew install --cask tailscale`을 실행한다. 앱을 열고 Cognee server와 같은 tailnet에 로그인하도록 안내한다.

## 4. client adapter 설치

[references/clients.md](references/clients.md)의 선택한 절만 따라 설치하고 설정한다. 기존 설정을 덮어쓰지 말고 Cognee 항목만 합친다. secret을 추적 파일에 쓰지 않는다.

설치 후 같은 client로 check를 다시 실행한다. `RESULT OK`는 로컬 설정 검사만 통과했다는 뜻이다.

## 5. 적용과 검증

direnv가 있으면 다음을 실행한다.

```bash
direnv allow <프로젝트 루트>
```

없으면 프로젝트 루트에서 `source .envrc` 후 client를 새로 시작하도록 안내한다.

다음 순서로 실제 동작을 검증한다.

| 단계 | 완료 조건 |
| --- | --- |
| 연결 | REST `/health` 또는 client의 MCP 상태가 정상 |
| 쓰기 | project dataset에 고유한 test memory 저장 |
| 읽기 | 같은 client가 test memory recall |
| 공유 | 여러 client를 설정했다면 다른 client가 같은 dataset에서 recall |

API key와 test memory 원문을 로그에 출력하지 않는다. 모든 검증을 통과해야 완료로 보고한다. 실패하면 client, mode, 남은 작업만 짧게 적는다.
