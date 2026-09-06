import SwiftUI
import DSHUI

package struct LocalModelToolbarButton: View {
    @ObservedObject private var model: LocalModelService
    package init(service: LocalModelService) { self.model = service }
    package var body: some View {
            Button(action: { model.toggleLocalModel() }) {
                ThemedToolbarIcon(
                    systemName: localModelSystemImage,
                    label: localModelButtonText,
                    isActive: localModelIsActive
                )
            }
            .buttonStyle(.plain)
            .disabled(!model.canToggleLocalModel)
            .help(localModelHelpText)

    }
    private var localModelButtonText: String {
        switch model.localModelState {
        case .stopped, .failed: return "启动 \(model.localModelDisplayName)"
        case .starting, .ready: return "停止 \(model.localModelDisplayName)"
        case .stopping: return "正在停止 \(model.localModelDisplayName)"
        }
    }

    private var localModelIsActive: Bool {
        if case .ready = model.localModelState { return true }
        return false
    }

    private var localModelSystemImage: String {
        switch model.localModelState {
        case .stopped: return "cpu"
        case .starting: return "hourglass"
        case .ready: return "stop.circle.fill"
        case .stopping: return "hourglass"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var localModelHelpText: String {
        let name = model.localModelDisplayName
        if model.localModelStartExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(name) · 未配置启动程序，请前往设置"
        }
        switch model.localModelState {
        case .stopped: return "\(name) · 点击启动"
        case .starting: return model.canStopLocalModel ? "\(name) · 正在启动，点击停止" : "\(name) · 正在启动"
        case .ready:
            return model.canStopLocalModel
                ? "\(name) · 已就绪，点击停止"
                : "\(name) · 已就绪；配置停止程序后可从此处停止"
        case .stopping: return "\(name) · 正在停止"
        case .failed(let message): return "\(name) · 异常：\(message)"
        }
    }

}
