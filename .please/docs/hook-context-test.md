# PostToolUse Hook Context Savings Test

## Overview

Test whether `updatedMCPToolOutput` actually reduces context window usage
by using a custom MCP server that generates exact token amounts.

## Setup

### Test MCP Server

`test-mcp-server.ts` - stdio MCP server with one tool:
- `generate_tokens(count)` - returns JSON with ~`count` estimated tokens (chars/4)

### Configuration

`.mcp.json` registers the test server:
```json
{ "test": { "command": "bun", "args": ["test-mcp-server.ts"] } }
```

## Test Procedure

### Session A: Hook OFF

```bash
MCP_HOOK_ENABLED=0 claude
```

1. `/cost` - record baseline
2. Call `generate_tokens(5000)` - below threshold
3. `/cost` - record delta A1
4. Call `generate_tokens(15000)` - above threshold
5. `/cost` - record delta A2
6. Call `generate_tokens(50000)` - well above threshold
7. `/cost` - record delta A3

### Session B: Hook ON

```bash
MCP_HOOK_ENABLED=1 claude
# or just: claude (default is enabled)
```

1. `/cost` - record baseline
2. Call `generate_tokens(5000)` - below threshold (should pass through)
3. `/cost` - record delta B1
4. Call `generate_tokens(15000)` - above threshold (should replace)
5. `/cost` - record delta B2
6. Call `generate_tokens(50000)` - well above threshold (should replace)
7. `/cost` - record delta B3

### Expected Results

| count  | Hook OFF (delta) | Hook ON (delta) | Savings |
|--------|-----------------|-----------------|---------|
| 5,000  | ~5,000 tokens   | ~5,000 tokens   | 0% (below threshold) |
| 15,000 | ~15,000 tokens  | ~200 tokens     | ~98%    |
| 50,000 | ~50,000 tokens  | ~200 tokens     | ~99%    |

### Verification

- Delta B1 should equal Delta A1 (below threshold, no replacement)
- Delta B2 should be << Delta A2 (above threshold, replaced)
- Delta B3 should be << Delta A3 (well above threshold, replaced)

## Key Question

Does `updatedMCPToolOutput` **replace** what enters the context window,
or does the original response **already exist** in context before the hook runs?

If deltas are similar between A and B for above-threshold calls,
then the original response is already in context and `updatedMCPToolOutput`
only appends rather than replaces.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_HOOK_ENABLED` | `1` | Enable/disable hook |
| `MCP_HOOK_LOG` | `0` | Log raw input to `/tmp/claude-post-tool-use.log` |
| `MAX_MCP_OUTPUT_TOKENS` | `10000` | Token threshold for replacement |

## Reference

- [PostToolUse Hook Docs](https://code.claude.com/docs/en/hooks#posttooluse-decision-control)
