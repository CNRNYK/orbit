import Foundation
@MainActor enum ExploreTests {
    static func run() async throws {
        let formulaJSON = Data(#"[{"name":"fixture-cli","tap":"homebrew/core","desc":"A fixture tool","homepage":"https://example.com","versions":{"stable":"1.2"},"license":"MIT","dependencies":["unselected-dependency"]},{"name":"--bad","tap":"homebrew/core"},{"name":"third-party","tap":"user/tap"}]"#.utf8)
        let caskJSON = Data(#"[{"token":"fixture-app","tap":"homebrew/cask","name":["Fixture App"],"desc":"A fixture app","homepage":"https://example.com","version":"2.0","artifacts":[{"app":["Original.app",{"target":"Fixture.app"}]}]},{"token":"disabled-fixture","tap":"homebrew/cask","disabled":true},{"token":"tap/package","tap":"homebrew/cask"}]"#.utf8)
        let formulas = try OfficialCatalog.parse(formulaJSON,cask:false)
        let casks = try OfficialCatalog.parse(caskJSON,cask:true)
        precondition(formulas.count == 1 && casks.count == 2)
        precondition(formulas[0].version == "1.2" && casks[0].appName == "Fixture")
        precondition(casks[1].installable == false)
        precondition(!OfficialCatalog.validToken("--force") && !OfficialCatalog.validToken("user/tap/name") && !OfficialCatalog.validToken("name; touch /tmp/x"))
        precondition((try? OfficialCatalog.parse(Data("{}".utf8),cask:true)) == nil)
        let model = Store(persistSelection:false); model.selected = []
        model.appPresent = { _ in false }; model.appScanner = { [] }; model.inventoryKnown = true
        let formula = formulas[0], app = casks[0]
        let initialCount = model.packages.count
        model.registerPersonal(formula,favorite:true); model.registerPersonal(formula,favorite:true)
        model.registerPersonal(app,favorite:true); model.registerPersonal(casks[1],favorite:true)
        precondition(model.packages.count == initialCount + 2 && model.personalPackages.count == 2 && model.myAppIDs == [formula.id,app.id])
        precondition(!model.packages.contains { $0.token == "unselected-dependency" })
        model.navigate(.install,category:"My apps")
        precondition(Set(model.visible.map(\.id)) == [formula.id,app.id])
        model.toggle(formula); precondition(model.installSelection.map(\.id) == [formula.id])
        model.navigate(.cleanup); model.navigate(.explore); model.navigate(.install,category:"My apps")
        precondition(model.selected == [formula.id],"Informational pages must preserve install selections")
        model.removeFavorite(formula)
        precondition(!model.myAppIDs.contains(formula.id) && model.packages.contains { $0.id == formula.id },"Removing a favorite must preserve package tracking")
        model.installed = [app.id]; precondition(!model.canInstall(app))
        let exported = Catalog.export([formula,app,formula])
        let imported = Catalog.parse(exported,packages:model.packages)
        precondition(imported.0 == [formula.id,app.id] && imported.1.isEmpty)
        precondition(!exported.contains("unselected-dependency"))
        let persisted = try JSONEncoder().encode(model.personalPackages)
        precondition(OfficialCatalog.saved(persisted).count == 2)
        var forged = try JSONSerialization.jsonObject(with: persisted) as! [[String:Any]]
        forged[0]["token"] = "--force"
        let sanitized = OfficialCatalog.saved(try JSONSerialization.data(withJSONObject:forged))
        precondition(sanitized.count == 1 && sanitized[0].id == model.personalPackages[1].id)
        model.exploreLoader = { ExploreSnapshot(packages:formulas + casks,fetched:Date()) }
        await model.loadExplore()
        precondition(model.explorePackages.count == 3 && model.exploreFetched != nil && !model.loadingExplore)
        model.exploreSearch = "fixture"; precondition(model.exploreMatches.count == 2)
        model.exploreKind = "Tools"; precondition(model.exploreMatches.map(\.id) == [formula.id])
        model.exploreKind = "All"; model.exploreAvailableOnly = false; precondition(model.exploreMatches.count == 3)
        model.exploreLoader = { throw URLError(.notConnectedToInternet) }
        await model.loadExplore(force:true)
        precondition(model.explorePackages.count == 3 && !model.exploreMessage.isEmpty && !model.loadingExplore)
        model.maintenanceState.items = [MaintenanceItem(path:"/fixture/cache",group:"App caches & logs",bytes:1,inode:1,device:1,removable:true)]
        model.navigate(.cleanup); model.navigate(.explore); model.navigate(.cleanup)
        precondition(model.maintenanceState.items.count == 1)
        model.navigate(.explore); model.installed = []; model.review = [ReviewItem(package:formula,managed:false,manual:false,installer:false,version:"1.2",problem:nil)]; model.showReview = true
        let commands = FakeCommands([(0,"Installed"),(0,"fixture-cli\n"),(0,"")])
        model.brewExecutable = "/fixture/brew"; model.commandRunner = commands
        await model.install()
        let calls = await commands.recorded()
        precondition(calls == [["install","--formula","homebrew/core/fixture-cli"],["list","--formula","-1"],["list","--cask","-1"]])
        precondition(model.installed.contains(formula.id) && model.selected.isEmpty, "Installed explorer packages must leave the installation selection")
        let updates = try UpdatePlan.parse(Data(#"{"formulae":[{"name":"fixture-cli","current_version":"2","installed_versions":["1"]}],"casks":[]}"#.utf8),packages:model.packages)
        precondition(updates.first?.package.id == formula.id)
        precondition(Store.removalArguments(app) == ["uninstall","--cask","homebrew/cask/fixture-app"])
        let suite = "explore-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let persistedStore = Store(preferences:defaults); persistedStore.inventoryKnown = true; persistedStore.appPresent = { _ in false }
        persistedStore.registerPersonal(formula,favorite:true); persistedStore.registerPersonal(app,favorite:true); persistedStore.toggle(formula)
        let reopened = Store(preferences:defaults)
        precondition(reopened.personalPackages.count == 2 && reopened.myAppIDs == [formula.id,app.id] && reopened.selected == [formula.id])
        reopened.removeFavorite(formula)
        let reopenedAgain = Store(preferences:defaults)
        precondition(reopenedAgain.personalPackages.count == 2 && !reopenedAgain.myAppIDs.contains(formula.id))
        let preview = Store(preview:true,persistSelection:false)
        preview.exploreLoader = { preconditionFailure("Preview must not fetch a catalog") }
        await preview.loadExplore(); precondition(preview.explorePackages.isEmpty)
        if let index = CommandLine.arguments.firstIndex(of:"--official-catalog-check"), CommandLine.arguments.count > index + 1 {
            let root = URL(fileURLWithPath:CommandLine.arguments[index + 1])
            let liveFormulas = try OfficialCatalog.parse(Data(contentsOf:root.appendingPathComponent("formula.json")),cask:false)
            let liveCasks = try OfficialCatalog.parse(Data(contentsOf:root.appendingPathComponent("cask.json")),cask:true)
            precondition(liveFormulas.count > 1000 && liveCasks.count > 1000)
            precondition((liveFormulas + liveCasks).allSatisfy(OfficialCatalog.validSaved))
            print("PASS: real official metadata parsed (\(liveFormulas.count) formulas, \(liveCasks.count) casks), no software installed")
        }
        print("PASS: official-only dynamic catalog, invalid tokens/taps, saved metadata deduplication, favorites, dynamic installation/update/removal, independent Brewfile export, no direct dependencies, offline refresh, search filters, inline cleanup state and nonoperating previews")
    }
}
