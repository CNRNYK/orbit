import Foundation

actor RepairCommands: CommandExecuting {
    let package: Package
    let root: String
    let source: String
    let finishRemoval: Bool
    let forceExit: Int32
    var forced = false
    var calls = [[String]]()
    init(package: Package, root: String, source: String, finishRemoval: Bool, forceExit: Int32 = 0) {
        self.package = package; self.root = root; self.source = source; self.finishRemoval = finishRemoval; self.forceExit = forceExit
    }
    func run(_ executable: String, _ arguments: [String], log: @escaping @Sendable (String) -> Void) async -> (Int32, String) {
        calls.append(arguments)
        if arguments == ["--caskroom"] { return (0, root + "\n") }
        if arguments == ["list", "--formula", "-1"] { return (0, "") }
        if arguments == ["list", "--cask", "-1"] { return (0, forced && finishRemoval && forceExit == 0 ? "" : package.token + "\n") }
        if arguments == ["uninstall", "--cask", "--force", package.token] {
            forced = true
            if finishRemoval && forceExit == 0 { try! FileManager.default.removeItem(atPath: source) }
            return (forceExit, forceExit == 0 ? "" : "Error: Permission denied")
        }
        if arguments == ["uninstall", "--cask", package.token] {
            return (1, "Error: It seems there is already an App at '\(source)'.\n")
        }
        preconditionFailure("Unexpected repair command: \(arguments)")
    }
    func recorded() -> [[String]] { calls }
}

enum RepairTests {
    @MainActor static func run() async {
        let original = Catalog.packages.first { $0.token == "figma" }!
        var object = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        object["appName"] = "MacSetupRepairFixture-" + UUID().uuidString
        let package = try! JSONDecoder().decode(Package.self, from: JSONSerialization.data(withJSONObject: object))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath().path
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let root = directory + "/Caskroom"
        let source = root + "/figma/126.9.11/" + package.appName! + ".app"
        func createSource() { try! FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true) }
        createSource()
        let conflict = "Warning: unrelated tap deprecation\nError: It seems there is already an App at '\(source)'.\n"
        let repair = RemovalRepair.inspect(package, error: conflict, caskroom: root, cleanup: [])!
        precondition(repair.unchanged)
        precondition(RemovalRepair.conflictPath("Error: Permission denied") == nil)
        precondition(RemovalRepair.inspect(package, error: conflict, caskroom: directory + "/other", cleanup: []) == nil)
        precondition(RemovalRepair.inspect(package, error: "Error: Permission denied\n" + conflict, caskroom: root, cleanup: []) == nil)
        // Replacement and symlink redirection invalidate the reviewed source.
        try! FileManager.default.moveItem(atPath: source, toPath: source + ".old")
        createSource(); precondition(!repair.unchanged)
        try! FileManager.default.removeItem(atPath: source)
        try! FileManager.default.createSymbolicLink(atPath: source, withDestinationPath: source + ".old")
        precondition(RemovalRepair.inspect(package, error: conflict, caskroom: root, cleanup: []) == nil)
        try! FileManager.default.removeItem(atPath: source); createSource()

        let dataPath = directory + "/reviewed-cache"
        try! Data("fixture".utf8).write(to: URL(fileURLWithPath: dataPath))
        let leftover = Leftover(packageID: package.id, appName: package.name, path: dataPath, kind: "Caches", bytes: 7, inode: 0, device: 0, dataSensitive: false)
        let commands = RepairCommands(package: package, root: root, source: source, finishRemoval: true)
        let store = Store(persistSelection: false); store.mode = .uninstall; store.brewExecutable = "/mock/brew"; store.commandRunner = commands
        store.removalPlan = [package]; store.selected = [package.id]; store.cleanRemoval = true
        store.leftovers = [leftover]; store.selectedLeftovers = [leftover.id]; store.showRemovalReview = true
        var cleaned = [String](); store.trashLeftover = { cleaned.append($0.id) }
        await store.uninstall()
        precondition(store.repairOptions[package.id] != nil && cleaned.isEmpty)
        let beforeApproval = await commands.recorded()
        precondition(!beforeApproval.contains { $0.contains("--force") }, "Recognizing a conflict must never force removal automatically")
        await store.prepareRepair(package.id)
        precondition(store.repairReview != nil && store.repairReview!.cleanup.map(\.id) == [leftover.id])
        await store.repairAndRetry()
        precondition(store.statuses[package.id] == "Removed" && cleaned == [leftover.id])
        precondition(!store.installed.contains(package.id) && store.repairOptions.isEmpty)
        let afterApproval = await commands.recorded()
        precondition(afterApproval.filter { $0.contains("--force") } == [["uninstall", "--cask", "--force", package.token]])

        for exitCode: Int32 in [0, 1] {
            createSource()
            let failure = Store(persistSelection: false)
            let runner = RepairCommands(package: package, root: root, source: source, finishRemoval: false, forceExit: exitCode)
            failure.brewExecutable = "/mock/brew"; failure.commandRunner = runner
            let candidate = RemovalRepair.inspect(package, error: conflict, caskroom: root, cleanup: [leftover])!
            failure.repairReview = candidate
            failure.trashLeftover = { _ in preconditionFailure("Unverified repairs must not clean user data") }
            await failure.repairAndRetry()
            precondition(failure.statuses[package.id] == "Repair failed" && failure.notice != nil)
        }
        let blocked = Store(persistSelection: false)
        let unused = RepairCommands(package: package, root: root, source: source, finishRemoval: true)
        blocked.brewExecutable = "/mock/brew"; blocked.commandRunner = unused
        // No review consent means no force command.
        await blocked.repairAndRetry()
        let unusedCalls = await unused.recorded(); precondition(unusedCalls.isEmpty)
        print("PASS: repair detection, path/inode/symlink checks, explicit consent, exact forced cask retry, verified success and cleanup gating")
    }
}
