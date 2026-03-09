#!/usr/bin/env bun
/**
 * PostToolUse hook: compresses MCP tool output before it enters Claude's context.
 * Reads JSON from stdin, calls `claude -p` for compression, outputs updatedMCPToolOutput.
 */

import path from "path";
import type { PostToolUseHookInput, SyncHookJSONOutput } from "@anthropic-ai/claude-agent-sdk";

const CONFIG_PATH = path.join(import.meta.dir, "slim.config.json");

interface SlimConfig {
  minSize: number;
  minReduction: number;
  maxInputChars: number;
  excludeTools: string[];
  useTranscript: boolean;
  transcriptLines: number;
  model: string | null;
  timeout: number;
}

const DEFAULT_CONFIG: SlimConfig = {
  minSize: 500,
  minReduction: 0.2,
  maxInputChars: 50000,
  excludeTools: [],
  useTranscript: false,
  transcriptLines: 10,
  model: null,
  timeout: 50000,
};

const SYSTEM_PROMPT = `You are a data compression specialist. Compress the MCP tool output below into a shorter version that preserves all actionable information.

Rules:
- Output ONLY the compressed text, nothing else
- Preserve all: IDs, URLs, file paths, error messages, counts, dates, names
- Remove: redundant metadata, verbose descriptions, boilerplate, repeated patterns
- For arrays of similar objects: show 2-3 examples then summarize the rest
- For deeply nested JSON: flatten to key facts
- Target 10-30% of original length`;

const JSON_SCHEMA = JSON.stringify({
  type: "object",
  properties: {
    compressed: { type: "string" },
  },
  required: ["compressed"],
});

async function loadConfig(): Promise<SlimConfig> {
  try {
    const file = Bun.file(CONFIG_PATH);
    if (!(await file.exists())) return { ...DEFAULT_CONFIG };
    const raw = await file.text();
    return { ...DEFAULT_CONFIG, ...(JSON.parse(raw) as Partial<SlimConfig>) };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

function isExcluded(toolName: string, excludeTools: string[]): boolean {
  if (excludeTools.length === 0) return false;
  return excludeTools.some((pattern) => {
    try {
      return new RegExp(pattern).test(toolName);
    } catch {
      return pattern === toolName;
    }
  });
}

async function extractTranscriptContext(
  transcriptPath: string,
  lines: number,
): Promise<string | null> {
  try {
    const file = Bun.file(transcriptPath);
    if (!(await file.exists())) return null;
    const content = await file.text();
    const allLines = content.trim().split("\n");
    const recentLines = allLines.slice(-lines);
    const messages: string[] = [];
    for (const line of recentLines) {
      try {
        const entry = JSON.parse(line) as { role?: string; content?: unknown };
        if (entry.role && entry.content) {
          const text =
            typeof entry.content === "string"
              ? entry.content
              : Array.isArray(entry.content)
                ? (entry.content as Array<{ type: string; text: string }>)
                    .filter((c) => c.type === "text")
                    .map((c) => c.text)
                    .join(" ")
                : "";
          if (text) messages.push(`${entry.role}: ${text.slice(0, 200)}`);
        }
      } catch {
        // skip malformed lines
      }
    }
    return messages.length > 0 ? messages.join("\n") : null;
  } catch {
    return null;
  }
}

function toolResponseToString(toolResponse: unknown): string {
  if (typeof toolResponse === "string") return toolResponse;
  try {
    return JSON.stringify(toolResponse, null, 2);
  } catch {
    return String(toolResponse);
  }
}

async function compress(
  toolName: string,
  toolInput: unknown,
  toolResponse: unknown,
  config: SlimConfig,
  transcriptPath: string,
): Promise<string | null> {
  const responseStr = toolResponseToString(toolResponse);

  if (responseStr.length < config.minSize) return null;
  if (isExcluded(toolName, config.excludeTools)) return null;

  let contextBlock = "";
  if (config.useTranscript && config.transcriptLines > 0) {
    const ctx = await extractTranscriptContext(transcriptPath, config.transcriptLines);
    if (ctx) contextBlock = `\nTask context:\n${ctx}\n`;
  }

  const inputStr = JSON.stringify(toolInput ?? {});
  const payload = [
    `Tool: ${toolName}`,
    `Input: ${inputStr.slice(0, 500)}`,
    contextBlock,
    `Output:\n${responseStr}`,
  ]
    .join("\n")
    .slice(0, config.maxInputChars);

  const args = [
    "-p",
    payload,
    "--system-prompt",
    SYSTEM_PROMPT,
    "--max-turns",
    "1",
    "--output-format",
    "json",
    "--json-schema",
    JSON_SCHEMA,
  ];

  if (config.model) {
    args.push("--model", config.model);
  }

  let result: ReturnType<typeof Bun.spawnSync>;
  try {
    result = Bun.spawnSync(["claude", ...args], {
      stdout: "pipe",
      stderr: "pipe",
      timeout: config.timeout,
    });
  } catch {
    return null;
  }

  if (!result.success) return null;

  const stdout = result.stdout.toString("utf8");
  let parsed: { structured_output?: { compressed?: unknown }; result?: { compressed?: unknown } };
  try {
    parsed = JSON.parse(stdout) as typeof parsed;
  } catch {
    return null;
  }

  const compressed =
    (parsed?.structured_output?.compressed ?? parsed?.result?.compressed ?? null) as
      | string
      | null;

  if (!compressed || typeof compressed !== "string") return null;

  const reduction = 1 - compressed.length / responseStr.length;
  if (reduction < config.minReduction) return null;

  return compressed;
}

async function main() {
  const input = await Bun.stdin.text();

  let hookData: PostToolUseHookInput;
  try {
    hookData = JSON.parse(input) as PostToolUseHookInput;
  } catch {
    process.exit(0);
  }

  const { tool_name, tool_input, tool_response, transcript_path } = hookData;

  if (!tool_name || !tool_response) process.exit(0);

  const config = await loadConfig();
  const compressed = await compress(tool_name, tool_input, tool_response, config, transcript_path);

  if (!compressed) process.exit(0);

  const output: SyncHookJSONOutput = {
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      updatedMCPToolOutput: compressed,
    },
  };

  process.stdout.write(JSON.stringify(output));
}

main().catch(() => process.exit(0));
