import Foundation

// MARK: - Web 框体语言

/// 将主题清单里的 frame 参数扩展到 DSH 的通用控件。
/// 选择器只依赖语义角色和稳定 HTML 元素；上游 CSS Module 改名时仍可安全退化。
func themeWebFrameStyles() -> String {
    #"""
    body[data-dsh-desktop-theme="true"] :is(
      [role="dialog"], [role="alertdialog"], [role="menu"], [role="listbox"],
      input, textarea, pre, blockquote, fieldset
    ) {
      border-width: var(--dsh-theme-border-width) !important;
    }

    body[data-dsh-desktop-theme="true"] :is(
      [role="dialog"], [role="alertdialog"], [role="menu"], [role="listbox"],
      pre, blockquote, [class*="_groupSection"], [class*="_sectionHeader"],
      div[role="treeitem"][aria-selected], button[role="treeitem"][aria-selected]
    ) {
      box-shadow: var(--dsh-theme-frame-shadow, var(--dsw-shadow-lv1));
    }

    /* 霓虹：双层冷光、悬停时短促通电。 */
    body[data-dsh-desktop-frame-style="neon"] :is(
      [role="dialog"], [role="alertdialog"], [role="menu"], [role="listbox"],
      pre, blockquote, [class*="_groupSection"], [class*="_sectionHeader"],
      div[role="treeitem"][aria-selected], button[role="treeitem"][aria-selected],
      input, textarea
    ) {
      border-style: solid !important;
      border-color: var(--dsw-alias-border-l3) !important;
      box-shadow:
        inset 0 0 0 1px var(--dsw-alias-state-business-tertiary),
        0 0 calc(18px * var(--dsh-theme-frame-glow)) var(--dsw-alias-state-business-tertiary),
        var(--dsw-shadow-lv1) !important;
    }
    body[data-dsh-desktop-frame-style="neon"] :is(button, [role="button"]):hover {
      box-shadow: 0 0 calc(14px * var(--dsh-theme-frame-glow)) var(--dsw-alias-state-business-tertiary);
    }

    /* 缝线：柔软外沿和内层虚线，适合猫系/可爱主题。 */
    body[data-dsh-desktop-frame-style="stitched"] :is(
      [role="dialog"], [role="alertdialog"], pre, blockquote,
      [class*="_groupSection"], div[role="treeitem"][aria-selected],
      button[role="treeitem"][aria-selected]
    ) {
      border-style: dashed !important;
      outline: 1px solid var(--dsw-alias-state-business-tertiary);
      outline-offset: -4px;
    }

    /* 花影：细边、内描线和柔和四角亮点，不把写真主题做成花哨相框。 */
    body[data-dsh-desktop-frame-style="floral"] :is(
      [role="dialog"], [role="alertdialog"], [role="menu"], [role="listbox"],
      pre, blockquote, [class*="_groupSection"], [class*="_sectionHeader"],
      div[role="treeitem"][aria-selected], button[role="treeitem"][aria-selected]
    ) {
      border-style: solid !important;
      box-shadow:
        inset 0 0 0 3px var(--dsw-alias-bg-layer-1),
        inset 0 0 0 4px var(--dsw-alias-state-business-tertiary),
        var(--dsw-shadow-lv1) !important;
    }

    /* 诡箓：长短不一的断线与冷硬内框。 */
    body[data-dsh-desktop-frame-style="talisman"] :is(
      [role="dialog"], [role="alertdialog"], pre, blockquote,
      [class*="_groupSection"], [class*="_sectionHeader"],
      div[role="treeitem"][aria-selected], button[role="treeitem"][aria-selected]
    ) {
      border-style: solid dashed !important;
      box-shadow:
        inset 3px 0 0 var(--dsw-alias-state-business-tertiary),
        inset -1px 0 0 var(--dsw-alias-border-l3),
        0 7px 18px rgba(0, 0, 0, .16) !important;
    }

    /* 秘法：金属感双线框。 */
    body[data-dsh-desktop-frame-style="arcane"] :is(
      [role="dialog"], [role="alertdialog"], [role="menu"], [role="listbox"],
      pre, blockquote, [class*="_groupSection"], [class*="_sectionHeader"],
      div[role="treeitem"][aria-selected], button[role="treeitem"][aria-selected]
    ) {
      border-style: double !important;
      border-width: max(3px, calc(var(--dsh-theme-border-width) * 2)) !important;
      border-color: var(--dsw-alias-border-l3) !important;
      box-shadow:
        0 0 calc(14px * var(--dsh-theme-frame-glow)) var(--dsw-alias-state-business-tertiary),
        inset 0 0 16px rgba(0, 0, 0, .07),
        var(--dsw-shadow-lv1) !important;
    }

    /* 风化：不规则短划线与厚重阴影。 */
    body[data-dsh-desktop-frame-style="weathered"] :is(
      [role="dialog"], [role="alertdialog"], pre, blockquote,
      [class*="_groupSection"], [class*="_sectionHeader"],
      div[role="treeitem"][aria-selected], button[role="treeitem"][aria-selected]
    ) {
      border-style: dashed !important;
      border-color: var(--dsw-alias-border-l3) !important;
      box-shadow:
        inset 0 0 0 2px var(--dsw-alias-bg-layer-3),
        5px 7px 0 rgba(0, 0, 0, .13) !important;
    }

    /* 像素：硬直角、阶梯投影、禁用平滑过渡。 */
    body[data-dsh-desktop-frame-style="pixel"] :is(
      button, input, textarea, [role="button"], [role="dialog"], [role="alertdialog"],
      [role="menu"], [role="listbox"], pre, blockquote, [class*="_groupSection"],
      [class*="_sectionHeader"], div[role="treeitem"][aria-selected],
      button[role="treeitem"][aria-selected]
    ) {
      border-radius: 1px !important;
      border-style: solid !important;
      image-rendering: pixelated;
      box-shadow: 3px 3px 0 var(--dsw-alias-border-l3) !important;
    }
    body[data-dsh-desktop-frame-style="pixel"] :is(button, [role="button"]):not(:disabled):active {
      transform: translate(2px, 2px) !important;
      box-shadow: 1px 1px 0 var(--dsw-alias-border-l3) !important;
    }
    body[data-dsh-desktop-frame-style="pixel"] * {
      transition-timing-function: steps(3, end) !important;
    }
    """#
}
