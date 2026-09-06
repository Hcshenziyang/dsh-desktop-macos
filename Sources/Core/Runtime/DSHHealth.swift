import Foundation

/// 对服务做一次真实 HTTP 健康检查：收到任何 HTTP 响应（2xx/3xx/4xx/5xx）都说明服务活着，
/// 而不仅仅是 TCP 端口连通。连接被拒 / 超时 / 挂死无响应 → 返回 false。
/// 用于区分「健康的 dsh 实例」与「残留的僵尸进程（占着端口但不响应）」。
func isHttpAlive(_ host: String, _ port: Int, timeout: TimeInterval = 2.0) -> Bool {
    let name = host.isEmpty ? "127.0.0.1" : host
    guard let url = URL(string: "http://\(name):\(port)/") else { return false }
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    req.cachePolicy = .reloadIgnoringLocalCacheData
    let sem = DispatchSemaphore(value: 0)
    var alive = false
    let task = URLSession.shared.dataTask(with: req) { _, resp, _ in
        if let r = resp as? HTTPURLResponse {
            alive = (100...599).contains(r.statusCode)
        }
        sem.signal()
    }
    task.resume()
    _ = sem.wait(timeout: .now() + timeout + 1.0)
    task.cancel()
    return alive
}
