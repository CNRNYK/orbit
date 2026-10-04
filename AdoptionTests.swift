import Foundation

enum AdoptionTests {
    @MainActor static func run() async {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath().path
        defer { try? fm.removeItem(atPath: root) }
        let original = Catalog.packages.first { $0.token == "figma" }!
        var json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json["appName"] = "Fixture"
        let package = try! JSONDecoder().decode(Package.self, from: JSONSerialization.data(withJSONObject: json))
        let path = root + "/Fixture.app"
        try! fm.createDirectory(atPath: path + "/Contents", withIntermediateDirectories: true)
        let plist = try! PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"org.fixture.app", "CFBundleShortVersionString":"1.0", "CFBundlePackageType":"APPL"], format: .xml, options: 0)
        try! plist.write(to: URL(fileURLWithPath: path + "/Contents/Info.plist"))
        let apps = AppScanner.scan(roots: [root], packages: [package], references: [package.token:"org.fixture.app"])
        precondition(apps.count == 1 && apps[0].identityMatched && apps[0].package?.id == package.id && apps[0].unchanged)
        let wrong = AppScanner.scan(roots: [root], packages: [package], references: [package.token:"org.other"])
        precondition(!wrong[0].identityMatched)
        let unknown = AppScanner.scan(roots: [root], packages: [], references: [:])
        precondition(unknown.count == 1 && unknown[0].package == nil)
        let plan = ManualRemovalPlan.inspect(apps[0],home:root,roots:[root])!
        precondition(plan.unchanged() && ManualRemovalPlan.inspect(apps[0],home:root) == nil)
        let cache = root + "/Library/Caches/org.fixture.app"
        let data = root + "/Library/Application Support/org.fixture.app"
        for folder in [cache,data] { try! fm.createDirectory(atPath:folder,withIntermediateDirectories:true) }
        let reviewed = ManualRemovalPlan.inspect(apps[0],home:root,roots:[root])!
        precondition(reviewed.leftovers.count == 2 && reviewed.leftovers.filter { !$0.dataSensitive }.map(\.path) == [cache])
        try! fm.createDirectory(atPath:root + "/Library/Application Support/org.fixture",withIntermediateDirectories:true)
        precondition(ManualRemovalPlan.inspect(apps[0],home:root,roots:[root])!.leftovers.count == 2,"Shared vendor directories must be excluded")
        let app = apps[0]
        let item = AdoptionItem(app: app, installer: false, version: "1", problem: nil)
        precondition(item.arguments == ["install", "--cask", "--appdir=" + root, "--adopt", "figma"])
        precondition(!item.arguments.contains("--force"))
        precondition(!AdoptionItem(app: app, installer: true, version: "1", problem: nil).arguments.contains("--adopt"))
        let state = Store(persistSelection: false); state.inventoryKnown = true; state.appPresent = { _ in false }
        state.localApps = apps
        precondition(!state.canInstall(package))
        state.localApps = []; state.installed = [original.id]
        precondition(!state.canInstall(original))
        state.selected = [original.id]; state.sanitizeInstallSelection(); precondition(state.installSelection.isEmpty && state.selected.isEmpty)
        state.exportSelected = [original.id]
        precondition(Catalog.export(Catalog.packages.filter { state.exportSelected.contains($0.id) }).contains(original.brewLine))
        state.notInstalledOnly = true; precondition(!state.visible.contains(original))

        let metadata = #"{"casks":[{"token":"figma","version":"1.0","artifacts":[{"app":["Fixture.app"]}]}]}"#
        for success in [true, false] {
            let store = Store(persistSelection: false); store.brewExecutable = "/mock/brew"; store.mode = .uninstall
            store.appScanner = { apps }; store.localApps = apps; store.selectedManual = [app.id]
            let runner = FakeCommands([(0,""),(0,""),(0,metadata),(0,""),(0,""),(success ? 0 : 1, success ? "" : "Error: Existing contents differ"),(0,""),(0,success ? "figma\n" : "")])
            store.commandRunner = runner
            await store.prepareAdoption()
            precondition(store.showAdoptionReview && store.adoptionPlan.count == 1 && store.adoptionPlan[0].problem == nil)
            let planned = await runner.recorded()
            precondition(!planned.contains { $0.first == "install" }, "Review alone must never run adoption")
            await store.adoptSelected()
            let calls = await runner.recorded()
            precondition(calls.filter { $0.first == "install" } == [item.arguments])
            precondition(app.unchanged, "Failed adoption must preserve the fixture app")
            precondition(success ? store.installed.contains(original.id) : !store.installed.contains(original.id))
        }
        let blocked = Store(persistSelection: false); blocked.brewExecutable = "/mock/brew"
        blocked.appScanner = { wrong }; blocked.localApps = wrong; blocked.selectedManual = [wrong[0].id]
        blocked.commandRunner = FakeCommands([(0,""),(0,""),(0,#"{"casks":[{"token":"figma","version":"1.0","artifacts":[{"pkg":["Fixture.pkg"]}]}]}"#)])
        await blocked.prepareAdoption()
        precondition(blocked.adoptionPlan.first?.problem != nil, "Unverified installer identities must be blocked")
        print("PASS: manual app scan and identity references, unknown apps, independent export, installed selection gating, reviewed exact adoption, failure preservation and installer identity blocking")
    }
}
