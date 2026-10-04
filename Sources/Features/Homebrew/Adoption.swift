import Foundation
import AppKit

struct LocalApp: Identifiable, Hashable {
    let path: String
    let name: String
    let identifier: String
    let version: String
    let package: Package?
    let identityMatched: Bool
    let inode: UInt64
    var id: String { path }
    var unchanged: Bool {
        guard URL(fileURLWithPath: path).resolvingSymlinksInPath().path == path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == inode else { return false }
        return Bundle(path: path)?.bundleIdentifier == identifier
    }
}
enum AppScanner {
    static var identifiers: [String: String] {
        let url = Bundle.main.url(forResource: "app-identifiers", withExtension: "json") ?? URL(fileURLWithPath: "Resources/app-identifiers.json")
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    static func scan(roots: [String] = ["/Applications", NSHomeDirectory() + "/Applications"], packages: [Package] = Catalog.packages, references: [String: String] = identifiers) -> [LocalApp] {
        var apps = [LocalApp](); var seen = Set<String>()
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { enumerator.skipDescendants(); continue }
                if enumerator.level > 2 { enumerator.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }
                enumerator.skipDescendants()
                let path = url.standardizedFileURL.path
                guard url.resolvingSymlinksInPath().path == path, seen.insert(path).inserted,
                      let bundle = Bundle(path: path), let identifier = bundle.bundleIdentifier, !identifier.isEmpty,
                      let attrs = try? FileManager.default.attributesOfItem(atPath: path), let inode = attrs[.systemFileNumber] as? NSNumber else { continue }
                let exact = packages.filter { $0.cask && references[$0.token] == identifier }
                let named = packages.filter { $0.cask && $0.appName == url.deletingPathExtension().lastPathComponent }
                let match = exact.count == 1 ? exact.first : named.count == 1 ? named.first : nil
                let verified = match.map { references[$0.token] == identifier } ?? false
                apps.append(LocalApp(path: path, name: url.deletingPathExtension().lastPathComponent, identifier: identifier, version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", package: match, identityMatched: verified, inode: inode.uint64Value))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
struct AdoptionItem: Identifiable {
    let app: LocalApp
    let installer: Bool
    let version: String
    let problem: String?
    var id: String { app.id }
    var action: String { problem ?? (installer ? "Run vendor installer; may update this app" : "Adopt only if existing contents match Homebrew") }
    var arguments: [String] {
        guard let package = app.package else { return [] }
        let parent = URL(fileURLWithPath: app.path).deletingLastPathComponent().path
        return ["install", "--cask", "--appdir=" + parent] + (installer ? [] : ["--adopt"]) + [package.operationToken]
    }
}

@MainActor extension Store {
    var manualApps: [LocalApp] { localApps.filter { app in app.package.map { !installed.contains($0.id) } ?? true } }
    var visibleManualApps: [LocalApp] { manualApps.filter { (category == "All Apps" || $0.package?.belongs(to: category, subcategory: subcategory) == true) && (search.isEmpty || ($0.name + " " + $0.identifier).localizedCaseInsensitiveContains(search)) } }
    func canInstall(_ package: Package) -> Bool { startupReady && inventoryKnown && package.installable && !installed.contains(package.id) && !appPresent(package) && !localApps.contains { $0.package?.id == package.id } }
    var installSelection: [Package] { selection.filter { canInstall($0) } }
    func sanitizeInstallSelection() {
        if mode != .uninstall && inventoryKnown { selected = Set(installSelection.map(\.id)) }
    }
    func prepareAdoption() async {
        guard !locked, startupReady, !selectedManual.isEmpty, let brew else { return }
        preparing = true; defer { preparing = false }
        adoptionPlan = []; await refresh(); guard inventoryKnown else { return }
        for app in manualApps where selectedManual.contains(app.id) {
            guard let package = app.package, package.installable, app.unchanged else {
                adoptionPlan.append(AdoptionItem(app: app, installer: false, version: "", problem: "No supported matching package or the app changed.")); continue
            }
            let result = await runJSONCommand(brew, ["info", "--json=v2", "--cask", package.operationToken])
            do {
                guard result.0 == 0, let root = try JSONSerialization.jsonObject(with: Data(result.1.utf8)) as? [String: Any], let info = (root["casks"] as? [[String: Any]])?.first,
                      info["token"] as? String == package.token, info["disabled"] as? Bool != true, info["deprecated"] as? Bool != true else { throw NSError(domain: "Adoption", code: 1) }
                let artifacts = info["artifacts"] as? [[String: Any]] ?? []
                let installer = artifacts.contains { $0["pkg"] != nil || $0["installer"] != nil }
                let artifactMatches = artifacts.contains { artifact in
                    let names = artifact["app"] as? [String] ?? []
                    return names.contains { URL(fileURLWithPath: $0).lastPathComponent == URL(fileURLWithPath: app.path).lastPathComponent }
                }
                var problem = installer ? (app.identityMatched ? nil : "Installer blocked: app identity has not been verified.") : (artifactMatches ? nil : "The official app artifact does not match this bundle name.")
                let version = info["version"] as? String ?? ""
                if installer, !app.version.isEmpty, version != "latest", !version.isEmpty, app.version.compare(version.components(separatedBy: ",")[0], options: .numeric) == .orderedDescending { problem = "Installer blocked: the installed app is newer than the Homebrew package." }
                adoptionPlan.append(AdoptionItem(app: app, installer: installer, version: info["version"] as? String ?? "", problem: problem))
            } catch { adoptionPlan.append(AdoptionItem(app: app, installer: false, version: "", problem: "Could not verify the official Homebrew package. See Operation details.")) }
        }
        showAdoptionReview = !adoptionPlan.isEmpty
    }
    func adoptSelected() async {
        guard !locked, startupReady, showAdoptionReview, let brew else { return }
        let queue = adoptionPlan.filter { $0.problem == nil }; guard !queue.isEmpty else { return }
        showAdoptionReview = false; busy = true; stopRequested = false; completed = 0; total = queue.count
        defer { busy = false }
        var failures = 0
        for item in queue {
            if stopRequested { break }
            guard let package = item.app.package, item.app.unchanged else { failures += 1; completed += 1; continue }
            await refresh()
            if !inventoryKnown { failures += 1; completed += 1; continue }
            if installed.contains(package.id) { completed += 1; continue }
            guard item.app.unchanged else { failures += 1; completed += 1; adoptionStatuses[item.id] = "App changed — review again"; continue }
            headline = "Managing \(item.app.name) with Homebrew…"
            appendLog("\n—— Manage with Homebrew: \(item.app.name) ——\n")
            let result = await runCommand(brew, item.arguments) { [weak self] chunk in Task { @MainActor in self?.appendLog(chunk) } }
            await refresh()
            if result.0 == 0 && inventoryKnown && installed.contains(package.id) {
                adoptionStatuses[item.id] = "Managed by Homebrew"; selectedManual.remove(item.id)
            } else {
                failures += 1; adoptionStatuses[item.id] = "Not adopted — see details"
                appendLog("\nAdoption failed (exit \(result.0)). No forced overwrite was requested.\n")
            }
            completed += 1
        }
        headline = stopRequested ? "Stopped after the current Homebrew management operation." : failures == 0 ? "Selected apps are now managed by Homebrew." : "Finished with \(failures) apps not adopted. Open Operation details."
    }
}
