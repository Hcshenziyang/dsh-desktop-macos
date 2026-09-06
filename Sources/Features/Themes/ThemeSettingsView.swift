import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DSHUI



package struct ThemeSettingsView: View {
    package init(isPresented: Binding<Bool>) { self._isPresented = isPresented }
    @Binding package var isPresented: Bool
    @EnvironmentObject private var store: ThemeStore
    @State private var dialog: ThemeDialogDescriptor?

    package var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("主题与壁纸").font(.title2).bold()
                    Text("独立客户端增强，不修改 DSH 核心或 Web profile")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("恢复默认", role: .destructive) { presentResetDialog() }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(ThemeChromeBackground())

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ThemePreview(configuration: store.configuration, wallpaperURL: store.wallpaperURL)

                    GroupBox(label: Label("主题引擎", systemImage: "paintpalette")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("启用客户端主题增强", isOn: binding(\.isEnabled))
                            Text("关闭后立即移除全部配色与壁纸覆盖，回到 DSH 原生外观。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }

                    GroupBox(label: Label("基础配色", systemImage: "swatchpalette")) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 155), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(ThemePresetCatalog.palettePresets) { preset in
                                ThemePresetButton(
                                    preset: preset,
                                    selected: store.configuration.presetID == preset.id
                                ) {
                                    store.selectPreset(preset)
                                }
                            }
                        }
                        .padding(4)
                    }

                    GroupBox(label: Label("完整主题套装", systemImage: "sparkles.rectangle.stack")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("每套会同时更换背景、侧栏、历史卡片、消息气泡、输入框、弹窗、图标语言、框体结构、圆角、玻璃感、字体和专属环境动效。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(ThemePresetCatalog.bundledPresets) { preset in
                                    ThemePackButton(
                                        preset: preset,
                                        wallpaperURL: ThemePresetCatalog.bundledWallpaperURL(for: preset),
                                        selected: store.configuration.presetID == preset.id
                                            && store.resolvedWallpaperSource == .preset
                                    ) {
                                        store.selectPreset(preset)
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }

                    GroupBox(label: Label("强调色", systemImage: "eyedropper")) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Toggle("覆盖预设强调色", isOn: binding(\.usesCustomAccent))
                                Spacer()
                                ColorPicker(
                                    "自定义强调色",
                                    selection: accentBinding,
                                    supportsOpacity: false
                                )
                                .labelsHidden()
                                .disabled(!store.configuration.usesCustomAccent)
                                Text(store.configuration.customAccentHex)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                    .frame(width: 72, alignment: .trailing)
                            }
                            Text("强调色会应用到 DSH 品牌色、业务状态和客户端原生控件。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }

                    GroupBox(label: Label("个人壁纸（独立）", systemImage: "photo")) {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(alignment: .top, spacing: 14) {
                                wallpaperThumbnail
                                    .frame(width: 210, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9)
                                            .stroke(Color.secondary.opacity(0.25))
                                    }

                                VStack(alignment: .leading, spacing: 9) {
                                    Toggle("显示壁纸", isOn: binding(\.wallpaperEnabled))
                                        .disabled(store.wallpaperURL == nil)
                                    HStack {
                                        Button("选择图片…") { pickWallpaper() }
                                        if store.customWallpaperURL != nil {
                                            Button("移除自选", role: .destructive) { store.removeWallpaper() }
                                        }
                                    }
                                    Text("支持 PNG、JPEG、HEIC、WebP、TIFF，最大 50 MB。图片会复制到应用自己的数据目录。")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let displayName = store.wallpaperDisplayName {
                                        Text(displayName)
                                            .font(.caption2.monospaced())
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Divider()

                            HStack {
                                Text("显示方式").frame(width: 84, alignment: .trailing)
                                Picker("", selection: binding(\.wallpaperDisplayMode)) {
                                    ForEach(WallpaperDisplayMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            .disabled(!wallpaperControlsEnabled)

                            themeSlider(
                                title: "模糊",
                                value: binding(\.wallpaperBlur),
                                range: 0...24,
                                step: 1,
                                formattedValue: "\(Int(store.configuration.wallpaperBlur)) px"
                            )
                            themeSlider(
                                title: "暗化",
                                value: binding(\.wallpaperDimming),
                                range: 0...0.8,
                                step: 0.01,
                                formattedValue: "\(Int(store.configuration.wallpaperDimming * 100))%"
                            )
                            themeSlider(
                                title: "面板不透明度",
                                value: binding(\.surfaceOpacity),
                                range: 0.45...1,
                                step: 0.01,
                                formattedValue: "\(Int(store.configuration.surfaceOpacity * 100))%"
                            )
                        }
                        .padding(4)
                    }

                    if let error = store.errorMessage {
                        ThemedStatusBanner(message: error, tone: .danger)
                    } else if let status = store.statusMessage {
                        ThemedStatusBanner(message: status, tone: .success)
                    }

                    Label(
                        "主题只作用于本客户端内嵌页面。壁纸通过客户端私有资源通道读取，不会交给 DSH 服务或上传。",
                        systemImage: "hand.raised"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(18)
            }

            Divider()

            HStack {
                Text("配色和滑杆会实时应用，无需重启 DSH。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("完成") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(ThemeChromeBackground())
        }
        .frame(width: 780, height: 600)
        .background(ThemeWindowBackground())
        .onAppear { store.clearMessages() }
        .themedDialog(item: $dialog)
    }

    private var wallpaperControlsEnabled: Bool {
        store.configuration.isEnabled && store.configuration.wallpaperEnabled && store.wallpaperURL != nil
    }

    private var wallpaperThumbnail: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if let url = store.wallpaperURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "photo")
                        .font(.system(size: 27))
                    Text("尚未选择壁纸").font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func themeSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formattedValue: String
    ) -> some View {
        HStack {
            Text(title).frame(width: 84, alignment: .trailing)
            Slider(value: value, in: range, step: step)
            Text(formattedValue)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .disabled(!wallpaperControlsEnabled)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ThemeConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { store.configuration[keyPath: keyPath] },
            set: { value in
                var next = store.configuration
                next[keyPath: keyPath] = value
                store.configuration = next
            }
        )
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: themeNSColor(store.configuration.customAccentHex)) },
            set: { color in
                guard let hex = themeHexColor(NSColor(color)) else { return }
                var next = store.configuration
                next.customAccentHex = hex
                next.usesCustomAccent = true
                next.isEnabled = true
                store.configuration = next
            }
        )
    }

    private func pickWallpaper() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "选择壁纸"
        panel.message = "选择一张静态图片；客户端会保存独立副本。"
        if panel.runModal() == .OK, let url = panel.url {
            store.importWallpaper(from: url)
        }
    }

    private func presentResetDialog() {
        dialog = ThemeDialogDescriptor(
            title: "恢复 DSH 原生外观？",
            message: "将重置配色设置，并删除客户端保存的壁纸副本；你选择壁纸时的原始图片不会被修改。",
            systemImage: "paintbrush.pointed.fill",
            tone: .warning,
            primaryTitle: "恢复默认",
            primaryRole: .destructive,
            primaryAction: { store.resetToDefaults() }
        )
    }
}

private struct ThemePackButton: View {
    package let preset: ThemePresetDefinition
    package let wallpaperURL: URL?
    package let selected: Bool
    package let action: () -> Void

    package var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geometry in
                    ZStack(alignment: .topTrailing) {
                        if let wallpaperURL, let image = NSImage(contentsOf: wallpaperURL) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } else {
                            LinearGradient(
                                colors: [color(preset.light.base), color(preset.light.accent)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(preset.category)
                            Label(preset.effects.kind.title, systemImage: preset.effects.kind.symbolName)
                        }
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .foregroundColor(.white)
                        .background(.black.opacity(0.58))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(8)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .frame(height: 112)
                .clipped()

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.name).fontWeight(.semibold)
                        Text(preset.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay {
                ThemeFrameOverlay(
                    frame: preset.effects.resolvedFrame,
                    color: selected ? Color.accentColor : color(preset.light.accent),
                    cornerRadius: 11,
                    opacity: selected ? 0.82 : 0.32
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private func color(_ hex: String) -> Color {
        Color(nsColor: themeNSColor(hex))
    }
}

private struct ThemePresetButton: View {
    package let preset: ThemePresetDefinition
    package let selected: Bool
    package let action: () -> Void

    package var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    swatch(preset.light.base)
                    swatch(preset.light.accent)
                    swatch(preset.dark.base)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                    }
                }
                Text(preset.name).fontWeight(.medium)
                Text(preset.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: selected ? 2 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ hex: String) -> some View {
        Circle()
            .fill(Color(nsColor: themeNSColor(hex)))
            .frame(width: 17, height: 17)
            .overlay(Circle().stroke(Color.secondary.opacity(0.25)))
    }
}

private struct ThemePreview: View {
    package let configuration: ThemeConfiguration
    package let wallpaperURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    package var body: some View {
        GeometryReader { geometry in
            ZStack {
                previewBackground
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                Color.black.opacity(configuration.wallpaperEnabled ? configuration.wallpaperDimming : 0)
                ThemeAmbientOverlay(compact: true)

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color(palette.sidebar).opacity(surfaceOpacity))
                        .frame(width: max(105, geometry.size.width * 0.20))
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 7) {
                                Capsule().fill(color(accent)).frame(width: 46, height: 7)
                                Capsule().fill(labelColor.opacity(0.30)).frame(width: 65, height: 6)
                                Capsule().fill(labelColor.opacity(0.22)).frame(width: 50, height: 6)
                            }
                            .padding(14)
                        }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("实时外观预览").fontWeight(.semibold)
                            Spacer()
                            Circle().fill(color(accent)).frame(width: 9, height: 9)
                        }
                        RoundedRectangle(cornerRadius: 9)
                            .fill(color(palette.layer1).opacity(surfaceOpacity))
                            .overlay(alignment: .leading) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Capsule().fill(labelColor.opacity(0.50)).frame(width: 135, height: 7)
                                    Capsule().fill(labelColor.opacity(0.22)).frame(width: 210, height: 6)
                                    Capsule().fill(color(accent).opacity(0.65)).frame(width: 90, height: 6)
                                }
                                .padding(12)
                            }
                    }
                    .padding(13)
                }
                .foregroundColor(labelColor)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                ThemeFrameOverlay(
                    frame: configuration.isEnabled ? preset.effects.resolvedFrame : .standard,
                    color: color(accent),
                    cornerRadius: 12,
                    opacity: configuration.isEnabled ? 0.54 : 0.25
                )
            }
        }
        .frame(height: 145)
        .clipped()
    }

    @ViewBuilder
    private var previewBackground: some View {
        if configuration.isEnabled,
           configuration.wallpaperEnabled,
           let wallpaperURL,
           let image = NSImage(contentsOf: wallpaperURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: configuration.wallpaperBlur * 0.35)
        } else {
            color(palette.base)
        }
    }

    private var preset: ThemePresetDefinition {
        ThemePresetCatalog.preset(id: configuration.presetID)
    }

    private var palette: ThemePaletteColors {
        colorScheme == .dark ? preset.dark : preset.light
    }

    private var accent: String {
        configuration.usesCustomAccent ? configuration.customAccentHex : palette.accent
    }

    private var surfaceOpacity: Double {
        configuration.wallpaperEnabled ? configuration.surfaceOpacity : 1
    }

    private var labelColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private func color(_ hex: String) -> Color {
        Color(nsColor: themeNSColor(hex))
    }
}
