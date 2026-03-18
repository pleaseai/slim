#!/usr/bin/env bun
/**
 * Test MCP Server - generates exact token amounts for hook testing
 *
 * Tools:
 *   generate_tokens(count): Returns text with approximately `count` estimated tokens
 *                           (uses chars/4 approximation, same as the hook)
 *
 * Usage:
 *   1. Register in .mcp.json: { "test": { "command": "bun", "args": ["test-mcp-server.ts"] } }
 *   2. Call mcp__test__generate_tokens with desired count
 *   3. Compare /cost before and after with hook ON vs OFF
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "test-token-generator",
  version: "1.0.0",
});

server.tool(
  "generate_tokens",
  "Generate text with approximately N estimated tokens (chars/4). Use to test PostToolUse hook context savings.",
  {
    count: z.number().min(1).max(200000).describe("Approximate token count to generate"),
  },
  async ({ count }) => {
    // Hook estimates tokens as chars/4, so generate count*4 chars
    const targetChars = count * 4;

    // Generate realistic-looking JSON data to simulate API responses
    const items: Record<string, unknown>[] = [];
    let currentChars = 0;
    let i = 0;

    while (currentChars < targetChars) {
      const item = {
        id: i,
        name: `item-${i}`,
        description: `This is a test item number ${i} with some descriptive text to simulate real API response data`,
        url: `https://example.com/items/${i}`,
        created_at: new Date(Date.now() - i * 86400000).toISOString(),
        metadata: {
          stars: Math.floor(Math.random() * 10000),
          language: ["TypeScript", "Python", "Rust", "Go"][i % 4],
          topics: ["testing", "mcp", "hooks", "context"],
        },
      };
      items.push(item);
      currentChars += JSON.stringify(item).length;
      i++;
    }

    const result = JSON.stringify({ total_count: items.length, items }, null, 2);
    const estimatedTokens = Math.round(result.length / 4);

    return {
      content: [
        {
          type: "text" as const,
          text: result,
        },
      ],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
