window.__ModuleLoader__.load({
  id: "dsh-desktop-project-views",
  factory: () => {
    const stylesheet = /* PROJECT_VIEWS_CSS */ "";
    const MarkdownIt = /* MARKDOWN_ENGINE */ null;
    const markdownTools = /* MARKDOWN_TOOLS */ null;
    // Membership is authoritative. Matching cwd would incorrectly adopt
    // ungrouped sessions or a different workspace pointing at the same path.
    function selectedWorkspace(sessions, workspaces) {
      if (!sessions.current || !workspaces.baselinesReady) return undefined;
      let current = sessions.current;
      const seen = new Set();
      while (current && !seen.has(current)) {
        seen.add(current);
        const match = workspaces.items.find((item) =>
          item.sessionIds.includes(current),
        );
        if (match) return match;
        const row = sessions.byId[current];
        current = row?.origin === "subagent" ? row.parentId : undefined;
      }
    }
    function createNavigation() {
      let generation = 0;
      return {
        workspace: undefined,
        mode: "traditional",
        path: "",
        select(workspace) {
          if (
            this.workspace?.workspaceId === workspace?.workspaceId &&
            this.workspace?.path === workspace?.path
          ) {
            this.workspace = workspace;
            return false;
          }
          this.workspace = workspace;
          this.path = "";
          this.mode = "traditional";
          generation++;
          return true;
        },
        invalidate() {
          generation++;
        },
        ticket() {
          const value = generation;
          return () => generation === value;
        },
      };
    }
    function element(tag, className, text) {
      const node = document.createElement(tag);
      if (className) node.className = className;
      if (text !== undefined) node.textContent = text;
      return node;
    }
    function button(label, action, className = "") {
      const node = element("button", className, label);
      node.type = "button";
      node.addEventListener("click", action);
      return node;
    }
    const icons = {
      folder:
        '<path d="M3 7a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/>',
      file: '<path d="M6 3h8l5 5v13H6Z"/><path d="M14 3v6h5M9 13h7M9 17h5"/>',
      image:
        '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 6-5 4 3 4-6 4 8"/>',
    };
    function icon(kind) {
      const node = element("span", "dpv-icon dpv-icon-" + kind);
      // Only constant, shipped SVG markup; no project text enters innerHTML.
      node.innerHTML =
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true">' +
        icons[kind] +
        "</svg>";
      return node;
    }
    function size(bytes) {
      if (bytes < 1024) return bytes + " B";
      if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
      return (bytes / 1024 / 1024).toFixed(1) + " MB";
    }
    // The only DOM adapter for upstream layout. Validate the whole shell before
    // touching it; unknown layouts retain the original UI. Never reparent or
    // unmount React's conversation/sidebar, so drafts and scroll state survive.
    function findSurface() {
      const overlay = document.querySelector("[data-shell-overlay]");
      const frame = overlay?.parentElement;
      if (!frame) return;
      const children = [...frame.children];
      const column = (suffix) =>
        children.find((node) =>
          [...node.classList].some((name) => name.endsWith(suffix)),
        );
      const center = column("_centerCol"),
        sidebar = column("_sidebarCol"),
        details = column("_detailsCol");
      if (center && sidebar && details) return { frame, center, details };
    }
    function apply(ctx) {
      const channel = window.webkit?.messageHandlers.dshProjectFiles;
      if (!channel) return;
      const navigation = createNavigation();
      let disposed = false,
        surface,
        scheduled = false,
        requestNumber = 0,
        geometry = "";
      let entries = [],
        selected,
        folderScroll = 0,
        scopeReady = false,
        scopeError = "",
        showHidden = false,
        listMode = false;
      let chatMode = null,
        publishedScope = "",
        lastCurrentSession;
      const header = element("div", "dpv-header");
      header.dataset.dshProjectUi = "";
      const title = element("div", "dpv-project-title", "项目视图");
      const switcher = element("div", "dpv-switcher");
      switcher.setAttribute("role", "group");
      switcher.setAttribute("aria-label", "项目视图");
      const traditional = button("传统视图", () => setMode("traditional"));
      const folder = button("文件夹", () => setMode("folder"));
      switcher.append(traditional, folder);
      const projectActions = element("div", "dpv-project-actions");
      projectActions.dataset.dshProjectActions = "";
      header.append(title, projectActions, switcher);
      const panel = element("section", "dpv-panel");
      panel.dataset.dshProjectUi = "";
      panel.setAttribute("aria-label", "项目文件夹");
      const toolsHost = element("div", "dpv-workspace-tools");
      toolsHost.dataset.dshWorkspaceTools = "";
      const rail = element("div", "dpv-chat-rail");
      rail.dataset.dshProjectUi = "";
      rail.append(
        button("对话", () => openChat("chat")),
        button("历史", () => openChat("history")),
      );
      const chatHeader = element("div", "dpv-chat-header");
      chatHeader.dataset.dshProjectUi = "";
      const chatTitle = element("strong", "", "项目对话");
      const newChat = button("新对话", () => {
        if (navigation.workspace) {
          ctx.workspaces.startSession(navigation.workspace.workspaceId);
          openChat("chat");
        }
      });
      const historyButton = button("历史", () =>
        openChat(chatMode === "history" ? "chat" : "history"),
      );
      const closeChat = button("×", () => openChat(null));
      closeChat.setAttribute("aria-label", "收起对话面板");
      chatHeader.append(chatTitle, newChat, historyButton, closeChat);
      const history = element("section", "dpv-chat-history");
      history.dataset.dshProjectUi = "";
      history.setAttribute("aria-label", "项目对话历史");
      const tools = element("div", "dpv-tools");
      const up = button(
        "↑",
        () => navigate(navigation.path.split("/").slice(0, -1).join("/")),
        "dpv-square",
      );
      up.title = "上一级";
      up.setAttribute("aria-label", "上一级");
      const breadcrumbs = element("nav", "dpv-breadcrumbs");
      breadcrumbs.setAttribute("aria-label", "文件夹路径");
      const refresh = button("刷新", () => loadDirectory());
      const finder = button("在 Finder 中打开", () => reveal(navigation.path));
      tools.append(up, breadcrumbs, refresh, finder);
      const controls = element("div", "dpv-controls");
      const search = element("input", "dpv-search");
      search.type = "search";
      search.placeholder = "搜索当前文件夹";
      search.setAttribute("aria-label", "搜索当前文件夹");
      search.addEventListener("input", renderEntries);
      const hiddenLabel = element("label", "dpv-hidden-label");
      const hidden = element("input");
      hidden.type = "checkbox";
      hidden.addEventListener("change", () => {
        showHidden = hidden.checked;
        loadDirectory();
      });
      hiddenLabel.append(hidden, document.createTextNode("显示隐藏项"));
      const layout = button("列表", () => {
        listMode = !listMode;
        layout.textContent = listMode ? "图标" : "列表";
        renderEntries();
      });
      layout.setAttribute("aria-label", "切换文件排列方式");
      controls.append(search, hiddenLabel, layout);
      const notice = element("div", "dpv-notice");
      notice.setAttribute("role", "status");
      notice.hidden = true;
      const body = element("div", "dpv-browser-body");
      const listing = element("div", "dpv-listing");
      listing.setAttribute("aria-label", "文件和文件夹");
      const footer = element("div", "dpv-footer");
      body.append(listing);
      panel.append(tools, controls, toolsHost, notice, body, footer);
      const markdownViewer = markdownTools.createViewer({
        panel,
        element,
        button,
        MarkdownIt,
        call: (workspaceID, action, extra = {}) =>
          channel.postMessage({ workspaceID, action, ...extra }),
        onClose: () => {
          selected = undefined;
          renderEntries();
          listing.scrollTop = folderScroll;
        },
        onOpenFile: (path) =>
          openEntry({ path, name: path.split("/").at(-1), accessible: true }),
        onSaved: () => {
          if (navigation.mode === "folder") loadDirectory();
        },
      });
      const style = element("style");
      style.textContent = stylesheet;
      document.head.append(style);
      const originalInert = new Map();
      function request(action, extra = {}) {
        const id = navigation.workspace?.workspaceId;
        if (!id) return Promise.reject(new Error("请先选择一个项目。"));
        return channel.postMessage({ action, workspaceID: id, ...extra });
      }
      function message(text) {
        notice.textContent = text;
        notice.hidden = !text;
      }
      function restore() {
        if (!surface) return;
        surface.center.removeAttribute("data-dsh-folder");
        surface.center.removeAttribute("data-dpv-chat");
        surface.frame.removeAttribute("data-dsh-folder-frame");
        surface.frame.style.removeProperty("--dpv-sidebar-width");
        for (const [node, value] of originalInert) node.inert = value;
        originalInert.clear();
        for (const node of surface.center.children)
          node.removeAttribute("data-dpv-conversation");
        header.remove();
        panel.remove();
        rail.remove();
        chatHeader.remove();
        history.remove();
      }
      function paintMode() {
        if (!surface) return;
        const isFolder = navigation.mode === "folder";
        traditional.setAttribute("aria-pressed", String(!isFolder));
        folder.setAttribute("aria-pressed", String(isFolder));
        folder.disabled = !navigation.workspace || (!scopeReady && !scopeError);
        title.textContent =
          navigation.workspace?.title ||
          navigation.workspace?.path?.split("/").filter(Boolean).at(-1) ||
          "项目视图";
        title.title = navigation.workspace?.path || "请先选择项目";
        panel.hidden = !isFolder;
        surface.center.toggleAttribute("data-dsh-folder", isFolder);
        if (isFolder && chatMode)
          surface.center.setAttribute("data-dpv-chat", chatMode);
        else surface.center.removeAttribute("data-dpv-chat");
        rail.hidden = !isFolder || Boolean(chatMode);
        chatHeader.hidden = !isFolder || !chatMode;
        history.hidden = !isFolder || chatMode !== "history";
        chatTitle.textContent =
          chatMode === "history" ? "对话历史" : "项目对话";
        historyButton.textContent =
          chatMode === "history" ? "返回对话" : "历史";
        surface.frame.toggleAttribute("data-dsh-folder-frame", isFolder);
        const targets = [...surface.center.children].filter(
          (node) => !node.hasAttribute("data-dsh-project-ui"),
        );
        targets.push(surface.details);
        for (const node of targets) {
          if (node !== surface.details)
            node.setAttribute("data-dpv-conversation", "");
          if (isFolder && (node === surface.details || chatMode !== "chat")) {
            if (!originalInert.has(node)) originalInert.set(node, node.inert);
            node.inert = true;
          } else if (originalInert.has(node)) {
            node.inert = originalInert.get(node);
            originalInert.delete(node);
          }
        }
        // Retain the sidebar's exact width, including upstream collapse/drag.
        geometry = surface.frame.style.gridTemplateColumns;
        const firstTrack = geometry.split(" ")[0];
        if (/^\d+(\.\d+)?px$/.test(firstTrack))
          surface.frame.style.setProperty("--dpv-sidebar-width", firstTrack);
        updateBreadcrumbs();
        publishScope();
      }
      // Small, event-based surface contract. Other workspace tools mount in the
      // provided host and receive identity; they never inspect upstream DOM.
      function publishScope(force = false) {
        const detail = {
          workspaceID: navigation.workspace?.workspaceId ?? null,
          sessionID: ctx.sessions.list.getSnapshot().current ?? null,
          mode: navigation.mode,
        };
        const key = JSON.stringify(detail);
        if (force || key !== publishedScope) {
          publishedScope = key;
          window.dispatchEvent(
            new CustomEvent("dsh:project-scope", { detail }),
          );
        }
      }
      async function openChat(mode, sessionID) {
        if (sessionID) {
          const w = ctx.workspaces.list
            .getSnapshot()
            .items.find((w) => w.sessionIds.includes(sessionID));
          if (!w || w.workspaceId !== navigation.workspace?.workspaceId) {
            message("该对话不属于当前项目。");
            return;
          }
          const current = navigation.ticket();
          try {
            if (!ctx.sessions.list.getSnapshot().byId[sessionID])
              await ctx.sessions.create({
                workspaceId: w.workspaceId,
                sessionId: sessionID,
              });
            if (!current() || disposed) return;
            ctx.sessions.open(sessionID);
          } catch (error) {
            message("无法打开对话：" + error.message);
            return;
          }
        }
        chatMode = mode;
        paintMode();
        renderHistory();
      }
      function renderHistory() {
        if (chatMode !== "history") return;
        const list = ctx.sessions.list.getSnapshot(),
          w = navigation.workspace,
          archived = new Set(
            ctx.workspaces.list.getSnapshot().archivedSessionIds,
          );
        const rows = (w?.sessionIds ?? [])
          .map((id) => list.byId[id])
          .filter(
            (row) =>
              row &&
              !archived.has(row.id) &&
              (!row.blank || row.id === list.current),
          )
          .sort((a, b) => b.updatedAt - a.updatedAt);
        history.replaceChildren();
        for (const row of rows) {
          const item = button(
            "",
            () => openChat("chat", row.id),
            "dpv-history-item",
          );
          item.append(
            element("strong", "", row.displayTitle || row.title || "新对话"),
            element(
              "span",
              "",
              row.running ? "进行中" : new Date(row.updatedAt).toLocaleString(),
            ),
          );
          if (row.id === list.current)
            item.setAttribute("aria-current", "true");
          history.append(item);
        }
        if (!rows.length)
          history.append(element("p", "dpv-empty", "这个项目还没有对话。"));
      }
      function updateBreadcrumbs() {
        breadcrumbs.replaceChildren();
        breadcrumbs.append(
          button(navigation.workspace?.title || "项目文件夹", () =>
            navigate(""),
          ),
        );
        const segments = navigation.path.split("/").filter(Boolean);
        segments.forEach((name, index) => {
          breadcrumbs.append(
            element("span", "", "›"),
            button(name, () =>
              navigate(segments.slice(0, index + 1).join("/")),
            ),
          );
        });
        up.disabled = !navigation.path;
      }
      async function setMode(mode) {
        if (mode === navigation.mode) return;
        if (mode === "folder" && !navigation.workspace) return;
        navigation.mode = mode;
        paintMode();
        const current = navigation.ticket();
        if (mode === "folder") {
          // Move focus out of the now-inert conversation, including its composer.
          folder.focus();
          loadDirectory();
        } else {
          requestNumber++;
          closePreview();
        }
        if (!current() || disposed) return;
        try {
          await request("mode", { mode });
        } catch (error) {
          if (current() && !disposed)
            message("视图偏好未保存：" + error.message);
        }
      }
      function closePreview() {
        markdownViewer.close();
      }
      function navigate(path) {
        navigation.path = path;
        search.value = "";
        closePreview();
        entries = [];
        listing.replaceChildren();
        updateBreadcrumbs();
        loadDirectory();
      }
      async function loadDirectory() {
        if (navigation.mode !== "folder") return;
        const number = ++requestNumber,
          current = navigation.ticket();
        const oldSelection = selected?.path;
        message("");
        listing.setAttribute("aria-busy", "true");
        footer.textContent = "正在读取文件夹…";
        try {
          if (!scopeReady) {
            await request("scope");
            if (disposed || !current() || number !== requestNumber) return;
            scopeReady = true;
            scopeError = "";
            paintMode();
          }
          const result = await request("list", {
            path: navigation.path,
            showHidden,
          });
          if (disposed || !current() || number !== requestNumber) return;
          entries = result.entries;
          renderEntries();
          if (
            oldSelection &&
            !entries.some((item) => item.path === oldSelection)
          )
            closePreview();
        } catch (error) {
          if (disposed || !current() || number !== requestNumber) return;
          entries = [];
          listing.replaceChildren();
          closePreview();
          message(error.message);
          footer.textContent = "无法读取文件夹 · 可刷新重试";
        } finally {
          if (number === requestNumber) listing.removeAttribute("aria-busy");
        }
      }
      function renderEntries() {
        const focusedPath =
          document.activeElement?.closest(".dpv-entry")?.dataset.path;
        listing.classList.toggle("dpv-list", listMode);
        const query = search.value.trim().toLocaleLowerCase();
        const visible = entries.filter((item) =>
          item.name.toLocaleLowerCase().includes(query),
        );
        const fragment = document.createDocumentFragment();
        for (const entry of visible) {
          const item = button(
            "",
            () =>
              entry.directory && entry.accessible
                ? navigate(entry.path)
                : openEntry(entry),
            "dpv-entry",
          );
          item.title = entry.name;
          item.dataset.path = entry.path;
          item.classList.toggle("dpv-selected", selected?.path === entry.path);
          const isImage = /\.(png|jpe?g|gif|webp)$/i.test(entry.name);
          item.append(
            icon(entry.directory ? "folder" : isImage ? "image" : "file"),
            element("span", "dpv-entry-name", entry.name),
          );
          const description = entry.accessible
            ? entry.directory
              ? "文件夹"
              : size(entry.size)
            : "项目外的链接";
          item.append(element("span", "dpv-entry-meta", description));
          const date = entry.modified
            ? new Date(entry.modified).toLocaleDateString()
            : "";
          item.append(element("span", "dpv-entry-date", date));
          fragment.append(item);
        }
        if (!visible.length) {
          const empty = element("div", "dpv-empty");
          empty.append(
            icon("folder"),
            element("p", "", query ? "没有匹配的文件" : "这个文件夹还是空的"),
            element(
              "span",
              "",
              query
                ? "试试其他名称，或清除搜索。"
                : "在这里存放资料，随时切回传统视图继续工作。",
            ),
          );
          fragment.append(empty);
        }
        listing.replaceChildren(fragment);
        if (focusedPath)
          [...listing.children]
            .find((node) => node.dataset.path === focusedPath)
            ?.focus({ preventScroll: true });
        footer.textContent = query
          ? `${visible.length} / ${entries.length} 项`
          : `${entries.length} 项`;
      }
      async function openEntry(entry) {
        if (!entry.accessible) {
          message("这个链接指向项目外，请在 Finder 中查看。");
          return;
        }
        if (markdownTools.isMarkdown(entry.path)) {
          selected = entry;
          folderScroll = listing.scrollTop;
          chatMode = null;
          paintMode();
          markdownViewer.open(navigation.workspace.workspaceId, entry.path);
          return;
        }
        const current = navigation.ticket();
        try {
          await request("open", { path: entry.path });
        } catch (error) {
          if (current() && !disposed) message(error.message);
        }
      }
      async function reveal(path) {
        const current = navigation.ticket();
        try {
          await request("reveal", { path });
        } catch (error) {
          if (current() && !disposed) message(error.message);
        }
      }
      function reconcile() {
        if (disposed) return;
        const next = selectedWorkspace(
          ctx.sessions.list.getSnapshot(),
          ctx.workspaces.list.getSnapshot(),
        );
        const currentSession = ctx.sessions.list.getSnapshot().current;
        const sessionChanged =
          lastCurrentSession !== undefined &&
          lastCurrentSession !== currentSession;
        lastCurrentSession = currentSession;
        const changed = navigation.select(next);
        if (changed) {
          requestNumber++;
          closePreview();
          entries = [];
          search.value = "";
          scopeReady = false;
          scopeError = "";
          listing.replaceChildren();
          message("");
          if (next) {
            const current = navigation.ticket();
            request("scope")
              .then((result) => {
                if (!current() || disposed) return;
                scopeReady = true;
                navigation.mode = result.mode;
                if (sessionChanged && navigation.mode === "folder")
                  chatMode = "chat";
                paintMode();
                loadDirectory();
              })
              .catch((error) => {
                if (!current() || disposed) return;
                scopeError = error.message;
                paintMode();
                if (navigation.mode === "folder") message(scopeError);
              });
          }
        }
        const nextSurface = findSurface();
        if (nextSurface?.center !== surface?.center) {
          restore();
          surface = nextSurface;
          if (surface) {
            surface.center.prepend(header);
            surface.center.append(panel, rail, chatHeader, history);
            publishScope(true);
          }
        }
        // Selecting a history row in the existing sidebar should reveal the
        // conversation while retaining folder mode and the project tools.
        if (sessionChanged && navigation.mode === "folder") chatMode = "chat";
        paintMode();
        renderHistory();
      }
      function schedule() {
        if (scheduled || disposed) return;
        scheduled = true;
        queueMicrotask(() => {
          scheduled = false;
          reconcile();
        });
      }
      const observer = new MutationObserver((records) => {
        // Ignore our own nodes and style writes. Observe shell replacement and
        // upstream grid geometry only; do not rerender on streamed token text.
        if (
          !surface?.center.isConnected ||
          records.some((record) =>
            record.type === "attributes"
              ? record.target === surface.frame &&
                record.target.style.gridTemplateColumns !== geometry
              : record.target === surface.center &&
                [...record.addedNodes].some(
                  (node) =>
                    node.nodeType === 1 &&
                    !node.hasAttribute("data-dsh-project-ui"),
                ),
          )
        )
          schedule();
      });
      ctx.effect(() => {
        const onScopeRequest = () => publishScope(true);
        const onChatRequest = (event) =>
          openChat("chat", event.detail?.sessionID);
        window.addEventListener("dsh:request-project-scope", onScopeRequest);
        window.addEventListener("dsh:open-project-chat", onChatRequest);
        const unsubscribeSessions = ctx.sessions.list.subscribe(schedule);
        const unsubscribeWorkspaces = ctx.workspaces.list.subscribe(schedule);
        observer.observe(document.body, {
          subtree: true,
          childList: true,
          attributes: true,
          attributeOldValue: true,
          attributeFilter: ["style"],
        });
        const onFocus = () => {
          if (!document.hidden && navigation.mode === "folder") loadDirectory();
        };
        window.addEventListener("focus", onFocus);
        document.addEventListener("visibilitychange", onFocus);
        reconcile();
        return () => {
          disposed = true;
          navigation.invalidate();
          unsubscribeSessions();
          unsubscribeWorkspaces();
          observer.disconnect();
          window.removeEventListener("focus", onFocus);
          document.removeEventListener("visibilitychange", onFocus);
          window.removeEventListener(
            "dsh:request-project-scope",
            onScopeRequest,
          );
          window.removeEventListener("dsh:open-project-chat", onChatRequest);
          markdownViewer.dispose();
          restore();
          style.remove();
        };
      });
    }
    return {
      inject: ["sessions", "workspaces"],
      apply,
      selectedWorkspace,
      createNavigation,
      findSurface,
    };
  },
});
