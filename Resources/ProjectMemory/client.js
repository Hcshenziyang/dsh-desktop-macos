window.__ModuleLoader__.load({
  id: "dsh-desktop-project-memory",
  factory: () => {
    const stylesheet = /* PROJECT_MEMORY_CSS */ "";
    const labels = {
      preference: "偏好",
      fact: "事实",
      convention: "约定",
      decision: "决定",
    };
    function apply(ctx) {
      const channel = window.webkit?.messageHandlers.dshProjectMemory;
      if (!channel) return;
      const el = (tag, cls, text) => {
        const n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined) n.textContent = text;
        return n;
      };
      const button = (text, fn, cls = "") => {
        const b = el("button", cls, text);
        b.type = "button";
        b.addEventListener("click", fn);
        return b;
      };
      const style = el("style");
      style.textContent = stylesheet;
      document.head.append(style);
      const trigger = button("记忆", open, "dpm-trigger");
      trigger.disabled = true;
      trigger.setAttribute("aria-label", "查看与编辑项目记忆");
      const dialog = el("dialog", "dpm-dialog");
      dialog.setAttribute("aria-label", "项目记忆");
      const head = el("header", "dpm-head"),
        heading = el("div"),
        title = el("h2", "", "项目记忆"),
        subtitle = el("p");
      heading.append(title, subtitle);
      head.append(
        heading,
        button("返回项目", () => dialog.close()),
      );
      const tabs = el("nav", "dpm-tabs"),
        main = el("div", "dpm-main"),
        status = el("p", "dpm-status");
      status.setAttribute("role", "status");
      dialog.append(head, tabs, status, main);
      document.body.append(dialog);
      let scope = {},
        disposed = false,
        sequence = 0,
        loading = false,
        saving = false,
        tab = "profile",
        archived = false,
        query = "";
      const states = new Map();
      const state = () => {
        if (!states.has(scope.workspaceID))
          states.set(scope.workspaceID, { data: null, draft: null, error: "" });
        return states.get(scope.workspaceID);
      };
      const notify = (text) => {
        status.textContent = text;
        status.hidden = !text;
      };
      const call = (workspaceID, action, input) =>
        channel.postMessage({ workspaceID, action, input });
      function mount() {
        const host = document.querySelector("[data-dsh-project-actions]");
        if (host && trigger.parentElement !== host) host.append(trigger);
      }
      async function open() {
        if (!scope.workspaceID) return;
        if (!dialog.open) dialog.showModal();
        render();
        await load();
      }
      async function load() {
        if (!scope.workspaceID) return;
        const id = scope.workspaceID,
          ticket = ++sequence;
        loading = true;
        try {
          const data = await call(id, "snapshot");
          if (disposed || ticket !== sequence || id !== scope.workspaceID)
            return;
          state().data = data;
          state().error = "";
        } catch (e) {
          if (ticket === sequence && id === scope.workspaceID)
            state().error = e.message;
        } finally {
          if (ticket === sequence) {
            loading = false;
            if (!state().draft) render();
            else
              notify(
                state().error || "草稿已保留，保存前会检查是否有其他修改。",
              );
          }
        }
      }
      function begin(kind, row, index) {
        const s = state();
        s.draft = {
          kind,
          operation: row === undefined ? "add" : "edit",
          version:
            kind === "profile"
              ? s.data.profile.version
              : (row?.version ?? s.data.emptyVersion),
          index,
          id: row?.id,
          text: kind === "profile" ? (row ?? "") : (row?.text ?? ""),
          category: row?.kind ?? "fact",
          tags: row?.tags?.join("，") ?? "",
        };
        s.error = "";
        render();
        main.querySelector("textarea")?.focus();
      }
      async function save(input, draft) {
        if (saving) return;
        const id = scope.workspaceID,
          s = state();
        saving = true;
        sequence++;
        loading = false;
        notify("正在保存…");
        setBusy(true);
        try {
          const data = await call(id, "mutate", input);
          s.data = data;
          s.error = "";
          if (s.draft === draft) s.draft = null;
          if (scope.workspaceID === id && !disposed) {
            render();
            notify("已保存到此项目的记忆库。");
          }
        } catch (e) {
          s.error = e.message;
          if (scope.workspaceID === id && !disposed) notify(e.message);
        } finally {
          saving = false;
          setBusy(false);
        }
      }
      function setBusy(value) {
        for (const node of main.querySelectorAll(
          "button,input,textarea,select",
        ))
          node.disabled = value;
      }
      function render() {
        const s = state(),
          data = s.data;
        title.textContent = (data?.title || "项目") + " · 记忆";
        subtitle.textContent = data?.sharedPath
          ? "此项目与另一个项目使用同一文件夹，共享记忆。"
          : "保留这个项目的偏好、背景与重要决定";
        subtitle.title = data?.path ?? "";
        tabs.replaceChildren();
        for (const [key, label] of [
          ["profile", "简要记忆"],
          ["fact", "长期记忆"],
        ]) {
          const b = button(label, () => {
            tab = key;
            render();
          });
          b.setAttribute("aria-pressed", String(tab === key));
          b.disabled = Boolean(s.draft);
          tabs.append(b);
        }
        notify(s.error);
        main.replaceChildren();
        if (!data) {
          main.append(
            el(
              "p",
              "dpm-empty",
              loading
                ? "正在读取项目记忆…"
                : s.error
                  ? "暂时无法读取记忆。"
                  : "这个项目还没有加载记忆。",
            ),
            button("重新读取", load),
          );
          return;
        }
        if (s.draft) {
          renderEditor(s);
          return;
        }
        const info = el("div", "dpm-info");
        info.append(
          el(
            "p",
            "",
            tab === "profile"
              ? data.config.injectProfile
                ? "简短、常用的项目背景，会由记忆插件带入对话。"
                : "记忆插件当前关闭了自动带入；这里仍可查看和整理。"
              : "更具体的经验与决定，由 AI 按需检索。归档后将不再被检索。",
          ),
        );
        const add = button("＋ 添加记忆", () => begin(tab), "dpm-primary");
        const count =
          tab === "profile"
            ? data.profile.entries.length
            : data.facts.filter((f) => f.state === "active").length;
        const max =
          tab === "profile"
            ? data.config.maxProfileEntries
            : data.config.maxFactsPerWorkspace;
        info.append(
          el("span", "dpm-count", `${count} / ${max} 条`),
          add,
          button("刷新", load),
        );
        main.append(info);
        if (tab === "profile") {
          if (!data.profile.entries.length)
            main.append(
              el(
                "p",
                "dpm-empty",
                "还没有简要记忆。可以先记下这个项目的目标、你的偏好或长期约定。",
              ),
            );
          data.profile.entries.forEach((text, index) => {
            const card = el("article", "dpm-card"),
              content = el("div", "dpm-content");
            content.append(
              el("span", "dpm-eyebrow", `简要记忆 ${index + 1}`),
              el("p", "dpm-text", text),
            );
            card.append(
              content,
              button("编辑", () => begin("profile", text, index)),
            );
            main.append(card);
          });
        } else {
          const filters = el("div", "dpm-filters"),
            search = el("input");
          search.type = "search";
          search.placeholder = "搜索内容或标签";
          search.setAttribute("aria-label", "搜索项目长期记忆");
          search.value = query;
          const toggle = el("label"),
            check = el("input");
          check.type = "checkbox";
          check.checked = archived;
          toggle.append(check, document.createTextNode("查看已归档"));
          filters.append(search, toggle);
          main.append(filters);
          const list = el("div");
          main.append(list);
          function rows() {
            list.replaceChildren();
            const q = query.trim().toLocaleLowerCase();
            const facts = data.facts.filter(
              (f) =>
                (archived ? f.state === "archived" : f.state === "active") &&
                (!q ||
                  (f.text + " " + f.tags.join(" "))
                    .toLocaleLowerCase()
                    .includes(q)),
            );
            if (!facts.length)
              list.append(
                el(
                  "p",
                  "dpm-empty",
                  q
                    ? "没有匹配的记忆。"
                    : archived
                      ? "没有已归档的记忆。"
                      : "还没有长期记忆，可以添加项目背景、经验或决定。",
                ),
              );
            for (const fact of facts) {
              const card = el("article", "dpm-card"),
                content = el("div", "dpm-content"),
                meta = el("div", "dpm-meta");
              meta.append(el("span", "dpm-eyebrow", labels[fact.kind]));
              if (fact.state === "archived")
                meta.append(el("span", "", "已归档"));
              content.append(meta, el("p", "dpm-text", fact.text));
              if (fact.tags.length)
                content.append(
                  el("p", "dpm-tags", fact.tags.map((t) => "#" + t).join("  ")),
                );
              const source = el(
                "small",
                "dpm-source",
                (fact.sessionId === "desktop-editor"
                  ? "手动编辑"
                  : "来自项目对话") +
                  " · " +
                  new Date(fact.updatedAt).toLocaleString(),
              );
              source.title =
                fact.sessionId === "desktop-editor"
                  ? "客户端手动编辑"
                  : `来源：${fact.sessionId} #${fact.seq}`;
              content.append(source);
              const actions = el("div", "dpm-card-actions");
              actions.append(
                button("编辑", () => begin("fact", fact)),
                button(fact.state === "archived" ? "恢复" : "归档", () =>
                  save({
                    kind: "fact",
                    operation:
                      fact.state === "archived" ? "restore" : "archive",
                    id: fact.id,
                    version: fact.version,
                  }),
                ),
              );
              card.append(content, actions);
              list.append(card);
            }
          }
          search.addEventListener("input", () => {
            query = search.value;
            rows();
          });
          check.addEventListener("change", () => {
            archived = check.checked;
            rows();
          });
          rows();
        }
      }
      function renderEditor(s) {
        const d = s.draft,
          max =
            d.kind === "profile"
              ? s.data.config.maxProfileEntryChars
              : s.data.config.maxFactChars;
        const top = el("div", "dpm-editor-title");
        top.append(
          el(
            "h3",
            "",
            (d.operation === "add" ? "添加" : "编辑") +
              (d.kind === "profile" ? "简要记忆" : "长期记忆"),
          ),
          button("放弃草稿并重载", () => {
            s.draft = null;
            s.error = "";
            render();
            load();
          }),
        );
        main.append(top);
        const form = el("form", "dpm-editor"),
          label = el("label", "", "记忆内容"),
          text = el("textarea");
        text.value = d.text;
        text.placeholder =
          d.kind === "profile"
            ? "例如：这个项目的文章面向初学者，表达简洁。"
            : "记下一条具体的项目背景、经验或决定。";
        text.setAttribute("aria-label", "记忆内容");
        label.append(text);
        const count = el("small", "dpm-source");
        const updateCount = () =>
          (count.textContent = `${[...d.text].length} / ${max} 字`);
        updateCount();
        text.addEventListener("input", () => {
          d.text = text.value;
          updateCount();
        });
        form.append(label, count);
        if (d.kind === "fact") {
          const fields = el("div", "dpm-fields"),
            categoryLabel = el("label", "", "分类"),
            category = el("select");
          category.setAttribute("aria-label", "记忆分类");
          for (const [value, title] of Object.entries(labels)) {
            const o = el("option", "", title);
            o.value = value;
            category.append(o);
          }
          category.value = d.category;
          category.addEventListener(
            "change",
            () => (d.category = category.value),
          );
          categoryLabel.append(category);
          const tagsLabel = el("label", "", "标签"),
            tags = el("input");
          tags.value = d.tags;
          tags.placeholder = "用逗号分隔，例如：写作，资料";
          tags.setAttribute("aria-label", "记忆标签");
          tags.addEventListener("input", () => (d.tags = tags.value));
          tagsLabel.append(tags);
          fields.append(categoryLabel, tagsLabel);
          form.append(fields);
        }
        const actions = el("div", "dpm-editor-actions"),
          submit = el("button", "dpm-primary", "保存记忆");
        submit.type = "submit";
        actions.append(
          submit,
          el("small", "dpm-source", "⌘ S 保存 · 返回项目会保留草稿"),
        );
        const submitDraft = () =>
          save(
            {
              ...d,
              tags: d.tags
                .split(/[,，]/)
                .map((t) => t.trim())
                .filter(Boolean),
            },
            d,
          );
        form.addEventListener("submit", (e) => {
          e.preventDefault();
          submitDraft();
        });
        text.addEventListener("keydown", (e) => {
          if ((e.metaKey || e.ctrlKey) && e.key === "s") {
            e.preventDefault();
            submitDraft();
          }
        });
        if (d.kind === "profile" && d.operation === "edit") {
          const remove = button(
            "移除这条记忆",
            () => {
              remove.replaceWith(
                button(
                  "确认移除",
                  () => save({ ...d, operation: "remove" }, d),
                  "dpm-danger",
                ),
              );
            },
            "dpm-danger",
          );
          actions.append(remove);
        }
        form.append(actions);
        main.append(form);
        setBusy(saving);
      }
      const onScope = (e) => {
        const next = e.detail ?? {};
        const changed = next.workspaceID !== scope.workspaceID;
        scope = next;
        trigger.disabled = !scope.workspaceID;
        if (changed) {
          sequence++;
          loading = false;
          query = "";
          if (dialog.open) {
            if (!scope.workspaceID) dialog.close();
            else {
              render();
              load();
            }
          }
        }
        mount();
      };
      const observer = new MutationObserver(mount);
      ctx.effect(() => {
        window.addEventListener("dsh:project-scope", onScope);
        observer.observe(document.body, { childList: true, subtree: true });
        mount();
        window.dispatchEvent(new CustomEvent("dsh:request-project-scope"));
        return () => {
          disposed = true;
          sequence++;
          observer.disconnect();
          window.removeEventListener("dsh:project-scope", onScope);
          trigger.remove();
          dialog.remove();
          style.remove();
          states.clear();
        };
      });
    }
    return { inject: [], apply };
  },
});
