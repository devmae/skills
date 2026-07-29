---
name: cognee-setup
description: 지정한 프로젝트에서 Claude Code, Codex, OpenCode, Antigravity와 그 밖의 MCP client가 Tailscale의 원격 Cognee memory를 API key나 프로젝트 env 파일 없이 쓰도록 점검하고 설정한다. Git 저장소가 아닌 폴더도 지원한다. 사용자가 "cognee 셋업", "cognee 체크", "cognee 환경 확인", "cognee 되는지 봐줘", "기억 서버 연결", "여러 agent에서 기억 공유" 등을 요청할 때 사용한다.
---

# Cognee Setup

API key와 프로젝트 env 파일 없이 Cognee를 연결한다. 원격 주소는 스킬에 고정하고 dataset은 프로젝트 폴더명으로 계산한다.

## 1. 범위 확정

사용자가 지정한 폴더를 프로젝트 루트로 쓴다. Git 정보로 다른 경로를 고르지 않는다.

경로가 없으면 local desktop에서 folder picker를 띄운다. GUI 승인이 필요하면 요청한다.

```bash
bash <이 스킬 경로>/scripts/check.sh --pick \
  --client <현재 client> \
  --mode remote
```

picker는 macOS에서 AppleScript, Windows에서 PowerShell을 쓴다. 사용자가 취소하면 멈춘다. GUI를 쓸 수 없으면 이유를 말하고 현재 폴더를 쓸지 확인한다.

현재 client를 우선 설정한다. 사용자가 여러 client를 말하면 모두 설정한다. client가 불명확하면 설치된 CLI를 검사한다.

이 스킬은 `remote` mode만 쓴다. 연결 경로는 local stdio MCP bridge → Tailscale Cognee REST다.

keyless remote mode에서는 native Cognee plugin을 쓰지 않는다. 현재 native plugin은 key를 찾거나 새로 만들기 때문이다. 모든 client에 같은 MCP bridge를 등록한다.

선택한 client 절만 [references/clients.md](references/clients.md)에서 읽는다.

## 2. 고정 규칙

다음 값은 묻거나 파일에서 읽지 않는다.

| 값 | 규칙 |
| --- | --- |
| Cognee REST URL | `https://kimtaehwan-macmini.tail9f3ac8.ts.net/` |
| dataset | 확정한 프로젝트 루트의 폴더명 |
| 인증 | Tailscale grant 또는 ACL |

예: `/work/my-project`의 dataset은 `my-project`다.

프로젝트 env 파일을 만들거나 읽지 않는다. Cognee API key를 만들거나 읽거나 client에 넘기지 않는다. 기존 프로젝트 파일도 이 스킬의 판정 근거로 쓰지 않는다.

remote server는 앱 인증을 꺼야 한다. Tailscale에서 server 접근을 허용할 device, user, tag만 제한한다. public network에 Cognee port를 열지 않는다.

## 3. 설정

remote mode는 다음 bridge를 stdio MCP server로 등록한다.

```bash
uvx cognee-mcp \
  --api-url https://kimtaehwan-macmini.tail9f3ac8.ts.net/
```

token 인자를 추가하지 않는다. URL 뒤에 `/mcp`도 붙이지 않는다. bridge가 REST API를 MCP tool로 바꾼다.

각 client 설정은 [references/clients.md](references/clients.md)를 따른다. 기존 설정을 보존하고 `cognee` 항목만 합친다. native Cognee plugin이 켜져 있으면 중복 저장과 key 발급을 막기 위해 끄거나 지운다.

agent에게 다음 규칙을 준다.

> Cognee의 `remember`, `recall`, `forget`을 쓸 때 dataset을 생략하지 말고 현재 프로젝트 루트의 폴더명을 쓴다.

MCP API mode는 dataset 기본값을 client별로 만들 수 있다. 따라서 모든 memory 호출에 계산한 dataset을 명시해야 여러 client가 기억을 공유한다.

## 4. 검사

`--client` 값은 `auto`, `all`, `claude`, `codex`, `opencode`, `antigravity`, `mcp`다. 쉼표로 여러 값을 줄 수 있다.

```bash
bash <이 스킬 경로>/scripts/check.sh <프로젝트 루트> \
  --client <현재 client> \
  --mode remote \
  --probe
```

`--probe`는 key 없이 `/health`와 `/api/v1/datasets`를 호출한다. `401` 또는 `403`이면 server 앱 인증이 아직 켜진 상태다. 이때 client 설정을 반복하지 말고 server 설정을 고친다.

`remote` mode는 Tailscale 연결, `uvx`, client MCP 등록, 고정 URL, token 인자 부재를 검사한다. `RESULT OK`는 설정과 keyless REST probe가 모두 통과했을 때만 쓴다.

## 5. 실제 검증

다음 순서로 검증한다.

| 단계 | 완료 조건 |
| --- | --- |
| 연결 | client에서 Cognee MCP가 connected |
| 쓰기 | 계산한 dataset에 고유 test memory 저장 |
| 읽기 | 같은 client가 같은 dataset에서 recall |
| 공유 | 다른 client가 같은 dataset에서 recall |

test memory 원문은 로그에 쓰지 않는다. 실패하면 client, 단계, 남은 작업만 짧게 적는다.

## 6. server 조건

Cognee server에서 다음 값을 적용하고 재시작한다. 이 값은 server 서비스 설정에 두며 프로젝트 env 파일에 두지 않는다.

```text
ENABLE_BACKEND_ACCESS_CONTROL=false
REQUIRE_AUTHENTICATION=false
```

Cognee는 loopback에 bind하고 Tailscale Serve로만 연다. 그 뒤 Tailscale grant 또는 ACL의 `src`를 허용할 device의 Tailscale IP `/32`나 전용 tag로 제한하고, `dst`를 Cognee server와 HTTPS port로 제한한다.

IP만 앱에서 검사하지 않는다. Tailscale 정책의 device, user, tag 조건을 쓴다. Serve identity header는 user 식별용이라 exact device allowlist의 대체가 아니다.
