import Foundation

@main enum Tests {
    @MainActor static func main() async {
        let literal = "space ' quote; $(never-run)"
        let arguments = await BrewRunner.run("/usr/bin/printf", ["%s", literal])
        precondition(arguments.0 == 0 && arguments.1 == literal, "Arguments must never be evaluated by a shell")
        let failure = await BrewRunner.run("/usr/bin/false", [])
        precondition(failure.0 != 0, "Failures must retain their exit code")
        let missing = await BrewRunner.run("/no/such/executable", [])
        precondition(missing.0 == -1 && !missing.1.isEmpty)
        let largeOutput = await BrewRunner.run("/usr/bin/head", ["-c", "200000", "/dev/zero"])
        precondition(largeOutput.0 == 0 && largeOutput.1.count == 200000, "Output larger than a pipe buffer must not deadlock")
        let separated = await BrewRunner.run("/bin/sh", ["-c", "printf 'warning from tap\\n' >&2; printf '{\"formulae\":[],\"casks\":[]}'"], separateError: true)
        precondition(separated.0 == 0 && (try! UpdatePlan.parse(Data(separated.1.utf8))).isEmpty, "Diagnostics must not contaminate JSON")
        let stderrFlood = await BrewRunner.run("/bin/sh", ["-c", "head -c 200000 /dev/zero >&2; printf '{\"formulae\":[],\"casks\":[]}'"], separateError: true)
        precondition(stderrFlood.0 == 0 && (try! UpdatePlan.parse(Data(stderrFlood.1.utf8))).isEmpty, "Large stderr must not deadlock or contaminate JSON")
        try! await RecorderTests.run()
        try! await MenuBarTests.run()
        try! await WorkflowUITests.run()
        try! await TerminalSetupTests.run()
        let model = Store(persistSelection: false)
        model.inventoryKnown = true; model.appPresent = { _ in false }; model.appScanner = { [] }
        precondition(Catalog.loadError == nil && Catalog.packages.count > 400)
        precondition(Set(Catalog.packages.flatMap(\.sourceNumbers)) == Set(1...437))
        precondition(Catalog.packages.flatMap(\.sourceNumbers).count == 437)
        precondition(Catalog.packages.allSatisfy { $0.websiteURL != nil && $0.homepageSource != nil })
        precondition(Catalog.packages.filter { $0.github != nil }.allSatisfy { $0.githubURL != nil && $0.githubSource != nil })
        precondition(Package.webURL("javascript:alert(1)") == nil)
        precondition(Package.webURL("file:///tmp/untrusted") == nil)
        precondition(Package.webURL("https://user:password@example.com") == nil)
        precondition(Package.webURL("https://github.com/microsoft/vscode") != nil)
        precondition(LogoStore.decode(Data("not an image".utf8)) == nil)
        precondition(LogoStore.decode(Data(repeating: 0, count: 1_000_001)) == nil)
        let logoPackages = Catalog.packages.filter { $0.logoAsset != nil }
        precondition(logoPackages.count > 250)
        for package in logoPackages {
            precondition(package.officialLogoURL != nil && Package.webURL(package.logoSource) != nil && package.logoFilename != nil)
            let file = URL(fileURLWithPath: "Resources/Logos").appendingPathComponent(package.logoFilename!)
            let data = try! Data(contentsOf: file)
            precondition(LogoStore.decode(data) != nil, "Bundled icon must decode: " + package.token)
        }
        let vscode = Catalog.packages.first { $0.token == "visual-studio-code" }!
        precondition(vscode.githubURL?.absoluteString == "https://github.com/microsoft/vscode")
        model.detailPackage = vscode
        precondition(model.selected.isEmpty || model.detailPackage?.id == vscode.id)
        let previousSelection = model.selected
        model.detailPackage = Catalog.packages.first
        precondition(model.selected == previousSelection, "Opening details must not change selection")
        for ids in Catalog.presets.values {
            precondition(ids.allSatisfy { id in Catalog.packages.contains { $0.id == id && $0.installable } })
        }
        let repeated = Catalog.packages.first { $0.placements.count > 1 }!
        precondition(repeated.placements.count > 1)
        for place in repeated.placements {
            model.category = place.category; model.subcategory = place.subcategory
            precondition(model.visible.contains(repeated))
        }
        model.category = "All Apps"; model.subcategory = "All"
        let manualPackage = Catalog.packages.first { !$0.installable }!
        model.selected = []
        model.toggle(manualPackage)
        precondition(model.selected.isEmpty)
        precondition(!Catalog.export([manualPackage]).contains(manualPackage.brewLine))
        model.selectPreset("Discover 20")
        precondition(model.selection.count == 20)
        model.selectPreset("Discover 20")
        precondition(model.selection.count == 20)
        let app = Catalog.packages[0]
        let managed = ReviewItem(package: app, managed: true, manual: false, installer: false, version: "", problem: nil)
        let manual = ReviewItem(package: app, managed: false, manual: true, installer: false, version: "", problem: nil)
        let installer = ReviewItem(package: app, managed: false, manual: true, installer: true, version: "", problem: nil)
        let unavailable = ReviewItem(package: app, managed: false, manual: false, installer: false, version: "", problem: "Unavailable")
        model.review = [managed, manual, installer, unavailable]
        model.adopt = false
        precondition(model.actionable.isEmpty)
        model.adopt = true
        precondition(model.actionable.isEmpty)
        model.selected = Set(Catalog.packages.prefix(3).map(\.id))
        model.installed = [app.id]
        model.inventoryKnown = false
        precondition(model.removable.isEmpty)
        model.inventoryKnown = true
        precondition(model.removable.map(\.id) == [app.id])
        model.uninstallMode = true
        precondition(model.visible.map(\.id) == [app.id])
        precondition(Store.removalArguments(app) == ["uninstall", "--cask", app.token])
        let formula = Catalog.packages.first { !$0.cask }!
        precondition(Store.removalArguments(formula) == ["uninstall", "--formula", formula.token])
        precondition(!Store.removalArguments(app).contains("--zap"))
        precondition(!Store.removalArguments(formula).contains("--ignore-dependencies"))
        precondition(Catalog.categories.count == 10 && !Catalog.categories.contains("Google"))
        precondition(Catalog.categoryDescriptions.count == 10)
        precondition(Catalog.subcategories(in: "Development").first == "Code Editors & IDEs")
        precondition(Catalog.packages.allSatisfy { !$0.placements.isEmpty && Set($0.placements).count == $0.placements.count && $0.placements.allSatisfy { Catalog.categories.contains($0.category) && Catalog.data?.subcategorySymbols?[$0.subcategory] != nil } })
        let chrome = Catalog.packages.first { $0.token == "google-chrome" }!
        let drive = Catalog.packages.first { $0.token == "google-drive" }!
        precondition(chrome.category == "Browsers & Internet" && drive.category == "Files & Storage")
        let docker = Catalog.packages.first { $0.token == "docker" }!
        model.navigate(.install, category: "Cloud & Databases"); model.search = ""; model.selected = []
        model.toggle(docker)
        precondition(model.visible.contains(docker))
        model.navigate(.install, category: "Development")
        precondition(model.selected == [docker.id] && model.visible.contains(docker) && model.selection.count == 1)
        model.category = "All Apps"
        precondition(model.visible.count == Set(model.visible.map(\.id)).count)
        model.search = "docker"
        precondition(model.visible.filter { $0.id == docker.id }.count == 1)
        model.search = ""; model.installed = [chrome.id, drive.id]; model.inventoryKnown = true
        model.navigate(.uninstall)
        precondition(Set(model.visible.map(\.id)) == [chrome.id, drive.id])
        precondition(model.count(in: "Browsers & Internet") == 1 && model.count(in: "Development") == 0)
        model.navigate(.uninstall, category: "Files & Storage")
        model.selected = [drive.id]
        model.navigate(.uninstall, category: "Browsers & Internet")
        precondition(model.selected == [drive.id], "Category navigation preserves the shared removal selection")
        precondition(model.visible.map(\.id) == [chrome.id])
        precondition(Catalog.parse(Catalog.export([docker, docker])).0 == [docker.id])
        print("PASS: ten-category taxonomy, icon metadata, Google redistribution, cross-category selection, unique lists/export, installed filtering and category counts")
        if CommandLine.arguments.contains("--live-updates"), let brew = BrewRunner.path {
            let live = await BrewRunner.run(brew, ["outdated", "--json=v2"], separateError: true)
            precondition(live.0 == 0 || live.0 == 1)
            let updates = try! UpdatePlan.parse(Data(live.1.utf8))
            print("PASS: read-only live Homebrew JSON parsed (\(updates.count) catalog updates)")
        }
        await LifecycleTests.run()
        await RepairTests.run()
        await AdoptionTests.run()
        try! MaintenanceTests.run()
        await StartupTests.run()
        try! await ExploreTests.run()
        print("PASS: process runner, full catalog coverage, verified links, web URL validation, detail selection isolation, official bundled icon decoding and size limits, presets, install/uninstall planning")
    }
}
