#!/bin/bash
# A/B test for PostToolUse hook context savings
#
# Runs claude -p twice with generate_tokens MCP tool:
#   A: MCP_HOOK_ENABLED=0 (hook off)
#   B: MCP_HOOK_ENABLED=1 (hook on)
#
# Compares total context tokens (input + cache_creation + cache_read)
# from --output-format json usage data
#
# Usage:
#   bash test-hook-context.sh [token_count]
#   bash test-hook-context.sh 15000
#   bash test-hook-context.sh 50000

set -euo pipefail

TOKEN_COUNT=${1:-15000}
REPORT_DIR="/tmp/claude-hook-reports"
MODEL="haiku"
PROMPT="Call the generate_tokens tool with count=${TOKEN_COUNT}. Just call the tool once and briefly confirm you called it."

# Clean previous reports
rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

echo "=== PostToolUse Hook Context Test ==="
echo "Token count: $TOKEN_COUNT"
echo "Threshold: ${MAX_MCP_OUTPUT_TOKENS:-10000}"
echo "Model: $MODEL"
echo ""

# Test A: Hook OFF
echo "--- Test A: Hook OFF ---"
MCP_HOOK_ENABLED=0 claude -p "$PROMPT" \
  --model "$MODEL" \
  --output-format json \
  --allowedTools "mcp__test__generate_tokens" \
  --max-turns 3 \
  --no-session-persistence \
  > "$REPORT_DIR/test-a.json" 2>/dev/null || true

# Test B: Hook ON
echo "--- Test B: Hook ON ---"
MCP_HOOK_ENABLED=1 claude -p "$PROMPT" \
  --model "$MODEL" \
  --output-format json \
  --allowedTools "mcp__test__generate_tokens" \
  --max-turns 3 \
  --no-session-persistence \
  > "$REPORT_DIR/test-b.json" 2>/dev/null || true

# Extract token counts
extract_tokens() {
  local file=$1
  jq -r '{
    input: .usage.input_tokens,
    cache_creation: .usage.cache_creation_input_tokens,
    cache_read: .usage.cache_read_input_tokens,
    output: .usage.output_tokens,
    total_context: ((.usage.input_tokens // 0) + (.usage.cache_creation_input_tokens // 0) + (.usage.cache_read_input_tokens // 0))
  }' "$file" 2>/dev/null
}

A_DATA=$(extract_tokens "$REPORT_DIR/test-a.json")
B_DATA=$(extract_tokens "$REPORT_DIR/test-b.json")

A_INPUT=$(echo "$A_DATA" | jq -r '.input')
A_CACHE_CREATE=$(echo "$A_DATA" | jq -r '.cache_creation')
A_CACHE_READ=$(echo "$A_DATA" | jq -r '.cache_read')
A_OUTPUT=$(echo "$A_DATA" | jq -r '.output')
A_TOTAL=$(echo "$A_DATA" | jq -r '.total_context')

B_INPUT=$(echo "$B_DATA" | jq -r '.input')
B_CACHE_CREATE=$(echo "$B_DATA" | jq -r '.cache_creation')
B_CACHE_READ=$(echo "$B_DATA" | jq -r '.cache_read')
B_OUTPUT=$(echo "$B_DATA" | jq -r '.output')
B_TOTAL=$(echo "$B_DATA" | jq -r '.total_context')

# Display results
echo ""
echo "=== Results ==="
echo ""
echo "┌───────────────────────┬──────────────────┬──────────────────┐"
echo "│                       │  Hook OFF (A)    │  Hook ON (B)     │"
echo "├───────────────────────┼──────────────────┼──────────────────┤"
printf "│ input_tokens          │ %16s │ %16s │\n" "$A_INPUT" "$B_INPUT"
printf "│ cache_creation        │ %16s │ %16s │\n" "$A_CACHE_CREATE" "$B_CACHE_CREATE"
printf "│ cache_read            │ %16s │ %16s │\n" "$A_CACHE_READ" "$B_CACHE_READ"
printf "│ output_tokens         │ %16s │ %16s │\n" "$A_OUTPUT" "$B_OUTPUT"
echo "├───────────────────────┼──────────────────┼──────────────────┤"
printf "│ TOTAL CONTEXT         │ %16s │ %16s │\n" "$A_TOTAL" "$B_TOTAL"
echo "└───────────────────────┴──────────────────┴──────────────────┘"

# Calculate savings
if [[ "$A_TOTAL" =~ ^[0-9]+$ ]] && [[ "$B_TOTAL" =~ ^[0-9]+$ ]] && [ "$A_TOTAL" -gt 0 ]; then
  DIFF=$((A_TOTAL - B_TOTAL))
  PERCENT=$((DIFF * 100 / A_TOTAL))
  CACHE_DIFF=$((A_CACHE_CREATE - B_CACHE_CREATE))
  echo ""
  echo "Total context difference: $DIFF tokens ($PERCENT%)"
  echo "Cache creation difference: $CACHE_DIFF tokens"
  echo ""
  if [ "$DIFF" -gt 1000 ]; then
    echo "=> Hook IS reducing context usage"
  elif [ "$DIFF" -gt -1000 ] && [ "$DIFF" -lt 1000 ]; then
    echo "=> No significant difference - updatedMCPToolOutput may NOT replace context"
  else
    echo "=> Hook ON uses MORE tokens (unexpected)"
  fi
fi

echo ""
echo "Raw JSON saved to:"
echo "  $REPORT_DIR/test-a.json (hook OFF)"
echo "  $REPORT_DIR/test-b.json (hook ON)"
