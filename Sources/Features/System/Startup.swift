import SwiftUI
import AppKit

struct StartupCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let ready: Bool
    let required: Bool
}
struct StartupEnvironment {
    let brew: String?
    let appPath: String
    let helperReady: Bool
    let macOSMajor: Int
    static func current(brew: String?) -> Self {
        let resources = Bundle.main.resourceURL
        let helperReady = ["askpass.sh", "OrbitAskpass"].allSatisfy { name in
            resources.map { FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent(name).path) } ?? false
        }
        return Self(brew: brew, appPath: Bundle.main.bundleURL.path, helperReady: helperReady, macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}
enum StartupInspector {
    static func checks(_ environment: StartupEnvironment, commands: any CommandExecuting) async -> [StartupCheck] {
        var checks = [StartupCheck(id: "macos", title: "macOS", detail: environment.macOSMajor >= 15 ? "macOS \(environment.macOSMajor) is supported by Homebrew." : "Orbit supports macOS 14+. Homebrew currently recommends macOS 15 or newer.", ready: environment.macOSMajor >= 15, required: false)]
        if let brew = environment.brew {
            let version = await commands.run(brew, ["--version"], log: { _ in })
            let ready = version.0 == 0 && version.1.hasPrefix("Homebrew ")
            checks.append(StartupCheck(id:"brew",title:"Homebrew",detail:ready ? String(version.1.prefix(200)).trimmingCharacters(in:.whitespacesAndNewlines) : "Homebrew was found but could not start. Use the official setup guide to repair it.",ready:ready,required:true))
        } else {
            checks.append(StartupCheck(id:"brew",title:"Homebrew",detail:"Not found. Install Homebrew using its official guide, then choose Check again.",ready:false,required:true))
        }
        let tools = await commands.run("/usr/bin/xcode-select",["-p"],log:{ _ in })
        let toolsReady = tools.0 == 0 && !tools.1.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        checks.append(StartupCheck(id:"tools",title:"Apple developer tools",detail:toolsReady ? "A developer tools directory is selected." : "Command Line Tools may be needed by Homebrew. Copy the setup command and run it in Terminal.",ready:toolsReady,required:false))
        let parent = URL(fileURLWithPath:environment.appPath).deletingLastPathComponent().path
        let located = parent == "/Applications" || parent == NSHomeDirectory() + "/Applications"
        checks.append(StartupCheck(id:"location",title:"App location",detail:located ? "Orbit is in Applications." : "For regular use, move Orbit.app to Applications and keep one copy.",ready:located,required:false))
        checks.append(StartupCheck(id:"helper",title:"Administrator prompt",detail:environment.helperReady ? "Native password helper is available. Permissions are requested only when an operation needs them." : "The password helper is missing or cannot run. Download a fresh copy of Orbit.",ready:environment.helperReady,required:true))
        return checks
    }
    static func shouldPresent(completed: Bool, checks: [StartupCheck]) -> Bool { checks.isEmpty || !completed || checks.contains { $0.required && !$0.ready } }
}

@MainActor extension Store {
    func startup() async {
        guard !startupStarted, !preview else { return }; startupStarted = true
        await checkStartup()
        showStartup = StartupInspector.shouldPresent(completed: setupDefaults.bool(forKey:"startup-completed-v1"), checks:startupChecks)
        if !showStartup, startupChecks.first(where: { $0.id == "brew" })?.ready == true { await refresh() }
    }
    func checkStartup() async {
        guard !locked, !checkingStartup, !preview else { return }
        checkingStartup = true
        defer { checkingStartup = false }
        startupChecks = await StartupInspector.checks(startupEnvironment?() ?? .current(brew:brew), commands:commandRunner)
        permissions.refresh()
        if startupChecks.contains(where: { $0.required && !$0.ready }) { inventoryKnown = false }
    }
    func openStartup() async {
        guard !locked else { return }
        showStartup = true
        await checkStartup()
    }
    func finishStartup() async {
        guard !checkingStartup else { return }
        if !preview { setupDefaults.set(true,forKey:"startup-completed-v1") }
        showStartup = false
        if startupReady, startupChecks.first(where: { $0.id == "brew" })?.ready == true { await refresh() }
    }
}
struct StartupView: View {
    @ObservedObject var store: Store
    var body: some View { SetupCenterView(store:store,onboarding:true).frame(width:720,height:680) }
}
