extension PluginRuntimeStatus {
    var displayName: String {
        switch self {
        case .notFound: return "未发现运行单元"
        case .disabled: return "已禁用"
        case .failed: return "加载失败"
        case .active: return "运行正常"
        case .partial: return "部分运行 · 等待依赖"
        case .pending: return "等待 / 加载中"
        }
    }
}
