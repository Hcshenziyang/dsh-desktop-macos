import Foundation
import DSHCore

package final class InspectorLaunchObserver {
    private let preferences: InspectorPreferences
    private let moduleURL: URL?
    private let outputURL: URL
    package init(preferences: InspectorPreferences, moduleURL: URL? = nil, outputURL: URL? = nil) {
        self.preferences = preferences
        self.moduleURL = moduleURL
        self.outputURL = outputURL ?? requestInspectorOutputURL()
    }

    package func prepare() -> DSHLaunchPreparation {
        cleanUp()
        guard preferences.captureModelRequests else { return DSHLaunchPreparation() }
        guard let module = moduleURL ?? requestInspectorResources()?.moduleURL else {
            return DSHLaunchPreparation(messages: ["⚠️ 未找到模型固定输入检查器资源；本次启动不会捕获固定输入"])
        }
        do {
            let patch = try prepareRequestInspectorPatch(moduleURL: module, outputURL: outputURL)
            return DSHLaunchPreparation(arguments: ["--patch", patch.path], messages: ["🔎 已启用模型固定输入检查器（仅本机临时缓存）"])
        } catch {
            return DSHLaunchPreparation(messages: ["⚠️ 无法准备模型固定输入检查器：\(error.localizedDescription)"])
        }
    }

    package func cleanUp() { try? FileManager.default.removeItem(at: outputURL) }
}
