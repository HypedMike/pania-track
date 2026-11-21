#!/usr/bin/env node
// Usage: node scripts/set-version.mjs 1.2.3
// Writes the version into every place that carries one, so a git tag is the
// single source of truth. Android's versionCode is derived by Tauri as
// major*1_000_000 + minor*1_000 + patch, so it always increases with semver.
import { readFileSync, writeFileSync } from "node:fs";

const version = (process.argv[2] ?? "").replace(/^v/, "");
const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
if (!m) {
  console.error(`Expected a plain X.Y.Z version, got "${process.argv[2]}"`);
  process.exit(1);
}
const [major, minor, patch] = m.slice(1).map(Number);
if (minor > 999 || patch > 999) {
  console.error("minor and patch must be <= 999 (they are packed into Android's versionCode)");
  process.exit(1);
}

const edit = (path, fn) => writeFileSync(path, fn(readFileSync(path, "utf8")));
const json = (path) => edit(path, (s) => s.replace(/("version"\s*:\s*")[^"]+(")/, `$1${version}$2`));

json("package.json");
json("src-tauri/tauri.conf.json");
edit("src-tauri/Cargo.toml", (s) => s.replace(/^version = ".*"$/m, `version = "${version}"`));

console.log(`version=${version}`);
console.log(`versionCode=${major * 1_000_000 + minor * 1_000 + patch}`);
