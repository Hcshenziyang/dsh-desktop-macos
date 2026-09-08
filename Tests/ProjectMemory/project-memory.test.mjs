import assert from "node:assert/strict";
import vm from "node:vm";
import { apply } from "../../Resources/ProjectMemory/host.mjs";
import { ProjectMemory } from "../../Resources/ProjectMemory/memory.mjs";

const routes = new Map();
let transform;
apply(
  {
    effect: (fn) => fn(),
    webServer: {
      register: (value) => {
        routes.set(value.path, value.handler);
        return () => {};
      },
      tapIndex: (value) => {
        transform = value;
        return () => {};
      },
    },
  },
  { token: "fixture-token-".repeat(4) },
);
const inline = transform("<head></head>").match(
  /<script>([\s\S]+)<\/script>/,
)[1];
const boot = { entries: [] };
vm.runInNewContext(inline, { __DSH_BOOT__: boot, window: {} });
assert.equal(
  boot.entries.length,
  0,
  "ordinary browser must not receive the native editing UI",
);
vm.runInNewContext(inline, {
  __DSH_BOOT__: boot,
  window: { webkit: { messageHandlers: { dshProjectMemory: {} } } },
});
assert.equal(boot.entries.length, 1);
let source;
routes.get("/dsh-desktop/project-memory.js")(
  {},
  {
    writeHead: (code) => assert.equal(code, 200),
    end: (value) => (source = value),
  },
);
new vm.Script(source);
assert.ok(source.includes(".dpm-dialog"));
assert.ok(!source.includes('/* PROJECT_MEMORY_CSS */ ""'));
const offline = new ProjectMemory({ loader: { entries: () => [] } });
await assert.rejects(offline.read({ id: "a", path: "/a" }), /尚未启用/);
// A pending agent proposal must not be overwritten, even from another session
// outside the Workspace membership which uses the same memory scope (cwd).
const busy = new ProjectMemory({
  agents: {
    list: () => [{ session: { header: { cwd: "/a" } }, status: "running" }],
  },
});
busy.open = async () => ({
  domain: {
    table() {
      assert.fail("Busy save reached storage");
    },
  },
  config: {},
});
await assert.rejects(
  busy.write({ id: "a", path: "/a" }, { kind: "profile", operation: "add" }),
  /AI 正在运行/,
);
console.log(
  "Project memory: native-only boot, bundled UI syntax, unavailable plugin and pending-agent protection passed.",
);
