import Foundation
import SwiftUI
import AppKit
import DSHCore

// MARK: - 内嵌 DSH 界面

/// `dsh plugin --profile web add ...` 会把用户安装的 Bundle 记录在这个 profile 的 dependencies 中。
/// 官方 Base/Web Bundle 由 DSH 运行时提供，不会出现在这里，因此可作为稳定的“用户安装”边界。
func webProfileUserPluginPackages() -> [String] {
    let packageURL = dshHomeDirectoryURL()
        .appendingPathComponent("profiles/web/package.json")
    guard let data = try? Data(contentsOf: packageURL),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let dependencies = root["dependencies"] as? [String: Any] else { return [] }
    return dependencies.keys.sorted()
}

private func javascriptJSON(_ value: Any, fallback: String) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let result = String(data: data, encoding: .utf8) else { return fallback }
    return result
}

/// 在客户端内嵌 Web UI 中把底层 Loader inventory 重排为用户视图。
/// 只依赖上游明确输出的 data-plugin-entry/data-phase/data-enabled 属性；结构不匹配时不做任何修改。
func pluginInventoryEnhancementScript(enabled: Bool, userPackages: [String]) -> String {
    let enabledLiteral = enabled ? "true" : "false"
    let packagesLiteral = javascriptJSON(userPackages, fallback: "[]")
    return #"""
    (() => {
      const globalKey = "__dshDesktopPluginInventory";
      const initialEnabled = \#(enabledLiteral);
      const initialPackages = \#(packagesLiteral);
      const existing = window[globalKey];
      if (existing && typeof existing.configure === "function") {
        existing.configure(initialEnabled, initialPackages);
        return;
      }

      const storageKey = "dshDesktop.pluginInventory.mode";
      let storedMode = "user";
      try { storedMode = localStorage.getItem(storageKey) || "user"; } catch (_) {}
      if (!["user", "issues", "all"].includes(storedMode)) storedMode = "user";

      const state = {
        enabled: initialEnabled,
        packages: new Set(initialPackages),
        mode: storedMode,
      };
      let scheduled = false;

      function copy() {
        const language = (document.documentElement.lang || navigator.language || "").toLowerCase();
        const zh = language.startsWith("zh");
        return zh ? {
          user: "用户安装",
          issues: "异常 / 等待",
          all: "全部运行单元",
          headingUser: "用户安装的插件",
          headingIssues: "需要关注的运行单元",
          headingAll: "全部运行单元（高级诊断）",
          emptyUser: "没有识别到用户安装插件贡献的运行单元。",
          emptyIssues: "当前没有挂载失败、等待依赖或加载中的运行单元。",
          note: (packages, units, hidden) => `${packages} 个用户包贡献 ${units} 个运行单元；默认隐藏 ${hidden} 个官方/内部运行单元。`,
        } : {
          user: "User installed",
          issues: "Issues / waiting",
          all: "All runtime units",
          headingUser: "User-installed plugins",
          headingIssues: "Runtime units needing attention",
          headingAll: "All runtime units (advanced diagnostics)",
          emptyUser: "No runtime units from user-installed plugins were identified.",
          emptyIssues: "No runtime units are failed, waiting for dependencies, or loading.",
          note: (packages, units, hidden) => `${packages} user packages contribute ${units} runtime units; ${hidden} official/internal units are hidden by default.`,
        };
      }

      function isUserModule(moduleName) {
        for (const packageName of state.packages) {
          if (moduleName === packageName || moduleName.startsWith(`${packageName}/`)) return true;
        }
        return false;
      }

      function facts(card) {
        const title = card.querySelector("strong[title]");
        const moduleName = title ? (title.getAttribute("title") || "") : "";
        const phaseNode = card.querySelector("[data-phase]");
        const phase = phaseNode ? phaseNode.getAttribute("data-phase") : "unobserved";
        const enabledNode = card.querySelector("[data-enabled]");
        const configured = enabledNode && enabledNode.getAttribute("data-enabled") === "true";
        const issue = configured && ["failed", "pending", "loading", "unloading", "unobserved"].includes(phase || "unobserved");
        return { card, moduleName, user: isUserModule(moduleName), issue };
      }

      function setText(node, value) {
        if (node && node.textContent !== String(value)) node.textContent = String(value);
      }

      function makeControls(catalog, list) {
        let controls = Array.from(catalog.children).find((node) => node.hasAttribute && node.hasAttribute("data-dsh-desktop-inventory-controls"));
        if (controls) return controls;

        controls = document.createElement("div");
        controls.setAttribute("data-dsh-desktop-inventory-controls", "true");
        const choices = document.createElement("div");
        choices.setAttribute("data-dsh-desktop-inventory-choices", "true");
        for (const mode of ["user", "issues", "all"]) {
          const button = document.createElement("button");
          button.type = "button";
          button.setAttribute("data-dsh-desktop-mode", mode);
          const label = document.createElement("span");
          label.setAttribute("data-dsh-desktop-label", "true");
          const count = document.createElement("span");
          count.setAttribute("data-dsh-desktop-count", "true");
          button.append(label, count);
          button.addEventListener("click", () => {
            state.mode = mode;
            try { localStorage.setItem(storageKey, mode); } catch (_) {}
            schedule();
          });
          choices.appendChild(button);
        }
        const note = document.createElement("p");
        note.setAttribute("data-dsh-desktop-inventory-note", "true");
        const empty = document.createElement("p");
        empty.setAttribute("data-dsh-desktop-inventory-empty", "true");
        empty.hidden = true;
        controls.append(choices, note, empty);

        const heading = catalog.querySelector("[data-plugin-count]")?.parentElement;
        catalog.insertBefore(controls, heading || list);
        return controls;
      }

      function restoreUpstream(catalog, list) {
        for (const card of Array.from(list.children)) {
          if (card.matches && card.matches("li[data-plugin-entry]")) card.hidden = false;
        }
        const controls = Array.from(catalog.children).find((node) => node.hasAttribute && node.hasAttribute("data-dsh-desktop-inventory-controls"));
        if (controls) controls.hidden = true;
        const count = catalog.querySelector("[data-plugin-count]");
        const heading = count ? count.parentElement?.querySelector("h3") : null;
        if (heading && heading.dataset.dshDesktopOriginalHeading) setText(heading, heading.dataset.dshDesktopOriginalHeading);
        const cards = Array.from(list.children).filter((node) => node.matches && node.matches("li[data-plugin-entry]"));
        setText(count, cards.length);
      }

      function applyList(list) {
        const catalog = list.parentElement;
        if (!catalog) return;
        if (!state.enabled) {
          restoreUpstream(catalog, list);
          return;
        }

        const labels = copy();
        const rows = Array.from(list.children)
          .filter((node) => node.matches && node.matches("li[data-plugin-entry]"))
          .map(facts);
        const userCount = rows.filter((row) => row.user).length;
        const issueCount = rows.filter((row) => row.issue).length;
        const internalCount = rows.filter((row) => !row.user).length;
        let visibleCount = 0;
        for (const row of rows) {
          const visible = state.mode === "all" || (state.mode === "user" ? row.user : row.issue);
          row.card.hidden = !visible;
          if (visible) visibleCount += 1;
        }

        const controls = makeControls(catalog, list);
        controls.hidden = false;
        for (const button of controls.querySelectorAll("button[data-dsh-desktop-mode]")) {
          const mode = button.getAttribute("data-dsh-desktop-mode");
          button.setAttribute("aria-pressed", mode === state.mode ? "true" : "false");
          const label = button.querySelector("[data-dsh-desktop-label]");
          const count = button.querySelector("[data-dsh-desktop-count]");
          setText(label, labels[mode]);
          setText(count, mode === "user" ? userCount : (mode === "issues" ? issueCount : rows.length));
        }
        setText(
          controls.querySelector("[data-dsh-desktop-inventory-note]"),
          labels.note(state.packages.size, userCount, internalCount)
        );
        const empty = controls.querySelector("[data-dsh-desktop-inventory-empty]");
        if (empty) {
          empty.hidden = visibleCount !== 0;
          setText(empty, state.mode === "issues" ? labels.emptyIssues : labels.emptyUser);
        }

        const count = catalog.querySelector("[data-plugin-count]");
        const heading = count ? count.parentElement?.querySelector("h3") : null;
        if (heading && !heading.dataset.dshDesktopOriginalHeading) heading.dataset.dshDesktopOriginalHeading = heading.textContent || "";
        setText(heading, state.mode === "user" ? labels.headingUser : (state.mode === "issues" ? labels.headingIssues : labels.headingAll));
        setText(count, visibleCount);
      }

      function apply() {
        scheduled = false;
        const lists = new Set();
        for (const card of document.querySelectorAll("li[data-plugin-entry]")) {
          if (card.parentElement) lists.add(card.parentElement);
        }
        for (const list of lists) applyList(list);
      }

      function schedule() {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(apply);
      }

      const style = document.createElement("style");
      style.setAttribute("data-dsh-desktop-plugin-inventory", "true");
      style.textContent = `
        [data-dsh-desktop-inventory-controls] { display:flex; flex-direction:column; gap:8px; padding:10px; border:1px solid var(--dsw-alias-border-l2); border-radius:10px; background:var(--dsw-alias-bg-layer-1); }
        [data-dsh-desktop-inventory-controls][hidden], li[data-plugin-entry][hidden], [data-dsh-desktop-inventory-empty][hidden] { display:none !important; }
        [data-dsh-desktop-inventory-choices] { display:flex; flex-wrap:wrap; gap:7px; }
        [data-dsh-desktop-inventory-choices] button { border:1px solid var(--dsw-alias-border-l2); color:var(--dsw-alias-label-secondary); background:var(--dsw-alias-bg-layer-3); min-height:30px; border-radius:7px; padding:4px 10px; font:inherit; font-size:12px; cursor:pointer; display:inline-flex; align-items:center; gap:6px; }
        [data-dsh-desktop-inventory-choices] button:hover { background:var(--dsw-alias-interactive-bg-hover); }
        [data-dsh-desktop-inventory-choices] button[aria-pressed=true] { border-color:var(--dsw-alias-state-business-primary); color:var(--dsw-alias-state-business-primary); background:color-mix(in srgb, var(--dsw-alias-state-business-primary) 10%, transparent); }
        [data-dsh-desktop-count] { min-width:18px; padding:0 5px; border-radius:999px; text-align:center; font-variant-numeric:tabular-nums; background:var(--dsw-alias-bg-module-platform); }
        [data-dsh-desktop-inventory-note], [data-dsh-desktop-inventory-empty] { margin:0; color:var(--dsw-alias-label-tertiary); font-size:12px; line-height:18px; }
        [data-dsh-desktop-inventory-empty] { padding:10px 2px 2px; }
      `;
      document.head.appendChild(style);

      const observer = new MutationObserver(schedule);
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["data-phase", "data-enabled", "title"],
      });

      window[globalKey] = {
        configure(nextEnabled, nextPackages) {
          state.enabled = Boolean(nextEnabled);
          state.packages = new Set(Array.isArray(nextPackages) ? nextPackages : []);
          schedule();
        },
        refresh: schedule,
      };
      schedule();
    })();
    """#
}

func pluginInventoryPreferenceScript(enabled: Bool, userPackages: [String]) -> String {
    let enabledLiteral = enabled ? "true" : "false"
    let packagesLiteral = javascriptJSON(userPackages, fallback: "[]")
    return "window.__dshDesktopPluginInventory?.configure(\(enabledLiteral), \(packagesLiteral));"
}


package enum PluginWebEnhancement {
    package static func userPackages() -> [String] { webProfileUserPluginPackages() }
    package static func script(enabled: Bool, packages: [String]) -> String {
        pluginInventoryEnhancementScript(enabled: enabled, userPackages: packages)
    }
    package static func update(enabled: Bool, packages: [String]) -> String {
        pluginInventoryPreferenceScript(enabled: enabled, userPackages: packages)
    }
}
