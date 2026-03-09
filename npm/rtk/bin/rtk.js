#!/usr/bin/env node

"use strict";

const { spawnSync } = require("child_process");
const path = require("path");

const PLATFORM_MAP = {
  "darwin-arm64": "@pleaseai/rtk-darwin-arm64",
  "darwin-x64": "@pleaseai/rtk-darwin-x64",
  "linux-arm64": "@pleaseai/rtk-linux-arm64",
  "linux-x64": "@pleaseai/rtk-linux-x64",
  "win32-x64": "@pleaseai/rtk-win32-x64",
};

function getBinaryPath() {
  // Allow override via environment variable
  if (process.env.RTK_BINARY) {
    return process.env.RTK_BINARY;
  }

  const key = `${process.platform}-${process.arch}`;
  const pkg = PLATFORM_MAP[key];

  if (!pkg) {
    console.error(
      `rtk: Unsupported platform: ${process.platform} ${process.arch}\n` +
        `Supported platforms: ${Object.keys(PLATFORM_MAP).join(", ")}\n` +
        `You can set RTK_BINARY=/path/to/rtk to use a custom binary.`
    );
    process.exit(1);
  }

  const binaryName = process.platform === "win32" ? "rtk.exe" : "rtk";

  try {
    return require.resolve(`${pkg}/${binaryName}`);
  } catch {
    console.error(
      `rtk: Could not find the binary for ${process.platform} ${process.arch}.\n` +
        `The optional dependency "${pkg}" may not have been installed.\n` +
        `Try running: npm install ${pkg}`
    );
    process.exit(1);
  }
}

const binaryPath = getBinaryPath();
const result = spawnSync(binaryPath, process.argv.slice(2), {
  stdio: "inherit",
  env: process.env,
});

if (result.error) {
  console.error(`rtk: Failed to spawn binary: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status ?? 1);
