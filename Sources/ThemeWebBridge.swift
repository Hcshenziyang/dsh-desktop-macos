import Foundation
@preconcurrency import WebKit

// MARK: - Web 主题快照

struct ThemeWebWallpaper: Codable, Equatable {
    let url: String
    let mode: WallpaperDisplayMode
    let blur: Double
    let dimming: Double
}

struct ThemeWebSnapshot: Codable, Equatable {
    let enabled: Bool
    let lightTokens: [String: String]
    let darkTokens: [String: String]
    let effects: ThemeEffects
    let wallpaper: ThemeWebWallpaper?
}

extension ThemeStore {
    /// SwiftUI 和文件存储细节在这里收敛成 WebView 唯一需要理解的不可变输入。
    var webSnapshot: ThemeWebSnapshot {
        let config = configuration
        let preset = ThemePresetCatalog.preset(id: config.presetID)
        let wallpaperURL = config.wallpaperEnabled ? wallpaperWebURL : nil
        let hasWallpaper = wallpaperURL != nil
        let customAccent = config.usesCustomAccent
            ? normalizedHexColor(config.customAccentHex)
            : nil

        return ThemeWebSnapshot(
            enabled: config.isEnabled,
            lightTokens: webThemeTokens(
                palette: preset.light,
                isNative: preset.id == ThemePresetCatalog.native.id,
                customAccent: customAccent,
                hasWallpaper: hasWallpaper,
                surfaceOpacity: config.surfaceOpacity,
                darkMode: false,
                typography: preset.typography
            ),
            darkTokens: webThemeTokens(
                palette: preset.dark,
                isNative: preset.id == ThemePresetCatalog.native.id,
                customAccent: customAccent,
                hasWallpaper: hasWallpaper,
                surfaceOpacity: config.surfaceOpacity,
                darkMode: true,
                typography: preset.typography
            ),
            effects: preset.effects,
            wallpaper: wallpaperURL.map {
                ThemeWebWallpaper(
                    url: $0.absoluteString,
                    mode: config.wallpaperDisplayMode,
                    blur: config.wallpaperBlur,
                    dimming: config.wallpaperDimming
                )
            }
        )
    }
}

private func webThemeTokens(
    palette: ThemePaletteColors,
    isNative: Bool,
    customAccent: String?,
    hasWallpaper: Bool,
    surfaceOpacity: Double,
    darkMode: Bool,
    typography: ThemeTypography
) -> [String: String] {
    var result: [String: String] = [:]
    let accent = customAccent.map {
        darkMode ? mixedHexColor($0, toward: "#FFFFFF", amount: 0.18) : $0
    } ?? palette.accent

    if !isNative || hasWallpaper {
        let base = hasWallpaper ? cssRGBA(palette.base, alpha: max(0.30, surfaceOpacity - 0.22)) : palette.base
        let layer1 = hasWallpaper ? cssRGBA(palette.layer1, alpha: surfaceOpacity) : palette.layer1
        let layer2 = hasWallpaper ? cssRGBA(palette.layer2, alpha: min(1, surfaceOpacity + 0.04)) : palette.layer2
        let layer3 = hasWallpaper ? cssRGBA(palette.layer3, alpha: min(1, surfaceOpacity + 0.08)) : palette.layer3
        let sidebar = hasWallpaper ? cssRGBA(palette.sidebar, alpha: min(1, surfaceOpacity + 0.02)) : palette.sidebar
        let overlay = hasWallpaper ? cssRGBA(palette.layer3, alpha: max(0.92, surfaceOpacity)) : palette.layer3
        let border = hasWallpaper ? cssRGBA(palette.border, alpha: max(0.55, surfaceOpacity)) : palette.border
        let primary = palette.labelPrimary ?? (darkMode ? "#F6F7FB" : "#171A20")
        let secondary = palette.labelSecondary ?? (darkMode ? "#C5CAD4" : "#555C66")
        let tertiary = palette.labelTertiary ?? (darkMode ? "#9299A7" : "#7A828E")
        let accentSoft = customAccent == nil
            ? (palette.accentSoft ?? mixedHexColor(accent, toward: palette.layer2, amount: 0.78))
            : mixedHexColor(accent, toward: palette.layer2, amount: 0.78)
        let accentHover = mixedHexColor(accent, toward: darkMode ? "#FFFFFF" : "#000000", amount: 0.13)
        let strongBorder = mixedHexColor(palette.border, toward: primary, amount: 0.22)
        let shadowColor = darkMode ? "rgba(0, 0, 0, 0.42)" : cssRGBA(primary, alpha: 0.14)

        result["--dsw-alias-bg-base"] = base
        result["--dsw-alias-bg-layer-1"] = layer1
        result["--dsw-alias-bg-layer-2"] = layer2
        result["--dsw-alias-bg-layer-3"] = layer3
        result["--dsw-alias-bg-module-platform"] = layer2
        result["--dsw-alias-bg-multi-select"] = layer2
        result["--dsw-alias-bg-overlay"] = overlay
        result["--dsw-alias-bg-skeleton"] = cssRGBA(primary, alpha: 0.07)
        result["--dsw-alias-bg-mask-1"] = "rgba(0, 0, 0, 0.24)"
        result["--dsw-alias-bg-mask-2"] = "rgba(0, 0, 0, 0.12)"
        result["--dsw-alias-bg-mask-3"] = "rgba(0, 0, 0, 0.48)"
        result["--dsw-alias-border-l1"] = border
        result["--dsw-alias-border-l2"] = border
        result["--dsw-alias-border-l2-darkmode-thin"] = border
        result["--dsw-alias-border-l3"] = strongBorder
        result["--dsw-alias-border-l4"] = strongBorder
        result["--dsw-alias-label-primary"] = primary
        result["--dsw-alias-label-primary-dimmed"] = primary
        result["--dsw-alias-label-primary-foreground"] = darkMode ? "#111318" : "#FFFFFF"
        result["--dsw-alias-label-primary-inverted"] = darkMode ? "#171A20" : "#FFFFFF"
        result["--dsw-alias-label-secondary"] = secondary
        result["--dsw-alias-label-tertiary"] = tertiary
        result["--dsw-alias-label-caption"] = tertiary
        result["--dsw-alias-label-dimmed"] = cssRGBA(tertiary, alpha: 0.62)
        result["--dsw-alias-brand-primary"] = accent
        result["--dsw-alias-brand-text"] = accent
        result["--dsw-alias-brand-primary-new-colorprimary-new-color"] = accent
        result["--dsw-alias-button-primary-fill"] = accent
        result["--dsw-alias-button-primary-hover"] = accentHover
        result["--dsw-alias-button-primary-dimmed"] = accentSoft
        result["--dsw-alias-button-info-fill"] = accent
        result["--dsw-alias-button-info-hover"] = accentHover
        result["--dsw-alias-button-elevated-fill"] = layer1
        result["--dsw-alias-button-floating-fill"] = layer1
        result["--dsw-alias-button-floating-hover"] = layer2
        result["--dsw-alias-button-ghost-active-border"] = strongBorder
        result["--dsw-alias-button-ghost-active-fill"] = accentSoft
        result["--dsw-alias-button-ghost-active-hover"] = layer3
        result["--dsw-alias-interactive-bg-hover"] = cssRGBA(accent, alpha: darkMode ? 0.14 : 0.09)
        result["--dsw-alias-interactive-bg-hover-accent"] = cssRGBA(accent, alpha: darkMode ? 0.22 : 0.14)
        result["--dsw-alias-interactive-bg-hover-solid"] = layer3
        result["--dsw-alias-interactive-bg-active"] = cssRGBA(accent, alpha: darkMode ? 0.28 : 0.18)
        result["--dsw-alias-markdown-citation"] = accentSoft
        result["--dsw-alias-markdown-code-block"] = layer2
        result["--dsw-alias-markdown-code-block-banner"] = layer3
        result["--dsw-alias-markdown-code-segment-selected"] = layer1
        result["--dsw-alias-markdown-code-segment-unselected"] = layer3
        result["--dsw-alias-markdown-inline-code"] = accentSoft
        result["--dsw-alias-markdown-placeholder"] = layer2
        result["--dsw-alias-markdown-tag"] = accentSoft
        result["--dsw-alias-scrollbar-bg-l1"] = cssRGBA(tertiary, alpha: 0.30)
        result["--dsw-alias-scrollbar-bg-l2"] = cssRGBA(tertiary, alpha: 0.30)
        result["--dsw-alias-scrollbar-hover-l1"] = cssRGBA(secondary, alpha: 0.48)
        result["--dsw-alias-scrollbar-hover-l2"] = cssRGBA(secondary, alpha: 0.48)
        result["--dsw-alias-state-business-primary"] = accent
        result["--dsw-alias-state-business-tertiary"] = accentSoft
        result["--dsw-alias-toast-bg"] = darkMode ? palette.layer3 : primary
        result["--dsw-alias-tooltip-bg"] = darkMode ? palette.layer3 : primary
        result["--dsw-specific-bubble"] = accentSoft
        result["--dsw-specific-bubble-highlight"] = mixedHexColor(accentSoft, toward: accent, amount: 0.18)
        result["--dsw-specific-sidebar-fill"] = sidebar
        result["--dsw-specific-sidebar-nav-item-active"] = accentSoft
        result["--dsw-specific-sidebar-nav-item-active-accent"] = accentSoft
        result["--dsw-specific-sidebar-nav-item-hover"] = layer3
        result["--dsw-specific-input-major"] = layer1
        result["--dsw-specific-login-input"] = layer1
        result["--dsw-specific-selector"] = layer2
        result["--dsw-specific-menu"] = overlay
        result["--dsw-specific-tip"] = layer2
        result["--dsw-hovercard-bg"] = overlay
        result["--dsw-shadow-lv1"] = "0 2px 10px \(shadowColor)"
        result["--dsw-shadow-lv2"] = "0 8px 24px \(shadowColor)"
        result["--dsw-shadow-lv3"] = "0 16px 42px \(shadowColor)"
        result["--dsw-linear-gradient-think"] = "linear-gradient(90deg, \(accent), \(accentHover))"
        result["--dsw-font-family"] = typography.cssFamily
        result["--dsw-desktop-danger"] = mixedHexColor(
            darkMode ? "#FF8797" : "#C83C54", toward: accent, amount: 0.16
        )
        result["--dsw-desktop-warning"] = mixedHexColor(
            darkMode ? "#F5BD6B" : "#A86818", toward: accent, amount: 0.12
        )
        result["--dsw-desktop-success"] = mixedHexColor(
            darkMode ? "#73D6A0" : "#278457", toward: accent, amount: 0.14
        )
    }

    if !isNative || customAccent != nil {
        result["--dsw-alias-brand-primary"] = accent
        result["--dsw-alias-brand-text"] = accent
        result["--dsw-alias-state-business-primary"] = accent
        result["--dsw-alias-button-info-fill"] = accent
        result["--dsw-alias-button-primary-fill"] = accent
        result["--dsw-alias-label-primary-bluish"] = accent
    }
    return result
}

private func cssRGBA(_ hex: String, alpha: Double) -> String {
    guard let components = themeColorComponents(hex) else { return hex }
    let red = Int(round(components.red * 255))
    let green = Int(round(components.green * 255))
    let blue = Int(round(components.blue * 255))
    return String(format: "rgba(%d, %d, %d, %.3f)", red, green, blue, min(1, max(0, alpha)))
}

private func mixedHexColor(_ source: String, toward target: String, amount: Double) -> String {
    guard let left = themeColorComponents(source), let right = themeColorComponents(target) else { return source }
    let ratio = min(1, max(0, amount))
    let red = Int(round((left.red + (right.red - left.red) * ratio) * 255))
    let green = Int(round((left.green + (right.green - left.green) * ratio) * 255))
    let blue = Int(round((left.blue + (right.blue - left.blue) * ratio) * 255))
    return String(format: "#%02X%02X%02X", red, green, blue)
}

// MARK: - Web 注入脚本

private func themeSnapshotJSON(_ snapshot: ThemeWebSnapshot) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(snapshot),
          let json = String(data: data, encoding: .utf8) else {
        return #"{"enabled":false,"lightTokens":{},"darkTokens":{},"effects":{"kind":"none","iconStyle":"hierarchical","motion":0,"cornerRadius":10,"glassBlur":0,"iconGlow":0},"wallpaper":null}"#
    }
    return json
}

func themeEnhancementScript(snapshot: ThemeWebSnapshot) -> String {
    let snapshotJSON = themeSnapshotJSON(snapshot)
    let componentStyles = themeWebComponentStyles()
    let frameStyles = themeWebFrameStyles()
    return #"""
    (() => {
      const globalKey = "__dshDesktopTheme";
      const initial = \#(snapshotJSON);
      const existing = window[globalKey];
      if (existing && typeof existing.configure === "function") {
        existing.configure(initial);
        return;
      }

      const style = document.createElement("style");
      style.setAttribute("data-dsh-desktop-theme", "true");
      (document.head || document.documentElement).appendChild(style);
      let current = initial;
      let waitingForBody = false;

      function clamp(value, lower, upper) {
        const number = Number(value);
        return Number.isFinite(number) ? Math.min(upper, Math.max(lower, number)) : lower;
      }

      function variableBlock(tokens) {
        if (!tokens || typeof tokens !== "object") return "";
        return Object.entries(tokens)
          .filter(([name, value]) => /^--dsw-[a-z0-9-]+$/i.test(name) && typeof value === "string")
          .map(([name, value]) => `${name}: ${value} !important;`)
          .join("\n");
      }

      function wallpaperRules(wallpaper) {
        if (!wallpaper || typeof wallpaper.url !== "string") return "";
        const modes = {
          fill: { size: "cover", position: "center", repeat: "no-repeat" },
          fit: { size: "contain", position: "center", repeat: "no-repeat" },
          center: { size: "auto", position: "center", repeat: "no-repeat" },
          tile: { size: "auto", position: "left top", repeat: "repeat" },
        };
        const mode = modes[wallpaper.mode] || modes.fill;
        const blur = clamp(wallpaper.blur, 0, 24);
        const dimming = clamp(wallpaper.dimming, 0, 0.8);
        const inset = Math.ceil(blur * 2 + 2);
        const imageURL = JSON.stringify(wallpaper.url);
        return `
          body[data-dsh-desktop-theme="true"][data-dsh-desktop-wallpaper="true"] {
            isolation: isolate;
            position: relative;
            z-index: 0;
            background: transparent !important;
          }
          body[data-dsh-desktop-theme="true"][data-dsh-desktop-wallpaper="true"]::before {
            content: "";
            position: fixed;
            inset: -${inset}px;
            z-index: -1;
            pointer-events: none;
            background-image: linear-gradient(rgba(0, 0, 0, ${dimming}), rgba(0, 0, 0, ${dimming})), url(${imageURL});
            background-size: ${mode.size};
            background-position: ${mode.position};
            background-repeat: ${mode.repeat};
            filter: blur(${blur}px);
            transform: translateZ(0);
            animation: dsh-theme-wallpaper-in 380ms ease-out both;
          }
        `;
      }

      function effectRules(effects) {
        const kind = effects && typeof effects.kind === "string" ? effects.kind : "none";
        const motion = clamp(effects && effects.motion, 0, 1);
        const duration = Math.round(24 - motion * 13);
        if (kind === "stars") return `
          body[data-dsh-desktop-effect="stars"]::after {
            content: ""; position: fixed; inset: 0; z-index: 2147483000; pointer-events: none;
            opacity: .34; mix-blend-mode: screen;
            background-image:
              radial-gradient(circle at 11% 16%, var(--dsw-alias-brand-primary) 0 1px, transparent 1.8px),
              radial-gradient(circle at 29% 72%, var(--dsw-alias-label-primary) 0 1px, transparent 2px),
              radial-gradient(circle at 54% 23%, var(--dsw-alias-brand-primary) 0 1.4px, transparent 2.2px),
              radial-gradient(circle at 73% 61%, var(--dsw-alias-label-primary) 0 1px, transparent 1.9px),
              radial-gradient(circle at 91% 31%, var(--dsw-alias-brand-primary) 0 1.2px, transparent 2px);
            background-size: 270px 230px, 330px 290px, 390px 310px, 460px 370px, 520px 410px;
            animation: dsh-theme-stars ${duration}s ease-in-out infinite alternate;
          }
        `;
        if (kind === "paper") return `
          body[data-dsh-desktop-effect="paper"]::after {
            content: ""; position: fixed; inset: 0; z-index: 2147483000; pointer-events: none;
            opacity: .13;
            background-image:
              repeating-linear-gradient(0deg, transparent 0 31px, var(--dsw-alias-border-l2) 31px 32px),
              linear-gradient(112deg, transparent 28%, var(--dsw-alias-brand-primary) 49%, transparent 70%);
            background-size: 100% 32px, 240% 100%;
            animation: dsh-theme-paper ${Math.max(18, duration * 2)}s linear infinite;
          }
        `;
        if (kind === "bubbles") return `
          body[data-dsh-desktop-effect="bubbles"]::after {
            content: ""; position: fixed; inset: -8%; z-index: 2147483000; pointer-events: none;
            opacity: .22;
            background-image:
              radial-gradient(circle at 8% 86%, var(--dsw-alias-brand-primary) 0 7px, transparent 8px),
              radial-gradient(circle at 22% 20%, var(--dsw-alias-label-primary) 0 3px, transparent 4px),
              radial-gradient(circle at 68% 78%, var(--dsw-alias-brand-primary) 0 5px, transparent 6px),
              radial-gradient(circle at 88% 27%, var(--dsw-alias-label-primary) 0 8px, transparent 9px);
            background-size: 260px 250px, 310px 300px, 370px 360px, 430px 410px;
            animation: dsh-theme-bubbles ${duration}s ease-in-out infinite alternate;
          }
        `;
        if (kind === "mist") return `
          body[data-dsh-desktop-effect="mist"]::after {
            content: ""; position: fixed; inset: -20%; z-index: 2147483000; pointer-events: none;
            opacity: .16; filter: blur(28px);
            background-image:
              radial-gradient(ellipse at 15% 58%, var(--dsw-alias-brand-primary) 0 8%, transparent 34%),
              radial-gradient(ellipse at 76% 32%, var(--dsw-alias-label-primary) 0 7%, transparent 31%);
            animation: dsh-theme-mist ${Math.max(20, duration * 2)}s ease-in-out infinite alternate;
          }
        `;
        if (kind === "neonRain") return `
          body[data-dsh-desktop-effect="neonRain"]::after {
            content: ""; position: fixed; inset: -12%; z-index: 2147483000; pointer-events: none;
            opacity: .22; mix-blend-mode: screen;
            background-image:
              repeating-linear-gradient(102deg, transparent 0 34px, var(--dsw-alias-brand-primary) 35px 36px, transparent 37px 74px),
              linear-gradient(90deg, var(--dsw-alias-brand-primary), transparent 24%, transparent 74%, var(--dsw-alias-label-primary));
            background-size: 190px 360px, 100% 100%;
            animation: dsh-theme-neon-rain ${Math.max(7, duration * .72)}s linear infinite;
          }
        `;
        if (kind === "nekoSparkle") return `
          body[data-dsh-desktop-effect="nekoSparkle"]::after {
            content: ""; position: fixed; inset: -8%; z-index: 2147483000; pointer-events: none;
            opacity: .20;
            background-image:
              radial-gradient(ellipse at 12% 19%, var(--dsw-alias-brand-primary) 0 3px, transparent 4px),
              radial-gradient(circle at 15% 15%, var(--dsw-alias-label-primary) 0 1.5px, transparent 2.5px),
              radial-gradient(circle at 75% 78%, var(--dsw-alias-brand-primary) 0 4px, transparent 5px),
              radial-gradient(circle at 84% 24%, var(--dsw-alias-label-primary) 0 2px, transparent 3px);
            background-size: 230px 210px, 260px 240px, 340px 300px, 390px 350px;
            animation: dsh-theme-neko ${Math.max(12, duration)}s ease-in-out infinite alternate;
          }
        `;
        if (kind === "bloom") return `
          body[data-dsh-desktop-effect="bloom"]::after {
            content: ""; position: fixed; inset: -10%; z-index: 2147483000; pointer-events: none;
            opacity: .12;
            background-image:
              radial-gradient(ellipse at 18% 22%, var(--dsw-alias-brand-primary) 0 3px, transparent 4px),
              radial-gradient(ellipse at 73% 64%, var(--dsw-alias-label-primary) 0 2px, transparent 3px),
              radial-gradient(ellipse at 91% 18%, var(--dsw-alias-brand-primary) 0 4px, transparent 5px);
            background-size: 290px 260px, 370px 330px, 470px 410px;
            animation: dsh-theme-bloom ${Math.max(18, duration * 1.7)}s ease-in-out infinite alternate;
          }
        `;
        if (kind === "eldritchInk") return `
          body[data-dsh-desktop-effect="eldritchInk"]::after {
            content: ""; position: fixed; inset: -12%; z-index: 2147483000; pointer-events: none;
            opacity: .16; filter: blur(.35px);
            background-image:
              repeating-linear-gradient(91deg, transparent 0 83px, var(--dsw-alias-brand-primary) 84px 85px, transparent 86px 171px),
              radial-gradient(ellipse at 18% 71%, var(--dsw-alias-brand-primary) 0 4%, transparent 27%),
              radial-gradient(ellipse at 84% 19%, var(--dsw-alias-label-primary) 0 3%, transparent 24%);
            background-size: 100% 100%, 130% 120%, 150% 140%;
            animation: dsh-theme-eldritch ${Math.max(21, duration * 2.2)}s ease-in-out infinite alternate;
          }
        `;
        if (kind === "dragonEmbers") return `
          body[data-dsh-desktop-effect="dragonEmbers"]::after {
            content: ""; position: fixed; inset: -10%; z-index: 2147483000; pointer-events: none;
            opacity: .23; mix-blend-mode: screen;
            background-image:
              radial-gradient(circle at 12% 84%, var(--dsw-alias-brand-primary) 0 2px, transparent 3px),
              radial-gradient(circle at 34% 71%, var(--dsw-alias-label-primary) 0 1px, transparent 2px),
              radial-gradient(circle at 68% 88%, var(--dsw-alias-brand-primary) 0 2.5px, transparent 3.5px),
              radial-gradient(circle at 89% 62%, var(--dsw-alias-label-primary) 0 1.5px, transparent 2.5px);
            background-size: 230px 270px, 310px 330px, 390px 410px, 470px 490px;
            animation: dsh-theme-embers ${Math.max(11, duration)}s linear infinite;
          }
        `;
        if (kind === "ashRunes") return `
          body[data-dsh-desktop-effect="ashRunes"]::after {
            content: ""; position: fixed; inset: -9%; z-index: 2147483000; pointer-events: none;
            opacity: .13;
            background-image:
              radial-gradient(circle at 79% 22%, transparent 0 42px, var(--dsw-alias-brand-primary) 43px 44px, transparent 45px),
              radial-gradient(circle at 14% 81%, var(--dsw-alias-label-primary) 0 1px, transparent 2px),
              radial-gradient(circle at 62% 69%, var(--dsw-alias-brand-primary) 0 1.5px, transparent 2.5px);
            background-size: 100% 100%, 230px 250px, 340px 370px;
            animation: dsh-theme-ash ${Math.max(24, duration * 2.4)}s ease-in-out infinite alternate;
          }
        `;
        if (kind === "pixels") return `
          body[data-dsh-desktop-effect="pixels"]::after {
            content: ""; position: fixed; inset: 0; z-index: 2147483000; pointer-events: none;
            opacity: .10;
            background-image:
              linear-gradient(90deg, var(--dsw-alias-border-l2) 1px, transparent 1px),
              linear-gradient(0deg, var(--dsw-alias-border-l2) 1px, transparent 1px),
              linear-gradient(90deg, transparent 0 48%, var(--dsw-alias-brand-primary) 48% 54%, transparent 54%);
            background-size: 16px 16px, 16px 16px, 240px 240px;
            animation: dsh-theme-pixels ${Math.max(10, duration)}s steps(6, end) infinite alternate;
          }
        `;
        return "";
      }

      function apply() {
        if (!document.body) {
          if (!waitingForBody) {
            waitingForBody = true;
            document.addEventListener("DOMContentLoaded", () => {
              waitingForBody = false;
              apply();
            }, { once: true });
          }
          return;
        }
        const enabled = Boolean(current && current.enabled);
        const hasWallpaper = Boolean(enabled && current.wallpaper && current.wallpaper.url);
        const effects = current && current.effects && typeof current.effects === "object" ? current.effects : {};
        const effectKind = [
          "stars", "paper", "bubbles", "mist", "neonRain", "nekoSparkle", "bloom",
          "eldritchInk", "dragonEmbers", "ashRunes", "pixels"
        ].includes(effects.kind) ? effects.kind : "none";
        const iconStyle = ["monochrome", "hierarchical", "playful", "luminous"].includes(effects.iconStyle)
          ? effects.iconStyle : "hierarchical";
        const frame = effects.frame && typeof effects.frame === "object" ? effects.frame : {};
        const frameStyle = [
          "soft", "neon", "stitched", "floral", "talisman", "arcane", "weathered", "pixel"
        ].includes(frame.style) ? frame.style : "soft";
        if (enabled) {
          document.body.setAttribute("data-dsh-desktop-theme", "true");
          document.body.setAttribute("data-dsh-desktop-effect", effectKind);
          document.body.setAttribute("data-dsh-desktop-icon-style", iconStyle);
          document.body.setAttribute("data-dsh-desktop-frame-style", frameStyle);
        } else {
          document.body.removeAttribute("data-dsh-desktop-theme");
          document.body.removeAttribute("data-dsh-desktop-effect");
          document.body.removeAttribute("data-dsh-desktop-icon-style");
          document.body.removeAttribute("data-dsh-desktop-frame-style");
        }
        if (hasWallpaper) {
          document.body.setAttribute("data-dsh-desktop-wallpaper", "true");
        } else {
          document.body.removeAttribute("data-dsh-desktop-wallpaper");
        }
        if (!enabled) {
          style.textContent = "";
          return;
        }
        const light = variableBlock(current.lightTokens);
        const dark = variableBlock(current.darkTokens);
        const corner = clamp(effects.cornerRadius, 6, 24);
        const glass = clamp(effects.glassBlur, 0, 28);
        const glow = clamp(effects.iconGlow, 0, 1);
        const borderWidth = clamp(frame.width, 0.5, 3);
        const frameGlow = clamp(frame.glow, 0, 1);
        style.textContent = `
          body[data-dsh-desktop-theme="true"] {
            ${light}
            --dsh-theme-corner: ${corner}px;
            --dsh-theme-corner-small: ${Math.max(5, corner * .62)}px;
            --dsh-theme-glass: ${glass}px;
            --dsh-theme-icon-glow: ${glow};
            --dsh-theme-border-width: ${borderWidth}px;
            --dsh-theme-frame-glow: ${frameGlow};
            --dsh-theme-frame-shadow: 0 0 calc(12px * ${frameGlow}) var(--dsw-alias-state-business-tertiary), var(--dsw-shadow-lv1);
          }
          body[data-dsh-desktop-theme="true"][data-ds-dark-theme] {
            ${dark}
          }
          body[data-dsh-desktop-theme="true"] ::selection {
            background: var(--dsw-alias-state-business-tertiary) !important;
          }
          body[data-dsh-desktop-theme="true"] :is(main, nav, aside, header, footer, section, article) {
            transition: background-color 260ms ease, border-color 260ms ease, box-shadow 260ms ease;
          }
          body[data-dsh-desktop-theme="true"] button,
          body[data-dsh-desktop-theme="true"] input,
          body[data-dsh-desktop-theme="true"] textarea,
          body[data-dsh-desktop-theme="true"] [role="button"] {
            border-radius: var(--dsh-theme-corner-small) !important;
            transition: background-color 180ms ease, border-color 180ms ease, color 180ms ease,
              box-shadow 180ms ease, transform 180ms ease;
          }
          body[data-dsh-desktop-theme="true"] :is(button, [role="button"]):not(:disabled):active {
            transform: scale(.97);
          }
          body[data-dsh-desktop-theme="true"] :is(input, textarea, [contenteditable="true"]):focus {
            outline: none !important;
            border-color: var(--dsw-alias-brand-primary) !important;
            box-shadow: 0 0 0 3px var(--dsw-alias-state-business-tertiary) !important;
          }
          body[data-dsh-desktop-theme="true"] :is([role="dialog"], [role="alertdialog"]) {
            border: 1px solid var(--dsw-alias-border-l3) !important;
            border-radius: calc(var(--dsh-theme-corner) + 4px) !important;
            background: var(--dsw-alias-bg-overlay) !important;
            box-shadow: var(--dsw-shadow-lv3) !important;
            backdrop-filter: blur(var(--dsh-theme-glass)) saturate(1.18);
            -webkit-backdrop-filter: blur(var(--dsh-theme-glass)) saturate(1.18);
            animation: dsh-theme-dialog-in 260ms cubic-bezier(.2,.9,.25,1.08) both;
          }
          body[data-dsh-desktop-theme="true"] :is([role="menu"], [role="listbox"], [data-radix-popper-content-wrapper] > *) {
            border-radius: var(--dsh-theme-corner) !important;
            border-color: var(--dsw-alias-border-l2) !important;
            background: var(--dsw-specific-menu) !important;
            box-shadow: var(--dsw-shadow-lv2) !important;
            backdrop-filter: blur(var(--dsh-theme-glass));
            -webkit-backdrop-filter: blur(var(--dsh-theme-glass));
          }
          body[data-dsh-desktop-theme="true"] :is([role="alert"], [role="status"]) {
            border-radius: var(--dsh-theme-corner-small);
            animation: dsh-theme-notice-in 240ms ease-out both;
          }
          body[data-dsh-desktop-theme="true"] :is([data-type="error"], [data-status="error"], [data-variant="destructive"]) {
            border-color: var(--dsw-desktop-danger) !important;
            color: var(--dsw-desktop-danger) !important;
          }
          body[data-dsh-desktop-theme="true"] :is(button, [role="button"]) svg {
            transition: color 180ms ease, filter 180ms ease, transform 180ms ease;
          }
          body[data-dsh-desktop-theme="true"][data-dsh-desktop-icon-style="luminous"] :is(button, [role="button"]) svg {
            color: var(--dsw-alias-brand-primary);
            filter: drop-shadow(0 0 calc(8px * var(--dsh-theme-icon-glow)) var(--dsw-alias-brand-primary));
          }
          body[data-dsh-desktop-theme="true"][data-dsh-desktop-icon-style="playful"] :is(button, [role="button"]):hover svg {
            color: var(--dsw-alias-brand-primary);
            transform: translateY(-1px) rotate(-6deg) scale(1.08);
          }
          body[data-dsh-desktop-theme="true"][data-dsh-desktop-icon-style="monochrome"] :is(button, [role="button"]) svg {
            filter: grayscale(.35);
          }
          @keyframes dsh-theme-dialog-in {
            from { opacity: 0; transform: translateY(10px) scale(.975); }
            to { opacity: 1; transform: translateY(0) scale(1); }
          }
          @keyframes dsh-theme-wallpaper-in {
            from { opacity: 0; transform: scale(1.012) translateZ(0); }
            to { opacity: 1; transform: scale(1) translateZ(0); }
          }
          @keyframes dsh-theme-notice-in {
            from { opacity: 0; transform: translateX(8px); }
            to { opacity: 1; transform: translateX(0); }
          }
          @keyframes dsh-theme-stars {
            from { transform: translate3d(-7px, -3px, 0); opacity: .20; }
            to { transform: translate3d(9px, 7px, 0); opacity: .42; }
          }
          @keyframes dsh-theme-paper {
            from { background-position: 0 0, 120% 0; }
            to { background-position: 0 0, -120% 0; }
          }
          @keyframes dsh-theme-bubbles {
            from { transform: translate3d(-8px, 10px, 0) rotate(-1deg); }
            to { transform: translate3d(12px, -14px, 0) rotate(2deg); }
          }
          @keyframes dsh-theme-mist {
            from { transform: translate3d(-4%, 1%, 0) scale(1); }
            to { transform: translate3d(5%, -2%, 0) scale(1.06); }
          }
          @keyframes dsh-theme-neon-rain {
            from { transform: translate3d(-2%, -18%, 0); background-position: 0 0, 0 0; }
            to { transform: translate3d(2%, 18%, 0); background-position: 70px 360px, 0 0; }
          }
          @keyframes dsh-theme-neko {
            from { transform: translate3d(-7px, 7px, 0) rotate(-.5deg); }
            to { transform: translate3d(11px, -12px, 0) rotate(1deg); }
          }
          @keyframes dsh-theme-bloom {
            from { transform: translate3d(-2%, -1%, 0) rotate(-1deg); opacity: .08; }
            to { transform: translate3d(3%, 4%, 0) rotate(2deg); opacity: .16; }
          }
          @keyframes dsh-theme-eldritch {
            from { transform: translate3d(-2%, 1%, 0) skewX(-.25deg); filter: blur(.2px); }
            to { transform: translate3d(3%, -2%, 0) skewX(.35deg); filter: blur(1.2px); }
          }
          @keyframes dsh-theme-embers {
            from { transform: translate3d(-1%, 12%, 0) scale(.98); opacity: .12; }
            to { transform: translate3d(2%, -13%, 0) scale(1.02); opacity: .28; }
          }
          @keyframes dsh-theme-ash {
            from { transform: translate3d(-1%, -1%, 0) rotate(-.3deg); opacity: .09; }
            to { transform: translate3d(2%, 2%, 0) rotate(.4deg); opacity: .16; }
          }
          @keyframes dsh-theme-pixels {
            from { background-position: 0 0, 0 0, -40px 30px; }
            to { background-position: 16px 0, 0 16px, 70px -50px; }
          }
          @media (prefers-reduced-motion: reduce) {
            body[data-dsh-desktop-theme="true"] *,
            body[data-dsh-desktop-theme="true"]::after {
              animation-duration: .001ms !important;
              animation-iteration-count: 1 !important;
              transition-duration: .001ms !important;
            }
          }
          \#(componentStyles)
          \#(frameStyles)
          ${effectRules(effects)}
          ${wallpaperRules(current.wallpaper)}
        `;
      }

      window[globalKey] = {
        configure(next) {
          current = next && typeof next === "object" ? next : { enabled: false };
          apply();
        },
      };
      apply();
    })();
    """#
}

func themePreferenceScript(snapshot: ThemeWebSnapshot) -> String {
    "window.__dshDesktopTheme?.configure(\(themeSnapshotJSON(snapshot)));"
}

// MARK: - 私有壁纸 URL Scheme

/// 只允许 WKWebView 读取应用自己复制到 Application Support/Themes 的图片。
/// 页面永远看不到用户原始图片路径，DSH HTTP 服务也不会获得文件访问能力。
private final class ThemeSchemeTaskBox: @unchecked Sendable {
    let task: WKURLSchemeTask

    init(_ task: WKURLSchemeTask) {
        self.task = task
    }
}

final class ThemeAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private let readQueue = DispatchQueue(
        label: "io.github.dramtea.dsh-desktop-community.theme-assets",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let lock = NSLock()
    private var activeTasks: Set<ObjectIdentifier> = []

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskBox = ThemeSchemeTaskBox(urlSchemeTask)
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        activeTasks.insert(identifier)
        lock.unlock()

        let requestURL = taskBox.task.request.url
        readQueue.async { [weak self, taskBox] in
            let result: Result<(Data, URLResponse), Error>
            do {
                guard let requestURL,
                      requestURL.scheme == ThemeAssetRepository.scheme else {
                    throw NSError(domain: "ThemeAssetScheme", code: 400, userInfo: [
                        NSLocalizedDescriptionKey: "无效的主题资源地址",
                    ])
                }
                guard let fileURL = ThemeAssetRepository.fileURL(for: requestURL) else {
                    throw NSError(domain: "ThemeAssetScheme", code: 404, userInfo: [
                        NSLocalizedDescriptionKey: "主题壁纸不存在",
                    ])
                }
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let response = URLResponse(
                    url: requestURL,
                    mimeType: Self.mimeType(for: fileURL.pathExtension),
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
                result = .success((data, response))
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard let self, self.consumeIfActive(identifier) else { return }
                switch result {
                case .success(let payload):
                    taskBox.task.didReceive(payload.1)
                    taskBox.task.didReceive(payload.0)
                    taskBox.task.didFinish()
                case .failure(let error):
                    taskBox.task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        activeTasks.remove(identifier)
        lock.unlock()
    }

    private func consumeIfActive(_ identifier: ObjectIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeTasks.remove(identifier) != nil
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "tif", "tiff": return "image/tiff"
        default: return "application/octet-stream"
        }
    }
}
