import Foundation
import AppKit
import ImageIO

// MARK: - 主题配置模型

package enum WallpaperDisplayMode: String, Codable, CaseIterable, Identifiable {
    case fill
    case fit
    case center
    case tile

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .fill: return "填充"
        case .fit: return "适应"
        case .center: return "居中"
        case .tile: return "平铺"
        }
    }
}

package struct ThemePaletteColors: Codable, Equatable {
    package let base: String
    package let layer1: String
    package let layer2: String
    package let layer3: String
    package let sidebar: String
    package let border: String
    package let accent: String
    package var labelPrimary: String? = nil
    package var labelSecondary: String? = nil
    package var labelTertiary: String? = nil
    package var accentSoft: String? = nil

    package var hasValidColors: Bool {
        let required = [base, layer1, layer2, layer3, sidebar, border, accent]
        let optional = [labelPrimary, labelSecondary, labelTertiary, accentSoft].compactMap { $0 }
        return (required + optional).allSatisfy { normalizedHexColor($0) != nil }
    }
}

package enum ThemeTypography: String, Codable {
    case system
    case rounded
    case modern
    case elegant

    package var cssFamily: String {
        switch self {
        case .system:
            return #"-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif"#
        case .rounded:
            return #""SF Pro Rounded", "PingFang SC", -apple-system, sans-serif"#
        case .modern:
            return #"Inter, "Avenir Next", -apple-system, "PingFang SC", sans-serif"#
        case .elegant:
            return #""Avenir Next", "PingFang SC", -apple-system, sans-serif"#
        }
    }
}

/// 完整皮肤不再只有颜色。这里描述背景氛围、控件几何和图标语言，
/// Web 与 SwiftUI 两侧都消费同一份参数，避免各自写死主题 id。
package enum ThemeEffectKind: String, Codable, Equatable {
    case none
    case stars
    case paper
    case bubbles
    case mist
    case neonRain
    case nekoSparkle
    case bloom
    case eldritchInk
    case dragonEmbers
    case ashRunes
    case pixels
}

package enum ThemeIconStyle: String, Codable, Equatable {
    case monochrome
    case hierarchical
    case playful
    case luminous
}

/// 边框是一等主题参数，不再只靠圆角和强调色间接推断。
/// Web 页面和原生弹窗会使用同一套框体语言。
package enum ThemeFrameStyle: String, Codable, Equatable {
    case soft
    case neon
    case stitched
    case floral
    case talisman
    case arcane
    case weathered
    case pixel
}

package struct ThemeFrameEffects: Codable, Equatable {
    package let style: ThemeFrameStyle
    package let width: Double
    package let glow: Double

    package static let standard = ThemeFrameEffects(style: .soft, width: 1, glow: 0)

    package var hasValidValues: Bool {
        (0.5...3).contains(width) && (0...1).contains(glow)
    }
}

package struct ThemeEffects: Codable, Equatable {
    package let kind: ThemeEffectKind
    package let iconStyle: ThemeIconStyle
    package let motion: Double
    package let cornerRadius: Double
    package let glassBlur: Double
    package let iconGlow: Double
    package var frame: ThemeFrameEffects? = nil

    package static let standard = ThemeEffects(
        kind: .none,
        iconStyle: .hierarchical,
        motion: 0,
        cornerRadius: 10,
        glassBlur: 0,
        iconGlow: 0
    )

    package var hasValidValues: Bool {
        (0...1).contains(motion)
            && (6...24).contains(cornerRadius)
            && (0...28).contains(glassBlur)
            && (0...1).contains(iconGlow)
            && (frame?.hasValidValues ?? true)
    }

    package var resolvedFrame: ThemeFrameEffects {
        frame ?? .standard
    }
}

package struct ThemePresetWallpaper: Codable, Equatable {
    package let filename: String
    package let mode: WallpaperDisplayMode
    package let blur: Double
    package let dimming: Double
    package let surfaceOpacity: Double
}

package struct ThemePresetDefinition: Identifiable, Equatable {
    package let id: String
    package let name: String
    package let category: String
    package let detail: String
    package let order: Int
    package let light: ThemePaletteColors
    package let dark: ThemePaletteColors
    package let typography: ThemeTypography
    package let effects: ThemeEffects
    package let wallpaper: ThemePresetWallpaper?
    package let packageDirectory: String?

    package init(
        id: String,
        name: String,
        category: String = "基础",
        detail: String,
        order: Int = 0,
        light: ThemePaletteColors,
        dark: ThemePaletteColors,
        typography: ThemeTypography = .system,
        effects: ThemeEffects = .standard,
        wallpaper: ThemePresetWallpaper? = nil,
        packageDirectory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.detail = detail
        self.order = order
        self.light = light
        self.dark = dark
        self.typography = typography
        self.effects = effects
        self.wallpaper = wallpaper
        self.packageDirectory = packageDirectory
    }
}

private struct ThemePackageManifest: Codable {
    package let schemaVersion: Int
    package let id: String
    package let name: String
    package let category: String
    package let detail: String
    package let order: Int
    package let typography: ThemeTypography
    package let light: ThemePaletteColors
    package let dark: ThemePaletteColors
    package let effects: ThemeEffects?
    package let wallpaper: ThemePresetWallpaper
}

/// 内置主题注册表。配置只保存字符串 id，未来可以从主题包或导入文件追加定义，
/// 不需要迁移用户已经保存的 ThemeConfiguration。
package enum ThemePresetCatalog {
    package static let native = ThemePresetDefinition(
        id: "native",
        name: "DSH 原生",
        detail: "保留 DSH 当前浅色或深色配色",
        light: ThemePaletteColors(
            base: "#FFFFFF", layer1: "#FFFFFF", layer2: "#F5F6F7",
            layer3: "#F1F3F5", sidebar: "#F9FAFB", border: "#CFD3D6", accent: "#4176E6"
        ),
        dark: ThemePaletteColors(
            base: "#151517", layer1: "#232324", layer2: "#2C2C2E",
            layer3: "#353638", sidebar: "#1B1B1C", border: "#43454A", accent: "#679EFE"
        )
    )

    package static let palettePresets: [ThemePresetDefinition] = [
        native,
        ThemePresetDefinition(
            id: "pine-mist",
            name: "松雾",
            detail: "低饱和柔和绿色",
            light: ThemePaletteColors(
                base: "#F3F7F2", layer1: "#FBFDFB", layer2: "#EAF2E9",
                layer3: "#DFEBDD", sidebar: "#E7F0E5", border: "#B8C9B7", accent: "#4C8061"
            ),
            dark: ThemePaletteColors(
                base: "#111713", layer1: "#18211A", layer2: "#1E2A21",
                layer3: "#27342A", sidebar: "#141D16", border: "#405346", accent: "#86C49C"
            )
        ),
        ThemePresetDefinition(
            id: "midnight-blue",
            name: "深海",
            detail: "克制的深蓝与冷灰",
            light: ThemePaletteColors(
                base: "#F3F6FA", layer1: "#FBFCFE", layer2: "#E9EEF6",
                layer3: "#DFE7F1", sidebar: "#E7EDF6", border: "#B7C3D4", accent: "#476FAD"
            ),
            dark: ThemePaletteColors(
                base: "#0F141D", layer1: "#161D29", layer2: "#1D2735",
                layer3: "#263243", sidebar: "#121925", border: "#3E4D62", accent: "#7FA7E2"
            )
        ),
        ThemePresetDefinition(
            id: "warm-sand",
            name: "暖砂",
            detail: "温和米色与棕金强调",
            light: ThemePaletteColors(
                base: "#F8F5EF", layer1: "#FEFCF8", layer2: "#F1EAE0",
                layer3: "#E9DED0", sidebar: "#F0E8DC", border: "#D0BEA8", accent: "#9A6840"
            ),
            dark: ThemePaletteColors(
                base: "#191510", layer1: "#231D17", layer2: "#2C241C",
                layer3: "#382D23", sidebar: "#1E1812", border: "#59493B", accent: "#D2A274"
            )
        ),
    ]

    /// 每套完整皮肤都来自 `Resources/Themes/<id>/theme.json`，资源和配置彼此隔离。
    package static let bundledPresets: [ThemePresetDefinition] = loadBundledPresets(
        from: ThemeAssetRepository.bundledDirectoryURL
    )
    package static let builtIns: [ThemePresetDefinition] = palettePresets + bundledPresets

    package static func preset(id: String) -> ThemePresetDefinition {
        builtIns.first { $0.id == id } ?? native
    }

    package static func bundledWallpaperURL(for preset: ThemePresetDefinition) -> URL? {
        guard let directory = preset.packageDirectory,
              let wallpaper = preset.wallpaper else { return nil }
        return ThemeAssetRepository.bundledURL(
            packageDirectory: directory,
            filename: wallpaper.filename
        )
    }

    package static func loadBundledPresets(from root: URL?) -> [ThemePresetDefinition] {
        guard let root,
              let directories = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        let reservedIDs = Set(palettePresets.map(\.id))
        var seenIDs = reservedIDs
        var result: [ThemePresetDefinition] = []
        let decoder = JSONDecoder()

        for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  ThemeAssetRepository.isSafeComponent(directory.lastPathComponent) else { continue }
            let manifestURL = directory.appendingPathComponent("theme.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(ThemePackageManifest.self, from: data),
                  (1...3).contains(manifest.schemaVersion),
                  manifest.schemaVersion == 1 || manifest.effects != nil,
                  manifest.schemaVersion < 3 || manifest.effects?.frame != nil,
                  manifest.id == directory.lastPathComponent,
                  ThemeAssetRepository.isSafeComponent(manifest.id),
                  !seenIDs.contains(manifest.id),
                  !manifest.name.isEmpty, manifest.name.count <= 40,
                  !manifest.category.isEmpty, manifest.category.count <= 20,
                  manifest.detail.count <= 100,
                  manifest.light.hasValidColors,
                  manifest.dark.hasValidColors,
                  (manifest.effects ?? .standard).hasValidValues,
                  (0...24).contains(manifest.wallpaper.blur),
                  (0...0.8).contains(manifest.wallpaper.dimming),
                  (0.45...1).contains(manifest.wallpaper.surfaceOpacity),
                  ThemeAssetRepository.bundledURL(
                    packageDirectory: manifest.id,
                    filename: manifest.wallpaper.filename,
                    rootURL: root
                  ) != nil else { continue }
            seenIDs.insert(manifest.id)
            result.append(ThemePresetDefinition(
                id: manifest.id,
                name: manifest.name,
                category: manifest.category,
                detail: manifest.detail,
                order: manifest.order,
                light: manifest.light,
                dark: manifest.dark,
                typography: manifest.typography,
                effects: manifest.effects ?? .standard,
                wallpaper: manifest.wallpaper,
                packageDirectory: manifest.id
            ))
        }
        return result.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
    }
}

package enum ThemeWallpaperSource: String, Codable {
    case preset
    case custom
}

package struct ThemeConfiguration: Codable, Equatable {
    package var isEnabled = true
    package var presetID = ThemePresetCatalog.native.id
    package var usesCustomAccent = false
    package var customAccentHex = "#4F7DF3"
    package var wallpaperEnabled = false
    package var wallpaperFilename: String?
    /// 可选是为了兼容 build 4/5 保存的 schema v1；nil 会按是否存在自选文件自动迁移。
    package var wallpaperSource: ThemeWallpaperSource? = nil
    package var wallpaperDisplayMode: WallpaperDisplayMode = .fill
    package var wallpaperBlur: Double = 0
    package var wallpaperDimming: Double = 0.34
    package var surfaceOpacity: Double = 0.88

    mutating func normalize() {
        if !ThemePresetCatalog.builtIns.contains(where: { $0.id == presetID }) {
            presetID = ThemePresetCatalog.native.id
        }
        if normalizedHexColor(customAccentHex) == nil {
            customAccentHex = "#4F7DF3"
        }
        wallpaperBlur = min(24, max(0, wallpaperBlur))
        wallpaperDimming = min(0.80, max(0, wallpaperDimming))
        surfaceOpacity = min(1, max(0.45, surfaceOpacity))
        if wallpaperSource == nil {
            wallpaperSource = wallpaperFilename == nil ? .preset : .custom
        }
        if wallpaperSource == .custom, wallpaperFilename == nil {
            if ThemePresetCatalog.preset(id: presetID).wallpaper != nil {
                wallpaperSource = .preset
            } else {
                wallpaperEnabled = false
            }
        }
        if wallpaperSource == .preset,
           ThemePresetCatalog.preset(id: presetID).wallpaper == nil {
            wallpaperEnabled = false
        }
    }
}

private struct ThemePersistenceEnvelope: Codable {
    package let schemaVersion: Int
    package let configuration: ThemeConfiguration
}

package enum ThemeAssetRepository {
    package static let scheme = "dsh-desktop-theme"
    package static let host = "wallpaper"
    package static let bundledHost = "bundled"

    package static var bundledDirectoryURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("Themes", isDirectory: true)
    }

    package static var directoryURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("io.github.dramtea.dsh-desktop-community", isDirectory: true)
            .appendingPathComponent("Themes", isDirectory: true)
    }

    package static func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw NSError(domain: "ThemeAssets", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "主题资源目录不是安全的普通目录",
            ])
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    package static func isSafeComponent(_ value: String) -> Bool {
        guard !value.isEmpty,
              value != ".", value != "..",
              value == URL(fileURLWithPath: value).lastPathComponent,
              !value.hasPrefix(".") else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }
    }

    package static func url(for filename: String?) -> URL? {
        guard let filename,
              isSafeComponent(filename) else { return nil }
        guard let rootValues = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true else { return nil }
        let root = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = directoryURL.appendingPathComponent(filename)
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.deletingLastPathComponent() == root,
              let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              FileManager.default.isReadableFile(atPath: resolved.path) else { return nil }
        return resolved
    }

    package static func webURL(for filename: String?) -> URL? {
        guard let filename, url(for: filename) != nil,
              let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(scheme)://\(host)/\(encoded)")
    }

    package static func bundledURL(
        packageDirectory: String,
        filename: String,
        rootURL: URL? = bundledDirectoryURL
    ) -> URL? {
        guard isSafeComponent(packageDirectory),
              isSafeComponent(filename),
              let rootURL else { return nil }
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let package = rootURL.appendingPathComponent(packageDirectory, isDirectory: true)
        let candidate = package.appendingPathComponent(filename)
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.deletingLastPathComponent() == package.resolvingSymlinksInPath().standardizedFileURL,
              resolved.path.hasPrefix(root.path + "/"),
              let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              FileManager.default.isReadableFile(atPath: resolved.path) else { return nil }
        return resolved
    }

    package static func bundledWebURL(for preset: ThemePresetDefinition) -> URL? {
        guard let packageDirectory = preset.packageDirectory,
              let wallpaper = preset.wallpaper,
              bundledURL(packageDirectory: packageDirectory, filename: wallpaper.filename) != nil,
              let encodedPackage = packageDirectory.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedFilename = wallpaper.filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "\(scheme)://\(bundledHost)/\(encodedPackage)/\(encodedFilename)")
    }

    package static func fileURL(for requestURL: URL) -> URL? {
        guard requestURL.scheme == scheme else { return nil }
        if requestURL.host == host {
            let encodedName = requestURL.lastPathComponent
            return url(for: encodedName.removingPercentEncoding ?? encodedName)
        }
        if requestURL.host == bundledHost {
            let components = requestURL.pathComponents.filter { $0 != "/" }
            guard components.count == 2 else { return nil }
            let package = components[0].removingPercentEncoding ?? components[0]
            let filename = components[1].removingPercentEncoding ?? components[1]
            return bundledURL(packageDirectory: package, filename: filename)
        }
        return nil
    }
}

private enum ThemeStoreError: LocalizedError {
    case message(String)

    package var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}

// MARK: - 主题状态与壁纸资产

package final class ThemeStore: ObservableObject {

    @Published package var configuration: ThemeConfiguration {
        didSet { persist() }
    }
    @Published package private(set) var statusMessage: String?
    @Published package private(set) var errorMessage: String?

    private static let defaultsKey = "themeConfigurationV1"
    private static let supportedWallpaperExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp", "tif", "tiff",
    ]
    private static let maximumWallpaperBytes: Int64 = 50 * 1024 * 1024

    package init() {
        var loaded = Self.loadConfiguration()
        if loaded.wallpaperFilename != nil,
           ThemeAssetRepository.url(for: loaded.wallpaperFilename) == nil {
            loaded.wallpaperFilename = nil
        }
        loaded.normalize()
        configuration = loaded
    }

    package var selectedPreset: ThemePresetDefinition {
        ThemePresetCatalog.preset(id: configuration.presetID)
    }

    package var resolvedWallpaperSource: ThemeWallpaperSource {
        configuration.wallpaperSource ?? (configuration.wallpaperFilename == nil ? .preset : .custom)
    }

    package var customWallpaperURL: URL? {
        ThemeAssetRepository.url(for: configuration.wallpaperFilename)
    }

    package var presetWallpaperURL: URL? {
        ThemePresetCatalog.bundledWallpaperURL(for: selectedPreset)
    }

    package var wallpaperURL: URL? {
        switch resolvedWallpaperSource {
        case .preset: return presetWallpaperURL
        case .custom: return customWallpaperURL
        }
    }

    package var wallpaperWebURL: URL? {
        switch resolvedWallpaperSource {
        case .preset: return ThemeAssetRepository.bundledWebURL(for: selectedPreset)
        case .custom: return ThemeAssetRepository.webURL(for: configuration.wallpaperFilename)
        }
    }

    package var wallpaperDisplayName: String? {
        switch resolvedWallpaperSource {
        case .preset: return selectedPreset.wallpaper == nil ? nil : "\(selectedPreset.name) · 内置素材"
        case .custom: return customWallpaperURL?.lastPathComponent
        }
    }

    package func selectPreset(_ preset: ThemePresetDefinition) {
        statusMessage = nil
        errorMessage = nil
        var next = configuration
        next.presetID = preset.id
        next.isEnabled = true
        next.usesCustomAccent = false
        next.wallpaperSource = .preset
        if let wallpaper = preset.wallpaper {
            next.wallpaperEnabled = true
            next.wallpaperDisplayMode = wallpaper.mode
            next.wallpaperBlur = wallpaper.blur
            next.wallpaperDimming = wallpaper.dimming
            next.surfaceOpacity = wallpaper.surfaceOpacity
        } else {
            next.wallpaperEnabled = false
        }
        configuration = next
        statusMessage = preset.wallpaper == nil
            ? "已应用“\(preset.name)”基础配色。"
            : "已应用“\(preset.name)”完整主题。"
    }

    package func importWallpaper(from sourceURL: URL) {
        statusMessage = nil
        errorMessage = nil
        do {
            let resolvedSourceURL = sourceURL.resolvingSymlinksInPath()
            let values = try resolvedSourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw ThemeStoreError.message("请选择一个普通图片文件。")
            }
            let byteCount = Int64(values.fileSize ?? 0)
            guard byteCount > 0, byteCount <= Self.maximumWallpaperBytes else {
                throw ThemeStoreError.message("壁纸文件必须小于 50 MB。")
            }
            let ext = resolvedSourceURL.pathExtension.lowercased()
            guard Self.supportedWallpaperExtensions.contains(ext) else {
                throw ThemeStoreError.message("当前支持 PNG、JPEG、HEIC、WebP 和 TIFF 静态图片。")
            }
            guard let imageSource = CGImageSourceCreateWithURL(resolvedSourceURL as CFURL, nil),
                  CGImageSourceGetCount(imageSource) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  width > 0, height > 0,
                  width <= 20_000, height <= 20_000,
                  Int64(width) * Int64(height) <= 100_000_000,
                  let image = NSImage(contentsOf: resolvedSourceURL),
                  image.size.width > 0, image.size.height > 0 else {
                throw ThemeStoreError.message("macOS 无法读取这张图片。")
            }

            try ThemeAssetRepository.prepareDirectory()
            let filename = "wallpaper-\(UUID().uuidString.lowercased()).\(ext)"
            let destination = ThemeAssetRepository.directoryURL.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: resolvedSourceURL, to: destination)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )

            let previousFilename = configuration.wallpaperFilename
            var next = configuration
            next.wallpaperFilename = filename
            next.wallpaperSource = .custom
            next.wallpaperEnabled = true
            next.isEnabled = true
            configuration = next
            removeManagedWallpaperFile(named: previousFilename)
            statusMessage = "已复制壁纸到应用数据目录；原始图片不会被修改。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func removeWallpaper() {
        statusMessage = nil
        errorMessage = nil
        let previousFilename = configuration.wallpaperFilename
        var next = configuration
        next.wallpaperFilename = nil
        next.wallpaperSource = .preset
        if let wallpaper = selectedPreset.wallpaper {
            next.wallpaperEnabled = true
            next.wallpaperDisplayMode = wallpaper.mode
            next.wallpaperBlur = wallpaper.blur
            next.wallpaperDimming = wallpaper.dimming
            next.surfaceOpacity = wallpaper.surfaceOpacity
        } else {
            next.wallpaperEnabled = false
        }
        configuration = next
        removeManagedWallpaperFile(named: previousFilename)
        statusMessage = selectedPreset.wallpaper == nil
            ? "已移除客户端保存的自选壁纸。"
            : "已移除自选壁纸，并恢复当前主题的内置素材。"
    }

    package func resetToDefaults() {
        statusMessage = nil
        errorMessage = nil
        let previousFilename = configuration.wallpaperFilename
        configuration = ThemeConfiguration()
        removeManagedWallpaperFile(named: previousFilename)
        statusMessage = "已恢复 DSH 原生外观。"
    }

    package func clearMessages() {
        statusMessage = nil
        errorMessage = nil
    }

    private func removeManagedWallpaperFile(named filename: String?) {
        guard let url = ThemeAssetRepository.url(for: filename) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            errorMessage = "旧壁纸副本未能清理：\(error.localizedDescription)"
        }
    }

    private static func loadConfiguration() -> ThemeConfiguration {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let envelope = try? JSONDecoder().decode(ThemePersistenceEnvelope.self, from: data),
              envelope.schemaVersion == 1 || envelope.schemaVersion == 2 else { return ThemeConfiguration() }
        return envelope.configuration
    }

    private func persist() {
        let envelope = ThemePersistenceEnvelope(schemaVersion: 2, configuration: configuration)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

// MARK: - 颜色工具

package func normalizedHexColor(_ value: String) -> String? {
    var raw = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if raw.hasPrefix("#") { raw.removeFirst() }
    guard raw.count == 6, raw.allSatisfy({ $0.isHexDigit }) else { return nil }
    return "#" + raw
}

package func themeColorComponents(_ value: String) -> (red: Double, green: Double, blue: Double)? {
    guard let normalized = normalizedHexColor(value) else { return nil }
    let raw = String(normalized.dropFirst())
    guard let number = UInt64(raw, radix: 16) else { return nil }
    return (
        Double((number >> 16) & 0xFF) / 255,
        Double((number >> 8) & 0xFF) / 255,
        Double(number & 0xFF) / 255
    )
}

package func themeNSColor(_ value: String) -> NSColor {
    guard let components = themeColorComponents(value) else { return .controlAccentColor }
    return NSColor(
        srgbRed: components.red,
        green: components.green,
        blue: components.blue,
        alpha: 1
    )
}

package func themeHexColor(_ color: NSColor) -> String? {
    guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
    let red = Int(round(min(1, max(0, rgb.redComponent)) * 255))
    let green = Int(round(min(1, max(0, rgb.greenComponent)) * 255))
    let blue = Int(round(min(1, max(0, rgb.blueComponent)) * 255))
    return String(format: "#%02X%02X%02X", red, green, blue)
}
