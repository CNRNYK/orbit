import Foundation

final class WorkflowLogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; lines.append(value) }
    func text() -> String { lock.lock(); defer { lock.unlock() }; return lines.joined() }
}
@MainActor enum WorkflowUITests {
    static func run() async throws {
        let center = Store(preview:true,persistSelection:false); center.selected = []; center.inventoryKnown = true; center.appPresent = { _ in false }
        let pending = Catalog.packages.first { $0.token == "git" && !$0.cask }!
        let removable = Catalog.packages.first { $0.token == "figma" }!
        center.installed = [removable.id]; center.toggle(pending)
        center.navigate(.explore); center.search = "git"; precondition(center.exploreSearch == "git")
        center.selectHomebrewTab(.library); center.toggle(removable)
        precondition(center.selected == [removable.id] && center.centerInstallSelection.map(\.id) == [pending.id], "Removal choices must remain separate from shared install choices")
        center.recorderState.phase = .recording; center.revealActiveRecorder()
        precondition(center.selected == [pending.id] && center.mode == .recorder, "Active recorder navigation must preserve installation choices when leaving Installed")
        center.recorderState.phase = .idle; center.selectHomebrewTab(.library); precondition(center.selected == [removable.id])
        center.selectHomebrewTab(.updates); precondition(center.selected == [pending.id] && center.homebrewTab == .updates)
        center.selectHomebrewTab(.discover); precondition(center.mode == .install, "Discover combines both catalog sources")
        center.navigate(.install,category:"My apps"); precondition(center.homebrewTab == .library && center.selected == [pending.id])
        center.selectHomebrewTab(.library); precondition(center.selected == [removable.id]); center.removeCenterInstall(pending)
        precondition(center.centerInstallSelection.isEmpty && center.selected == [removable.id])
        center.navigate(.cleanup); center.openHomebrewCenter(); precondition(center.homebrewTab == .library)
        center.busy = true; center.selectHomebrewTab(.updates); precondition(center.homebrewTab == .library)
        center.busy = false; center.selectHomebrewTab(.discover); precondition(center.selected.isEmpty)
        let suite = "OrbitHomebrewCenterTests-" + UUID().uuidString
        let prefs = UserDefaults(suiteName:suite)!; defer { prefs.removePersistentDomain(forName:suite) }
        let persisted = Store(preferences:prefs); persisted.inventoryKnown = true; persisted.appPresent = { _ in false }; persisted.selected = [pending.id]; persisted.installed = [removable.id]
        persisted.navigate(.uninstall); persisted.toggle(removable)
        precondition(Set(prefs.stringArray(forKey:"selection") ?? []) == [pending.id], "Removal selections must never overwrite persisted installation choices")
        let reopened = Store(preferences:prefs); precondition(reopened.selected == [pending.id])
        let extra = try OfficialCatalog.parse(Data(#"[{"name":"center-fixture","tap":"homebrew/core","versions":{"stable":"1"}}]"#.utf8),cask:false)[0]
        center.registerPersonal(extra,favorite:true); center.navigate(.install); center.search = ""; precondition(!center.visible.contains { $0.id == extra.id })
        center.navigate(.install,category:"My apps"); precondition(center.visible.contains { $0.id == extra.id })
        center.explorePackages = [extra,pending]; center.search = "center-fixture"; center.navigate(.install)
        precondition(center.discoverMatches.map(\.id) == [extra.id])
        center.search = "git"; precondition(center.discoverMatches.filter { $0.id == pending.id }.count == 1)
        center.search = ""; precondition(!center.discoverMatches.contains { $0.id == extra.id }); precondition(center.displayedDiscoverMatches.count > 300,"All recommended packages must remain browsable")
        center.navigate(.uninstall); center.myAppIDs = [pending.id]; center.libraryFilter = .all
        precondition(Set(center.libraryPackages.map(\.id)) == [pending.id,removable.id])
        center.libraryFilter = .saved; precondition(center.libraryPackages.map(\.id) == [pending.id])
        center.libraryFilter = .installed; precondition(center.libraryPackages.map(\.id) == [removable.id])
        print("PASS: Homebrew Center tabs, remembered source/shared search, curated catalog scope, independent removal/install selections and persisted installation choices")
        let cleanup = MaintenanceState()
        let cache = MaintenanceItem(path:"/fixture/cache",group:"Homebrew cache",bytes:1,inode:1,device:1,removable:true)
        let app = MaintenanceItem(path:"/fixture/app",group:"App caches & logs",bytes:1,inode:1,device:1,removable:true)
        let large = MaintenanceItem(path:"/fixture/document",group:"Large files",bytes:1,inode:1,device:1,removable:false)
        cleanup.items = [cache,app,large]
        cleanup.selectCleanable(group:"Homebrew cache"); precondition(cleanup.selected == [cache.id])
        cleanup.selectCleanable(); precondition(cleanup.selected == [cache.id,app.id] && !cleanup.selected.contains(large.id))
        cleanup.clearGroup("Homebrew cache"); precondition(cleanup.selected == [app.id])
        cleanup.working = true; cleanup.selectCleanable(); cleanup.clearGroup("App caches & logs"); precondition(cleanup.selected == [app.id])
        let model = Store(persistSelection:false); model.selected = []; model.inventoryKnown = true; model.appPresent = { _ in false }
        let dynamic = try OfficialCatalog.parse(Data(#"[{"token":"workflow-fixture","tap":"homebrew/cask","name":["Workflow Fixture"],"homepage":"https://example.com","version":"1"}]"#.utf8),cask:true)[0]
        model.navigate(.explore); model.toggle(dynamic)
        precondition(model.installSelection.map(\.id) == [dynamic.id])
        model.registerPersonal(dynamic,favorite:true); model.removeFavorite(dynamic)
        precondition(!model.myAppIDs.contains(dynamic.id) && model.selected.contains(dynamic.id), "Removing a favorite must not alter installation selection or uninstall")
        model.toggle(dynamic); precondition(model.installSelection.isEmpty)
        model.total = 4; model.completed = 2
        precondition(model.progressSummary == "2/4 processed · 2 remaining")
        model.statuses = [dynamic.id:"Failed"]
        precondition(model.operationResults.first?.name == dynamic.name && model.operationResults.first?.status == "Failed")
        model.output = "Error: fixture failed\nError: fixture failed\nExit status: 0\nExit status: 1\n"
        precondition(model.operationIssues == ["Error: fixture failed","Exit status: 1"])
        let capture = WorkflowLogCapture()
        let reply = await BrewRunner.run("/bin/sh",["-c","printf '{\"fixture\":true}'; printf 'fixture warning\\n' >&2"],separateError:true,log:{ capture.append($0) })
        precondition(reply.0 == 0 && reply.1 == "{\"fixture\":true}")
        precondition(capture.text().contains("fixture warning") && !capture.text().contains("fixture\""), "Inventory and metadata stdout must not pollute logs; stderr must remain visible")
        print("PASS: safe cleanup bulk selection, Explore toggle and favorites, shared selection, aggregate progress, result/error summaries and diagnostic-only metadata logging")
    }
}
