import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const MARKETPLACE_PATH = resolve(ROOT, ".claude-plugin", "marketplace.json");
const PLUGIN_PATH = resolve(ROOT, "plugins", "my-logger", ".claude-plugin", "plugin.json");
const SKILL_PATH = resolve(ROOT, "plugins", "my-logger", "skills", "my-logger", "SKILL.md");
const STALE_ROOT_SKILL = resolve(ROOT, "SKILL.md");

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf-8"));
}

describe("Marketplace structure (Pattern B: multi-skill plugin)", () => {
  it("marketplace.json exists at .claude-plugin/marketplace.json", () => {
    assert.ok(existsSync(MARKETPLACE_PATH), `Required: ${MARKETPLACE_PATH}`);
  });

  it("plugin.json exists at plugins/my-logger/.claude-plugin/plugin.json", () => {
    assert.ok(existsSync(PLUGIN_PATH), `Required: ${PLUGIN_PATH}`);
  });

  it("SKILL.md exists at plugins/my-logger/skills/my-logger/SKILL.md", () => {
    assert.ok(existsSync(SKILL_PATH), `Required: ${SKILL_PATH}`);
  });

  it("NO stale SKILL.md at repo root", () => {
    assert.ok(!existsSync(STALE_ROOT_SKILL), "Root SKILL.md would conflict. Keep only in plugins/<name>/skills/<name>/");
  });

  it("marketplace.json source path points to ./plugins/my-logger", () => {
    const mkt = readJson(MARKETPLACE_PATH);
    const src = mkt.plugins[0].source;
    assert.equal(src, "./plugins/my-logger", `source must be "./plugins/my-logger", got "${src}"`);
  });

  it("marketplace.json has owner-prefixed name (not same as plugin name)", () => {
    const mkt = readJson(MARKETPLACE_PATH);
    const plugin = readJson(PLUGIN_PATH);
    assert.notEqual(mkt.name, plugin.name, "Marketplace name must differ from plugin name (owner-prefixed)");
    assert.ok(mkt.name.includes("Zahrannnn"), `Marketplace name "${mkt.name}" should contain owner prefix`);
  });

  it("marketplace.json plugins[0].name matches plugin.json name", () => {
    const mkt = readJson(MARKETPLACE_PATH);
    const plugin = readJson(PLUGIN_PATH);
    assert.equal(mkt.plugins[0].name, plugin.name, `Expected "${plugin.name}" in marketplace.plugins[0].name`);
  });

  it("marketplace.json plugins[0].version matches plugin.json version", () => {
    const mkt = readJson(MARKETPLACE_PATH);
    const plugin = readJson(PLUGIN_PATH);
    assert.equal(mkt.plugins[0].version, plugin.version, "Version mismatch between marketplace and plugin");
  });

  it("SKILL.md has matching name in frontmatter", () => {
    const raw = readFileSync(SKILL_PATH, "utf-8");
    const match = raw.match(/^name:\s*(.+)$/m);
    assert.ok(match, "SKILL.md has a 'name:' field in frontmatter");
    const plugin = readJson(PLUGIN_PATH);
    assert.equal(match[1].trim(), plugin.name, `SKILL.md name "${match[1].trim()}" != plugin.json name "${plugin.name}"`);
  });

  it("SKILL.md has description in frontmatter", () => {
    const raw = readFileSync(SKILL_PATH, "utf-8");
    const match = raw.match(/^description:\s*(.+)$/m);
    assert.ok(match, "SKILL.md has a 'description:' field in frontmatter");
  });

  it("README exists with minimal sections", () => {
    const readmePath = resolve(ROOT, "README.md");
    assert.ok(existsSync(readmePath), "README.md required");
    const raw = readFileSync(readmePath, "utf-8");
    assert.ok(raw.includes("Installation"), "README must have Installation section");
    assert.ok(raw.includes("License"), "README must have License section");
  });

  it("README screenshots reference files in docs/ if mentioned", () => {
    const readmePath = resolve(ROOT, "README.md");
    const raw = readFileSync(readmePath, "utf-8");
    const imgRe = /!\[.*?\]\((docs\/[^)]+)\)/g;
    let match;
    while ((match = imgRe.exec(raw)) !== null) {
      const imgPath = resolve(ROOT, match[1]);
      assert.ok(existsSync(imgPath), `Screenshot referenced in README but missing: ${match[1]}`);
    }
  });
});

describe("Script integrity", () => {
  const scriptDir = resolve(ROOT, "plugins", "my-logger", "skills", "my-logger", "scripts");
  const expectedScripts = ["my-api.ps1", "my-init.ps1", "my-submit.ps1", "my-edit.ps1"];

  for (const name of expectedScripts) {
    it(`${name} exists`, () => {
      const fp = resolve(scriptDir, name);
      assert.ok(existsSync(fp), `Required script: ${name}`);
    });
  }
});