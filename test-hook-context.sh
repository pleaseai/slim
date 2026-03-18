#!/bin/bash
# A/B test for PostToolUse hook context savings
#
# Runs claude -p twice with generate_tokens MCP tool:
#   A: MCP_HOOK_ENABLED=0 (hook off)
#   B: MCP_HOOK_ENABLED=1 (hook on)
#
# Results saved to /tmp/claude-hook-reports/
#
# Usage:
#   bash test-hook-context.sh [token_count]
#   bash test-hook-context.sh 15000

set -euo pipefail

TOKEN_COUNT=${1:-15000}
REPORT_DIR="/tmp/claude-hook-reports"

# Clean previous reports
rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

echo "=== PostToolUse Hook Context Test ==="
echo "Token count: $TOKEN_COUNT"
echo "Threshold: ${MAX_MCP_OUTPUT_TOKENS:-10000}"
echo ""

# Test A: Hook OFF
echo "--- Test A: Hook OFF ---"
MCP_HOOK_ENABLED=0 claude -p "Call generate_tokens with count=$TOKEN_COUNT. Just call the tool and report the estimated token count from the response." --allowedTools "mcp__test__generate_tokens" 2>/dev/null || true
echo ""

# Test B: Hook ON
echo "--- Test B: Hook ON ---"
MCP_HOOK_ENABLED=1 claude -p "Call generate_tokens with count=$TOKEN_COUNT. Just call the tool and report the estimated token count from the response." --allowedTools "mcp__test__generate_tokens" 2>/dev/null || true
echo ""

# Compare results
echo "=== Results ==="
if [ -f "$REPORT_DIR/combined.jsonl" ]; then
  echo "Reports:"
  cat "$REPORT_DIR/combined.jsonl" | jq -s '
    . as $reports |
    {
      test_token_count: '"$TOKEN_COUNT"',
      results: [
        $reports[] | {
          hook_enabled: .hook_enabled,
          total_mcp_tokens: .summary.totalEstimatedTokens,
          replaced_by_hook: .summary.replacedByHook,
          direct_responses: .summary.directResponses
        }
      ]
    }
  '
else
  echo "No reports generated. Check /tmp/hook-size-check.log for errors."
fi
