# slim

A Claude Code plugin that compresses MCP tool output to reduce token usage and improve context efficiency.

## Overview

MCP tools often return verbose, structured data that consumes large amounts of context window tokens. `slim` intercepts and compresses MCP output by stripping redundant fields, truncating large payloads, and summarizing repetitive content — without losing the information Claude needs to complete tasks.

## Features

- Automatically compress MCP tool responses via PostToolUse hooks
- Configurable compression strategies per MCP server or tool
- Token usage reporting before/after compression
- Lossless mode (structure-preserving) and lossy mode (aggressive summarization)
- Works with all MCP server types: stdio, SSE, HTTP, WebSocket

## Installation

### From local directory

```bash
claude plugin install /path/to/slim
```

### Enable the plugin

```bash
claude plugin enable slim
```

Or via Claude Code settings UI: **Settings > Plugins > slim > Enable**

## How It Works

`slim` registers a `PostToolUse` hook that intercepts responses from MCP tools before they are added to the context window. The hook applies compression rules based on the tool name and response structure:

1. **Field filtering** — removes known low-value fields (e.g., metadata, audit timestamps, internal IDs)
2. **Array truncation** — limits list responses to a configurable maximum length with a count summary
3. **String truncation** — shortens long string values with ellipsis and byte count
4. **Deduplication** — collapses repeated object patterns into a representative sample

## Configuration

Configuration is managed via Claude Code plugin settings. Create or edit `.claude-plugin/settings.local.md` in the plugin directory:

```md
# slim settings

maxArrayLength: 20
maxStringLength: 500
mode: lossless
excludeTools:
  - mcp__my_server__sensitive_tool
```

### Options

| Option | Default | Description |
|---|---|---|
| `mode` | `lossless` | `lossless` preserves structure; `lossy` aggressively summarizes |
| `maxArrayLength` | `20` | Maximum number of array items to retain |
| `maxStringLength` | `500` | Maximum character length for string values |
| `excludeTools` | `[]` | List of MCP tool names to skip compression |

### Environment Variables

You can also control behavior via environment variables or by adding them to your shell profile (`.zshrc`, `.bashrc`) or Claude Code's `settings.json`.

| Variable | Default | Description |
|---|---|---|
| `ENABLE_TOOL_SEARCH` | `auto` | Controls MCP tool search behavior |

#### `ENABLE_TOOL_SEARCH` values

| Value | Behavior |
|---|---|
| `auto` | Enables tool search automatically when context reaches 10% remaining |
| `auto:N` | Enables tool search at a custom threshold (e.g., `auto:5` = 5% remaining) |
| `true` | Always enables tool search |
| `false` | Disables tool search entirely |

**Recommended:** Use `auto` (default) for most cases. Use `auto:N` to tune the threshold if you find tool search triggering too early or too late.

**Example — set in shell profile:**

```bash
export ENABLE_TOOL_SEARCH=auto:5
```

**Example — set in `settings.json`:**

```json
{
  "env": {
    "ENABLE_TOOL_SEARCH": "auto:5"
  }
}
```

## Plugin Structure

```
slim/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── hooks/
│   ├── hooks.json           # PostToolUse hook registration
│   └── scripts/
│       └── compress.js      # Compression logic
├── skills/
│   └── slim-output/
│       └── SKILL.md         # Usage guidance skill
└── README.md
```

## Requirements

- Claude Code v1.0+
- Node.js 18+ (for the compression hook script)

## Development

```bash
# Clone the repository
git clone https://github.com/pleaseai/slim.git
cd slim

# Install dependencies
npm install

# Install plugin locally for testing
claude plugin install .
claude plugin enable slim
```

Run Claude Code with debug logging to observe compression activity:

```bash
claude --debug
```

## License

MIT