import SwiftUI
import AppKit
import DSHUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var container: AppContainer?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if container?.runtime.isMaintaining == true {
            NSApp.activate(ignoringOtherApps: true)
            NSSound.beep()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { container?.terminateOnQuit() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DSHLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup("DSH Desktop Community") {
            ContentView(container: container)
                .environmentObject(container.theme)
                .onAppear { appDelegate.container = container }
        }
        .windowResizability(.contentMinSize)
    }
}
