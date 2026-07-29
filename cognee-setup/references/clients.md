# Cognee client 설정

원격 연결은 모두 같은 stdio MCP bridge를 쓴다.

```text
uvx cognee-mcp --api-url https://kimtaehwan-macmini.tail9f3ac8.ts.net/
```

인증 token과 env를 넣지 않는다. 각 memory tool에는 프로젝트 폴더명을 dataset으로 명시한다.

모든 client에서 user scope만 쓴다. project, local, workspace scope의 `cognee` 설정은 user scope로 옮긴 뒤 지운다. 다른 MCP 설정은 보존한다.

## Claude Code

user scope에 등록한다. `local`과 `project` scope는 쓰지 않는다.

```bash
claude mcp add --scope user cognee -- \
  uvx cognee-mcp \
  --api-url https://kimtaehwan-macmini.tail9f3ac8.ts.net/
```

`claude mcp get cognee`로 scope가 `User`인지, command와 args가 맞는지 확인한다. 기존 `cognee-memory` native plugin은 끄거나 지운다.

## Codex

`codex mcp add`가 쓰는 user 설정 `~/.codex/config.toml`에 등록한다. 프로젝트의 `.codex/config.toml`에는 넣지 않는다.

```bash
codex mcp add cognee -- \
  uvx cognee-mcp \
  --api-url https://kimtaehwan-macmini.tail9f3ac8.ts.net/
```

`codex mcp get cognee`와 `~/.codex/config.toml`의 `[mcp_servers.cognee]`를 확인한다. 기존 Cognee native plugin은 끄거나 지운다.

## OpenCode

user 설정 `~/.config/opencode/opencode.json` 또는 `opencode.jsonc`에 `mcp.servers.cognee`만 합친다. 프로젝트의 `opencode.json`, `opencode.jsonc`, `.opencode/opencode.json`, `.opencode/opencode.jsonc`에는 넣지 않는다.

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

client의 user scope 설정 파일에 같은 command와 args를 넣는다. user scope가 없거나 scope를 구분할 수 없으면 설정하지 않는다.

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

설정 뒤에는 해당 user 설정 JSON 파일의 절대 경로를 검사 명령의 `--mcp-config`에 넘긴다. 프로젝트 안의 파일은 넘기지 않는다.
