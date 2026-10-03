import Foundation

final class WorkflowLogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; lines.append(value) }
    func text() -> String { lock.lock(); defer { lock.unlock() }; return lines.joined() }
}
@MainActor enum WorkflowUITests {
    static func run() async throws {
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
