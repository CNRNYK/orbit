import SwiftUI
import AppKit

struct MaintenanceItem: Identifiable, Hashable {
    let path: String
    let group: String
    let bytes: Int64
    let inode: UInt64
    let device: UInt64
    let removable: Bool
    var id: String { path }
    var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
enum MaintenanceScan {
    static let groups = ["Homebrew cache", "App caches & logs", "App leftovers", "Developer caches", "Large files"]
    static func permitted(_ path: String, group: String, home: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path == path, url.resolvingSymlinksInPath().path == path else { return false }
        let roots: [String]
        switch group {
        case "Homebrew cache": roots = [home + "/Library/Caches/Homebrew"]
        case "App caches & logs", "App leftovers": roots = [home + "/Library/Caches", home + "/Library/Logs"]
        case "Developer caches": roots = [home + "/Library/Developer/Xcode/DerivedData"]
        default: return false
        }
        return roots.contains { url.deletingLastPathComponent().path == $0 } && !url.lastPathComponent.hasPrefix(".") && url.lastPathComponent != "Homebrew"
    }
    static func snapshot(_ path: String, group: String, home: String, removable: Bool = true) -> MaintenanceItem? {
        guard !removable || permitted(path, group: group, home: home),
              URL(fileURLWithPath: path).resolvingSymlinksInPath().path == path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              attrs[.type] as? FileAttributeType != .typeSymbolicLink,
              let inode = attrs[.systemFileNumber] as? NSNumber, let device = attrs[.systemNumber] as? NSNumber else { return nil }
        var bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if attrs[.type] as? FileAttributeType == .typeDirectory {
            bytes = 0; var visited = 0; var unreadable = false
            if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey], options: [], errorHandler: { _, _ in unreadable = true; return false }) {
                for case let url as URL in enumerator {
                    visited += 1
                    // Do not offer incomplete scans for cleanup.
                    if visited > 100_000 { return nil }
                    guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey]) else { return nil }
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
                }
            } else { return nil }
            if unreadable { return nil }
        }
        guard bytes > 0 else { return nil }
        return MaintenanceItem(path: path, group: group, bytes: bytes, inode: inode.uint64Value, device: device.uint64Value, removable: removable)
    }
    static func unchanged(_ item: MaintenanceItem, home: String = NSHomeDirectory()) -> Bool {
        guard item.removable, permitted(item.path, group: item.group, home: home),
              let attrs = try? FileManager.default.attributesOfItem(atPath: item.path), attrs[.type] as? FileAttributeType != .typeSymbolicLink else { return false }
        return (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == item.inode && (attrs[.systemNumber] as? NSNumber)?.uint64Value == item.device
    }
    static func trash(_ item: MaintenanceItem, home: String = NSHomeDirectory(), move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        guard unchanged(item, home: home) else { throw NSError(domain: "Cleanup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Path changed since scan; skipped."]) }
        try move(URL(fileURLWithPath: item.path))
    }
    static func scan(home: String = NSHomeDirectory(), installed: Set<String> = [], appIDs: Set<String> = [], developer: Bool = false) -> [MaintenanceItem] {
        var items = [MaintenanceItem](); var seen = Set<String>()
        func add(_ path: String, _ group: String, removable: Bool = true) {
            if !seen.contains(path), let item = snapshot(path, group: group, home: home, removable: removable) { seen.insert(path); items.append(item) }
        }
        for (relative, group) in [("Library/Caches/Homebrew","Homebrew cache"),("Library/Caches","App caches & logs"),("Library/Logs","App caches & logs")] {
            let root = home + "/" + relative
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where !name.hasPrefix(".") { add(root + "/" + name, group) }
        }
        // Exact reference identifiers only; no application settings or user documents.
        for package in Catalog.packages where package.cask && !installed.contains(package.id) {
            guard let identifier = AppScanner.identifiers[package.token], !appIDs.contains(identifier) else { continue }
            for root in ["Library/Caches", "Library/Logs"] {
                let path = home + "/" + root + "/" + identifier
                if let index = items.firstIndex(where: { $0.path == path }) { items.remove(at: index); seen.remove(path) }
                add(path, "App leftovers")
            }
        }
        if developer {
            let root = home + "/Library/Developer/Xcode/DerivedData"
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where !name.hasPrefix(".") { add(root + "/" + name,"Developer caches") }
        }
        for relative in ["Downloads", "Desktop"] {
            let root = URL(fileURLWithPath: home + "/" + relative)
            // Discovery only. Personal files cannot enter the deletion selection.
            for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? [] {
                if let values = try? url.resourceValues(forKeys: [.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) >= 500_000_000 { add(url.path,"Large files",removable:false) }
            }
        }
        return items.sorted { $0.bytes > $1.bytes }
    }
}

@MainActor final class MaintenanceState: ObservableObject {
    @Published var items = [MaintenanceItem]()
    @Published var selected = Set<String>()
    @Published var developer = false
    @Published var working = false
    @Published var scanned = false
    @Published var showDetails = false
    @Published var confirm = false
    @Published var status = "Scan to review files. Nothing is selected automatically."
}
struct MaintenanceView: View {
    @ObservedObject var store: Store
    @ObservedObject private var state: MaintenanceState
    init(store: Store) {
        self.store = store
        let model = store.maintenanceState
        if store.preview {
            model.scanned = true; model.status = "Preview data · no files were scanned."
            model.items = [MaintenanceItem(path: "/Users/example/Library/Caches/Homebrew/downloads", group: "Homebrew cache", bytes: 920_000_000, inode: 0, device: 0, removable: true), MaintenanceItem(path: "/Users/example/Library/Caches/com.example.app", group: "App caches & logs", bytes: 180_000_000, inode: 0, device: 0, removable: true), MaintenanceItem(path: "/Users/example/Downloads/Archive.zip", group: "Large files", bytes: 1_250_000_000, inode: 0, device: 0, removable: false)]
        }
        _state = ObservedObject(wrappedValue: model)
    }
    var selection: [MaintenanceItem] { state.items.filter { $0.removable && state.selected.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleanup").font(.largeTitle.bold())
            Text("Review caches and logs, then move selected items to Trash. Close affected apps first. Caches may be recreated; developer builds may take longer afterward.").foregroundStyle(.secondary)
            HStack {
                Toggle("Include Xcode build caches", isOn: $state.developer).disabled(state.working)
                Spacer()
                Button("Scan") { Task { await scan() } }.disabled(state.working || store.locked)
            }
            if state.working { ProgressView() }
            Text(state.status).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(MaintenanceScan.groups, id: \.self) { group in
                        let rows = state.items.filter { $0.group == group }
                        if !rows.isEmpty {
                            Text(group).font(.headline)
                            ForEach(rows) { item in
                                HStack {
                                    if item.removable {
                                        Toggle("", isOn: Binding(get: { state.selected.contains(item.id) }, set: { if $0 { state.selected.insert(item.id) } else { state.selected.remove(item.id) } })).labelsHidden().disabled(state.working)
                                    } else { Image(systemName: "doc") }
                                    VStack(alignment: .leading) {
                                        Text(URL(fileURLWithPath: item.path).lastPathComponent).font(.subheadline.bold())
                                        Text(item.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                    Spacer(); Text(item.size).monospacedDigit()
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                                }.padding(8).background(Color.primary.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    if state.scanned && state.items.isEmpty { Text("No accessible cleanup candidates or large files found.").foregroundStyle(.secondary) }
                }
            }
            Text("Large files: Downloads and Desktop, 500 MB or larger. App leftovers: known app cache/log identifiers only. Other leftovers are reviewed during Uninstall & Clean.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Clear selection") { state.selected = [] }.disabled(state.working)
                Button("Operation details") { state.showDetails.toggle() }
                Spacer()
                Text("\(selection.count) items · " + ByteCountFormatter.string(fromByteCount: selection.reduce(0) { $0 + $1.bytes }, countStyle: .file))
                Button("Move to Trash") { state.confirm = true }.buttonStyle(.borderedProminent).disabled(selection.isEmpty || state.working || store.locked)
            }
            if state.showDetails { ScrollView { Text(store.output.isEmpty ? "No cleanup operation has run yet." : store.output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 120) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        .alert("Move selected files to Trash?", isPresented: $state.confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { Task { await clean() } }
        } message: { Text("\(selection.count) reviewed items will be moved to Trash. Only paths whose filesystem identity still matches the scan will be processed.") }
    }
    func scan() async {
        guard !store.preview else { return }
        state.working = true; state.selected = []; store.preparing = true
        defer { state.working = false; store.preparing = false }
        let installed = store.installed
        let includeDeveloper = state.developer
        state.items = await Task.detached {
            let ids = Set(AppScanner.scan().map(\.identifier))
            return MaintenanceScan.scan(installed: installed, appIDs: ids, developer: includeDeveloper)
        }.value
        state.scanned = true; state.status = "\(state.items.count) candidates. Sizes are estimates; inaccessible paths are omitted."
    }
    func clean() async {
        guard !store.preview, !state.working, !store.locked else { return }
        let queue = selection; state.working = true; store.busy = true
        defer { state.working = false; store.busy = false }
        var failures = 0
        for item in queue {
            do {
                try MaintenanceScan.trash(item)
                state.items.removeAll { $0.id == item.id }; state.selected.remove(item.id)
                store.appendLog("\nCleanup: moved to Trash: \(item.path)\n")
            } catch { failures += 1; store.appendLog("\nCleanup failed: \(item.path): \(error.localizedDescription)\n") }
            await Task.yield()
        }
        state.status = "Moved \(queue.count - failures) items to Trash. \(failures) skipped or failed."
    }
}
