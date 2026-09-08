import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import vm from "node:vm";
import {
  WorkspaceToolsStore,
  Conflict,
  scheduleRule,
  nextOccurrence,
} from "../../Resources/WorkspaceTools/store.mjs";
import {
  WorkspaceScheduler,
  toolDefinitions,
  workspaceForAgent,
} from "../../Resources/WorkspaceTools/runtime.mjs";
function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), "dsh-workspace-tools-"));
  let now = Date.parse("2026-09-08T01:00:00Z");
  const path = join(directory, "tools.json");
  const store = new WorkspaceToolsStore(path, { now: () => now });
  t.after(() => {
    store.close();
    rmSync(directory, { recursive: true, force: true });
  });
  return { store, path, setNow: (value) => (now = value) };
}
function rule(now, extra = {}) {
  return {
    title: "每日整理",
    prompt: "整理今天的资料",
    execution: "reminder",
    frequency: "once",
    at: new Date(now + 1000).toISOString(),
    timezone: "Asia/Shanghai",
    ...extra,
  };
}
test("shared records survive restart, isolate workspaces and preserve conflicts", (t) => {
  const { store, path } = fixture(t);
  const todo = store.mutate("a", "todos", "add", { title: "交稿" });
  store.mutate("a", "todos", "update", {
    id: todo.id,
    revision: todo.revision,
    status: "completed",
  });
  assert.throws(
    () =>
      store.mutate("a", "todos", "update", {
        id: todo.id,
        revision: todo.revision,
        title: "stale",
      }),
    Conflict,
  );
  assert.equal(store.snapshot("a").todos[0].title, "交稿");
  assert.equal(store.snapshot("b").todos.length, 0);
  store.close();
  const reopened = new WorkspaceToolsStore(path);
  t.after(() => reopened.close());
  assert.equal(reopened.snapshot("a").todos[0].status, "completed");
});
test("note summaries are bounded, full content is available, archive and restore work", (t) => {
  const { store } = fixture(t);
  const body = "用户资料。".repeat(2000);
  const note = store.mutate("a", "notes", "add", {
    title: "背景",
    body,
    pinned: true,
  });
  assert.equal(store.readNote("a", note.id).body, body);
  assert.equal(store.snapshot("a").notes[0].body, undefined);
  assert.ok(store.summary("a").length < 10500);
  let updated = store.mutate("a", "notes", "update", {
    id: note.id,
    revision: note.revision,
    archived: true,
  });
  assert.ok(!store.summary("a").includes("背景"));
  store.mutate("a", "notes", "update", {
    id: note.id,
    revision: updated.revision,
    archived: false,
  });
  assert.ok(store.summary("a").includes("背景"));
});
test("invalid writes and corrupt stores never replace the previous document", (t) => {
  const { store, path } = fixture(t);
  store.mutate("a", "todos", "add", { title: "保留" });
  const before = readFileSync(path, "utf8");
  assert.throws(() => store.mutate("a", "todos", "add", { title: "" }));
  assert.equal(readFileSync(path, "utf8"), before);
  assert.throws(() => new WorkspaceToolsStore(path), /另一个/);
  store.close();
  writeFileSync(path, "broken");
  assert.throws(() => new WorkspaceToolsStore(path));
  assert.equal(readFileSync(path, "utf8"), "broken");
});
test("reminders dispatch once and retain task content in a todo", (t) => {
  const { store, setNow } = fixture(t);
  const now = store.now();
  const schedule = store.mutate("a", "schedules", "add", rule(now));
  setNow(now + 2000);
  const { run } = store.claim("a", schedule.id);
  assert.equal(run.status, "reminded");
  assert.equal(store.snapshot("a").todos[0].details, "整理今天的资料");
  assert.equal(store.due().length, 0);
  assert.throws(() => store.claim("a", schedule.id));
  assert.equal(store.snapshot("a").runs.length, 1);
});
test("pause, archive and active-run guards prevent unwanted dispatch", (t) => {
  const { store, setNow } = fixture(t);
  const now = store.now();
  let schedule = store.mutate(
    "a",
    "schedules",
    "add",
    rule(now, { execution: "agent" }),
  );
  schedule = store.mutate("a", "schedules", "update", {
    id: schedule.id,
    revision: schedule.revision,
    enabled: false,
  });
  setNow(now + 2000);
  assert.equal(store.due().length, 0);
  store.claim("a", schedule.id, true);
  assert.throws(() => store.claim("a", schedule.id, true), /正在进行/);
});
test("interrupted AI jobs are recorded without redispatch after restart", (t) => {
  const { store, path, setNow } = fixture(t);
  const now = store.now();
  const schedule = store.mutate(
    "a",
    "schedules",
    "add",
    rule(now, { execution: "agent" }),
  );
  setNow(now + 2000);
  store.claim("a", schedule.id);
  store.close();
  const reopened = new WorkspaceToolsStore(path);
  t.after(() => reopened.close());
  assert.equal(reopened.snapshot("a").runs[0].status, "interrupted");
  assert.equal(reopened.due().length, 0);
});
test("timezone recurrence handles catch-up, DST and weekly calendar time", () => {
  const due = Date.parse("2026-09-07T01:00:00Z");
  const daily = {
    frequency: "daily",
    timezone: "Asia/Shanghai",
    time: "09:00",
    weekday: "Mon",
    nextAt: due,
  };
  assert.equal(
    nextOccurrence(daily, Date.parse("2026-09-08T00:00:00Z")),
    Date.parse("2026-09-08T01:00:00Z"),
  );
  assert.equal(
    nextOccurrence(
      { ...daily, nextAt: Date.parse("2026-09-08T01:00:00Z") },
      Date.parse("2026-09-08T01:01:00Z"),
    ),
    Date.parse("2026-09-09T01:00:00Z"),
  );
  const fall = {
    frequency: "daily",
    timezone: "America/New_York",
    time: "01:30",
    nextAt: Date.parse("2026-11-01T05:30:00Z"),
  };
  assert.equal(
    nextOccurrence(fall, fall.nextAt),
    Date.parse("2026-11-02T06:30:00Z"),
  );
  assert.equal(
    nextOccurrence({ ...daily, frequency: "weekly" }, due),
    Date.parse("2026-09-14T01:00:00Z"),
  );
  assert.throws(() =>
    scheduleRule({
      frequency: "once",
      execution: "agent",
      at: "bad",
      timezone: "Asia/Shanghai",
    }),
  );
});
test("editing a recurring title preserves its next execution even after its first date", (t) => {
  const { store, setNow } = fixture(t);
  const now = store.now();
  let schedule = store.mutate(
    "a",
    "schedules",
    "add",
    rule(now, { frequency: "daily" }),
  );
  setNow(now + 2000);
  store.claim("a", schedule.id);
  schedule = store.snapshot("a").schedules[0];
  const changed = store.mutate("a", "schedules", "update", {
    ...schedule,
    title: "新的名字",
  });
  assert.equal(changed.nextAt, schedule.nextAt);
});
test("agent and UI use the same records and cannot choose another workspace", async (t) => {
  const { store } = fixture(t);
  const workspace = { id: "a", sessionIds: ["one"] };
  const agent = {
    id: "one",
    session: { id: "one", header: {} },
    options: { provider: "test", model: "fixture" },
  };
  const ctx = {
    workspaceRegistry: { list: () => [workspace] },
    agentPresets: { defaultId: "standard" },
    sessions: { get: () => undefined },
  };
  const tools = toolDefinitions(ctx, store),
    add = tools.find((t) => t.name === "workspace_note_add");
  await add.execute(
    { title: "Agent 写入", body: "共享内容" },
    { agent, signal: new AbortController().signal },
  );
  assert.equal(store.snapshot("a").notes[0].title, "Agent 写入");
  await assert.rejects(() =>
    add.execute(
      { title: "越界", body: "内容" },
      {
        agent: {
          ...agent,
          id: "else",
          session: { id: "else", header: { cwd: "/same" } },
        },
      },
    ),
  );
  assert.equal(
    workspaceForAgent(ctx, {
      session: {
        id: "child",
        header: { origin: "subagent", parentSession: "one" },
      },
    }),
    undefined,
  );
  ctx.sessions.get = (id) => (id === "one" ? agent.session : undefined);
  assert.equal(
    workspaceForAgent(ctx, {
      session: {
        id: "child",
        header: { origin: "subagent", parentSession: "one" },
      },
    }).id,
    "a",
  );
});
test("scheduler runs a job once, records completion and keeps manual runs separate", async (t) => {
  const { store, setNow } = fixture(t);
  const now = store.now();
  const ruleRow = store.mutate(
    "a",
    "schedules",
    "add",
    rule(now, { execution: "agent" }),
  );
  let calls = 0;
  const scheduler = new WorkspaceScheduler({}, store, {
    tickMS: 100000,
    execute: async () => {
      calls++;
      return { status: "completed", sessionID: "fixture-session" };
    },
  });
  t.after(() => scheduler.stop());
  setNow(now + 2000);
  scheduler.tick();
  scheduler.tick();
  await Promise.all([...scheduler.active.values()]);
  assert.equal(calls, 1);
  assert.equal(store.snapshot("a").runs[0].status, "completed");
  await scheduler.run("a", ruleRow.id, true);
  await Promise.all([...scheduler.active.values()]);
  assert.equal(calls, 2);
  assert.equal(store.snapshot("a").runs.length, 2);
});
test("reminders are not blocked by two AI tasks awaiting completion", async (t) => {
  const { store, setNow } = fixture(t),
    now = store.now();
  store.mutate("a", "schedules", "add", rule(now));
  for (let i = 0; i < 3; i++)
    store.mutate("a", "schedules", "add", rule(now, { execution: "agent" }));
  const releases = [];
  const scheduler = new WorkspaceScheduler({}, store, {
    tickMS: 100000,
    execute: () =>
      new Promise((resolve) =>
        releases.push(() => resolve({ status: "completed" })),
      ),
  });
  t.after(() => scheduler.stop());
  setNow(now + 2000);
  scheduler.tick();
  assert.equal(scheduler.active.size, 2);
  assert.equal(store.snapshot("a").todos.length, 1);
  assert.equal(store.due().length, 1);
  releases.forEach((release) => release());
  await Promise.all([...scheduler.active.values()]);
});
test("switching a reminder to AI captures the selected model without enabling a paused task", (t) => {
  const { store } = fixture(t);
  const row = store.mutate(
    "a",
    "schedules",
    "add",
    rule(store.now(), { enabled: false }),
  );
  const updated = store.mutate(
    "a",
    "schedules",
    "update",
    { id: row.id, revision: row.revision, execution: "agent" },
    { kind: "user", sessionID: "selected" },
    { provider: "fixture", model: "local" },
  );
  assert.equal(updated.enabled, false);
  assert.equal(updated.sourceSessionID, "selected");
  assert.equal(updated.agentOptions.model, "local");
});
test("bundled client is syntactically valid and does not run without a native bridge", () => {
  let registration;
  vm.runInNewContext(
    readFileSync(
      new URL("../../Resources/WorkspaceTools/client.js", import.meta.url),
      "utf8",
    ),
    { window: { __ModuleLoader__: { load: (r) => (registration = r) } } },
  );
  assert.equal(registration.id, "dsh-desktop-workspace-tools");
  registration.factory().apply({});
});
