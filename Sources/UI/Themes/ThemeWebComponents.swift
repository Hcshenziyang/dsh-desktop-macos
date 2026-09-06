import Foundation

// MARK: - Web 组件皮肤

/// 会话历史、工作区分组和同类语义列表的深度皮肤。
///
/// 会话与工作区首先依赖 WAI-ARIA (`treeitem` + `aria-selected/aria-expanded`)；
/// CSS Module 名称只用于标题和按钮等渐进增强。上游改名时，卡片主体仍然保持可用。
package func themeWebComponentStyles() -> String {
    #"""
    body[data-dsh-desktop-theme="true"] {
      --dsh-history-glyph-1: "◇";
      --dsh-history-glyph-2: "◦";
      --dsh-history-glyph-3: "▹";
      --dsh-history-glyph-4: "·";
      --dsh-history-section-glyph: "◈";
      --dsh-history-card-radius: var(--dsh-theme-corner-small);
      --dsh-history-card-fill: var(--dsw-alias-bg-layer-1);
      --dsh-history-card-hover: linear-gradient(100deg, var(--dsw-alias-interactive-bg-hover), var(--dsw-alias-bg-layer-1));
      --dsh-history-card-active: linear-gradient(100deg, var(--dsw-specific-sidebar-nav-item-active), var(--dsw-alias-bg-layer-1));
    }

    body[data-dsh-desktop-effect="stars"] {
      --dsh-history-glyph-1: "✦";
      --dsh-history-glyph-2: "✧";
      --dsh-history-glyph-3: "⋆";
      --dsh-history-glyph-4: "⟡";
      --dsh-history-section-glyph: "✦";
    }
    body[data-dsh-desktop-effect="paper"] {
      --dsh-history-glyph-1: "▤";
      --dsh-history-glyph-2: "▥";
      --dsh-history-glyph-3: "▦";
      --dsh-history-glyph-4: "▧";
      --dsh-history-section-glyph: "▣";
    }
    body[data-dsh-desktop-effect="bubbles"] {
      --dsh-history-glyph-1: "♡";
      --dsh-history-glyph-2: "✿";
      --dsh-history-glyph-3: "☁";
      --dsh-history-glyph-4: "⌁";
      --dsh-history-section-glyph: "❀";
    }
    body[data-dsh-desktop-effect="mist"] {
      --dsh-history-glyph-1: "⌁";
      --dsh-history-glyph-2: "◌";
      --dsh-history-glyph-3: "◇";
      --dsh-history-glyph-4: "≈";
      --dsh-history-section-glyph: "◌";
    }
    body[data-dsh-desktop-effect="neonRain"] {
      --dsh-history-glyph-1: "⌁";
      --dsh-history-glyph-2: "◫";
      --dsh-history-glyph-3: "◈";
      --dsh-history-glyph-4: "⟟";
      --dsh-history-section-glyph: "◇";
    }
    body[data-dsh-desktop-effect="nekoSparkle"] {
      --dsh-history-glyph-1: "♡";
      --dsh-history-glyph-2: "ฅ";
      --dsh-history-glyph-3: "✦";
      --dsh-history-glyph-4: "☾";
      --dsh-history-section-glyph: "♧";
    }
    body[data-dsh-desktop-effect="bloom"] {
      --dsh-history-glyph-1: "✿";
      --dsh-history-glyph-2: "❁";
      --dsh-history-glyph-3: "◇";
      --dsh-history-glyph-4: "◌";
      --dsh-history-section-glyph: "❀";
    }
    body[data-dsh-desktop-effect="eldritchInk"] {
      --dsh-history-glyph-1: "◬";
      --dsh-history-glyph-2: "⟁";
      --dsh-history-glyph-3: "⌁";
      --dsh-history-glyph-4: "◇";
      --dsh-history-section-glyph: "◉";
    }
    body[data-dsh-desktop-effect="dragonEmbers"] {
      --dsh-history-glyph-1: "✦";
      --dsh-history-glyph-2: "♢";
      --dsh-history-glyph-3: "△";
      --dsh-history-glyph-4: "⌁";
      --dsh-history-section-glyph: "✧";
    }
    body[data-dsh-desktop-effect="ashRunes"] {
      --dsh-history-glyph-1: "◌";
      --dsh-history-glyph-2: "◇";
      --dsh-history-glyph-3: "⌁";
      --dsh-history-glyph-4: "◉";
      --dsh-history-section-glyph: "◍";
    }
    body[data-dsh-desktop-effect="pixels"] {
      --dsh-history-glyph-1: "■";
      --dsh-history-glyph-2: "◆";
      --dsh-history-glyph-3: "▣";
      --dsh-history-glyph-4: "▦";
      --dsh-history-section-glyph: "▦";
    }

    /* 历史会话：独立卡片、主题图标、选中强调和轻微浮起。 */
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-selected] {
      box-sizing: border-box;
      min-height: 38px;
      height: 38px;
      margin-block: 2px;
      border: 1px solid var(--dsw-alias-border-l1);
      border-radius: var(--dsh-history-card-radius) !important;
      background: var(--dsh-history-card-fill);
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, .04), 0 2px 8px rgba(0, 0, 0, .035);
      position: relative;
      transition: transform 180ms ease, border-color 180ms ease, background 180ms ease, box-shadow 180ms ease;
    }
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-selected]:hover {
      border-color: var(--dsw-alias-border-l3);
      background: var(--dsh-history-card-hover);
      box-shadow: var(--dsw-shadow-lv1);
      transform: translate3d(2px, -1px, 0);
    }
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-selected="true"] {
      border-color: var(--dsw-alias-brand-primary);
      background: var(--dsh-history-card-active);
      box-shadow: 0 0 0 1px var(--dsw-alias-state-business-tertiary), var(--dsw-shadow-lv1);
      transform: translateX(2px);
    }

    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-selected]
      > span[class*="_title"]::before,
    body[data-dsh-desktop-theme="true"] button[role="treeitem"][aria-selected]
      span[class*="_searchResultTitle"]::before {
      content: var(--dsh-history-glyph-1);
      box-sizing: border-box;
      width: 19px;
      height: 19px;
      margin-right: 6px;
      border: 1px solid var(--dsw-alias-border-l2);
      border-radius: calc(var(--dsh-history-card-radius) * .66);
      color: var(--dsw-alias-brand-primary);
      background: var(--dsw-alias-state-business-tertiary);
      box-shadow: 0 2px 6px rgba(0, 0, 0, .07);
      align-items: center;
      justify-content: center;
      vertical-align: -3px;
      font-family: var(--dsw-font-family);
      font-size: 12px;
      font-weight: 700;
      line-height: 17px;
      display: inline-flex;
      transition: transform 180ms ease, box-shadow 180ms ease, border-color 180ms ease;
    }
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-selected]:nth-child(4n + 2)
      > span[class*="_title"]::before,
    body[data-dsh-desktop-theme="true"] button[role="treeitem"][aria-selected]:nth-child(4n + 2)
      span[class*="_searchResultTitle"]::before { content: var(--dsh-history-glyph-2); }
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-selected]:nth-child(4n + 3)
      > span[class*="_title"]::before,
    body[data-dsh-desktop-theme="true"] button[role="treeitem"][aria-selected]:nth-child(4n + 3)
      span[class*="_searchResultTitle"]::before { content: var(--dsh-history-glyph-3); }
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-selected]:nth-child(4n)
      > span[class*="_title"]::before,
    body[data-dsh-desktop-theme="true"] button[role="treeitem"][aria-selected]:nth-child(4n)
      span[class*="_searchResultTitle"]::before { content: var(--dsh-history-glyph-4); }

    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-selected]:hover
      > span[class*="_title"]::before,
    body[data-dsh-desktop-theme="true"] button[role="treeitem"][aria-selected]:hover
      span[class*="_searchResultTitle"]::before {
      border-color: var(--dsw-alias-brand-primary);
      box-shadow: 0 3px 9px rgba(0, 0, 0, .10);
      transform: translateY(-1px) scale(1.06);
    }

    /* 搜索结果也采用同一张卡片语言，但保留双行摘要布局。 */
    body[data-dsh-desktop-theme="true"] button[role="treeitem"][aria-selected] {
      margin-block: 3px;
      border: 1px solid var(--dsw-alias-border-l1) !important;
      border-radius: var(--dsh-history-card-radius) !important;
      background: var(--dsh-history-card-fill) !important;
      box-shadow: 0 2px 8px rgba(0, 0, 0, .035);
      transition: transform 180ms ease, border-color 180ms ease, background 180ms ease, box-shadow 180ms ease;
    }
    body[data-dsh-desktop-theme="true"] button[role="treeitem"][aria-selected]:hover {
      border-color: var(--dsw-alias-border-l3) !important;
      background: var(--dsh-history-card-hover) !important;
      box-shadow: var(--dsw-shadow-lv1);
      transform: translateY(-1px);
    }
    body[data-dsh-desktop-theme="true"] button[role="treeitem"][aria-selected="true"] {
      border-color: var(--dsw-alias-brand-primary) !important;
      background: var(--dsh-history-card-active) !important;
    }

    /* 工作区既有文件夹图标保留，但给它一个主题徽章框。 */
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-expanded] {
      box-sizing: border-box;
      min-height: 38px;
      height: 38px;
      border: 1px solid transparent;
      border-radius: var(--dsh-history-card-radius) !important;
      transition: background 180ms ease, border-color 180ms ease, transform 180ms ease;
    }
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-expanded]:hover,
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-expanded="true"] {
      border-color: var(--dsw-alias-border-l2);
      background: var(--dsw-alias-interactive-bg-hover);
    }
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-expanded]:hover {
      transform: translateX(1px);
    }
    body[data-dsh-desktop-theme="true"] div[role="treeitem"][aria-expanded] > span:first-child {
      width: 22px;
      height: 22px;
      border: 1px solid var(--dsw-alias-border-l2);
      border-radius: calc(var(--dsh-history-card-radius) * .66);
      color: var(--dsw-alias-brand-primary);
      background: var(--dsw-alias-state-business-tertiary);
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, .08);
    }

    /* 每个工作区包成一个小面板；标题、搜索和“新会话”使用同一套几何。 */
    body[data-dsh-desktop-theme="true"] [class*="_groupSection"] {
      margin-block: 7px !important;
      padding: 4px 4px 5px;
      border: 1px solid var(--dsw-alias-border-l1);
      border-radius: calc(var(--dsh-theme-corner) + 2px);
      background: var(--dsw-alias-bg-layer-1);
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, .04), 0 4px 12px rgba(0, 0, 0, .035);
    }
    body[data-dsh-desktop-theme="true"] [class*="_sectionHeader"] {
      border: 1px solid var(--dsw-alias-border-l1);
      border-radius: var(--dsh-theme-corner) !important;
      background: var(--dsw-alias-bg-layer-1);
      box-shadow: 0 2px 8px rgba(0, 0, 0, .035);
      padding-inline: 8px !important;
    }
    body[data-dsh-desktop-theme="true"] [class*="_sectionLabel"]::before {
      content: var(--dsh-history-section-glyph);
      color: var(--dsw-alias-brand-primary);
      margin-right: 5px;
      font-size: 12px;
    }
    body[data-dsh-desktop-theme="true"] [class*="_searchExpanded"] {
      border-color: var(--dsw-alias-border-l3) !important;
      border-radius: var(--dsh-theme-corner-small) !important;
      background: var(--dsw-alias-bg-layer-1) !important;
      box-shadow: 0 0 0 2px var(--dsw-alias-state-business-tertiary);
    }
    body[data-dsh-desktop-theme="true"] button[class*="_newSession"] {
      border-color: var(--dsw-alias-border-l3) !important;
      border-radius: var(--dsh-theme-corner) !important;
      background: linear-gradient(110deg, var(--dsw-alias-button-elevated-fill), var(--dsw-alias-state-business-tertiary)) !important;
      box-shadow: var(--dsw-shadow-lv1);
      position: relative;
      transition: transform 180ms ease, border-color 180ms ease, box-shadow 180ms ease;
    }
    body[data-dsh-desktop-theme="true"] button[class*="_newSession"]:hover {
      border-color: var(--dsw-alias-brand-primary) !important;
      box-shadow: var(--dsw-shadow-lv2);
      transform: translateY(-1px);
    }
    body[data-dsh-desktop-theme="true"] [class*="_brandMark"] {
      width: 30px;
      height: 30px;
      border: 1px solid var(--dsw-alias-border-l2);
      border-radius: var(--dsh-theme-corner-small);
      color: var(--dsw-alias-brand-primary);
      background: var(--dsw-alias-state-business-tertiary);
      box-shadow: 0 3px 10px rgba(0, 0, 0, .07);
    }

    /* 同类列表：菜单、选项和插件单元也获得较轻的卡片反馈。 */
    body[data-dsh-desktop-theme="true"] :is([role="listbox"] [role="option"], li[data-plugin-entry]) {
      border: 1px solid var(--dsw-alias-border-l1);
      border-radius: var(--dsh-history-card-radius) !important;
      transition: transform 180ms ease, border-color 180ms ease, box-shadow 180ms ease;
    }
    body[data-dsh-desktop-theme="true"] :is([role="listbox"] [role="option"], li[data-plugin-entry]):hover {
      border-color: var(--dsw-alias-border-l3);
      box-shadow: var(--dsw-shadow-lv1);
      transform: translateY(-1px);
    }

    /* 各套主题保留自己的交互性格，不把所有皮肤强行变成同一种卡片。 */
    body[data-dsh-desktop-effect="stars"] [class*="_groupSection"] {
      border-color: var(--dsw-alias-border-l3);
      box-shadow: 0 0 18px rgba(109, 92, 232, .11), inset 0 1px 0 rgba(255, 255, 255, .07);
    }
    body[data-dsh-desktop-effect="stars"] div[role="treeitem"][aria-selected="true"]
      > span[class*="_title"]::before {
      animation: dsh-history-star 2.4s ease-in-out infinite;
    }
    body[data-dsh-desktop-effect="paper"] [class*="_groupSection"] {
      border-radius: 6px;
      background-image: repeating-linear-gradient(0deg, transparent 0 27px, var(--dsw-alias-border-l1) 27px 28px);
    }
    body[data-dsh-desktop-effect="paper"] div[role="treeitem"][aria-selected] {
      border-radius: 5px !important;
      box-shadow: 3px 3px 0 var(--dsw-alias-bg-layer-3);
    }
    body[data-dsh-desktop-effect="bubbles"] [class*="_groupSection"] {
      border-radius: 20px;
      box-shadow: 0 5px 18px rgba(217, 111, 157, .10), inset 0 0 0 2px var(--dsw-alias-state-business-tertiary);
    }
    body[data-dsh-desktop-effect="bubbles"] div[role="treeitem"][aria-selected] {
      border-radius: 15px !important;
    }
    body[data-dsh-desktop-effect="bubbles"] div[role="treeitem"][aria-selected="true"]
      > span[class*="_title"]::before {
      animation: dsh-history-bubble 2.8s ease-in-out infinite;
    }
    body[data-dsh-desktop-effect="mist"] [class*="_groupSection"] {
      background: var(--dsw-alias-bg-layer-1);
      backdrop-filter: blur(var(--dsh-theme-glass));
      -webkit-backdrop-filter: blur(var(--dsh-theme-glass));
      box-shadow: 0 8px 22px rgba(27, 79, 92, .08);
    }
    body[data-dsh-desktop-effect="mist"] div[role="treeitem"][aria-selected="true"]
      > span[class*="_title"]::before {
      animation: dsh-history-mist 3.8s ease-in-out infinite;
    }
    body[data-dsh-desktop-effect="neonRain"] [class*="_groupSection"] {
      background-image: linear-gradient(115deg, transparent 12%, var(--dsw-alias-state-business-tertiary) 48%, transparent 82%);
      background-size: 240% 100%;
      animation: dsh-history-neon-panel 8s linear infinite;
    }
    body[data-dsh-desktop-effect="neonRain"] div[role="treeitem"][aria-selected="true"]
      > span[class*="_title"]::before {
      animation: dsh-history-neon-glyph 1.7s steps(4, end) infinite;
    }
    body[data-dsh-desktop-effect="nekoSparkle"] [class*="_groupSection"] {
      box-shadow: inset 0 0 0 3px var(--dsw-alias-state-business-tertiary), 0 7px 20px rgba(0, 0, 0, .06);
    }
    body[data-dsh-desktop-effect="nekoSparkle"] div[role="treeitem"][aria-selected="true"]
      > span[class*="_title"]::before {
      animation: dsh-history-neko 2.2s ease-in-out infinite;
    }
    body[data-dsh-desktop-effect="bloom"] div[role="treeitem"][aria-selected]:hover
      > span[class*="_title"]::before {
      animation: dsh-history-bloom 1.8s ease-in-out infinite;
    }
    body[data-dsh-desktop-effect="eldritchInk"] [class*="_groupSection"] {
      background-image: linear-gradient(90deg, var(--dsw-alias-state-business-tertiary), transparent 15%, transparent 85%, var(--dsw-alias-state-business-tertiary));
    }
    body[data-dsh-desktop-effect="eldritchInk"] div[role="treeitem"][aria-selected="true"]
      > span[class*="_title"]::before {
      animation: dsh-history-ink 4.6s ease-in-out infinite;
    }
    body[data-dsh-desktop-effect="dragonEmbers"] [class*="_groupSection"] {
      box-shadow: inset 0 0 22px var(--dsw-alias-state-business-tertiary), 0 9px 24px rgba(0, 0, 0, .10);
    }
    body[data-dsh-desktop-effect="dragonEmbers"] div[role="treeitem"][aria-selected="true"]
      > span[class*="_title"]::before {
      animation: dsh-history-ember 2.1s ease-in-out infinite;
    }
    body[data-dsh-desktop-effect="ashRunes"] [class*="_groupSection"] {
      filter: saturate(.82);
      box-shadow: inset 0 0 0 2px var(--dsw-alias-bg-layer-3), 6px 7px 0 rgba(0, 0, 0, .11);
    }
    body[data-dsh-desktop-effect="ashRunes"] div[role="treeitem"][aria-selected="true"]
      > span[class*="_title"]::before {
      animation: dsh-history-ash 5.4s ease-in-out infinite;
    }
    body[data-dsh-desktop-effect="pixels"] [class*="_groupSection"] {
      background-image:
        linear-gradient(90deg, var(--dsw-alias-border-l1) 1px, transparent 1px),
        linear-gradient(0deg, var(--dsw-alias-border-l1) 1px, transparent 1px);
      background-size: 8px 8px;
    }
    body[data-dsh-desktop-effect="pixels"] div[role="treeitem"][aria-selected="true"]
      > span[class*="_title"]::before {
      animation: dsh-history-pixel .9s steps(2, end) infinite alternate;
    }

    @keyframes dsh-history-star {
      0%, 100% { transform: rotate(0deg) scale(1); filter: brightness(1); }
      50% { transform: rotate(18deg) scale(1.12); filter: brightness(1.35); }
    }
    @keyframes dsh-history-bubble {
      0%, 100% { transform: translateY(0) rotate(-4deg); }
      50% { transform: translateY(-2px) rotate(5deg); }
    }
    @keyframes dsh-history-mist {
      0%, 100% { transform: translateX(0); opacity: .78; }
      50% { transform: translateX(2px); opacity: 1; }
    }
    @keyframes dsh-history-neon-panel {
      from { background-position: 120% 0; }
      to { background-position: -120% 0; }
    }
    @keyframes dsh-history-neon-glyph {
      0%, 100% { filter: brightness(.85) drop-shadow(0 0 0 transparent); }
      48% { filter: brightness(1.45) drop-shadow(0 0 5px var(--dsw-alias-brand-primary)); }
      54% { filter: brightness(.75); }
    }
    @keyframes dsh-history-neko {
      0%, 100% { transform: translateY(0) rotate(-5deg); }
      50% { transform: translateY(-2px) rotate(7deg) scale(1.08); }
    }
    @keyframes dsh-history-bloom {
      0%, 100% { transform: rotate(-4deg) scale(1); }
      50% { transform: rotate(7deg) scale(1.10); }
    }
    @keyframes dsh-history-ink {
      0%, 100% { transform: skewX(0); filter: blur(0); opacity: .78; }
      50% { transform: skewX(-6deg) translateX(1px); filter: blur(.35px); opacity: 1; }
    }
    @keyframes dsh-history-ember {
      0%, 100% { transform: translateY(0); filter: brightness(.85); }
      50% { transform: translateY(-2px) scale(1.13); filter: brightness(1.45); }
    }
    @keyframes dsh-history-ash {
      0%, 100% { transform: rotate(0); opacity: .64; }
      50% { transform: rotate(12deg); opacity: 1; }
    }
    @keyframes dsh-history-pixel {
      from { transform: translate(0, 0); }
      to { transform: translate(1px, -1px); }
    }

    @media (prefers-reduced-motion: reduce) {
      body[data-dsh-desktop-theme="true"] div[role="treeitem"],
      body[data-dsh-desktop-theme="true"] button[role="treeitem"],
      body[data-dsh-desktop-theme="true"] div[role="treeitem"] span::before {
        animation: none !important;
        transition: none !important;
        transform: none !important;
      }
    }
    """#
}
