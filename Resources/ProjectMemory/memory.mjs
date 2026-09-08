import { createHash, randomUUID } from "node:crypto";

const kinds = ["preference", "fact", "convention", "decision"];
export const version = (value) =>
  createHash("sha256")
    .update(JSON.stringify(value ?? null))
    .digest("hex");
const conflict = () => {
  const e = new Error(
    "这条记忆已被修改。草稿已保留，请放弃草稿并重载后重新核对。",
  );
  e.name = "Conflict";
  throw e;
};
const limits = {
  maxFactsPerWorkspace: 300,
  maxFactChars: 2000,
  maxProfileEntries: 8,
  maxProfileEntryChars: 240,
};

// Compatibility adapter for dsh-native-memory's v1 storage domain. The plugin
// owns opening/closing and schema validation. All writes use its live domain's
// serialized storage queue; never open another domain or write the JSON file.
export class ProjectMemory {
  constructor(ctx) {
    this.ctx = ctx;
    this.pending = Promise.resolve();
  }
  plugin() {
    const row = [...this.ctx.loader.entries()].find(
      (e) =>
        !e.disabled &&
        e.fiber?.state === 2 &&
        (e.options.name === "dsh-native-memory" ||
          /\/dsh-native-memory\/lib\/index\.mjs$/.test(e.options.name)),
    );
    if (!row)
      throw new Error(
        "此项目的记忆服务尚未启用。请在插件管理中启用 dsh-native-memory，再重新启动服务。",
      );
    const config = row.options.config ?? {};
    const resolved = { injectProfile: config.injectProfile !== false };
    for (const [key, fallback] of Object.entries(limits)) {
      const value = config[key] ?? fallback;
      if (!Number.isInteger(value) || value < 0)
        throw new Error("记忆插件配置不兼容。");
      resolved[key] = value;
    }
    return resolved;
  }
  async open(workspace) {
    const config = this.plugin();
    const facility = this.ctx.get("storageDomain");
    if (!facility) throw new Error("记忆存储服务尚未就绪。");
    let domain = facility.get("dsh_memory");
    if (!domain) {
      const agent = workspace.sessionIds
        .map((id) => this.ctx.agents.get(id))
        .find((a) => a?.session.header.cwd === workspace.path);
      if (!agent) throw new Error("请先打开此项目的一次对话，再查看记忆。");
      // A read-only tool initializes the plugin's own domain. No model turn,
      // approval request, synthetic user message, or remote API is involved.
      const result = await this.ctx.tools.execute({
        name: "memory_profile",
        arguments: {},
        agent,
        callId: randomUUID(),
        signal: new AbortController().signal,
      });
      domain = facility.get("dsh_memory");
      if (result.isError || !domain)
        throw new Error("记忆库暂时无法读取，请检查记忆插件的运行状态。");
    }
    return { domain, config };
  }
  snapshot(workspace, domain, config) {
    const path = workspace.path;
    const profile = domain.table("profiles").get(path);
    const facts = [...domain.table("facts").entries()]
      .map(([, f]) => f)
      .filter((f) => f.workspacePath === path);
    // Refuse unknown domain shapes instead of editing a future schema blindly.
    if (
      (profile &&
        (!Array.isArray(profile.entries) || profile.workspacePath !== path)) ||
      facts.some(
        (f) =>
          !kinds.includes(f.kind) || !["active", "archived"].includes(f.state),
      )
    )
      throw new Error("记忆库格式已变化，请更新客户端后再编辑。");
    return {
      workspaceID: workspace.id,
      title: workspace.title,
      path,
      sharedPath:
        this.ctx.workspaceRegistry.list().filter((w) => w.path === path)
          .length > 1,
      config,
      emptyVersion: version(undefined),
      profile: {
        entries: profile?.entries ?? [],
        updatedAt: profile?.updatedAt ?? 0,
        version: version(profile),
      },
      facts: facts
        .sort((a, b) => b.updatedAt - a.updatedAt || a.id.localeCompare(b.id))
        .map((f) => ({ ...f, version: version(f) })),
    };
  }
  async read(workspace) {
    const { domain, config } = await this.open(workspace);
    return this.snapshot(workspace, domain, config);
  }
  mutate(workspace, input) {
    const job = this.pending.then(() => this.write(workspace, input));
    this.pending = job.catch(() => {});
    return job;
  }
  async write(workspace, input) {
    const { domain, config } = await this.open(workspace),
      path = workspace.path;
    // The native plugin's agent tools can hold a proposed write while awaiting
    // approval. Avoid racing that proposal (or first-row creation) with a user
    // edit. This also covers sessions outside the registry using the same cwd.
    if (
      this.ctx.agents
        .list()
        .some((a) => a.session.header.cwd === path && a.status === "running")
    )
      throw new Error(
        "这个项目的 AI 正在运行或等待审批。草稿已保留，结束后即可保存。",
      );
    const check = (record) => {
      if (
        typeof input.version !== "string" ||
        version(record) !== input.version
      )
        conflict();
    };
    const nonempty = (value, max) => {
      if (typeof value !== "string" || !value.trim())
        throw new Error("记忆内容不能为空。");
      if ([...value].length > max)
        throw new Error(`这条记忆最多 ${max} 个字，请精简内容。`);
      return value.trim();
    };
    if (input.kind === "profile") {
      const table = domain.table("profiles"),
        current = table.get(path);
      const update = (row) => {
        check(row);
        const entries = [...(row?.entries ?? [])];
        if (input.operation === "add") {
          entries.push(nonempty(input.text, config.maxProfileEntryChars));
        } else {
          if (
            !Number.isInteger(input.index) ||
            input.index < 0 ||
            input.index >= entries.length
          )
            conflict();
          if (input.operation === "remove") entries.splice(input.index, 1);
          else if (input.operation === "edit")
            entries[input.index] = nonempty(
              input.text,
              config.maxProfileEntryChars,
            );
          else throw new Error("未知的记忆操作。");
        }
        if (entries.length > config.maxProfileEntries)
          throw new Error(
            `简要记忆最多 ${config.maxProfileEntries} 条，请先整理已有内容。`,
          );
        return { workspacePath: path, entries, updatedAt: Date.now() };
      };
      if (current)
        await table.update(path, update); // Compare within the domain write queue.
      else await table.put(path, update(undefined));
    } else if (input.kind === "fact") {
      const table = domain.table("facts");
      const activeCount = () =>
        [...table.entries()].filter(
          ([, r]) => r.workspacePath === path && r.state === "active",
        ).length;
      const update = (row) => {
        if (row && row.workspacePath !== path)
          throw new Error("这条记忆不属于当前项目。");
        check(row);
        let next;
        const now = Date.now();
        if (input.operation === "archive" || input.operation === "restore") {
          if (!row) conflict();
          next = {
            ...row,
            state: input.operation === "archive" ? "archived" : "active",
            updatedAt: now,
          };
        } else if (input.operation === "add" || input.operation === "edit") {
          if (!kinds.includes(input.category))
            throw new Error("请选择有效的记忆分类。");
          if (
            !Array.isArray(input.tags) ||
            input.tags.length > 30 ||
            input.tags.some((t) => typeof t !== "string" || [...t].length > 80)
          )
            throw new Error("标签过多或过长。");
          next = {
            id: row?.id ?? randomUUID(),
            workspacePath: path,
            kind: input.category,
            text: nonempty(input.text, config.maxFactChars),
            tags: [...new Set(input.tags.map((t) => t.trim()).filter(Boolean))],
            sessionId: "desktop-editor",
            seq: 0,
            createdAt: row?.createdAt ?? now,
            updatedAt: now,
            state: row?.state ?? "active",
          };
        } else throw new Error("未知的记忆操作。");
        if (
          next.state === "active" &&
          row?.state !== "active" &&
          activeCount() >= config.maxFactsPerWorkspace
        )
          throw new Error(
            `长期记忆最多 ${config.maxFactsPerWorkspace} 条，请先归档不再需要的内容。`,
          );
        return next;
      };
      if (input.operation === "add") {
        if (input.id) throw new Error("新增记忆不能指定已有编号。");
        const next = update(undefined);
        await table.put(next.id, next);
      } else {
        if (typeof input.id !== "string" || !table.get(input.id)) conflict();
        await table.update(input.id, update);
      }
    } else throw new Error("未知的记忆类型。");
    return this.snapshot(workspace, domain, config);
  }
}
