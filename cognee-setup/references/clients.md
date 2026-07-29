# Cognee client 설정

원격 연결은 모두 같은 stdio MCP bridge를 쓴다.

```text
uvx cognee-mcp --api-url https://kimtaehwan-macmini.tail9f3ac8.ts.net/
```

인증 token과 env를 넣지 않는다. 각 memory tool에는 프로젝트 폴더명을 dataset으로 명시한다.

## Claude Code

프로젝트 scope에 등록한다.

```bash
claude mcp add --scope project cognee -- \
  uvx cognee-mcp \
  --api-url https://kimtaehwan-macmini.tail9f3ac8.ts.net/
```

`claude mcp get cognee`로 command와 args를 확인한다. 기존 `cognee-memory` native plugin은 끄거나 지운다.

## Codex

MCP server를 등록한다.

```bash
codex mcp add cognee -- \
  uvx cognee-mcp \
  --api-url https://kimtaehwan-macmini.tail9f3ac8.ts.net/
```

`codex mcp get cognee`로 확인한다. 기존 Cognee native plugin은 끄거나 지운다.

## OpenCode

프로젝트의 기존 `opencode.json` 또는 `opencode.jsonc`에 `mcp.servers.cognee`만 합친다.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "cognee": {
        "type": "local",
        "command": [
          "uvx",
          "cognee-mcp",
          "--api-url",
          "https://kimtaehwan-macmini.tail9f3ac8.ts.net/"
        ]
      }
    }
  }
}
```

기존 `@cognee/cognee-opencode` plugin은 뺀다.

## Antigravity

`~/.gemini/config/mcp_config.json`의 기존 server를 보존하고 `cognee`만 합친다.

```json
{
  "mcpServers": {
    "cognee": {
      "command": "uvx",
      "args": [
        "cognee-mcp",
        "--api-url",
        "https://kimtaehwan-macmini.tail9f3ac8.ts.net/"
      ]
    }
  }
}
```

Antigravity는 이 user 설정을 IDE와 CLI에서 함께 쓴다. project-local 대체 파일을 만들지 않는다.

## Generic MCP client

stdio 설정에 같은 command와 args를 넣는다.

```json
{
  "mcpServers": {
    "cognee": {
      "command": "uvx",
      "args": [
        "cognee-mcp",
        "--api-url",
        "https://kimtaehwan-macmini.tail9f3ac8.ts.net/"
      ]
    }
  }
}
```

client가 local stdio MCP를 지원하지 않으면 이 방식으로 연결할 수 없다. REST URL에 `/mcp`를 붙이지 않는다.

설정 뒤에는 해당 JSON 파일을 검사 명령의 `--mcp-config`에 넘긴다.
