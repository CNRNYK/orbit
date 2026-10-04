import Foundation
import AppKit

enum ActionMode: String { case install, uninstall, updates, cleanup, explore, terminal, recorder, permissions, health, login, screenshots }

struct UpdateItem: Identifiable, Hashable {
    let package: Package
    let installedVersion: String
    let availableVersion: String
    var id: String { package.id }
}
enum UpdatePlan {
    static func parse(_ data: Data, packages: [Package] = Catalog.packages) throws -> [UpdateItem] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulas = root["formulae"] as? [[String: Any]], let casks = root["casks"] as? [[String: Any]] else {
            throw NSError(domain: "Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Homebrew returned an invalid update list."])
        }
        var items = [UpdateItem]()
        for (rows, cask) in [(formulas, false), (casks, true)] {
            for row in rows {
                guard row["pinned"] as? Bool != true,
                      let name = row["name"] as? String,
                      let package = packages.first(where: { $0.cask == cask && ($0.token == name || $0.operationToken == name) && $0.installable }),
                      let current = row["current_version"] as? String, current != "latest", !current.isEmpty else { continue }
                let installed = (row["installed_versions"] as? [String])?.joined(separator: ", ") ?? row["installed_versions"] as? String ?? "Unknown"
                // Self-updating apps can be newer than Homebrew's receipt. Skip when the app's actual version is not older.
                if cask, let version = installedAppVersion(package), !version.isEmpty {
                    let target = current.components(separatedBy: ",")[0]
                    if version.compare(target, options: .numeric) != .orderedAscending { continue }
                }
                items.append(UpdateItem(package: package, installedVersion: installedAppVersion(package) ?? installed, availableVersion: current))
            }
        }
        return items.sorted { $0.package.name.localizedCaseInsensitiveCompare($1.package.name) == .orderedAscending }
    }
    static func installedAppVersion(_ package: Package) -> String? {
        guard package.cask, let name = package.appName else { return nil }
        for base in ["/Applications", NSHomeDirectory() + "/Applications"] {
            if let version = Bundle(path: base + "/" + name + ".app")?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { return version }
        }
        return nil
    }
    static func arguments(_ item: UpdateItem) -> [String] {
        ["upgrade", item.package.cask ? "--cask" : "--formula"] + (item.package.cask ? ["--greedy-auto-updates"] : []) + [item.package.operationToken]
    }
}

struct Leftover: Identifiable, Hashable {
    let packageID: String
    let appName: String
    let path: String
    let kind: String
    let bytes: Int64
    let inode: UInt64
    let device: UInt64
    let dataSensitive: Bool
    var id: String { path }
    var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
enum Cleanup {
    static let folders = ["Caches", "Logs", "Application Support", "Preferences", "Saved Application State", "Containers", "HTTPStorages", "WebKit", "Application Scripts", "Cookies"]
    // Narrow application-specific paths verified against Homebrew's cask zap lists.
    // https://github.com/Homebrew/homebrew-cask/tree/HEAD/Casks
    static let knownPaths = [
        "visual-studio-code": ["Application Support/Code", "Caches/com.microsoft.VSCode.ShipIt", "Preferences/com.microsoft.VSCode.helper.plist"],
        "google-chrome": ["Application Support/Google/Chrome", "Caches/Google/Chrome"],
        "blender": ["Application Support/Blender"],
        "slack": ["Application Support/Slack", "Logs/Slack"]
    ]
    static func safe(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path == path, url.resolvingSymlinksInPath().path == path else { return false }
        let library = URL(fileURLWithPath: home).standardizedFileURL.appendingPathComponent("Library")
        if knownPaths.values.flatMap({ $0 }).contains(where: { library.appendingPathComponent($0).path == path }) { return true }
        return folders.contains { folder in
            let root = library.appendingPathComponent(folder).path
            return url.deletingLastPathComponent().path == root && !url.lastPathComponent.isEmpty && !url.lastPathComponent.hasPrefix(".")
        }
    }
    static func snapshot(packageID: String, appName: String, path: String, kind: String, home: String = NSHomeDirectory()) -> Leftover? {
        guard safe(path, home: home), let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType != .typeSymbolicLink,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber else { return nil }
        var bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        if attributes[.type] as? FileAttributeType == .typeDirectory {
            bytes = 0
            if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]) {
                for case let url as URL in enumerator {
                    guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]) else { continue }
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
                }
            }
        }
        return Leftover(packageID: packageID, appName: appName, path: path, kind: kind, bytes: bytes, inode: inode.uint64Value, device: device.uint64Value, dataSensitive: !["Caches", "Logs"].contains(kind))
    }
    static func scan(_ packages: [Package], home: String = NSHomeDirectory(), appRoots: [String]? = nil) -> [Leftover] {
        var found = [Leftover](); var seen = Set<String>()
        for package in packages where package.cask {
            guard let name = package.appName else { continue }
            let bundles = (appRoots ?? ["/Applications", home + "/Applications"]).map { $0 + "/" + name + ".app" }
            guard let identifier = bundles.compactMap({ Bundle(path: $0)?.bundleIdentifier }).first,
                  identifier.contains("."), identifier.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil else { continue }
            for folder in folders {
                // Exact bundle IDs only: no vendor-wide folders, substring matches, or shared group containers.
                let basename = folder == "Preferences" ? identifier + ".plist" : folder == "Saved Application State" ? identifier + ".savedState" : folder == "Cookies" ? identifier + ".binarycookies" : identifier
                let path = home + "/Library/" + folder + "/" + basename
                if let item = snapshot(packageID: package.id, appName: package.name, path: path, kind: folder, home: home), seen.insert(path).inserted { found.append(item) }
            }
            for relative in knownPaths[package.token] ?? [] {
                let path = home + "/Library/" + relative
                let kind = String(relative.split(separator: "/")[0])
                if let item = snapshot(packageID: package.id, appName: package.name, path: path, kind: kind, home: home), seen.insert(path).inserted { found.append(item) }
            }
        }
        return found
    }
    static func unchanged(_ item: Leftover, home: String = NSHomeDirectory()) -> Bool {
        guard safe(item.path, home: home), let attrs = try? FileManager.default.attributesOfItem(atPath: item.path) else { return false }
        return (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == item.inode && (attrs[.systemNumber] as? NSNumber)?.uint64Value == item.device && attrs[.type] as? FileAttributeType != .typeSymbolicLink
    }
    static func trash(_ item: Leftover) throws {
        guard unchanged(item) else { throw NSError(domain: "Cleanup", code: 1, userInfo: [NSLocalizedDescriptionKey: "The path changed since review; skipped for safety."]) }
        try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
    }
}

@MainActor extension Store {
    func checkUpdates() async {
        guard !locked, startupReady, let brew else { return }
        preparing = true; updates = []; selectedUpdates = []; updatesChecked = false
        defer { preparing = false }
        headline = "Checking for updates…"
        let metadata = await runCommand(brew, ["update"]) { [weak self] chunk in Task { @MainActor in self?.appendLog(chunk) } }
        guard metadata.0 == 0 else { notice = "Homebrew could not refresh its catalog. Open Operation details."; return }
        await refresh()
        guard inventoryKnown else { return }
        let args = ["outdated", "--json=v2"] + (includeSelfUpdating ? ["--greedy-auto-updates"] : [])
        let result = await runJSONCommand(brew, args)
        do {
            guard result.0 == 0 || result.0 == 1 else { throw NSError(domain: "Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: result.1]) }
            updates = try UpdatePlan.parse(Data(result.1.utf8), packages: packages).filter { installed.contains($0.id) }
            updatesChecked = true; lastUpdateCheck = Date(); headline = updates.isEmpty ? "No updates found for apps in this catalog." : "\(updates.count) updates available."
        } catch { appendLog(result.1); notice = "Could not read Homebrew’s update list. Open Operation details for diagnostics, then try again." }
    }
    func prepareUpdates() {
        guard !locked, startupReady else { return }
        updateQueue = updates.filter { selectedUpdates.contains($0.id) && installed.contains($0.id) }
        showUpdateReview = !updateQueue.isEmpty
    }
    func upgrade() async {
        guard !locked, startupReady, showUpdateReview, let brew else { return }
        let queue = updateQueue; guard !queue.isEmpty else { return }
        showUpdateReview = false; busy = true; stopRequested = false; completed = 0; total = queue.count; statuses = [:]
        defer { busy = false }
        var failures = 0
        for item in queue { statuses[item.id] = "Waiting" }
        for item in queue {
            if stopRequested { break }
            headline = "Updating \(item.package.name)…"; statuses[item.id] = "Updating"
            // Recheck actual bundle version immediately before upgrading a self-updating app.
            if let actual = UpdatePlan.installedAppVersion(item.package), actual.compare(item.availableVersion.components(separatedBy: ",")[0], options: .numeric) != .orderedAscending {
                statuses[item.id] = "Already current — skipped"; completed += 1; continue
            }
            appendLog("\n—— Update \(item.package.name) ——\n")
            let result = await runCommand(brew, UpdatePlan.arguments(item)) { [weak self] chunk in Task { @MainActor in self?.appendLog(chunk) } }
            if result.0 == 0 { statuses[item.id] = "Updated"; selectedUpdates.remove(item.id); updates.removeAll { $0.id == item.id } }
            else { statuses[item.id] = "Failed"; failures += 1 }
            completed += 1
        }
        for item in queue where statuses[item.id] == "Waiting" { statuses[item.id] = "Skipped" }
        headline = stopRequested ? "Stopped after the current update." : failures == 0 ? "Selected updates completed. Check again for the latest status." : "Finished with \(failures) failed updates. Open Operation details."
        await refresh()
    }
    func checkAppRelease() async {
        guard !checkingAppRelease else { return }; checkingAppRelease = true
        defer { checkingAppRelease = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/CNRNYK/orbit/releases/latest")!)
            request.timeoutInterval = 15; request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = release["tag_name"] as? String else {
                appReleaseStatus = "Release information is unavailable. This repository is private; open releases and sign in to GitHub."; return
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.6.0"
            appReleaseStatus = version.compare(current, options: .numeric) == .orderedDescending ? "Orbit \(version) is available. Open releases to download it." : "Orbit is up to date (\(current))."
        } catch { appReleaseStatus = "Could not check releases. Open releases to check manually." }
    }
}
