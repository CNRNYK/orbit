import Foundation
@MainActor enum StartupTests {
    static func run() async {
        let healthy = StartupEnvironment(brew:"/fixture/brew",appPath:"/Applications/Mac Setup.app",helperReady:true,macOSMajor:15)
        let commands = FakeCommands([(0,"Homebrew 7.0.0\n"),(0,"/Library/Developer/CommandLineTools\n")])
        let checks = await StartupInspector.checks(healthy,commands:commands)
        precondition(checks.count == 5 && checks.allSatisfy(\.ready))
        let calls = await commands.recorded()
        precondition(calls == [["--version"],["-p"]],"Startup must only execute read-only checks")
        precondition(StartupInspector.shouldPresent(completed:false,checks:checks))
        precondition(!StartupInspector.shouldPresent(completed:true,checks:checks))
        precondition(StartupInspector.shouldPresent(completed:true,checks:[]))
        let absent = StartupEnvironment(brew:nil,appPath:"/Downloads/Mac Setup.app",helperReady:false,macOSMajor:14)
        let absentCommands = FakeCommands([(1,"No developer directory")])
        let missing = await StartupInspector.checks(absent,commands:absentCommands)
        precondition(missing.filter { $0.required && !$0.ready }.map(\.id) == ["brew","helper"])
        precondition(StartupInspector.shouldPresent(completed:true,checks:missing))
        let absentCalls = await absentCommands.recorded()
        precondition(absentCalls == [["-p"]],"Missing brew must not trigger installation")
        let broken = FakeCommands([(1,"broken"),(0,"/tools")])
        let bad = await StartupInspector.checks(healthy,commands:broken)
        precondition(bad.first { $0.id == "brew" }?.ready == false)
        let optional = FakeCommands([(0,"Homebrew 7.0.0"),(1,"Missing tools")])
        let optionalEnvironment = StartupEnvironment(brew:healthy.brew,appPath:"/Downloads/Mac Setup.app",helperReady:true,macOSMajor:14)
        let optionalChecks = await StartupInspector.checks(optionalEnvironment,commands:optional)
        precondition(!StartupInspector.shouldPresent(completed:true,checks:optionalChecks),"Optional suggestions must not repeatedly interrupt launches")
        let suite = "startup-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let store = Store(persistSelection:false)
        store.setupDefaults = defaults
        store.startupEnvironment = { absent }
        let flowCommands = FakeCommands([(1,"Missing tools"),(1,"Missing tools")])
        store.commandRunner = flowCommands
        await store.startup()
        precondition(store.showStartup && !store.checkingStartup && store.startupStarted)
        await store.finishStartup()
        precondition(!store.showStartup && defaults.bool(forKey:"startup-completed-v1"))
        await store.startup()
        let startupCalls = await flowCommands.recorded()
        precondition(startupCalls.count == 1,"Starting a second window must not repeat initial setup")
        await store.openStartup()
        precondition(store.showStartup)
        let reopened = await flowCommands.recorded()
        precondition(reopened.count == 2)
        store.inventoryKnown = true
        let git = Catalog.packages.first { $0.token == "git" }!
        store.appPresent = { _ in false }
        precondition(!store.canInstall(git), "Failed required checks must block install selection even if inventory was cached")
        store.selected = [git.id]; store.showReview = true
        await store.prepare(); await store.install(); await store.checkUpdates(); await store.refresh()
        let gated = await flowCommands.recorded(); precondition(gated.count == 2, "Failed prerequisites must prevent Homebrew operations")
        let completedStore = Store(persistSelection:false)
        completedStore.setupDefaults = defaults; completedStore.brewExecutable = "/fixture/brew"
        completedStore.startupEnvironment = { healthy }; completedStore.appScanner = { [] }
        let completedCommands = FakeCommands([(0,"Homebrew 7.0.0"),(0,"/tools"),(0,"git\n"),(0,"")])
        completedStore.commandRunner = completedCommands
        await completedStore.startup()
        precondition(!completedStore.showStartup && completedStore.inventoryKnown && completedStore.installed.contains(git.id))
        let completedCalls = await completedCommands.recorded()
        precondition(completedCalls == [["--version"],["-p"],["list","--formula","-1"],["list","--cask","-1"]])
        let preview = Store(preview:true,persistSelection:false)
        preview.setupDefaults = defaults
        let previewCommands = FakeCommands([]); preview.commandRunner = previewCommands
        await preview.startup(); await preview.checkStartup()
        let previewCalls = await previewCommands.recorded()
        precondition(previewCalls.isEmpty)
        print("PASS: first-launch checks, read-only command scope, missing/broken Homebrew, optional guidance, persisted completion, repeat-window guard, setup reopening and nonoperating previews")
    }
}
