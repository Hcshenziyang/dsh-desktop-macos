import Foundation
import Combine
import DSHCore
import DSHUI
import DSHWeb
import LocalModelFeature
import PluginsFeature
import InspectorFeature

/// The single composition root. Feature implementations do not construct or locate each other.
@MainActor
final class AppContainer: ObservableObject {
    let activityLog: ActivityLog
    let runtime: DSHService
    let localModel: LocalModelService
    let plugins: PluginManagerStore
    let theme: ThemeStore
    let pluginPreferences: PluginPreferences
    let inspectorPreferences: InspectorPreferences

    init() {
        let log = ActivityLog()
        let inspectorPreferences = InspectorPreferences()
        let pluginObserver = PluginLaunchObserver()
        let inspectorObserver = InspectorLaunchObserver(preferences: inspectorPreferences)
        let runtime = DSHService(prepareLaunch: {
            let plugin = pluginObserver.prepare()
            let inspector = inspectorObserver.prepare()
            return DSHLaunchPreparation(arguments: inspector.arguments + plugin.arguments,
                                        messages: plugin.messages + inspector.messages)
        }, cleanUpLaunch: {
            inspectorObserver.cleanUp()
            pluginObserver.cleanUp()
        }, log: log.append)
        activityLog = log
        self.runtime = runtime
        localModel = LocalModelService(log: log.append)
        plugins = PluginManagerStore(runtime: runtime)
        theme = ThemeStore()
        pluginPreferences = PluginPreferences()
        self.inspectorPreferences = inspectorPreferences
    }

    func webEnhancements(theme: ThemeWebSnapshot) -> [WebEnhancement] {
        let packages = PluginWebEnhancement.userPackages()
        let simplified = pluginPreferences.simplifyPluginInventory
        return [
            WebEnhancement(id: "theme", source: themeEnhancementScript(snapshot: theme), atStart: true,
                           update: themePreferenceScript(snapshot: theme)),
            WebEnhancement(id: "plugin-inventory", source: PluginWebEnhancement.script(enabled: simplified, packages: packages),
                           update: PluginWebEnhancement.update(enabled: simplified, packages: packages))
        ]
    }

    func terminateOnQuit() {
        localModel.terminateOnQuit()
        runtime.terminateOnQuit()
    }
}
