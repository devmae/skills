# Cognee client 설정

선택한 client 절만 읽는다. 모든 client가 같은 Cognee backend, principal, dataset을 쓰게 맞춰야 기억을 공유할 수 있다.

## Claude Code

native plugin을 설치한다.

```bash
claude plugin marketplace add topoteretes/cognee-integrations
claude plugin install cognee-memory@cognee
```

`remote` mode는 `COGNEE_BASE_URL`, `COGNEE_API_KEY`, `COGNEE_PLUGIN_DATASET`을 읽는다. `local` mode에서는 `COGNEE_BASE_URL`을 비우고 `LLM_API_KEY`를 쓴다.

설치 후 Claude Code를 새로 시작한다. `claude plugin list`에서 `cognee-memory@cognee`를 확인한다.

## Codex

native plugin과 hooks를 설치한다.

```bash
codex features enable hooks
codex plugin marketplace add topoteretes/cognee-integrations --ref main
codex plugin add cognee@cognee
```

`remote` mode는 Claude와 같은 env를 읽는다. 설치 후 Codex를 새로 시작한다. `codex plugin list`에서 `cognee@cognee`가 `installed, enabled`인지 확인한다.

## OpenCode

프로젝트의 기존 `opencode.json` 또는 `opencode.jsonc`에 plugin을 합친다.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@cognee/cognee-opencode"]
}
```

기존 `plugin` 배열과 다른 설정을 보존한다. OpenCode는 REST URL로 `COGNEE_SERVICE_URL`을 읽으므로 `.envrc`에 다음 alias를 둔다.

```bash
export COGNEE_SERVICE_URL="${COGNEE_BASE_URL}"
```

`local` mode에서는 기본 `http://localhost:8000`에 Cognee service가 실행 중이어야 한다. upstream OpenCode plugin의 기본 dataset은 다른 client와 다르므로 `COGNEE_PLUGIN_DATASET`을 반드시 지정한다.

## Antigravity

Antigravity는 Cognee MCP를 쓴다. REST API URL이 아니라 Streamable HTTP 또는 SSE endpoint가 필요하다.

프로젝트의 `.agents/mcp_config.json`에 기존 server를 보존하며 Cognee를 합친다.

```json
{
  "mcpServers": {
    "cognee": {
      "serverUrl": "https://your-cognee-mcp.example/mcp"
    }
  }
}
```

Antigravity remote schema는 `url`이 아니라 `serverUrl`을 쓴다. 인증 header에 key 문자열을 넣어야 한다면 이 파일을 Git에서 ignore한다. 먼저 Antigravity UI, OAuth, OS secret store처럼 key를 저장하지 않는 방법을 쓴다. secret 참조를 지원하는지 확인하지 않고 env 문법을 만들지 않는다.

IDE 또는 CLI의 MCP manager에서 Cognee server가 연결됐는지 확인한다.

## Generic MCP client

client가 Streamable HTTP를 지원하면 `COGNEE_MCP_URL`을 등록한다. stdio만 지원하면 로컬 `cognee-mcp`를 실행한다.

```json
{
  "mcpServers": {
    "cognee": {
      "url": "https://your-cognee-mcp.example/mcp"
    }
  }
}
```

실제 field 이름은 client 문서를 따른다. 예를 들어 Antigravity는 `serverUrl`, OpenCode V2는 `mcp.servers.<name>.url`, Codex는 `codex mcp add --url`을 쓴다.

Codex에서 native plugin 대신 MCP만 쓸 때는 다음처럼 등록한다.

```bash
codex mcp add cognee \
  --url "$COGNEE_MCP_URL" \
  --bearer-token-env-var COGNEE_MCP_BEARER_TOKEN
```

Claude에서는 `claude mcp add --transport http cognee "$COGNEE_MCP_URL"`을 쓴다. OpenCode V2에서는 `mcp.servers.cognee`에 `type: "remote"`와 URL을 넣고, 인증 header 값은 `{env:COGNEE_MCP_BEARER_TOKEN}`으로 참조한다.

native plugin이 없는 client에서는 자동 capture를 보장하지 않는다. client instruction에 project dataset으로 `remember`, `recall`, `improve`를 쓰도록 적고 실제 호출로 검증한다.
## MCP bridge

원격 Cognee REST API가 `/mcp`를 직접 제공하지 않으면 Cognee MCP를 별도로 실행한다. self-hosted backend에는 `--api-url`과 `--api-token`, Cognee Cloud에는 `--serve-url`과 `--serve-api-key`를 쓴다.

MCP endpoint를 만들기 전에는 `COGNEE_BASE_URL` 뒤에 `/mcp`를 붙이지 않는다.
