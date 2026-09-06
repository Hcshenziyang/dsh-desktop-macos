import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ThemeStore {
    package var appAccentColor: Color {
        guard configuration.isEnabled else { return Color(nsColor: .controlAccentColor) }
        if configuration.usesCustomAccent,
           let custom = normalizedHexColor(configuration.customAccentHex) {
            return Color(nsColor: themeNSColor(custom))
        }
        let preset = ThemePresetCatalog.preset(id: configuration.presetID)
        if preset.id == ThemePresetCatalog.native.id {
            return Color(nsColor: .controlAccentColor)
        }
        return Color(nsColor: themeNSColor(preset.light.accent))
    }

    package var hasActiveSkin: Bool {
        configuration.isEnabled && selectedPreset.id != ThemePresetCatalog.native.id
    }

    package func nativePalette(for colorScheme: ColorScheme) -> ThemePaletteColors {
        colorScheme == .dark ? selectedPreset.dark : selectedPreset.light
    }

    package var activeEffects: ThemeEffects {
        hasActiveSkin ? selectedPreset.effects : .standard
    }

    package func resolvedAccentColor(for colorScheme: ColorScheme) -> Color {
        guard configuration.isEnabled else { return Color(nsColor: .controlAccentColor) }
        if configuration.usesCustomAccent,
           let custom = normalizedHexColor(configuration.customAccentHex) {
            return Color(nsColor: themeNSColor(custom))
        }
        if selectedPreset.id == ThemePresetCatalog.native.id {
            return Color(nsColor: .controlAccentColor)
        }
        return Color(nsColor: themeNSColor(nativePalette(for: colorScheme).accent))
    }
}

extension ThemeEffectKind {
    package var title: String {
        switch self {
        case .none: return "静态"
        case .stars: return "星轨微光"
        case .paper: return "纸面流光"
        case .bubbles: return "软糖浮泡"
        case .mist: return "海雾呼吸"
        case .neonRain: return "霓雨脉冲"
        case .nekoSparkle: return "猫爪星糖"
        case .bloom: return "花影呼吸"
        case .eldritchInk: return "诡墨游移"
        case .dragonEmbers: return "龙焰星屑"
        case .ashRunes: return "灰烬残环"
        case .pixels: return "像素跃迁"
        }
    }

    package var symbolName: String {
        switch self {
        case .none: return "circle.dotted"
        case .stars: return "sparkles"
        case .paper: return "doc.text"
        case .bubbles: return "circle.hexagongrid"
        case .mist: return "wind"
        case .neonRain: return "cloud.rain.fill"
        case .nekoSparkle: return "pawprint.fill"
        case .bloom: return "camera.aperture"
        case .eldritchInk: return "seal.fill"
        case .dragonEmbers: return "flame.fill"
        case .ashRunes: return "circle.hexagongrid.fill"
        case .pixels: return "square.grid.3x3.fill"
        }
    }
}

/// 原生窗口使用的轻量环境层。所有图形由 SwiftUI 绘制，不依赖额外图片；
/// 开启系统“减少动态效果”后会停在静态帧。
package struct ThemeAmbientOverlay: View {
    private var compact: Bool

    package init(compact: Bool = false) { self.compact = compact }

    @EnvironmentObject private var store: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package var body: some View {
        Group {
            if store.hasActiveSkin, store.activeEffects.kind != .none {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
                    Canvas(rendersAsynchronously: true) { context, size in
                        render(
                            context: &context,
                            size: size,
                            time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        let effects = store.activeEffects
        let palette = store.nativePalette(for: colorScheme)
        let accent = Color(nsColor: themeNSColor(palette.accent))
        let secondary = Color(nsColor: themeNSColor(palette.labelSecondary ?? palette.border))
        let speed = max(0.08, effects.motion)

        switch effects.kind {
        case .none:
            break
        case .stars:
            let count = compact ? 12 : 30
            for index in 0..<count {
                let x = CGFloat(unit(Double(index) * 3.17 + 0.2)) * size.width
                let y = CGFloat(unit(Double(index) * 7.91 + 1.4)) * size.height
                let pulse = 0.35 + 0.65 * ((sin(time * speed * 1.8 + Double(index)) + 1) / 2)
                let radius = CGFloat(0.7 + unit(Double(index) * 2.3) * (compact ? 1.2 : 2.0))
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(0.10 + pulse * 0.30)))
            }
        case .paper:
            let spacing: CGFloat = compact ? 22 : 32
            var path = Path()
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(secondary.opacity(0.10)), lineWidth: 0.6)
            let progress = CGFloat((time * speed * 0.025).truncatingRemainder(dividingBy: 1.4)) - 0.2
            let sweepX = progress * size.width
            var sweep = Path()
            sweep.move(to: CGPoint(x: sweepX - 70, y: size.height))
            sweep.addLine(to: CGPoint(x: sweepX + 70, y: 0))
            context.stroke(sweep, with: .color(accent.opacity(0.09)), lineWidth: compact ? 14 : 30)
        case .bubbles:
            let count = compact ? 7 : 16
            for index in 0..<count {
                let baseX = unit(Double(index) * 5.23 + 0.7)
                let baseY = unit(Double(index) * 9.11 + 2.2)
                let drift = sin(time * speed * 0.55 + Double(index) * 1.7)
                let x = CGFloat(baseX) * size.width + CGFloat(drift * 9)
                let y = CGFloat(baseY) * size.height - CGFloat(drift * 7)
                let radius = CGFloat(3 + unit(Double(index) * 4.7) * (compact ? 7 : 16))
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(0.035 + effects.iconGlow * 0.06)))
                context.stroke(Path(ellipseIn: rect), with: .color(secondary.opacity(0.10)), lineWidth: 0.7)
            }
        case .mist:
            context.addFilter(.blur(radius: compact ? 10 : 28))
            for index in 0..<3 {
                let phase = time * speed * 0.10 + Double(index) * 2.1
                let x = size.width * CGFloat(0.18 + Double(index) * 0.31) + CGFloat(sin(phase) * 34)
                let y = size.height * CGFloat(0.30 + Double(index % 2) * 0.35) + CGFloat(cos(phase) * 16)
                let width = size.width * (compact ? 0.30 : 0.42)
                let height = max(30, size.height * (compact ? 0.50 : 0.34))
                let rect = CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
                context.fill(Path(ellipseIn: rect), with: .color((index == 1 ? secondary : accent).opacity(0.065)))
            }
        case .neonRain:
            let count = compact ? 16 : 38
            for index in 0..<count {
                let phase = (time * speed * 0.18 + Double(index) * 0.071).truncatingRemainder(dividingBy: 1)
                let x = CGFloat(unit(Double(index) * 4.13)) * size.width
                let y = CGFloat(phase) * (size.height + 90) - 45
                var streak = Path()
                streak.move(to: CGPoint(x: x, y: y - (compact ? 8 : 18)))
                streak.addLine(to: CGPoint(x: x - (compact ? 2 : 5), y: y + (compact ? 8 : 18)))
                context.stroke(
                    streak,
                    with: .color((index.isMultiple(of: 3) ? secondary : accent).opacity(0.10 + effects.iconGlow * 0.14)),
                    lineWidth: index.isMultiple(of: 5) ? 1.2 : 0.65
                )
            }
        case .nekoSparkle:
            let count = compact ? 4 : 10
            for index in 0..<count {
                let drift = sin(time * speed * 0.72 + Double(index) * 1.4)
                let x = CGFloat(unit(Double(index) * 5.77 + 0.8)) * size.width + CGFloat(drift * 8)
                let y = CGFloat(unit(Double(index) * 8.31 + 1.5)) * size.height - CGFloat(drift * 6)
                let radius: CGFloat = compact ? 3 : 5
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(accent.opacity(0.10 + effects.iconGlow * 0.10))
                )
                for toe in 0..<3 {
                    let toeX = x + CGFloat(toe - 1) * radius * 1.05
                    let toeY = y - radius * 1.45 - CGFloat(toe % 2)
                    let toeRadius = radius * 0.38
                    context.fill(
                        Path(ellipseIn: CGRect(x: toeX - toeRadius, y: toeY - toeRadius, width: toeRadius * 2, height: toeRadius * 2)),
                        with: .color(secondary.opacity(0.13))
                    )
                }
            }
        case .bloom:
            let count = compact ? 7 : 18
            for index in 0..<count {
                let phase = time * speed * 0.11 + Double(index) * 0.73
                let x = CGFloat(unit(Double(index) * 6.17) + sin(phase) * 0.025) * size.width
                let y = CGFloat((unit(Double(index) * 9.43) + phase * 0.025).truncatingRemainder(dividingBy: 1)) * size.height
                let width = CGFloat(compact ? 3.5 : 6.5)
                let height = width * 1.8
                context.fill(
                    Path(ellipseIn: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)),
                    with: .color((index.isMultiple(of: 3) ? secondary : accent).opacity(0.09))
                )
            }
        case .eldritchInk:
            context.addFilter(.blur(radius: compact ? 1.5 : 3.5))
            let count = compact ? 5 : 12
            for index in 0..<count {
                let sway = sin(time * speed * 0.20 + Double(index) * 1.3)
                let x = CGFloat(unit(Double(index) * 7.27)) * size.width + CGFloat(sway * 7)
                let top = CGFloat(unit(Double(index) * 3.71)) * size.height
                let height = CGFloat(compact ? 18 : 48) * CGFloat(0.7 + unit(Double(index) * 2.9))
                let rect = CGRect(x: x - 1, y: top - height / 2, width: index.isMultiple(of: 4) ? 3 : 1.3, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color((index.isMultiple(of: 4) ? accent : secondary).opacity(0.10)))
            }
        case .dragonEmbers:
            let count = compact ? 9 : 24
            for index in 0..<count {
                let phase = time * speed * 0.24 + Double(index) * 0.8
                let x = CGFloat(unit(Double(index) * 5.11) + sin(phase) * 0.018) * size.width
                let y = size.height - CGFloat((unit(Double(index) * 8.87) + phase * 0.035).truncatingRemainder(dividingBy: 1)) * size.height
                let radius = CGFloat(0.8 + unit(Double(index) * 3.4) * (compact ? 1.5 : 2.7))
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color((index.isMultiple(of: 4) ? secondary : accent).opacity(0.13 + effects.iconGlow * 0.12))
                )
            }
        case .ashRunes:
            let count = compact ? 7 : 17
            for index in 0..<count {
                let phase = time * speed * 0.08 + Double(index)
                let x = CGFloat(unit(Double(index) * 4.79) + sin(phase) * 0.012) * size.width
                let y = CGFloat((unit(Double(index) * 9.07) + phase * 0.018).truncatingRemainder(dividingBy: 1)) * size.height
                let radius = CGFloat(1 + unit(Double(index) * 3.2) * (compact ? 1.2 : 2.3))
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color((index.isMultiple(of: 5) ? accent : secondary).opacity(0.10))
                )
            }
            let ring = CGRect(
                x: size.width * 0.72,
                y: size.height * 0.12,
                width: min(size.width, size.height) * (compact ? 0.18 : 0.23),
                height: min(size.width, size.height) * (compact ? 0.18 : 0.23)
            )
            context.stroke(Path(ellipseIn: ring), with: .color(accent.opacity(0.08)), lineWidth: compact ? 0.8 : 1.2)
        case .pixels:
            let count = compact ? 10 : 28
            for index in 0..<count {
                let phase = time * speed * 0.10 + Double(index) * 0.3
                let cell = CGFloat(index.isMultiple(of: 4) ? (compact ? 4 : 7) : (compact ? 2 : 4))
                let x = floor((CGFloat(unit(Double(index) * 5.31)) * size.width + CGFloat(sin(phase) * 5)) / cell) * cell
                let y = floor((CGFloat(unit(Double(index) * 7.63)) * size.height + CGFloat(cos(phase) * 5)) / cell) * cell
                context.fill(
                    Path(CGRect(x: x, y: y, width: cell, height: cell)),
                    with: .color((index.isMultiple(of: 3) ? accent : secondary).opacity(0.08 + effects.iconGlow * 0.05))
                )
            }
        }
    }

    private func unit(_ seed: Double) -> Double {
        let value = sin(seed * 12.9898) * 43_758.5453
        return value - floor(value)
    }
}

/// 主题框体语言：虚线缝线、双层秘法框、霓虹辉光、像素硬边等都从清单读取。
/// 传入 frame 而不是直接读取全局 store，主题选择卡也能预览尚未选中的框体。
package struct ThemeFrameOverlay: View {
    package init(frame: ThemeFrameEffects, color: Color, cornerRadius: CGFloat, opacity: Double = 0.46) {
        self.frame = frame; self.color = color; self.cornerRadius = cornerRadius; self.opacity = opacity
    }
    package let frame: ThemeFrameEffects
    package let color: Color
    package let cornerRadius: CGFloat
    package var opacity: Double = 0.46

    package var body: some View {
        let radius = resolvedCornerRadius
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    color.opacity(opacity),
                    style: StrokeStyle(
                        lineWidth: frame.width,
                        lineCap: frame.style == .pixel ? .square : .round,
                        lineJoin: frame.style == .pixel ? .miter : .round,
                        dash: dashPattern
                    )
                )
            decoration(radius: radius)
        }
        .shadow(color: color.opacity(frame.glow * 0.48), radius: 4 + frame.glow * 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var resolvedCornerRadius: CGFloat {
        switch frame.style {
        case .pixel: return 1
        case .weathered: return max(3, cornerRadius * 0.55)
        case .talisman: return max(4, cornerRadius * 0.68)
        case .soft, .neon, .stitched, .floral, .arcane: return cornerRadius
        }
    }

    private var dashPattern: [CGFloat] {
        switch frame.style {
        case .stitched: return [5, 3]
        case .talisman: return [13, 4, 2, 4]
        case .weathered: return [2, 3, 7, 3]
        case .soft, .neon, .floral, .arcane, .pixel: return []
        }
    }

    @ViewBuilder
    private func decoration(radius: CGFloat) -> some View {
        switch frame.style {
        case .soft:
            EmptyView()
        case .neon:
            RoundedRectangle(cornerRadius: max(1, radius - 3), style: .continuous)
                .stroke(color.opacity(0.34), lineWidth: max(0.5, frame.width * 0.55))
                .padding(3)
                .shadow(color: color.opacity(0.52 + frame.glow * 0.26), radius: 5)
        case .stitched:
            RoundedRectangle(cornerRadius: max(2, radius - 4), style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 0.65)
                .padding(4)
        case .floral:
            VStack {
                HStack {
                    Image(systemName: "sparkle")
                    Spacer()
                    Circle().frame(width: 3, height: 3)
                }
                Spacer()
                HStack {
                    Circle().frame(width: 3, height: 3)
                    Spacer()
                    Image(systemName: "sparkle")
                }
            }
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(color.opacity(0.62))
            .padding(5)
        case .talisman:
            VStack(spacing: 0) {
                Rectangle().frame(height: max(1, frame.width * 0.65))
                Spacer()
                Rectangle().frame(height: max(1, frame.width * 0.65))
            }
            .foregroundColor(color.opacity(0.26))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
        case .arcane:
            RoundedRectangle(cornerRadius: max(1, radius - 5), style: .continuous)
                .stroke(color.opacity(0.30), lineWidth: max(0.6, frame.width * 0.52))
                .padding(5)
        case .weathered:
            RoundedRectangle(cornerRadius: max(2, radius - 3), style: .continuous)
                .stroke(
                    color.opacity(0.18),
                    style: StrokeStyle(lineWidth: 0.8, dash: [9, 5, 2, 5])
                )
                .padding(3)
        case .pixel:
            RoundedRectangle(cornerRadius: 0)
                .stroke(color.opacity(0.26), lineWidth: max(1, frame.width * 0.62))
                .padding(3)
                .offset(x: 2, y: 2)
        }
    }
}

/// 工具栏的主题化图标：几何、光晕和悬停动作均来自主题清单。
package struct ThemedToolbarIcon: View {
    package init(systemName: String, label: String, isActive: Bool = false) {
        self.systemName = systemName; self.label = label; self.isActive = isActive
    }
    package let systemName: String
    package let label: String
    package var isActive = false

    @EnvironmentObject private var store: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    package var body: some View {
        let effects = store.activeEffects
        let accent = store.resolvedAccentColor(for: colorScheme)
        let radius = min(12, effects.cornerRadius * 0.58)

        Image(systemName: systemName)
            .symbolRenderingMode(symbolMode)
            .font(.system(size: 14, weight: isActive ? .semibold : .medium))
            .foregroundColor(store.hasActiveSkin ? accent : .primary)
            .frame(width: 29, height: 27)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(accent.opacity(store.hasActiveSkin ? (isActive ? 0.24 : hovered ? 0.17 : 0.09) : 0))
                    iconDecoration(accent: accent)
                }
            }
            .overlay {
                if store.hasActiveSkin {
                    ThemeFrameOverlay(
                        frame: effects.resolvedFrame,
                        color: accent,
                        cornerRadius: radius,
                        opacity: hovered ? 0.52 : 0.24
                    )
                }
            }
            .shadow(
                color: accent.opacity(store.hasActiveSkin ? effects.iconGlow * (hovered ? 0.55 : 0.26) : 0),
                radius: hovered ? 8 : 4
            )
            .scaleEffect(hovered && !reduceMotion ? 1.07 : 1)
            .rotationEffect(.degrees(playfulRotation))
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.68), value: hovered)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovered = $0 }
            .accessibilityLabel(label)
    }

    private var symbolMode: SymbolRenderingMode {
        switch store.activeEffects.iconStyle {
        case .monochrome: return .monochrome
        case .hierarchical, .luminous, .playful: return .hierarchical
        }
    }

    private var playfulRotation: Double {
        guard !reduceMotion,
              store.activeEffects.iconStyle == .playful,
              hovered else { return 0 }
        return -7
    }

    @ViewBuilder
    private func iconDecoration(accent: Color) -> some View {
        if store.hasActiveSkin {
            switch store.activeEffects.iconStyle {
            case .monochrome:
                HStack {
                    Capsule().fill(accent.opacity(0.45)).frame(width: 2, height: 13)
                    Spacer()
                }
                .padding(.leading, 3)
            case .hierarchical:
                Capsule()
                    .fill(accent.opacity(0.16))
                    .frame(width: 18, height: 5)
                    .blur(radius: 2)
                    .offset(y: 7)
            case .playful:
                ZStack {
                    Circle().fill(accent.opacity(0.22)).frame(width: 5, height: 5).offset(x: -10, y: -8)
                    Circle().fill(accent.opacity(0.15)).frame(width: 7, height: 7).offset(x: 10, y: 8)
                }
            case .luminous:
                if reduceMotion {
                    Circle().fill(accent.opacity(0.65)).frame(width: 3, height: 3).offset(x: 10, y: -7)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate * 1.1
                        Circle()
                            .fill(accent.opacity(0.78))
                            .frame(width: 3, height: 3)
                            .shadow(color: accent.opacity(0.8), radius: 3)
                            .offset(x: CGFloat(cos(phase) * 10), y: CGFloat(sin(phase) * 8))
                    }
                }
            }
        }
    }
}

/// 服务状态点在启动/停止阶段会呼吸；不同主题的核心形状也略有差异。
package struct ThemedStatusIndicator: View {
    package init(color: Color, isAnimating: Bool = false) { self.color = color; self.isAnimating = isAnimating }
    package let color: Color
    package var isAnimating = false

    @EnvironmentObject private var store: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    package var body: some View {
        ZStack {
            if isAnimating && !reduceMotion {
                Circle()
                    .stroke(color.opacity(0.48), lineWidth: 1.2)
                    .scaleEffect(pulse ? 1.9 : 0.8)
                    .opacity(pulse ? 0 : 0.8)
            }
            core
        }
        .frame(width: 12, height: 12)
        .shadow(color: color.opacity(store.activeEffects.iconGlow * 0.70), radius: 5)
        .onAppear { updatePulse() }
        .onChange(of: isAnimating) { _ in updatePulse() }
        .animation(
            isAnimating && !reduceMotion
                ? .easeOut(duration: 1.25).repeatForever(autoreverses: false)
                : nil,
            value: pulse
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var core: some View {
        switch store.activeEffects.iconStyle {
        case .monochrome:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: 5, height: 11)
        case .playful:
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .rotationEffect(.degrees(-8))
        case .hierarchical, .luminous:
            Circle().fill(color).frame(width: 9, height: 9)
        }
    }

    private func updatePulse() {
        pulse = false
        guard isAnimating, !reduceMotion else { return }
        DispatchQueue.main.async { pulse = true }
    }
}

package enum ThemeStatusTone {
    case info
    case success
    case warning
    case danger

    package var symbolName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }
}

/// 错误、成功和警告共用同一种主题表面，避免各页面继续散落红绿文字。
package struct ThemedStatusBanner: View {
    package init(message: String, tone: ThemeStatusTone) { self.message = message; self.tone = tone }
    package let message: String
    package let tone: ThemeStatusTone

    @EnvironmentObject private var store: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    package var body: some View {
        let palette = store.nativePalette(for: colorScheme)
        let toneColor = resolvedToneColor
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(toneColor)
                .shadow(color: toneColor.opacity(store.activeEffects.iconGlow * 0.45), radius: 5)
            Text(message)
                .font(.callout)
                .foregroundColor(Color(nsColor: themeNSColor(palette.labelPrimary ?? palette.accent)))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: store.activeEffects.cornerRadius, style: .continuous)
                .fill(Color(nsColor: themeNSColor(palette.layer2)).opacity(store.hasActiveSkin ? 0.92 : 0.55))
        }
        .overlay {
            ThemeFrameOverlay(
                frame: store.activeEffects.resolvedFrame,
                color: toneColor,
                cornerRadius: store.activeEffects.cornerRadius,
                opacity: 0.46
            )
        }
    }

    private var resolvedToneColor: Color {
        switch tone {
        case .info: return store.resolvedAccentColor(for: colorScheme)
        case .success: return Color(nsColor: themeNSColor(colorScheme == .dark ? "#73D6A0" : "#278457"))
        case .warning: return Color(nsColor: themeNSColor(colorScheme == .dark ? "#F5BD6B" : "#A86818"))
        case .danger: return Color(nsColor: themeNSColor(colorScheme == .dark ? "#FF8797" : "#C83C54"))
        }
    }
}

package enum ThemeDialogTone {
    case info
    case warning
    case danger
    case success
}

package struct ThemeDialogDescriptor: Identifiable {
    package init(title: String, message: String, systemImage: String, tone: ThemeDialogTone,
                 primaryTitle: String, primaryRole: ButtonRole? = nil, cancelTitle: String = "取消",
                 primaryAction: @escaping () -> Void) {
        self.title = title; self.message = message; self.systemImage = systemImage; self.tone = tone
        self.primaryTitle = primaryTitle; self.primaryRole = primaryRole
        self.cancelTitle = cancelTitle; self.primaryAction = primaryAction
    }
    package let id = UUID()
    package let title: String
    package let message: String
    package let systemImage: String
    package let tone: ThemeDialogTone
    package let primaryTitle: String
    package var primaryRole: ButtonRole? = nil
    package var cancelTitle = "取消"
    package let primaryAction: () -> Void
}

private struct ThemedDialogPresenter: ViewModifier {
    @Binding package var item: ThemeDialogDescriptor?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(item != nil)

            if let dialog = item {
                Color.black.opacity(0.30)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .transition(.opacity)

                ThemedDialogCard(
                    dialog: dialog,
                    cancel: dismiss,
                    confirm: {
                        let action = dialog.primaryAction
                        dismiss()
                        action()
                    }
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82),
            value: item?.id
        )
    }

    private func dismiss() {
        item = nil
    }
}

private struct ThemedDialogCard: View {
    package let dialog: ThemeDialogDescriptor
    package let cancel: () -> Void
    package let confirm: () -> Void

    @EnvironmentObject private var store: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    package var body: some View {
        let palette = store.nativePalette(for: colorScheme)
        let effects = store.activeEffects
        let accent = toneColor
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: min(16, effects.cornerRadius), style: .continuous)
                        .fill(accent.opacity(0.15))
                    Image(systemName: dialog.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(accent)
                        .shadow(color: accent.opacity(effects.iconGlow * 0.72), radius: 8)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 7) {
                    Text(dialog.title)
                        .font(.title3.weight(.semibold))
                    Text(dialog.message)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                themeSignature
                Spacer()
                Button(dialog.cancelTitle, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(role: dialog.primaryRole, action: confirm) {
                    Text(dialog.primaryTitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: 440)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: effects.cornerRadius + 4, style: .continuous)
                    .fill(Color(nsColor: themeNSColor(palette.layer1)).opacity(store.hasActiveSkin ? 0.96 : 1))
                ThemeAmbientOverlay(compact: true)
                    .clipShape(RoundedRectangle(cornerRadius: effects.cornerRadius + 4, style: .continuous))
            }
        }
        .overlay {
            ThemeFrameOverlay(
                frame: effects.resolvedFrame,
                color: accent,
                cornerRadius: effects.cornerRadius + 4,
                opacity: 0.44
            )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.48 : 0.20), radius: 28, y: 12)
        .padding(28)
    }

    @ViewBuilder
    private var themeSignature: some View {
        let effect = store.activeEffects.kind
        Label(effect.title, systemImage: effect.symbolName)
            .font(.caption2.weight(.medium))
            .foregroundColor(store.resolvedAccentColor(for: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(store.resolvedAccentColor(for: colorScheme).opacity(0.10))
            .clipShape(Capsule())
            .opacity(store.hasActiveSkin ? 1 : 0)
    }

    private var toneColor: Color {
        switch dialog.tone {
        case .info: return store.resolvedAccentColor(for: colorScheme)
        case .warning: return Color(nsColor: themeNSColor(colorScheme == .dark ? "#F5BD6B" : "#A86818"))
        case .danger: return Color(nsColor: themeNSColor(colorScheme == .dark ? "#FF8797" : "#C83C54"))
        case .success: return Color(nsColor: themeNSColor(colorScheme == .dark ? "#73D6A0" : "#278457"))
        }
    }
}

extension View {
    package func themedDialog(item: Binding<ThemeDialogDescriptor?>) -> some View {
        modifier(ThemedDialogPresenter(item: item))
    }
}

/// 原生工具栏和各管理窗口共用这一层，保证 SwiftUI 外壳与 Web 主题属于同一套配色。
package struct ThemeChromeBackground: View {
    package init() {}
    @EnvironmentObject private var store: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package var body: some View {
        Group {
            if store.hasActiveSkin {
                let palette = store.nativePalette(for: colorScheme)
                ZStack {
                    LinearGradient(
                        colors: [color(palette.sidebar), color(palette.layer2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    ThemeAmbientOverlay(compact: true)
                }
                .clipped()
            } else {
                Rectangle().fill(.bar)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: store.configuration.presetID)
    }

    private func color(_ hex: String) -> Color {
        Color(nsColor: themeNSColor(hex))
    }
}

package struct ThemeWindowBackground: View {
    package init() {}
    @EnvironmentObject private var store: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package var body: some View {
        Group {
            if store.hasActiveSkin {
                ZStack {
                    Color(nsColor: themeNSColor(store.nativePalette(for: colorScheme).base))
                    ThemeAmbientOverlay()
                }
                .clipped()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: store.configuration.presetID)
    }
}
