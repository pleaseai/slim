#!/usr/bin/env bun
/**
 * Build script: Downloads RTK binaries from GitHub releases and updates package.json versions.
 *
 * Usage: bun npm/scripts/build.ts <version>
 * Example: bun npm/scripts/build.ts 0.27.2
 */

import { $ } from "bun";
import path from "path";
import fs from "fs";

const NPM_DIR = path.join(import.meta.dir, "..");

interface PlatformConfig {
  pkg: string;
  asset: string;
  binary: string;
  isZip: boolean;
}

const PLATFORMS: PlatformConfig[] = [
  {
    pkg: "rtk-darwin-arm64",
    asset: "rtk-aarch64-apple-darwin.tar.gz",
    binary: "rtk",
    isZip: false,
  },
  {
    pkg: "rtk-darwin-x64",
    asset: "rtk-x86_64-apple-darwin.tar.gz",
    binary: "rtk",
    isZip: false,
  },
  {
    pkg: "rtk-linux-arm64",
    asset: "rtk-aarch64-unknown-linux-gnu.tar.gz",
    binary: "rtk",
    isZip: false,
  },
  {
    pkg: "rtk-linux-x64",
    asset: "rtk-x86_64-unknown-linux-musl.tar.gz",
    binary: "rtk",
    isZip: false,
  },
  {
    pkg: "rtk-win32-x64",
    asset: "rtk-x86_64-pc-windows-msvc.zip",
    binary: "rtk.exe",
    isZip: true,
  },
];

async function downloadAndExtract(
  version: string,
  platform: PlatformConfig
): Promise<void> {
  const url = `https://github.com/rtk-ai/rtk/releases/download/v${version}/${platform.asset}`;
  const pkgDir = path.join(NPM_DIR, platform.pkg);
  const tmpFile = path.join(pkgDir, platform.asset);
  const destBinary = path.join(pkgDir, platform.binary);

  console.log(`Downloading ${platform.asset}...`);

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `Failed to download ${url}: ${response.status} ${response.statusText}`
    );
  }

  const buffer = await response.arrayBuffer();
  await Bun.write(tmpFile, buffer);

  console.log(`Extracting ${platform.binary} from ${platform.asset}...`);

  if (platform.isZip) {
    await $`unzip -o -j ${tmpFile} ${platform.binary} -d ${pkgDir}`;
  } else {
    await $`tar -xzf ${tmpFile} -C ${pkgDir} --strip-components=0 ${platform.binary}`;
  }

  fs.unlinkSync(tmpFile);

  if (!platform.isZip) {
    fs.chmodSync(destBinary, 0o755);
  }

  console.log(`  Done: ${destBinary}`);
}

function updatePackageJson(pkgDir: string, version: string): void {
  const pkgPath = path.join(pkgDir, "package.json");
  const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf-8"));
  pkg.version = version;

  // Update optionalDependencies versions in main package
  if (pkg.optionalDependencies) {
    for (const dep of Object.keys(pkg.optionalDependencies)) {
      pkg.optionalDependencies[dep] = version;
    }
  }

  fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
  console.log(`Updated ${pkgPath} to version ${version}`);
}

async function main() {
  const version = process.argv[2];
  if (!version) {
    console.error("Usage: bun npm/scripts/build.ts <version>");
    console.error("Example: bun npm/scripts/build.ts 0.27.2");
    process.exit(1);
  }

  // Validate version format
  if (!/^\d+\.\d+\.\d+/.test(version)) {
    console.error(`Invalid version format: ${version}. Expected: x.y.z`);
    process.exit(1);
  }

  console.log(`Building @pleaseai/rtk v${version}\n`);

  // Download binaries in parallel
  await Promise.all(
    PLATFORMS.map((platform) => downloadAndExtract(version, platform))
  );

  console.log("\nUpdating package.json versions...");

  // Update all platform package.json files
  for (const platform of PLATFORMS) {
    updatePackageJson(path.join(NPM_DIR, platform.pkg), version);
  }

  // Update main package.json (also updates optionalDependencies versions)
  updatePackageJson(path.join(NPM_DIR, "rtk"), version);

  console.log(`\nBuild complete! All packages updated to v${version}`);
  console.log("\nNext steps:");
  console.log(`  1. Test locally: cd npm/rtk && node bin/rtk.js --version`);
  console.log(`  2. Dry-run: cd npm/rtk && npm publish --dry-run`);
  console.log(`  3. Publish: bun npm/scripts/publish.ts ${version}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
