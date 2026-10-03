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
        let model = Store()
        precondition(Catalog.loadError == nil && Catalog.packages.count > 400)
        precondition(Set(Catalog.packages.flatMap(\.sourceNumbers)) == Set(1...437))
        precondition(Catalog.packages.flatMap(\.sourceNumbers).count == 437)
        precondition(Catalog.packages.allSatisfy { $0.websiteURL != nil && $0.homepageSource != nil })
        precondition(Catalog.packages.filter { $0.github != nil }.allSatisfy { $0.githubURL != nil && $0.githubSource != nil })
        precondition(Package.webURL("javascript:alert(1)") == nil)
        precondition(Package.webURL("file:///tmp/untrusted") == nil)
        precondition(Package.webURL("https://user:password@example.com") == nil)
        precondition(Package.webURL("https://github.com/microsoft/vscode") != nil)
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
        let repeated = Catalog.packages.first { $0.sourceNumbers.count > 1 }!
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
        precondition(model.actionable.count == 1 && model.actionable[0].installer)
        model.adopt = true
        precondition(model.actionable.count == 2)
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
        print("PASS: process runner, full catalog coverage, verified links, web URL validation, detail selection isolation, presets, install/uninstall planning")
    }
}
