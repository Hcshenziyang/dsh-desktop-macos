import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { snapshot, apply } from "../../Resources/PluginInventory/plugin-inventory.mjs";

const entries = [
  { options: { name: "group", group: true } },
  { options: { name: "sample/tool", config: { credential: "must-not-export" } }, fiber: { state: 2 } },
  { options: { name: "bad" }, fiber: { state: 3 } },
  { options: { name: "disabled" }, disabled: true },
];
const loader = { entries: () => entries.values() };
const result = snapshot(loader, 42, 1234);
assert.equal(result.entries.length, 3);
assert.equal(result.entries[0].fiberPhase, "active");
assert.equal(result.entries[1].fiberPhase, "failed");
assert.equal(result.entries[2].enabled, false);
assert.equal(result.entries[2].fiberPhase, null);
assert.equal(JSON.stringify(result).includes("must-not-export"), false);
assert.equal(result.pid, 42);

const directory = await mkdtemp(join(tmpdir(), "dsh-inventory-test-"));
try {
  let dispose;
  const outputPath = join(directory, "inventory.json");
  apply({ loader, effect(callback) { dispose = callback(); } }, { outputPath });
  let saved;
  for (let i = 0; i < 50; i++) {
    try { saved = JSON.parse(await readFile(outputPath, "utf8")); break; } catch {}
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  assert.equal(saved.pid, process.pid);
  assert.equal(saved.entries[0].moduleName, "sample/tool");
  await dispose();
  await assert.rejects(readFile(outputPath), { code: "ENOENT" });
} finally { await rm(directory, { recursive: true, force: true }); }
console.log("Plugin inventory tests passed: public projection, credentials excluded, atomic publication, cleanup.");
