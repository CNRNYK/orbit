import Foundation

actor FakeCommands: CommandExecuting {
    var replies: [(Int32, String)]
    var calls = [[String]]()
    init(_ replies: [(Int32, String)]) { self.replies = replies }
    func run(_ executable: String, _ arguments: [String], log: @escaping @Sendable (String) -> Void) async -> (Int32, String) {
        calls.append(arguments)
        guard !replies.isEmpty else { return (0, "") }
        let reply = replies.removeFirst(); log(reply.1); return reply
    }
    func recorded() -> [[String]] { calls }
}

enum LifecycleTests {
    @MainActor static func run() async {
        let app = Catalog.packages.first { $0.token == "blender" }!
        let git = Catalog.packages.first { $0.token == "git" && !$0.cask }!
        let fixture = #"{"formulae":[{"name":"git","installed_versions":["1.0"],"current_version":"999.0","pinned":false},{"name":"git","installed_versions":["1.0"],"current_version":"999.0","pinned":true},{"name":"not-in-catalog","installed_versions":["1"],"current_version":"2"}],"casks":[{"name":"blender","installed_versions":"1.0","current_version":"999.0"},{"name":"vlc","installed_versions":"1","current_version":"latest"}]}"#
        let updates = try! UpdatePlan.parse(Data(fixture.utf8))
        precondition(Set(updates.map(\.id)) == [app.id, git.id])
        precondition(updates.first { $0.id == git.id }!.installedVersion == "1.0")
        precondition(UpdatePlan.arguments(updates.first { $0.id == app.id }!) == ["upgrade", "--cask", "--greedy-auto-updates", "blender"])
        do { _ = try UpdatePlan.parse(Data("invalid".utf8)); preconditionFailure() } catch {}
        do { _ = try UpdatePlan.parse(Data("{}".utf8)); preconditionFailure() } catch {}

        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath().path
        try! files.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? files.removeItem(atPath: home) }
        let identifier = "org.orbit.testfixture"
        for folder in Cleanup.folders { try! files.createDirectory(atPath: home + "/Library/" + folder, withIntermediateDirectories: true) }
        let cachePath = home + "/Library/Caches/" + identifier
        try! files.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
        try! Data(repeating: 1, count: 128).write(to: URL(fileURLWithPath: cachePath + "/cache"))
        let settingsPath = home + "/Library/Preferences/" + identifier + ".plist"
        try! Data("settings".utf8).write(to: URL(fileURLWithPath: settingsPath))
        let bundle = home + "/Applications/" + app.appName! + ".app/Contents"
        try! files.createDirectory(atPath: bundle, withIntermediateDirectories: true)
        let plist = try! PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleName": "Test", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try! plist.write(to: URL(fileURLWithPath: bundle + "/Info.plist"))
        let found = Cleanup.scan([app], home: home, appRoots: [home + "/Applications"])
        precondition(found.count == 2)
        let cache = found.first { $0.kind == "Caches" }!
        let settings = found.first { $0.kind == "Preferences" }!
        precondition(cache.bytes == 128 && !cache.dataSensitive && settings.dataSensitive)
        precondition(Cleanup.unchanged(cache, home: home))
        precondition(!Cleanup.safe(home + "/Library/Caches", home: home))
        precondition(!Cleanup.safe(home + "/Documents/valuable", home: home))
        precondition(!Cleanup.safe(home + "/Library/Caches/../Preferences/valuable", home: home))
        try! files.createSymbolicLink(atPath: home + "/Library/Caches/symlink", withDestinationPath: home)
        precondition(!Cleanup.safe(home + "/Library/Caches/symlink", home: home))
        // Renaming the reviewed directory away and replacing it must reject the new inode.
        try! files.moveItem(atPath: cachePath, toPath: cachePath + ".old")
        try! files.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
        precondition(!Cleanup.unchanged(cache, home: home))

        func removalStore(_ replies: [(Int32, String)]) -> (Store, FakeCommands) {
            let store = Store(persistSelection: false); store.mode = .uninstall; let commands = FakeCommands(replies)
            store.brewExecutable = "/mock/brew"; store.commandRunner = commands
            store.inventoryKnown = true; store.installed = [app.id]; store.selected = [app.id]
            store.removalPlan = [app]; store.cleanRemoval = true; store.leftovers = [cache, settings]
            store.selectedLeftovers = [cache.id]; store.showRemovalReview = true
            return (store, commands)
        }
        let preparing = Store(persistSelection: false); preparing.mode = .uninstall
        preparing.brewExecutable = "/mock/brew"; preparing.commandRunner = FakeCommands([(0, ""), (0, "blender\n")])
        preparing.selected = [app.id]; preparing.cleanRemoval = true; preparing.scanLeftovers = { _ in found }
        await preparing.prepareRemoval()
        precondition(preparing.showRemovalReview && preparing.selectedLeftovers == [cache.id])
        let (failed, failedCommands) = removalStore([(1, "Removal failed"), (0, ""), (0, "blender\n")])
        var deleted = [String]()
        failed.trashLeftover = { deleted.append($0.id) }
        await failed.uninstall()
        precondition(deleted.isEmpty && failed.statuses[app.id] == "Failed")
        let failedCalls = await failedCommands.recorded()
        precondition(failedCalls.first == ["uninstall", "--cask", "blender"])
        let (success, _) = removalStore([(0, ""), (0, ""), (0, "")])
        success.trashLeftover = { deleted.append($0.id) }
        await success.uninstall()
        precondition(deleted == [cache.id], "Only checked leftovers belonging to successfully removed apps may be touched")
        let (cleanupFailure, _) = removalStore([(0, ""), (0, ""), (0, "")])
        cleanupFailure.trashLeftover = { _ in throw NSError(domain: "Test", code: 1) }
        await cleanupFailure.uninstall()
        precondition(cleanupFailure.statuses[app.id] == "Removed; cleanup incomplete" && !cleanupFailure.cleanupMessages.isEmpty)

        let checking = Store(persistSelection: false)
        let commands = FakeCommands([(0, ""), (0, "git\n"), (0, "blender\n"), (1, fixture)])
        checking.brewExecutable = "/mock/brew"; checking.commandRunner = commands
        checking.includeSelfUpdating = true
        await checking.checkUpdates()
        precondition(checking.updatesChecked && checking.updates.count == 2)
        let checkCalls = await commands.recorded()
        precondition(checkCalls.last == ["outdated", "--json=v2", "--greedy-auto-updates"])
        checking.selectedUpdates = [git.id]; checking.prepareUpdates()
        precondition(checking.showUpdateReview && checking.updateQueue.map(\.id) == [git.id])
        let upgradeCommands = FakeCommands([(0, "Updated"), (0, "git\n"), (0, "blender\n")])
        checking.commandRunner = upgradeCommands
        await checking.upgrade()
        let upgradeCalls = await upgradeCommands.recorded()
        precondition(upgradeCalls.first == ["upgrade", "--formula", "git"])
        precondition(checking.statuses[git.id] == "Updated" && !checking.updates.contains { $0.id == git.id })
        let malformed = Store(persistSelection: false)
        malformed.brewExecutable = "/mock/brew"; malformed.commandRunner = FakeCommands([(0, ""), (0, "git\n"), (0, ""), (0, "not-json")])
        await malformed.checkUpdates()
        precondition(!malformed.updatesChecked && malformed.notice != nil && malformed.updates.isEmpty)
        print("PASS: update parsing/planning/execution, invalid responses, pinned/latest exclusion, exact cleanup matching, sizes, sensitive defaults, symlink/inode protection, failure-gated selected cleanup")
    }
}
