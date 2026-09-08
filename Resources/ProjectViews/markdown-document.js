(function () {
  const isMarkdown = (path) => /\.(md|markdown)$/i.test(path);
  function localTarget(documentPath, reference) {
    if (
      !reference ||
      /^[a-z][a-z\d+.-]*:/i.test(reference) ||
      reference.startsWith("//")
    )
      return null;
    let decoded;
    try {
      decoded = decodeURIComponent(reference.split(/[?#]/)[0]);
    } catch {
      return null;
    }
    if (
      !decoded ||
      decoded.startsWith("/") ||
      decoded.includes("\0") ||
      decoded.includes("\\")
    )
      return null;
    const parts = documentPath.split("/").slice(0, -1);
    for (const part of decoded.split("/")) {
      if (part === "..") {
        if (!parts.length) return null;
        parts.pop();
      } else if (part && part !== ".") parts.push(part);
    }
    return parts.join("/");
  }
  function renderer(MarkdownIt) {
    const parser = new MarkdownIt({
      html: false,
      linkify: false,
      typographer: false,
      maxNesting: 32,
    });
    const escape = parser.utils.escapeHtml;
    // Images are hydrated through the workspace-bound native reader. No document
    // can silently fetch a remote image or inject active HTML into the client.
    parser.renderer.rules.image = (tokens, index) => {
      const token = tokens[index],
        src = token.attrGet("src") ?? "",
        label = token.content || "图片";
      return `<span class="dpv-md-image" data-md-image="${escape(src)}" data-md-alt="${escape(label)}">${escape(label)}</span>`;
    };
    parser.renderer.rules.heading_open = (
      tokens,
      index,
      options,
      env,
      self,
    ) => {
      const label = tokens[index + 1]?.content ?? "";
      const base =
        label
          .toLowerCase()
          .replace(/[^\p{L}\p{N}_\s-]/gu, "")
          .trim()
          .replace(/\s+/g, "-") || "section";
      env.headings ??= new Map();
      const count = env.headings.get(base) ?? 0;
      env.headings.set(base, count + 1);
      tokens[index].attrSet(
        "id",
        "dpv-md-" + base + (count ? "-" + count : ""),
      );
      return self.renderToken(tokens, index, options);
    };
    return (text) => parser.render(text, {});
  }
  function createViewer({
    panel,
    element,
    button,
    MarkdownIt,
    call,
    onClose,
    onOpenFile,
    onSaved,
  }) {
    const render = renderer(MarkdownIt),
      cache = new Map();
    const root = element("section", "dpv-document");
    root.hidden = true;
    root.setAttribute("aria-label", "Markdown 文档");
    const top = element("div", "dpv-document-header"),
      back = element("button", "", "← 返回文件夹");
    back.type = "button";
    back.addEventListener("click", () =>
      active?.mode === "edit" ? setMode("read") : close(),
    );
    const name = element("strong", "dpv-document-name"),
      actions = element("div", "dpv-document-actions");
    const edit = button("编辑", () => setMode("edit"));
    const saveButton = button("保存", () => save(), "dpv-document-primary");
    const external = button("默认应用打开", () => {
      if (active) request(active, "open").catch((error) => say(error.message));
    });
    actions.append(edit, saveButton, external);
    top.append(back, name, actions);
    const status = element("div", "dpv-document-status");
    status.setAttribute("aria-live", "polite");
    const reload = button("放弃草稿并重载", () => {
      if (active) open(active.workspaceID, active.path, true);
    });
    const statusText = element("span");
    status.append(statusText, reload);
    const article = element("article", "dpv-markdown");
    article.setAttribute("aria-label", "Markdown 阅读");
    article.tabIndex = 0;
    const editor = element("textarea", "dpv-markdown-editor");
    editor.spellcheck = false;
    editor.setAttribute("aria-label", "Markdown 编辑正文");
    const body = element("div", "dpv-document-body");
    body.append(article, editor);
    root.append(top, status, body);
    panel.append(root);
    let active = null,
      generation = 0,
      draftTimer,
      readNumber = 0;
    const keyFor = (workspaceID, path) =>
      "dsh-desktop.markdown-draft.v1." + workspaceID + "/" + path;
    const request = (state, action, extra = {}) =>
      call(state.workspaceID, action, { path: state.path, ...extra });
    const dirty = (state) => state.text !== state.savedText;
    function say(message) {
      statusText.textContent = message;
      status.hidden = !message;
    }
    function remember(state) {
      if (!state?.version) return;
      const key = keyFor(state.workspaceID, state.path);
      try {
        if (dirty(state))
          localStorage.setItem(
            key,
            JSON.stringify({ version: state.version, text: state.text }),
          );
        else localStorage.removeItem(key);
      } catch {
        if (state === active) say("草稿暂存空间不足，离开应用前请保存文件。");
      }
      if (dirty(state))
        cache.set(key, { version: state.version, text: state.text });
      else cache.delete(key);
    }
    function flush() {
      clearTimeout(draftTimer);
      if (active) remember(active);
    }
    function updateControls() {
      if (!active) return;
      const editing = active.mode === "edit";
      back.textContent = editing ? "← 返回阅读" : "← 返回文件夹";
      edit.hidden = editing || !active.version;
      saveButton.hidden = !active.version || (!editing && !dirty(active));
      saveButton.disabled = active.saving || !dirty(active);
      saveButton.textContent = active.saving ? "保存中…" : "保存";
      reload.hidden = !active.version;
      editor.hidden = !editing;
      article.hidden = editing;
      root.dataset.mode = active.mode;
    }
    const controls = updateControls;
    function close() {
      flush();
      generation++;
      readNumber++;
      active = null;
      root.hidden = true;
      panel.removeAttribute("data-document");
      onClose?.();
    }
    async function open(workspaceID, path, discard = false) {
      flush();
      const ticket = ++generation;
      readNumber++;
      active = {
        workspaceID,
        path,
        name: path.split("/").at(-1),
        mode: "read",
        text: "",
        savedText: "",
        version: null,
        saving: false,
      };
      const state = active;
      root.hidden = false;
      panel.setAttribute("data-document", "");
      name.textContent = state.name;
      name.title = path;
      article.replaceChildren(element("p", "", "正在读取…"));
      body.scrollTop = 0;
      say("");
      controls();
      try {
        const value = await request(state, "markdownRead");
        if (ticket !== generation) return;
        state.savedText = value.text;
        state.version = value.version;
        state.text = value.text;
        const key = keyFor(workspaceID, path);
        if (discard) {
          cache.delete(key);
          try {
            localStorage.removeItem(key);
          } catch {}
        } else {
          let draft = cache.get(key);
          try {
            draft ??= JSON.parse(localStorage.getItem(key) || "null");
          } catch {}
          if (
            draft &&
            typeof draft.text === "string" &&
            draft.text !== value.text
          ) {
            state.text = draft.text;
            state.version = draft.version;
            say(
              draft.version === value.version
                ? "已恢复未保存的草稿。"
                : "磁盘文件已有更新，正在展示保留的草稿；保存前请核对。",
            );
          }
        }
        paintRead();
        controls();
      } catch (error) {
        if (ticket !== generation) return;
        article.replaceChildren(
          element("p", "dpv-document-error", error.message),
        );
        say("可使用右上角的默认应用打开。");
      }
    }
    function setMode(mode) {
      if (!active?.version) return;
      flush();
      active.mode = mode;
      if (mode === "edit") {
        editor.value = active.text;
        controls();
        editor.focus();
        editor.setSelectionRange(0, 0);
        editor.scrollTop = 0;
        body.scrollTop = 0;
      } else {
        paintRead();
        controls();
        body.scrollTop = 0;
      }
      if (dirty(active)) say("有未保存修改，草稿已暂存。");
    }
    function paintRead() {
      if (!active) return;
      const state = active,
        revision = ++readNumber;
      // markdown-it runs with raw HTML disabled and its URL validator enabled.
      article.innerHTML = state.text
        ? render(state.text)
        : '<p class="dpv-document-empty">这是一篇空白文档，点击“编辑”开始书写。</p>';
      for (const link of article.querySelectorAll("a")) {
        link.setAttribute("rel", "noopener noreferrer");
      }
      let total = 0;
      for (const image of article.querySelectorAll("[data-md-image]")) {
        const source = image.dataset.mdImage,
          label = image.dataset.mdAlt,
          path = localTarget(state.path, source);
        if (!path) {
          image.textContent = "图片：" + label;
          if (/^https?:\/\//i.test(source))
            image.append(
              button("在浏览器查看", () =>
                call(state.workspaceID, "openLink", { url: source }).catch(
                  (error) => say(error.message),
                ),
              ),
            );
          continue;
        }
        if (++total > 20) {
          image.textContent = "图片较多，请用默认应用查看其余图片。";
          continue;
        }
        call(state.workspaceID, "preview", { path })
          .then((result) => {
            if (active !== state || revision !== readNumber) return;
            if (result.kind === "image") {
              const img = element("img");
              img.alt = label;
              img.src = result.url;
              image.replaceChildren(img);
            } else
              image.textContent = "图片：" + label + "（可在默认应用中查看）";
          })
          .catch(() => {
            if (active === state && revision === readNumber)
              image.textContent = "无法读取图片：" + label;
          });
      }
    }
    editor.addEventListener("input", () => {
      if (!active) return;
      active.text = editor.value;
      controls();
      say(dirty(active) ? "有未保存修改，草稿自动暂存。" : "");
      clearTimeout(draftTimer);
      draftTimer = setTimeout(flush, 300);
    });
    root.addEventListener("keydown", (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        save();
      }
    });
    article.addEventListener("click", (event) => {
      const link = event.target.closest("a");
      if (!link || !article.contains(link) || !active) return;
      event.preventDefault();
      const href = link.getAttribute("href") ?? "",
        state = active;
      if (href.startsWith("#")) {
        let anchor;
        try {
          anchor = decodeURIComponent(href.slice(1));
        } catch {
          return;
        }
        [...article.querySelectorAll("[id]")]
          .find((el) => el.id === "dpv-md-" + anchor)
          ?.scrollIntoView({ block: "start" });
        return;
      }
      if (/^(https?:|mailto:)/i.test(href)) {
        call(state.workspaceID, "openLink", { url: href }).catch((error) =>
          say(error.message),
        );
        return;
      }
      const path = localTarget(state.path, href);
      if (!path) {
        say("此链接不在当前项目内。");
        return;
      }
      if (isMarkdown(path)) open(state.workspaceID, path);
      else onOpenFile(path);
    });
    async function save() {
      const state = active;
      if (!state?.version || state.saving || !dirty(state)) return;
      const text = state.text;
      state.saving = true;
      controls();
      try {
        const result = await request(state, "markdownSave", {
          text,
          version: state.version,
        });
        state.version = result.version;
        state.savedText = result.text;
        remember(state);
        onSaved?.();
        if (active === state) {
          say(dirty(state) ? "已保存，还有新的修改待保存。" : "已保存。");
          if (state.mode === "read") paintRead();
        }
      } catch (error) {
        remember(state);
        if (active === state) say(error.message);
      } finally {
        state.saving = false;
        if (active === state) controls();
      }
    }
    window.addEventListener("pagehide", flush);
    return {
      open,
      close,
      get path() {
        return active?.path;
      },
      dispose() {
        flush();
        window.removeEventListener("pagehide", flush);
        generation++;
        readNumber++;
        root.remove();
      },
    };
  }
  return { isMarkdown, localTarget, renderer, createViewer };
})();
