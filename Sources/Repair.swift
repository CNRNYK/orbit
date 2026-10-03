import Foundation

struct RemovalRepair: Identifiable {
    let package: Package
    let caskroom: String
    let source: String
    let inode: UInt64
    let device: UInt64
    let cleanup: [Leftover]
    var id: String { package.id }
    static func conflictPath(_ text: String) -> String? {
        guard let error = text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.hasPrefix("Error:") }),
              error.hasPrefix("Error: It seems there is already an App at '"), error.hasSuffix("'.") else { return nil }
        return String(error.dropFirst("Error: It seems there is already an App at '".count).dropLast(2))
    }
    static func inspect(_ package: Package, error: String, caskroom: String, cleanup: [Leftover]) -> RemovalRepair? {
        guard package.cask, let name = package.appName, !package.manualAppExists,
              let path = conflictPath(error), path.hasPrefix("/"), caskroom.hasPrefix("/") else { return nil }
        let source = URL(fileURLWithPath: path).standardizedFileURL
        let root = URL(fileURLWithPath: caskroom).standardizedFileURL
        guard source.path == path, source.resolvingSymlinksInPath().path == path,
              source.lastPathComponent == name + ".app",
              source.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == package.token,
              source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path == root.path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path), attrs[.type] as? FileAttributeType == .typeDirectory,
              let inode = attrs[.systemFileNumber] as? NSNumber, let device = attrs[.systemNumber] as? NSNumber else { return nil }
        return RemovalRepair(package: package, caskroom: root.path, source: path, inode: inode.uint64Value, device: device.uint64Value, cleanup: cleanup.filter { $0.packageID == package.id })
    }
    var unchanged: Bool {
        guard !package.manualAppExists, URL(fileURLWithPath: source).resolvingSymlinksInPath().path == source,
              let attrs = try? FileManager.default.attributesOfItem(atPath: source) else { return false }
        return attrs[.type] as? FileAttributeType == .typeDirectory && (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == inode && (attrs[.systemNumber] as? NSNumber)?.uint64Value == device
    }
    static func explanation(_ text: String) -> String {
        if conflictPath(text) != nil { return "Homebrew found an existing copy in its app storage. The app and removal record may be out of sync." }
        if text.localizedCaseInsensitiveContains("permission denied") || text.localizedCaseInsensitiveContains("not permitted") || text.localizedCaseInsensitiveContains("sudo:") { return "Removal needs permission. Open Operation details for the specific access error." }
        if text.localizedCaseInsensitiveContains("required by") || text.localizedCaseInsensitiveContains("depend") { return "Another package may depend on this software. Open Operation details; dependency protection was not bypassed." }
        if text.localizedCaseInsensitiveContains("running") || text.localizedCaseInsensitiveContains("quit") { return "The app or a background helper may still be running. Close it and review Operation details." }
        return "Homebrew could not remove this app. Open Operation details to review the error."
    }
    var arguments: [String] { ["uninstall", "--cask", "--force", package.token] }
}

@MainActor extension Store {
    func proposeRepair(_ package: Package, output: String, cleanup: [Leftover]) async {
        failureMessages[package.id] = RemovalRepair.explanation(output)
        guard package.cask, RemovalRepair.conflictPath(output) != nil, let brew else { return }
        let root = await runJSONCommand(brew, ["--caskroom"])
        guard root.0 == 0 else { return }
        if let repair = RemovalRepair.inspect(package, error: output, caskroom: root.1.trimmingCharacters(in: .whitespacesAndNewlines), cleanup: cleanup) {
            repairOptions[package.id] = repair
            statuses[package.id] = "Repair available"
        }
    }
    func prepareRepair(_ id: String) async {
        guard !locked, let candidate = repairOptions[id] else { return }
        preparing = true; defer { preparing = false }
        await refresh()
        guard inventoryKnown, installed.contains(id), candidate.unchanged else {
            repairOptions.removeValue(forKey: id)
            notice = "The app or its Homebrew record changed. Review its current state before trying removal again."; return
        }
        repairReview = candidate
    }
    func repairAndRetry() async {
        guard !locked, let repair = repairReview, let brew else { return }
        preparing = true
        let root = await runJSONCommand(brew, ["--caskroom"])
        preparing = false
        guard repairReview?.id == repair.id else { return }
        guard root.0 == 0, root.1.trimmingCharacters(in: .whitespacesAndNewlines) == repair.caskroom, repair.unchanged else { repairReview = nil; repairOptions.removeValue(forKey: repair.id); notice = "The stored app changed since review. Repair was cancelled."; return }
        repairReview = nil; busy = true; stopRequested = false; completed = 0; total = 1
        defer { busy = false }
        headline = "Repairing removal of \(repair.package.name)…"; statuses[repair.id] = "Repairing"
        appendLog("\n—— Repair & Retry \(repair.package.name) ——\n")
        let result = await runCommand(brew, repair.arguments) { [weak self] chunk in Task { @MainActor in self?.appendLog(chunk) } }
        await refresh()
        guard result.0 == 0, inventoryKnown, !installed.contains(repair.id), !repair.package.manualAppExists,
              !FileManager.default.fileExists(atPath: repair.source) else {
            statuses[repair.id] = "Repair failed"; repairOptions.removeValue(forKey: repair.id)
            failureMessages[repair.id] = "Repair did not confirm complete removal. Review Operation details before retrying."
            appendLog("\nRepair verification failed (exit status: \(result.0)). No leftover cleanup performed.\n")
            headline = "Removal repair failed. Open Operation details."; completed = 1
            notice = failureMessages[repair.id]; return
        }
        repairOptions.removeValue(forKey: repair.id); failureMessages.removeValue(forKey: repair.id)
        selected.remove(repair.id); statuses[repair.id] = "Removed"; var errors = 0
        for item in repair.cleanup {
            if !FileManager.default.fileExists(atPath: item.path) { continue }
            do { try trashLeftover(item); appendLog("Moved to Trash: " + item.path + "\n") }
            catch { errors += 1; appendLog("Cleanup skipped: " + item.path + " — " + error.localizedDescription + "\n") }
        }
        if errors > 0 { statuses[repair.id] = "Removed; cleanup incomplete" }
        completed = 1; headline = errors == 0 ? "\(repair.package.name) was removed and its Homebrew record verified." : "App removed; some leftovers could not be cleaned. Open Operation details."
    }
}
