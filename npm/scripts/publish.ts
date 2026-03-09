#!/usr/bin/env bun
/**
 * Publish script: Publishes all @pleaseai/rtk packages to npm in the correct order.
 *
 * Usage: bun npm/scripts/publish.ts [--dry-run]
 * Example: bun npm/scripts/publish.ts
 *          bun npm/scripts/publish.ts --dry-run
 */

import { $ } from "bun";
import path from "path";

const NPM_DIR = path.join(import.meta.dir, "..");

// Platform packages must be published before the main package
const PLATFORM_PACKAGES = [
  "rtk-darwin-arm64",
  "rtk-darwin-x64",
  "rtk-linux-arm64",
  "rtk-linux-x64",
  "rtk-win32-x64",
];

const MAIN_PACKAGE = "rtk";

async function publishPackage(
  pkgDir: string,
  dryRun: boolean
): Promise<void> {
  const pkgPath = path.join(pkgDir, "package.json");
  const pkg = JSON.parse(await Bun.file(pkgPath).text());
  const name = pkg.name;
  const version = pkg.version;

  console.log(`Publishing ${name}@${version}...`);

  const args = ["publish", "--access", "public"];
  if (dryRun) {
    args.push("--dry-run");
  }

  try {
    await $`npm ${args} --prefix ${pkgDir}`.cwd(pkgDir);
    console.log(`  Published ${name}@${version}`);
  } catch (err) {
    throw new Error(`Failed to publish ${name}: ${err}`);
  }
}

async function main() {
  const dryRun = process.argv.includes("--dry-run");

  if (dryRun) {
    console.log("DRY RUN MODE - no packages will actually be published\n");
  }

  console.log("Publishing @pleaseai/rtk packages...\n");

  // Publish platform packages first (main package depends on them)
  for (const pkg of PLATFORM_PACKAGES) {
    await publishPackage(path.join(NPM_DIR, pkg), dryRun);
  }

  // Publish main package last
  await publishPackage(path.join(NPM_DIR, MAIN_PACKAGE), dryRun);

  console.log("\nAll packages published successfully!");

  if (!dryRun) {
    const pkgPath = path.join(NPM_DIR, MAIN_PACKAGE, "package.json");
    const pkg = JSON.parse(await Bun.file(pkgPath).text());
    console.log(`\nVerify: npx @pleaseai/rtk@${pkg.version} --version`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
