#!/bin/bash
# Stop hook: Measure MCP tool response sizes in transcript for context savings analysis
#
# Reads the transcript JSONL file and calculates:
# - Total MCP tool response chars/tokens
# - Number of MCP tool calls
# - Whether responses were replaced by hook (filePath pattern)
#
# Output saved to /tmp/hook-size-report.json

INPUT=$(cat /dev/stdin)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

REPORT_DIR="/tmp/claude-hook-reports"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/${SESSION_ID:-unknown}.json"

# Parse transcript for tool_result entries from MCP tools
# Transcript is JSONL format - each line is a JSON object
bun -e "
const fs = require('fs');
const lines = fs.readFileSync('${TRANSCRIPT_PATH}', 'utf-8').split('\n').filter(Boolean);

let mcpResponses = [];
let totalMcpChars = 0;
let replacedCount = 0;
let directCount = 0;

for (const line of lines) {
  try {
    const entry = JSON.parse(line);

    // Look for assistant messages with tool_use or tool_result content
    if (entry.type === 'tool_result' || entry.role === 'tool') {
      const content = typeof entry.content === 'string' ? entry.content : JSON.stringify(entry.content);

      // Check if this is an MCP tool response
      if (entry.tool_name?.startsWith('mcp__') || content.includes('mcp__')) {
        const chars = content.length;
        const isReplaced = content.includes('filePath') && content.includes('/tmp/claude-mcp-responses/');

        mcpResponses.push({
          tool_name: entry.tool_name || 'unknown',
          chars,
          estimatedTokens: Math.round(chars / 4),
          replaced: isReplaced,
        });

        totalMcpChars += chars;
        if (isReplaced) replacedCount++;
        else directCount++;
      }
    }
  } catch {}
}

const report = {
  session_id: '${SESSION_ID}',
  hook_enabled: process.env.MCP_HOOK_ENABLED !== '0',
  timestamp: new Date().toISOString(),
  summary: {
    totalMcpCalls: mcpResponses.length,
    totalMcpChars,
    totalEstimatedTokens: Math.round(totalMcpChars / 4),
    replacedByHook: replacedCount,
    directResponses: directCount,
  },
  responses: mcpResponses,
};

fs.writeFileSync('${REPORT_FILE}', JSON.stringify(report, null, 2));

// Also append to combined report
const combinedFile = '${REPORT_DIR}/combined.jsonl';
fs.appendFileSync(combinedFile, JSON.stringify(report) + '\n');

// Print summary to stderr for visibility
console.error(JSON.stringify(report.summary, null, 2));
" 2>/tmp/hook-size-check.log

exit 0
