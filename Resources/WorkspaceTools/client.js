window.__ModuleLoader__.load({
  id: "dsh-desktop-workspace-tools",
  factory: () => {
    const css = /* WORKSPACE_TOOLS_CSS */ "";
    function node(tag, cls, text) {
      const n = document.createElement(tag);
      if (cls) n.className = cls;
      if (text !== undefined) n.textContent = text;
      return n;
    }
    function button(text, fn, cls = "") {
      const n = node("button", cls, text);
      n.type = "button";
      n.addEventListener("click", fn);
      return n;
    }
    function apply(ctx) {
      const channel = window.webkit?.messageHandlers.dshWorkspaceTools;
      if (!channel) return;
      let scope = {},
        generation = 0,
        disposed = false,
        loading = false,
        data,
        tab = "todos",
        collapsed = false,
        showArchived = false,
        editorKey = null;
      const views = new Map(),
        drafts = new Map();
      const root = node("section", "dwt-root");
      root.setAttribute("aria-label", "工作区工具");
      const style = node("style");
      style.textContent = css;
      document.head.append(style);
      const top = node("div", "dwt-top");
      const tabs = node("div", "dwt-tabs");
      tabs.setAttribute("role", "tablist");
      const tabButtons = {};
      for (const [key, label] of [
        ["todos", "待办"],
        ["notes", "便签"],
        ["schedules", "定时任务"],
      ]) {
        const b = button(label, () => {
          saveView();
          tab = key;
          editorKey = null;
          build();
        });
        b.setAttribute("role", "tab");
        tabs.append(b);
        tabButtons[key] = b;
      }
      const fold = button("收起", () => {
        collapsed = !collapsed;
        content.hidden = collapsed;
        fold.textContent = collapsed ? "展开" : "收起";
      });
      const reload = button("刷新", () => refresh(true));
      top.append(tabs, reload, fold);
      const feedback = node("div", "dwt-feedback");
      feedback.setAttribute("aria-live", "polite");
      feedback.hidden = true;
      const content = node("div", "dwt-content");
      const actions = node("div", "dwt-actions");
      const archiveLabel = node("label");
      const archived = node("input");
      archived.type = "checkbox";
      archived.addEventListener("change", () => {
        showArchived = archived.checked;
        renderList();
      });
      archiveLabel.append(archived, document.createTextNode("已归档"));
      const add = button("+ 添加待办", () => openEditor(null));
      actions.append(archiveLabel, add);
      const items = node("div", "dwt-items");
      const editor = node("form", "dwt-editor");
      editor.hidden = true;
      const main = node("div", "dwt-main");
      main.append(items, editor);
      content.append(actions, main);
      root.append(top, feedback, content);
      function say(text) {
        feedback.textContent = text;
        feedback.hidden = !text;
      }
      function call(action, extra = {}) {
        if (!scope.workspaceID)
          return Promise.reject(new Error("请先选择项目。"));
        return channel.postMessage({
          action,
          workspaceID: scope.workspaceID,
          sessionID: scope.sessionID,
          ...extra,
        });
      }
      function saveView() {
        if (scope.workspaceID)
          views.set(scope.workspaceID, { tab, showArchived, editorKey });
      }
      function mount() {
        const host = document.querySelector("[data-dsh-workspace-tools]");
        if (host && root.parentElement !== host) host.append(root);
      }
      async function refresh(explicit = false) {
        if (
          disposed ||
          loading ||
          !scope.workspaceID ||
          (!explicit && scope.mode !== "folder")
        )
          return;
        const own = generation;
        loading = true;
        try {
          const next = await call("snapshot");
          if (disposed || own !== generation) return;
          const changed = !data || next.revision !== data.revision;
          data = next;
          if (changed || explicit) renderList();
          if (explicit)
            say(editor.hidden ? "已刷新。" : "已刷新，未保存的输入仍保留。");
        } catch (error) {
          if (own === generation && !disposed) say(error.message);
        } finally {
          if (own === generation) loading = false;
        }
      }
      async function mutate(kind, operation, input, success) {
        const own = generation;
        try {
          const result = await call("mutate", { kind, operation, input });
          if (own !== generation || disposed) return;
          say("已保存。");
          success?.(result);
          await refresh();
        } catch (error) {
          if (own === generation && !disposed) say(error.message);
        }
      }
      function build() {
        for (const [key, b] of Object.entries(tabButtons))
          b.setAttribute("aria-selected", String(key === tab));
        add.textContent = {
          todos: "+ 添加待办",
          notes: "+ 新建便签",
          schedules: "+ 定时任务",
        }[tab];
        archived.checked = showArchived;
        editor.hidden = true;
        editor.replaceChildren();
        renderList();
        if (editorKey) showEditor(drafts.get(editorKey));
      }
      function renderList() {
        for (const [key, b] of Object.entries(tabButtons)) {
          const count =
            data?.[key]?.filter(
              (r) =>
                !r.archived && (key !== "todos" || r.status !== "completed"),
            ).length ?? 0;
          b.textContent =
            { todos: "待办", notes: "便签", schedules: "定时任务" }[key] +
            (count ? " " + count : "");
        }
        if (!data) {
          items.replaceChildren(node("p", "dwt-empty", "正在连接工作区工具…"));
          return;
        }
        const rows = data[tab].filter(
          (r) => Boolean(r.archived) === showArchived,
        );
        const fragment = document.createDocumentFragment();
        if (tab === "schedules")
          fragment.append(
            node(
              "p",
              "dwt-hint",
              "DSH 运行时执行；休眠或关闭后，恢复时补执行一次。AI 任务使用创建时对话的模型，并保留通常的操作确认。",
            ),
          );
        for (const row of rows) {
          const card = node("div", "dwt-item");
          if (tab === "todos") {
            const check = node("input");
            check.type = "checkbox";
            check.checked = row.status === "completed";
            check.setAttribute("aria-label", "完成待办：" + row.title);
            check.addEventListener("change", () => {
              check.disabled = true;
              mutate("todos", "update", {
                id: row.id,
                revision: row.revision,
                status: check.checked ? "completed" : "pending",
              }).finally(() => (check.disabled = false));
            });
            card.append(check);
          }
          const open = button("", () => openEditor(row), "dwt-item-body");
          open.append(
            node(
              "strong",
              row.status === "completed" ? "dwt-done" : "",
              row.title,
            ),
          );
          if (tab === "todos" && (row.due || row.details))
            open.append(
              node(
                "span",
                "",
                row.due ? `截止 ${row.due}` : row.details.slice(0, 80),
              ),
            );
          if (tab === "notes")
            open.append(
              node(
                "span",
                "",
                `${row.pinned ? "置顶 · " : ""}${row.excerpt || "空白便签"}`,
              ),
            );
          if (tab === "schedules")
            open.append(
              node(
                "span",
                "",
                `${row.execution === "agent" ? "AI 执行" : "提醒"} · ${row.enabled && row.nextAt ? "下次 " + new Date(row.nextAt).toLocaleString() : row.nextAt === null ? "已结束" : "已暂停"}`,
              ),
            );
          card.append(open);
          if (tab === "schedules") {
            if (row.nextAt !== null)
              card.append(
                button(row.enabled ? "暂停" : "启用", () =>
                  mutate(tab, "update", {
                    id: row.id,
                    revision: row.revision,
                    enabled: !row.enabled,
                  }),
                ),
              );
            card.append(
              button("运行一次", async () => {
                const own = generation;
                try {
                  await call("run", { id: row.id });
                  if (own === generation) {
                    say("已开始，执行情况见下方记录。");
                    refresh();
                  }
                } catch (error) {
                  if (own === generation) say(error.message);
                }
              }),
            );
          }
          card.append(
            button(
              row.archived ? "恢复" : "归档",
              () =>
                mutate(tab, "update", {
                  id: row.id,
                  revision: row.revision,
                  archived: !row.archived,
                }),
              "dwt-subtle",
            ),
          );
          fragment.append(card);
        }
        if (!rows.length)
          fragment.append(
            node(
              "p",
              "dwt-empty",
              showArchived
                ? "没有已归档内容。"
                : {
                    todos: "把要做的事记在这里，也可以让 Agent 帮你添加。",
                    notes: "记录想法和项目背景，Agent 在对话中也能参考。",
                    schedules: "设置一个时间，让提醒或工作按时开始。",
                  }[tab],
            ),
          );
        if (tab === "schedules" && data.runs.length) {
          fragment.append(node("h4", "", "最近执行"));
          for (const run of data.runs.slice(0, 8)) {
            const line = node("div", "dwt-run");
            const states = {
              running: "执行中",
              reminded: "已加入待办",
              completed: "已完成",
              failed: "失败",
              interrupted: "已中断",
            };
            line.append(
              node("strong", "", run.title),
              node(
                "span",
                "",
                `${states[run.status] ?? run.status} · ${new Date(run.startedAt).toLocaleString()}`,
              ),
            );
            if (run.error) line.append(node("span", "dwt-error", run.error));
            if (run.sessionID)
              line.append(
                button("查看对话", () =>
                  window.dispatchEvent(
                    new CustomEvent("dsh:open-project-chat", {
                      detail: { sessionID: run.sessionID },
                    }),
                  ),
                ),
              );
            fragment.append(line);
          }
        }
        items.replaceChildren(fragment);
      }
      async function openEditor(row) {
        const key = scope.workspaceID + "/" + tab + "/" + (row?.id ?? "new");
        editorKey = key;
        if (drafts.has(key)) {
          showEditor(drafts.get(key));
          return;
        }
        const kind = tab,
          own = generation;
        try {
          let value = row ? { ...row } : {};
          if (row && kind === "notes")
            value = await call("readNote", { id: row.id });
          if (own !== generation || editorKey !== key || disposed) return;
          if (!row && kind === "schedules") {
            const next = new Date(
              Math.ceil((Date.now() + 3600000) / 60000) * 60000,
            );
            value = {
              frequency: "once",
              execution: "reminder",
              enabled: true,
              timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
              at: next.toISOString(),
            };
          }
          const draft = { kind, key, value, dirty: false };
          drafts.set(key, draft);
          showEditor(draft);
        } catch (error) {
          if (own === generation) say(error.message);
        }
      }
      function showEditor(draft) {
        if (!draft) {
          editor.hidden = true;
          return;
        }
        editor.hidden = false;
        editor.replaceChildren();
        const value = draft.value;
        const heading = node("div", "dwt-editor-heading");
        heading.append(
          node(
            "strong",
            "",
            value.id
              ? "编辑" +
                  { todos: "待办", notes: "便签", schedules: "定时任务" }[
                    draft.kind
                  ]
              : "新建" +
                  { todos: "待办", notes: "便签", schedules: "定时任务" }[
                    draft.kind
                  ],
          ),
          button("收起", () => {
            editor.hidden = true;
            editorKey = null;
          }),
        );
        editor.append(heading);
        if (value.id)
          editor.append(
            button(
              "放弃草稿并重载",
              async () => {
                const own = generation,
                  key = draft.key;
                try {
                  const snapshot = await call("snapshot");
                  if (own !== generation || editorKey !== key || disposed)
                    return;
                  const latest = snapshot[draft.kind].find(
                    (row) => row.id === value.id,
                  );
                  if (!latest) throw new Error("条目已不存在。");
                  data = snapshot;
                  drafts.delete(key);
                  await openEditor(latest);
                  renderList();
                  say("已载入最新内容。");
                } catch (error) {
                  if (own === generation) say(error.message);
                }
              },
              "dwt-subtle",
            ),
          );
        function field(
          label,
          key,
          { type = "text", options, required = false, max = 240 } = {},
        ) {
          const holder = node("label", "dwt-field");
          holder.append(node("span", "", label));
          let input;
          if (options) {
            input = node("select");
            for (const [v, t] of options) {
              const option = node("option", "", t);
              option.value = v;
              input.append(option);
            }
          } else input = node(type === "textarea" ? "textarea" : "input");
          if (type !== "textarea" && !options) input.type = type;
          input.required = required;
          if (!options) input.maxLength = max;
          input.setAttribute("aria-label", label);
          if (type === "checkbox") input.checked = Boolean(value[key]);
          else if (type === "datetime-local") {
            const d = value[key] ? new Date(value[key]) : new Date();
            input.value = new Date(d.getTime() - d.getTimezoneOffset() * 60000)
              .toISOString()
              .slice(0, 16);
          } else {
            if (options && value[key] === undefined) value[key] = options[0][0];
            input.value = value[key] ?? "";
          }
          input.addEventListener("input", () => {
            value[key] =
              type === "checkbox"
                ? input.checked
                : type === "datetime-local"
                  ? input.value
                    ? new Date(input.value).toISOString()
                    : ""
                  : input.value;
            draft.dirty = true;
            save.textContent = "保存修改";
          });
          holder.append(input);
          editor.append(holder);
          return input;
        }
        field("标题", "title", { required: true });
        if (draft.kind === "todos") {
          field("状态", "status", {
            options: [
              ["pending", "待完成"],
              ["in_progress", "进行中"],
              ["completed", "已完成"],
            ],
          });
          field("截止日期（可选）", "due", { type: "date" });
          field("补充说明（可选）", "details", { type: "textarea", max: 8000 });
        }
        if (draft.kind === "notes") {
          field("正文", "body", { type: "textarea", max: 16000 });
          field("置顶，优先供 Agent 参考", "pinned", { type: "checkbox" });
        }
        if (draft.kind === "schedules") {
          field("执行方式", "execution", {
            options: [
              ["reminder", "到时提醒（加入待办）"],
              ["agent", "交给 AI 执行"],
            ],
          });
          field("任务内容", "prompt", {
            type: "textarea",
            required: true,
            max: 8000,
          });
          field("重复", "frequency", {
            options: [
              ["once", "仅一次"],
              ["daily", "每天"],
              ["weekly", "每周"],
            ],
          });
          field("首次执行时间", "at", {
            type: "datetime-local",
            required: true,
          });
          const localZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
          editor.append(
            node(
              "p",
              "dwt-hint",
              "输入时间按本机 " +
                localZone +
                " 显示；重复任务按 " +
                (value.timezone ?? localZone) +
                " 执行。",
            ),
          );
        }
        const save = node(
          "button",
          "dwt-primary",
          value.id
            ? "保存修改"
            : "创建" + (draft.kind === "schedules" ? "并启用" : ""),
        );
        save.type = "submit";
        editor.append(save);
        editor.onsubmit = (event) => {
          event.preventDefault();
          save.disabled = true;
          const allowed = {
            todos: ["id", "revision", "title", "status", "due", "details"],
            notes: ["id", "revision", "title", "body", "pinned"],
            schedules: [
              "id",
              "revision",
              "title",
              "prompt",
              "execution",
              "frequency",
              "at",
              "timezone",
              "enabled",
            ],
          }[draft.kind];
          const input = Object.fromEntries(
            allowed
              .filter((k) => value[k] !== undefined)
              .map((k) => [k, value[k]]),
          );
          if (draft.kind === "schedules") {
            input.timezone ??= Intl.DateTimeFormat().resolvedOptions().timeZone;
          }
          mutate(draft.kind, value.id ? "update" : "add", input, () => {
            drafts.delete(draft.key);
            editorKey = null;
            editor.hidden = true;
          }).finally(() => (save.disabled = false));
        };
      }
      function onScope(event) {
        const next = event.detail;
        if (!next || !("workspaceID" in next)) return;
        const changed = scope.workspaceID !== next.workspaceID;
        if (changed) {
          saveView();
          generation++;
          loading = false;
          data = undefined;
          scope = next;
          const view = views.get(next.workspaceID);
          tab = view?.tab ?? "todos";
          showArchived = view?.showArchived ?? false;
          editorKey = view?.editorKey ?? null;
          build();
          say("");
        } else scope = next;
        mount();
        root.hidden = !scope.workspaceID;
        refresh();
      }
      const observer = new MutationObserver(() => {
        if (!root.isConnected) mount();
      });
      window.addEventListener("dsh:project-scope", onScope);
      observer.observe(document.body, { childList: true, subtree: true });
      mount();
      window.dispatchEvent(new CustomEvent("dsh:request-project-scope"));
      const timer = setInterval(() => {
        if (!document.hidden) refresh();
      }, 2500);
      ctx.effect(() => () => {
        disposed = true;
        generation++;
        clearInterval(timer);
        observer.disconnect();
        window.removeEventListener("dsh:project-scope", onScope);
        root.remove();
        style.remove();
      });
    }
    return { inject: ["sessions", "workspaces"], apply };
  },
});
