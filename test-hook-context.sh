#!/bin/bash
# A/B test for PostToolUse hook context savings
#
# Runs claude -p twice with generate_tokens MCP tool:
#   A: MCP_HOOK_ENABLED=0 (hook off)
#   B: MCP_HOOK_ENABLED=1 (hook on)
#
# Compares input_tokens from --output-format json usage data
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

# Compare results
echo ""
echo "=== Results ==="

A_INPUT=$(jq -r '.usage.input_tokens // "N/A"' "$REPORT_DIR/test-a.json" 2>/dev/null || echo "N/A")
A_OUTPUT=$(jq -r '.usage.output_tokens // "N/A"' "$REPORT_DIR/test-a.json" 2>/dev/null || echo "N/A")
A_COST=$(jq -r '.cost_usd // "N/A"' "$REPORT_DIR/test-a.json" 2>/dev/null || echo "N/A")

B_INPUT=$(jq -r '.usage.input_tokens // "N/A"' "$REPORT_DIR/test-b.json" 2>/dev/null || echo "N/A")
B_OUTPUT=$(jq -r '.usage.output_tokens // "N/A"' "$REPORT_DIR/test-b.json" 2>/dev/null || echo "N/A")
B_COST=$(jq -r '.cost_usd // "N/A"' "$REPORT_DIR/test-b.json" 2>/dev/null || echo "N/A")

echo ""
echo "┌─────────────────┬──────────────────┬──────────────────┐"
echo "│                 │  Hook OFF (A)    │  Hook ON (B)     │"
echo "├─────────────────┼──────────────────┼──────────────────┤"
printf "│ input_tokens    │ %16s │ %16s │\n" "$A_INPUT" "$B_INPUT"
printf "│ output_tokens   │ %16s │ %16s │\n" "$A_OUTPUT" "$B_OUTPUT"
printf "│ cost_usd        │ %16s │ %16s │\n" "$A_COST" "$B_COST"
echo "└─────────────────┴──────────────────┴──────────────────┘"

# Calculate savings if both are numbers
if [[ "$A_INPUT" =~ ^[0-9]+$ ]] && [[ "$B_INPUT" =~ ^[0-9]+$ ]]; then
  DIFF=$((A_INPUT - B_INPUT))
  if [ "$A_INPUT" -gt 0 ]; then
    PERCENT=$((DIFF * 100 / A_INPUT))
    echo ""
    echo "Input token difference: $DIFF ($PERCENT% reduction)"
    if [ "$DIFF" -gt 1000 ]; then
      echo "=> Hook IS reducing context usage"
    elif [ "$DIFF" -gt -1000 ] && [ "$DIFF" -lt 1000 ]; then
      echo "=> No significant difference - hook may NOT be replacing context"
    else
      echo "=> Hook ON uses MORE tokens (unexpected)"
    fi
  fi
fi

echo ""
echo "Raw JSON saved to:"
echo "  $REPORT_DIR/test-a.json (hook OFF)"
echo "  $REPORT_DIR/test-b.json (hook ON)"
