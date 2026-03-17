#!/bin/bash
# PostToolUse hook: Save MCP tool response to file, replace output with filePath
#
# Environment variables:
#   MCP_HOOK_ENABLED=1|0  - Enable/disable hook (default: 1)
#   MCP_HOOK_LOG=1|0      - Log raw input to /tmp/claude-post-tool-use.log (default: 0)

# Skip if disabled
if [ "${MCP_HOOK_ENABLED:-1}" = "0" ]; then
  exit 0
fi

INPUT=$(cat /dev/stdin)

# Optional logging
if [ "${MCP_HOOK_LOG:-0}" = "1" ]; then
  echo "$INPUT" | jq . >> /tmp/claude-post-tool-use.log 2>&1
fi

TOOL_USE_ID=$(echo "$INPUT" | jq -r '.tool_use_id')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

# Create response directory
RESPONSE_DIR="/tmp/claude-mcp-responses"
mkdir -p "$RESPONSE_DIR"

RESPONSE_FILE="${RESPONSE_DIR}/${TOOL_USE_ID}.json"

# Extract and save the MCP tool response text to file
echo "$INPUT" | jq -r '.tool_response[0].text // empty' > "$RESPONSE_FILE" 2>/dev/null

# If file is empty or extraction failed, save raw tool_response
if [ ! -s "$RESPONSE_FILE" ]; then
  echo "$INPUT" | jq '.tool_response' > "$RESPONSE_FILE" 2>/dev/null
fi

# Extract top-level keys and structure hint
KEYS=$(jq -r 'if type == "object" then keys | join(", ") elif type == "array" then "array[\(length)] with keys: \(.[0] | keys | join(", "))" else type end' "$RESPONSE_FILE" 2>/dev/null || echo "unknown")

# Output hook response: replace MCP output and add context
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "updatedMCPToolOutput": "{\"filePath\": \"${RESPONSE_FILE}\"}",
    "additionalContext": "MCP tool '${TOOL_NAME}' response saved to ${RESPONSE_FILE}. Response structure: [${KEYS}]. Use Bash with jq to extract only the data you need."
  }
}
EOF
