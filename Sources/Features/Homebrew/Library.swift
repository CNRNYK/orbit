import SwiftUI
import AppKit

enum ManualAppOwnership {
    static func mayRemove(_ app: LocalApp, metadata: Data, tokens: Set<String>, packages: [Package] = Catalog.packages) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with:metadata) as? [String:Any], let casks = root["casks"] as? [[String:Any]],
              Set(casks.compactMap { $0["token"] as? String }) == tokens else { throw RecorderProblem(message:"Installed Homebrew app ownership could not be verified.") }
        let target = URL(fileURLWithPath:app.path).lastPathComponent
        for cask in casks {
            guard let token = cask["token"] as? String, let artifacts = cask["artifacts"] as? [[String:Any]] else { throw RecorderProblem(message:"Homebrew returned incomplete app metadata.") }
            var names = [String]()
            for artifact in artifacts {
                if let bundle = artifact["app"] as? [Any] {
                    guard let name = (bundle.last as? [String:Any])?["target"] as? String ?? bundle.first as? String, name.hasSuffix(".app") else { throw RecorderProblem(message:"Homebrew app paths could not be verified.") }
                    names.append(URL(fileURLWithPath:name).lastPathComponent)
                }
            }
            if let known = packages.first(where:{ $0.cask && $0.token == token })?.appName { names.append(known + ".app") }
            if names.contains(where:{ $0.caseInsensitiveCompare(target) == .orderedSame }) { return false }
            if names.isEmpty && artifacts.contains(where:{ $0["pkg"] != nil || $0["installer"] != nil }) { throw RecorderProblem(message:"A vendor-installed Homebrew app has no verified bundle mapping (\(token)). Review it before removing an unmatched app.") }
        }
        return true
    }
}
struct ManualRemovalPlan: Identifiable {
    let app: LocalApp
    let device: UInt64
    let leftovers: [Leftover]
    var id: String { app.id }
    static func inspect(_ app: LocalApp, home: String = NSHomeDirectory(), roots: [String]? = nil) -> Self? {
        let allowed = roots ?? ["/Applications",home + "/Applications"]
        guard allowed.contains(where: { app.path.hasPrefix($0 + "/") }), app.unchanged,
              let device = (try? FileManager.default.attributesOfItem(atPath:app.path)[.systemNumber] as? NSNumber)?.uint64Value else { return nil }
        var found = [Leftover]()
        if app.identifier.contains("."), app.identifier.range(of:#"^[A-Za-z0-9.-]+$"#,options:.regularExpression) != nil {
            for folder in Cleanup.folders {
                let basename = folder == "Preferences" ? app.identifier + ".plist" : folder == "Saved Application State" ? app.identifier + ".savedState" : folder == "Cookies" ? app.identifier + ".binarycookies" : app.identifier
                if let item = Cleanup.snapshot(packageID:app.id,appName:app.name,path:home + "/Library/" + folder + "/" + basename,kind:folder,home:home) { found.append(item) }
            }
        }
        return Self(app:app,device:device,leftovers:found)
    }
    func unchanged() -> Bool {
        app.unchanged && (try? FileManager.default.attributesOfItem(atPath:app.path)[.systemNumber] as? NSNumber)?.uint64Value == device
    }
}
@MainActor extension Store {
    var libraryPackages: [Package] {
        packages.filter { package in
            let managed = installed.contains(package.id), saved = myAppIDs.contains(package.id)
            if !managed && localApps.contains(where: { $0.package?.id == package.id }) { return false }
            return (libraryFilter == .installed ? managed : libraryFilter == .saved ? saved : managed || saved) &&
                (search.isEmpty || (package.name + " " + package.detail).localizedCaseInsensitiveContains(search)) &&
                (category == "All Apps" || category == "My apps" || package.belongs(to:category,subcategory:subcategory))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var libraryManualApps: [LocalApp] { visibleManualApps.filter { libraryFilter != .saved || $0.package.map { myAppIDs.contains($0.id) } == true } }
    func toggleLibraryInstall(_ package: Package) {
        guard !locked, canInstall(package) else { return }
        registerPersonal(package)
        if mode == .uninstall {
            if savedInstallSelection.contains(package.id) { savedInstallSelection.remove(package.id) } else { savedInstallSelection.insert(package.id) }
        } else { toggle(package) }
    }
    func verifiedManualOwnership(_ app: LocalApp) async -> Bool {
        let tokens = Set(installed.filter { $0.hasPrefix("cask:") }.map { String($0.dropFirst(5)) })
        guard !tokens.isEmpty else { return true }
        guard let brew else { notice = "Homebrew ownership cannot be verified."; return false }
        let response = await runJSONCommand(brew,["info","--json=v2","--cask"] + tokens.sorted())
        do {
            guard response.0 == 0 else { throw RecorderProblem(message:"Could not read installed Homebrew app metadata. Refresh and try again.") }
            let removable = try ManualAppOwnership.mayRemove(app,metadata:Data(response.1.utf8),tokens:tokens,packages:packages)
            if !removable { notice = "This app is managed by Homebrew. Use Homebrew removal rather than manual Trash." }
            return removable
        } catch { notice = error.localizedDescription; return false }
    }
    func reviewManualRemoval(_ app: LocalApp) async {
        guard !preview, !locked, inventoryKnown, manualApps.contains(where: { $0.id == app.id }) else { return }
        preparing = true; defer { preparing = false }
        guard await verifiedManualOwnership(app) else { return }
        guard let plan = await Task.detached(operation:{ ManualRemovalPlan.inspect(app) }).value else { notice = "This app changed or is outside Applications. Refresh before trying again."; return }
        manualRemoval = plan; manualLeftovers = Set(plan.leftovers.filter { !$0.dataSensitive }.map(\.id))
    }
    func removeManualApp() async {
        guard !preview, !locked, let plan = manualRemoval else { return }
        preparing = true; defer { preparing = false }
        await refresh()
        guard inventoryKnown, manualApps.contains(where: { $0.id == plan.app.id }), plan.unchanged() else { manualRemoval = nil; notice = "The app changed or is now managed by Homebrew. Refresh and review again."; return }
        guard await verifiedManualOwnership(plan.app), plan.unchanged() else { return }
        guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL.path == plan.app.path }) else { notice = "Quit \(plan.app.name) before removing it."; return }
        do {
            try FileManager.default.trashItem(at:URL(fileURLWithPath:plan.app.path),resultingItemURL:nil)
            var failures = [String]()
            for item in plan.leftovers where manualLeftovers.contains(item.id) {
                do { try Cleanup.trash(item) } catch { failures.append(item.path + ": " + error.localizedDescription) }
            }
            appendLog("Moved \(plan.app.name) to Trash.\n" + failures.joined(separator:"\n")); manualRemoval = nil
            if !failures.isEmpty { notice = "The app was moved to Trash. Some leftovers could not be moved; see Operation details." }
            await refresh()
        } catch { notice = "Could not move the app to Trash: " + error.localizedDescription }
    }
}
struct LibraryView: View {
    @ObservedObject var store: Store
    @ObservedObject var detach: CaskDetachState
    init(store: Store) { self.store = store; detach = store.detachState }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Library").font(.title2.bold()); Spacer(); TextField("Search your library",text:$store.search).textFieldStyle(.roundedBorder).frame(width:240); Button("Refresh",systemImage:"arrow.clockwise") { Task { await store.refresh() } }.disabled(store.locked) }
            Text("Installed apps and saved favorites together. Saving an app does not install it.").foregroundStyle(.secondary)
            Picker("Show",selection:$store.libraryFilter) { ForEach(LibraryFilter.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(store.locked)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:0) {
                    ForEach(store.libraryPackages) { package in
                        HStack(spacing:12) {
                            if store.installed.contains(package.id) {
                                Toggle("Select for uninstall",isOn:Binding(get:{store.selected.contains(package.id)},set:{_ in store.toggle(package)})).labelsHidden().disabled(store.locked || !store.inventoryKnown)
                            } else {
                                Toggle("Select for installation",isOn:Binding(get:{store.centerInstallSelection.contains { $0.id == package.id }},set:{_ in store.toggleLibraryInstall(package)})).labelsHidden().disabled(store.locked || !store.canInstall(package))
                            }
                            AppIcon(package:package).frame(width:36,height:36)
                            Button { store.detailPackage = package } label: { VStack(alignment:.leading,spacing:4) { Text(package.name).bold(); Text(package.detail).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading) }.buttonStyle(.plain)
                            Text(store.installed.contains(package.id) ? "Homebrew-managed" : store.appPresent(package) ? "Installed manually" : "Saved").font(.caption).foregroundStyle(.secondary)
                            if package.cask && store.installed.contains(package.id) { if let reason = detach.unsupported[package.id] { Text("Cannot detach safely").font(.caption).foregroundStyle(.secondary).help(reason) } else { Button("Stop managing with Homebrew…") { Task { await store.reviewDetach(package) } }.help("Review eligibility before changing management") } }
                            if store.myAppIDs.contains(package.id) { Button("Unsave",systemImage:"star.slash") { store.removeFavorite(package) }.help("Remove from saved apps without uninstalling") }
                            else { Button("Save",systemImage:"star") { store.registerPersonal(package,favorite:true) } }
                        }.padding(.vertical,12).disabled(store.locked)
                        Divider()
                    }
                    if !store.libraryManualApps.isEmpty { Text("Installed manually").font(.headline).padding(.top,20) }
                    ForEach(store.libraryManualApps) { app in
                        HStack(spacing:12) {
                            if let package = app.package { AppIcon(package:package).frame(width:36,height:36) } else { Image(systemName:"app").font(.title).frame(width:36,height:36) }
                            VStack(alignment:.leading,spacing:4) { Text(app.name).bold(); Text(app.path).font(.caption).foregroundStyle(.secondary) }; Spacer()
                            if let package = app.package { Button { if store.myAppIDs.contains(package.id) { store.removeFavorite(package) } else { store.registerPersonal(package,favorite:true) } } label: { Image(systemName:store.myAppIDs.contains(package.id) ? "star.fill" : "star") }.help(store.myAppIDs.contains(package.id) ? "Unsave from Library" : "Save to Library") }
                            if app.package?.installable == true { Button("Manage with Homebrew") { store.selectedManual = [app.id]; Task { await store.prepareAdoption() } } }
                            Button("Uninstall & Clean",systemImage:"trash") { Task { await store.reviewManualRemoval(app) } }.disabled(!store.inventoryKnown)
                        }.padding(.vertical,12).disabled(store.locked); Divider()
                    }
                    if store.libraryPackages.isEmpty && store.libraryManualApps.isEmpty { ContentUnavailableView("Your library is empty",systemImage:"books.vertical",description:Text("Refresh installed apps or save apps from Discover.")) }
                }
            }
            if let backup = detach.backup { HStack { Text("Recoverable Homebrew backup").font(.caption); Button("Show backup") { NSWorkspace.shared.activateFileViewerSelecting([backup.directory]) }; Button("Restore management") { Task { await store.restoreDetach() } }.disabled(store.locked) } }
            if store.busy { ProgressView(value:Double(store.completed),total:Double(max(store.total,1))); HStack { Text(store.progressSummary).font(.caption); Spacer(); Button("Stop after current app") { store.stopRequested = true }.disabled(store.stopRequested) } }
            Toggle("Review leftover files when uninstalling",isOn:$store.cleanRemoval).disabled(store.locked)
            HStack { Button("Operation details") { store.showLog = true }; Button("Export setup") { store.showSetupExport = true }; Spacer(); Button("Uninstall \(store.removable.count) apps") { Task { await store.prepareRemoval() } }.buttonStyle(.borderedProminent).disabled(store.locked || store.removable.isEmpty || !store.startupReady) }
        }.padding(24).sheet(item:$detach.plan) { plan in
            VStack(alignment:.leading,spacing:16) {
                Text("Stop managing " + plan.app.name + " with Homebrew?").font(.title2.bold())
                Text("The app remains installed at its current path. Personal data, preferences and support files remain untouched. Homebrew will no longer update, uninstall or list this cask. A built-in updater may become available, depending on the app.")
                Text("Orbit backs up the app and registration, removes only the registration, then opens the app once to verify launch. A failed check restores registration. This feature supports only verified, standard single-app casks; installers and background components cannot detach safely.").foregroundStyle(.secondary)
                Text(plan.app.path).font(.caption).textSelection(.enabled)
                HStack { Button("Cancel") { detach.plan = nil }; Spacer(); Button("Back up & stop managing") { Task { await store.detachApp() } }.buttonStyle(.borderedProminent).disabled(store.locked) }
            }.padding(24).frame(width:640)
        }.sheet(item:$store.manualRemoval) { plan in
            VStack(alignment:.leading,spacing:16) {
                Text("Uninstall & Clean · " + plan.app.name).font(.title2.bold())
                Text("The application and selected files will move to Trash. Application data is optional; review each path. Shared vendor folders are excluded.").foregroundStyle(.secondary)
                Label(plan.app.path,systemImage:"app.badge.checkmark").textSelection(.enabled)
                ScrollView { ForEach(plan.leftovers) { item in Toggle(isOn:Binding(get:{store.manualLeftovers.contains(item.id)},set:{if $0 {store.manualLeftovers.insert(item.id)} else {store.manualLeftovers.remove(item.id)}})) { VStack(alignment:.leading) { Text(item.kind + " · " + item.size); Text(item.path).font(.caption).textSelection(.enabled); if item.dataSensitive { Text("May contain settings or personal data").font(.caption).foregroundStyle(.orange) } } }.padding(.vertical,8) } }
                if plan.leftovers.isEmpty { Text("No exact matching leftover paths were found.").foregroundStyle(.secondary) }
                HStack { Button("Cancel") { store.manualRemoval = nil }; Spacer(); Button("Move to Trash",role:.destructive) { Task { await store.removeManualApp() } }.buttonStyle(.borderedProminent).disabled(store.locked) }
            }.padding(24).frame(width:720,height:520)
        }
    }
}
