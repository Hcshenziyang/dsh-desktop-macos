import Foundation

package enum DSHState: Equatable {
    case stopped
    case starting
    case running(Int32)
    case externalRunning(Int32)
    case stopping
    case failed(String)

    package static func == (l: DSHState, r: DSHState) -> Bool {
        switch (l, r) {
        case (.stopped, .stopped), (.starting, .starting), (.stopping, .stopping):
            return true
        case (.running(let a), .running(let b)):
            return a == b
        case (.externalRunning(let a), .externalRunning(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }

    /// 端口上有服务在监听（无论是本应用启动的还是外部实例）。
    package var portActive: Bool {
        switch self {
        case .running, .externalRunning, .starting:
            return true
        default:
            return false
        }
    }

    /// 空闲状态（stopped / failed）—— 可以尝试启动
    package var canTryStart: Bool {
        switch self {
        case .stopped, .failed:
            return true
        default:
            return false
        }
    }

    /// 服务已就绪，可以嵌入显示 DSH 界面
    package var webReady: Bool {
        switch self {
        case .running, .externalRunning:
            return true
        default:
            return false
        }
    }
}
