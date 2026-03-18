# PostToolUse Hook Input Schema

> Reference: https://code.claude.com/docs/en/hooks#posttooluse-decision-control

PostToolUse hooks fire after a tool has already executed successfully. The input is provided via stdin as JSON.

## Schema

The input includes both `tool_input` (the arguments sent to the tool) and `tool_response` (the result it returned). The exact schema for both depends on the tool.

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../00893aaf.jsonl",
  "cwd": "/Users/...",
  "permission_mode": "default",
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_input": { ... },
  "tool_response": { ... },
  "tool_use_id": "toolu_01ABC123..."
}
```

## Example: MCP tool (GitHub search_repositories)

MCP tool responses are wrapped in a `[{type, text}]` array format.

```json
{
  "session_id": "71e3fceb-2a70-46c8-a7e5-cd3fd366d1c7",
  "transcript_path": "/Users/lms/.claude/projects/-Users-lms-conductor-workspaces-slim-boston-v1/71e3fceb-2a70-46c8-a7e5-cd3fd366d1c7.jsonl",
  "cwd": "/Users/lms/conductor/workspaces/slim/boston-v1",
  "permission_mode": "default",
  "hook_event_name": "PostToolUse",
  "tool_name": "mcp__plugin_github_github__search_repositories",
  "tool_input": {
    "query": "repo:pleaseai/slim",
    "minimal_output": false
  },
  "tool_response": [
    {
      "type": "text",
      "text": "{\"total_count\":1,...}"
    }
  ],
  "tool_use_id": "toolu_016g7Md7hhy7t2eGvpdJXVqq"
}
```

## Decision Control (Hook Output)

PostToolUse hooks can provide feedback to Claude by writing JSON to stdout. The hook script can return these fields:

| Field | Description |
|-------|-------------|
| `decision` | `"block"` prompts Claude with the reason. Omit to allow the action to proceed |
| `reason` | Explanation shown to Claude when decision is `"block"` |
| `additionalContext` | Additional context for Claude to consider |
| `updatedMCPToolOutput` | For MCP tools only: replaces the tool's output with the provided value |

### Example: Block with reason

```json
{
  "decision": "block",
  "reason": "Explanation for decision",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Additional information for Claude"
  }
}
```

### Example: Replace MCP tool output

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "updatedMCPToolOutput": "{ \"transformed\": true }"
  }
}
```

## MCP Output Schema 현황

MCP spec (2025-06-18~)에 `outputSchema`가 정의되어 있으나, Claude Code에서는 사용할 수 없음.

| 항목 | 상태 |
|------|------|
| MCP spec | `outputSchema` 지원 (2025-06-18~) |
| Python/TypeScript/Ruby SDK | 구현 중이나 버그 다수 |
| **Claude Code** | `outputSchema` 포함 시 tool이 무시됨 ([#25081](https://github.com/anthropics/claude-code/issues/25081)) |
| GitHub MCP server | `outputSchema` 미제공 |

### 현재 해결 방법

PostToolUse hook에서 응답을 파일로 저장하고 top-level keys를 `additionalContext`로 전달하는 방식으로 대체.

- 스크립트: `.claude/hooks/post-mcp-tool-use.sh`
- 응답 저장 경로: `/tmp/claude-mcp-responses/{tool_use_id}.json`
- `updatedMCPToolOutput`: `{"filePath": "..."}` 로 대체하여 context 절약
- `additionalContext`: 응답의 top-level keys + jq 사용 안내

### TODO: MCP Output Schema Registry

추후 유명 MCP server들의 output schema를 정의하거나 가져오는 방법 추가 예정.
hook에서 tool_name 기반으로 알려진 output schema를 매칭하여 `additionalContext`에 포함시키는 방식 검토.

## Context 절약 효과 테스트 방법

Hook 적용 전후의 context 사용량 차이를 측정하는 방법.

### 방법 1: `/cost` 비교 (권장)

가장 간단하고 직관적인 방법. Claude Code에서 `/cost` 입력 시 토큰 사용량 확인 가능.

1. **세션 A** (hook 비활성): settings.json에서 hooks 제거 → 새 세션 시작
2. **세션 B** (hook 활성): hooks 복원 → 새 세션 시작
3. 양쪽 세션에서 동일한 MCP 호출 수행
4. 각 호출 전후 `/cost` 확인하여 input tokens 증가량 비교

| 단계 | 세션 A (hook 없음) | 세션 B (hook 있음) |
|------|---|---|
| MCP 호출 전 | `/cost` 확인 | `/cost` 확인 |
| MCP 호출 5회 후 | `/cost` 확인 | `/cost` 확인 |
| 차이 | input tokens 차이 비교 | input tokens 차이 비교 |

### 방법 2: Transcript 파일 크기 비교

각 세션의 transcript 파일(`.jsonl`)에 모든 tool 호출/응답이 기록됨.

```bash
# 세션 transcript 경로 확인 (PostToolUse hook 로그에서 transcript_path 참조)
ls -lh ~/.claude/projects/-Users-lms-conductor-workspaces-slim-boston-v1/*.jsonl
```

### 방법 3: Compact 시점 비교

장기 테스트. 대량 MCP 호출 시 hook 적용 세션이 context window compact 없이 더 오래 유지되는지 확인.

### 예상 효과

- `search_repositories` (minimal_output=false): ~3,000+ tokens → ~80 tokens (97% 절감)
- 단, jq 실행을 위한 Bash tool 호출 1회 추가 비용 발생
- 대량/반복적 MCP 호출이 많을수록 효과 큼

## Key Observations

- **MCP tools**: `tool_response` is an array of `{type: "text", text: "..."}` objects where `text` contains the JSON-stringified result
- `tool_input` matches exactly what was sent to the tool
- Hook scripts can **block** tool results, **add context**, or **replace MCP tool output** by writing JSON to stdout
- `updatedMCPToolOutput` only works for MCP tools, not built-in tools
