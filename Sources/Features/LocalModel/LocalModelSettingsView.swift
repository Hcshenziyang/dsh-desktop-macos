import Foundation
import SwiftUI
import AppKit
import DSHCore
import DSHUI

package struct LocalModelSettingsView: View {
    @ObservedObject private var model: LocalModelService
    package init(service: LocalModelService) { self.model = service }
    package var body: some View {
                    GroupBox(label: Label("本地模型服务", systemImage: "cpu")) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 10) {
                                Text("名称:").frame(width: 86, alignment: .trailing)
                                TextField("例如：Qwen 27B", text: $model.localModelName)
                            }
                            HStack(spacing: 10) {
                                Text("启动程序:").frame(width: 86, alignment: .trailing)
                                TextField("可执行文件或脚本路径", text: $model.localModelStartExecutable)
                                    .font(.system(.body, design: .monospaced))
                                Button("浏览…") { pickLocalModelExecutable(forStop: false) }
                                Text(
                                    FileManager.default.isExecutableFile(atPath: model.localModelStartPath) ? "✓" : "✗"
                                )
                                .foregroundColor(
                                    FileManager.default.isExecutableFile(atPath: model.localModelStartPath)
                                        ? .green : .red)
                            }
                            HStack(spacing: 10) {
                                Text("启动参数:").frame(width: 86, alignment: .trailing)
                                TextField("例如：--port 8000 --model \"/路径/模型\"", text: $model.localModelStartArguments)
                                    .font(.system(.body, design: .monospaced))
                            }
                            HStack(spacing: 10) {
                                Text("停止程序:").frame(width: 86, alignment: .trailing)
                                TextField("可选；后台服务建议配置 stop.sh", text: $model.localModelStopExecutable)
                                    .font(.system(.body, design: .monospaced))
                                Button("浏览…") { pickLocalModelExecutable(forStop: true) }
                            }
                            HStack(spacing: 10) {
                                Text("停止参数:").frame(width: 86, alignment: .trailing)
                                TextField("可选", text: $model.localModelStopArguments)
                                    .font(.system(.body, design: .monospaced))
                            }
                            HStack(spacing: 10) {
                                Text("健康检查:").frame(width: 86, alignment: .trailing)
                                TextField("可选，例如 http://127.0.0.1:<端口>/health", text: $model.localModelHealthURL)
                                    .font(.system(.body, design: .monospaced))
                            }
                            HStack(spacing: 10) {
                                ThemedStatusIndicator(
                                    color: localModelStatusColor,
                                    isAnimating: localModelStatusIsAnimating
                                )
                                Text(localModelStatusText)
                                Spacer()
                                Toggle("退出应用时停止本地模型", isOn: $model.stopLocalModelOnQuit)
                                Button(
                                    model.localModelState == .starting || model.localModelState == .ready ? "停止" : "启动"
                                ) {
                                    model.toggleLocalModel()
                                }
                                .disabled(!model.canToggleLocalModel)
                            }
                            Text("程序将直接以当前用户权限运行；参数不会经过 Shell，也不支持管道、重定向或命令替换。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }

        .onChange(of: model.localModelName) { _ in model.persist() }
        .onChange(of: model.localModelStartExecutable) { _ in
            model.persist(); model.refreshLocalModel()
        }
        .onChange(of: model.localModelStartArguments) { _ in model.persist() }
        .onChange(of: model.localModelStopExecutable) { _ in model.persist() }
        .onChange(of: model.localModelStopArguments) { _ in model.persist() }
        .onChange(of: model.localModelHealthURL) { _ in
            model.persist(); model.refreshLocalModel()
        }
        .onChange(of: model.stopLocalModelOnQuit) { _ in model.persist() }
    }
    private var localModelStatusText: String {
        switch model.localModelState {
        case .stopped: return "未运行"
        case .starting: return "正在启动 \(model.localModelDisplayName)…"
        case .ready: return "\(model.localModelDisplayName) 已就绪"
        case .stopping: return "正在停止…"
        case .failed(let message): return "异常：\(message)"
        }
    }

    private var localModelStatusColor: Color {
        switch model.localModelState {
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .ready: return .green
        case .failed: return .red
        }
    }

    private var localModelStatusIsAnimating: Bool {
        switch model.localModelState {
        case .starting, .stopping: return true
        default: return false
        }
    }

    private func pickLocalModelExecutable(forStop: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = forStop ? "选择停止程序" : "选择启动程序"
        panel.message = "请选择可信的可执行文件或带有执行权限的脚本"
        if panel.runModal() == .OK, let url = panel.url {
            if forStop {
                model.localModelStopExecutable = url.path
            } else {
                model.localModelStartExecutable = url.path
            }
            model.persist()
            model.refreshLocalModel()
        }
    }
}
