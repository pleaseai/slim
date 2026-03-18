# PostToolUse Hook Context Savings Test

## Overview

Test whether `updatedMCPToolOutput` actually reduces context window usage
by using a custom MCP server that generates exact token amounts.

## Test Results (2026-03-18)

### Finding: `updatedMCPToolOutput` does NOT reduce context

| | Hook OFF | Hook ON | Difference |
|---|---|---|---|
| input_tokens | 23 | 23 | 0 |
| cache_creation | 60,521 | 60,513 | -8 |
| cache_read | 60,052 | 60,052 | 0 |
| **total context** | **~120,573** | **~120,565** | **~8 tokens** |

With `generate_tokens(15000)`, the total context is virtually identical
whether the hook replaces the output or not.

### Analysis

The original MCP tool response is already included in the context **before**
the PostToolUse hook executes. `updatedMCPToolOutput` appears to only affect
what is shown in the transcript/UI, not the actual tokens sent to the model.

### Implications

- `updatedMCPToolOutput` is useful for **logging/UI** but not for **context savings**
- To actually reduce context from large MCP responses, a different approach is needed:
  - PreToolUse hook to intercept before the call
  - MCP server-side response truncation
  - Custom MCP proxy that filters responses before returning

## Setup

### Test MCP Server

`test-mcp-server.ts` - stdio MCP server with one tool:
- `generate_tokens(count)` - returns JSON with ~`count` estimated tokens (chars/4)

### Configuration

`.mcp.json` registers the test server:
```json
{ "test": { "command": "bun", "args": ["test-mcp-server.ts"] } }
```

## Automated Test

```bash
bash test-hook-context.sh [token_count]
bash test-hook-context.sh 15000
bash test-hook-context.sh 50000
```

Uses `claude -p` with `--output-format json` and `--model haiku` for fast, cheap testing.
Compares total context tokens (input + cache_creation + cache_read) between hook ON/OFF.

Note: `total_cost_usd` is not meaningful for subscription users.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_HOOK_ENABLED` | `1` | Enable/disable hook |
| `MCP_HOOK_LOG` | `0` | Log raw input to `/tmp/claude-post-tool-use.log` |
| `MAX_MCP_OUTPUT_TOKENS` | `10000` | Token threshold for replacement |

## Reference

- [PostToolUse Hook Docs](https://code.claude.com/docs/en/hooks#posttooluse-decision-control)
- [CLI Reference](https://code.claude.com/docs/en/cli-reference)
- [Headless Mode](https://code.claude.com/docs/en/headless)
