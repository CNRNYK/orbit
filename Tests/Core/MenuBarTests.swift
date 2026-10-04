import Foundation
import AppKit

@MainActor enum MenuBarTests {
    static func run() async throws {
        let model = Store(preview: true, persistSelection: false)
        model.brewExecutable = "/fixture/brew"; model.selected = []; model.inventoryKnown = true
        let state = MenuBarState(store: model)
        precondition(state.canNavigate && state.canCheckUpdates && !state.operating && !state.canStop)
        precondition(state.updatesLabel == "Updates · not checked")
        let package = Catalog.packages.first { $0.token == "git" }!
        model.updates = [UpdateItem(package: package, installedVersion: "1", availableVersion: "2")]
        model.installed = [package.id]; model.updatesChecked = true; model.search = "nonmatching search"
        precondition(state.updateCount == 1 && state.updatesLabel == "Updates · 1 available", "Menu counts must be independent of current search")
        model.busy = true; model.total = 3; model.completed = 1; model.headline = "Updating Git…"
        precondition(state.operating && !state.canNavigate && !state.canCheckUpdates && state.canStop && state.status == "Updating Git…")
        let controller = MenuBarController(store: model)
        model.mode = .install; controller.perform(.cleanup)
        precondition(model.mode == .install, "Navigation must not interrupt operations")
        model.maintenanceState.working = true
        precondition(!state.canStop && state.status == "Cleanup in progress", "Cleanup must not display stale package counters or a stop button")
        model.busy = false; model.maintenanceState.working = false; model.preparing = true
        precondition(state.operating && !state.canNavigate && !state.canStop)
        model.preparing = false; model.terminalState.working = true
        precondition(state.operating && !state.canCheckUpdates && !state.canStop)
        model.terminalState.working = false; model.startupChecks = [StartupCheck(id: "required", title: "Required", detail: "Missing", ready: false, required: true)]
        precondition(state.canNavigate && !state.canCheckUpdates && state.status == "Setup needs attention")
        for active in [false, true] { let icon = MenuBarController.icon(active: active); precondition(icon.isTemplate && icon.size == NSSize(width: 22, height: 22)) }
        print("PASS: menu bar update count independent of search, operation/setup guards, cleanup progress isolation and template icon")
    }
}
