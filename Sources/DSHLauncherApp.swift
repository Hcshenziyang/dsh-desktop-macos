import SwiftUI
import AppKit

// MARK: - 应用委托（退出时清理）

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        Manager.shared.terminateChild()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - 应用入口

@main  // 告诉程序启动入口
struct DSHLauncherApp: App {  // 定义一个结构体，遵循swiftui的app协议，这儿逻辑不是继承，更像是一种声明的实现
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // 层级：app-scene（窗口、设置窗口、菜单栏）-view（页面中的具体界面）-text、button、image
    var body: some Scene {  // 计算属性（类似于无参函数），返回一个secne协议的类型
        WindowGroup("DSH Desktop Community") {  //声明一组应用窗口，并制定窗口显示什么
            ContentView() // 创建一个contentview结构体实例
        }
        .windowResizability(.contentMinSize) // 限制窗口的最小尺寸
    }
}
