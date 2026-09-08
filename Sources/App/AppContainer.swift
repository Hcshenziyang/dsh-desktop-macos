import Foundation
import Combine
import DSHCore
import DSHUI
import DSHWeb
import LocalModelFeature
import PluginsFeature
import InspectorFeature
import ProjectViewsFeature
import WorkspaceToolsFeature
import ProjectMemoryFeature

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
    let projectViews: ProjectViewsBridge
    let projectMemory: ProjectMemoryService
    let workspaceTools: WorkspaceToolsService

    init() {
        let log = ActivityLog()
        let inspectorPreferences = InspectorPreferences()
        let pluginObserver = PluginLaunchObserver()
        let inspectorObserver = InspectorLaunchObserver(preferences: inspectorPreferences)
        let projectViewsLaunch = ProjectViewsLaunch()
        let workspaceTools = WorkspaceToolsService()
        let projectMemory = ProjectMemoryService()
        let runtime = DSHService(prepareLaunch: {
            let plugin = pluginObserver.prepare()
            let inspector = inspectorObserver.prepare()
            let projectViews = projectViewsLaunch.prepare()
            let tools = workspaceTools.prepare()
            let memory = projectMemory.prepare()
            return DSHLaunchPreparation(arguments: inspector.arguments + plugin.arguments + projectViews.arguments + tools.arguments + memory.arguments,
                                        messages: plugin.messages + inspector.messages + projectViews.messages + tools.messages + memory.messages)
        }, cleanUpLaunch: {
            inspectorObserver.cleanUp()
            pluginObserver.cleanUp()
            projectViewsLaunch.cleanUp()
            workspaceTools.cleanUp()
            projectMemory.cleanUp()
        }, log: log.append)
        activityLog = log
        self.runtime = runtime
        localModel = LocalModelService(log: log.append)
        plugins = PluginManagerStore(runtime: runtime)
        theme = ThemeStore()
        pluginPreferences = PluginPreferences()
        self.inspectorPreferences = inspectorPreferences
        projectViews = ProjectViewsBridge()
        self.workspaceTools = workspaceTools
        self.projectMemory = projectMemory
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
