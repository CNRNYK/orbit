import SwiftUI
import AppKit

struct ReviewItem: Identifiable {
    let package: Package
    let managed: Bool
    let manual: Bool
    let installer: Bool
    let version: String
    let problem: String?
    var id: String { package.id }
    func action(adopt: Bool) -> String {
        if let problem { return "Unavailable: " + problem }
        if managed { return "Already managed — skip" }
        if installer { return "Run vendor installer; may update an existing app" }
        if manual { return adopt ? "Adopt existing app if identical" : "Existing app — skip" }
        return "Install"
    }
}

enum BrewRunner {
    static var path: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func run(_ executable: String, _ arguments: [String], log: @escaping @Sendable (String) -> Void = { _ in }) async -> (Int32, String) {
        await Task.detached(priority: .userInitiated) {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_INSTALL_UPGRADE"] = "1"
            env["HOMEBREW_NO_COLOR"] = "1"
            env["HOMEBREW_NO_AUTOREMOVE"] = "1"
            env.removeValue(forKey: "HOMEBREW_UPGRADE_GREEDY")
            env.removeValue(forKey: "HOMEBREW_UPGRADE_GREEDY_CASKS")
            if let helper = Bundle.main.path(forResource: "askpass", ofType: "sh") { env["SUDO_ASKPASS"] = helper }
            process.environment = env
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe; process.standardError = pipe
            do {
                try process.run()
                var data = Data()
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    data.append(chunk)
                    log(String(decoding: chunk, as: UTF8.self))
                }
                process.waitUntilExit()
                return (process.terminationStatus, String(decoding: data, as: UTF8.self))
            } catch { return (-1, error.localizedDescription) }
        }.value
    }
}

protocol CommandExecuting: Sendable {
    func run(_ executable: String, _ arguments: [String], log: @escaping @Sendable (String) -> Void) async -> (Int32, String)
}
struct SystemCommands: CommandExecuting {
    func run(_ executable: String, _ arguments: [String], log: @escaping @Sendable (String) -> Void) async -> (Int32, String) {
        await BrewRunner.run(executable, arguments, log: log)
    }
}

@MainActor final class Store: ObservableObject {
    @Published var mode = ActionMode.install
    var uninstallMode: Bool { get { mode == .uninstall } set { mode = newValue ? .uninstall : .install } }
    var updateMode: Bool { mode == .updates }
    @Published var updates = [UpdateItem]()
    @Published var selectedUpdates = Set<String>()
    @Published var updateQueue = [UpdateItem]()
    @Published var includeSelfUpdating = false
    @Published var updatesChecked = false
    @Published var showUpdateReview = false
    @Published var cleanRemoval = false
    @Published var leftovers = [Leftover]()
    @Published var selectedLeftovers = Set<String>()
    @Published var cleanupMessages = [String]()
    @Published var checkingAppRelease = false
    @Published var appReleaseStatus = "Check published releases for Mac Setup updates."
    @Published var removalPlan = [Package]()
    @Published var showRemovalReview = false
    @Published var category = "All Apps"
    @Published var subcategory = "All"
    @Published var detailPackage: Package?
    @Published var search = ""
    @Published var selected = Set<String>() {
        didSet { if persistSelection { UserDefaults.standard.set(Array(selected), forKey: "selection") } }
    }
    @Published var installed = Set<String>()
    @Published var inventoryKnown = false
    @Published var statuses = [String: String]()
    @Published var busy = false
    @Published var preparing = false
    @Published var refreshing = false
    @Published var review = [ReviewItem]()
    @Published var showReview = false
    @Published var adopt = false
    @Published var stopRequested = false
    @Published var completed = 0
    @Published var total = 0
    @Published var output = ""
    @Published var showLog = false
    @Published var notice: String?
    @Published var headline = "Choose your apps. Make it yours."
    var commandRunner: any CommandExecuting = SystemCommands()
    var brewExecutable: String?
    var scanLeftovers: @Sendable ([Package]) -> [Leftover] = { Cleanup.scan($0) }
    var trashLeftover: (Leftover) throws -> Void = { try Cleanup.trash($0) }
    var brew: String? { brewExecutable ?? BrewRunner.path }
    func runCommand(_ executable: String, _ arguments: [String], log: @escaping @Sendable (String) -> Void = { _ in }) async -> (Int32, String) {
        await commandRunner.run(executable, arguments, log: log)
    }
    var visibleUpdates: [UpdateItem] { updates.filter { search.isEmpty || ($0.package.name + " " + $0.package.detail).localizedCaseInsensitiveContains(search) } }
    var selection: [Package] { Catalog.packages.filter { selected.contains($0.id) } }
    var visible: [Package] {
        Catalog.packages.filter { (!uninstallMode || (inventoryKnown && installed.contains($0.id))) && (category == "All Apps" || $0.belongs(to: category, subcategory: subcategory)) && (search.isEmpty || ($0.name + " " + $0.detail + " " + $0.placements.map { $0.category + " " + $0.subcategory }.joined(separator: " ")).localizedCaseInsensitiveContains(search)) }
    }
    var locked: Bool { busy || preparing || refreshing }
    let preview: Bool
    private let persistSelection: Bool
    init(preview: Bool = false, persistSelection: Bool = true) {
        self.preview = preview
        self.persistSelection = persistSelection && !preview
        if preview {
            selected = Set(Catalog.packages.filter { ["google-chrome", "chatgpt", "visual-studio-code", "git", "python@3.14", "slack"].contains($0.token) }.map(\.id))
        } else { selected = Set(UserDefaults.standard.stringArray(forKey: "selection") ?? []).intersection(Set(Catalog.packages.filter(\.installable).map(\.id))) }
    }
    func toggle(_ package: Package) {
        guard uninstallMode || package.installable else { return }
        if selected.contains(package.id) { selected.remove(package.id) } else { selected.insert(package.id) }
    }
    func selectPreset(_ name: String) {
        guard !locked, !uninstallMode else { return }
        selected.formUnion(Catalog.presets[name] ?? [])
    }
    func appendLog(_ text: String) {
        output += text
        if output.count > 120_000 { output = String(output.suffix(100_000)) }
    }
    func refresh() async {
        guard !refreshing, let brew else { return }
        refreshing = true
        defer { refreshing = false }
        let formulas = await runCommand(brew, ["list", "--formula", "-1"])
        let casks = await runCommand(brew, ["list", "--cask", "-1"])
        guard formulas.0 == 0, casks.0 == 0 else {
            inventoryKnown = false; notice = "Could not read Homebrew's installed packages. Open installation details for the error."
            appendLog(formulas.1 + casks.1); return
        }
        installed = Set(formulas.1.split(whereSeparator: \.isNewline).map { "brew:" + $0 }).union(casks.1.split(whereSeparator: \.isNewline).map { "cask:" + $0 })
        inventoryKnown = true
    }
    func prepare() async {
        guard !locked, !selection.isEmpty, brew != nil else { return }
        preparing = true; review = []; adopt = false
        defer { preparing = false }
        await refresh()
        guard inventoryKnown else { return }
        for package in selection {
            if !package.installable {
                review.append(ReviewItem(package: package, managed: false, manual: false, installer: false, version: "", problem: package.availability)); continue
            }
            if installed.contains(package.id) {
                review.append(ReviewItem(package: package, managed: true, manual: false, installer: false, version: "", problem: nil)); continue
            }
            do {
                let url = URL(string: "https://formulae.brew.sh/api/\(package.cask ? "cask" : "formula")/\(package.token).json")!
                var request = URLRequest(url: url); request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let info = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NSError(domain: "Catalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not verify package in the official catalog."]) }
                let disabled = (info["disabled"] as? Bool == true) || (info["deprecated"] as? Bool == true)
                let artifacts = info["artifacts"] as? [[String: Any]] ?? []
                let installer = artifacts.contains { $0["pkg"] != nil || $0["installer"] != nil }
                let version = info["version"] as? String ?? (info["versions"] as? [String: Any])?["stable"] as? String ?? ""
                review.append(ReviewItem(package: package, managed: false, manual: package.manualAppExists, installer: installer, version: version, problem: disabled ? "Disabled or deprecated by Homebrew" : nil))
            } catch {
                review.append(ReviewItem(package: package, managed: false, manual: package.manualAppExists, installer: false, version: "", problem: error.localizedDescription))
            }
        }
        showReview = true
    }
    var actionable: [ReviewItem] { review.filter { $0.problem == nil && !$0.managed && (!$0.manual || $0.installer || adopt) } }
    var removable: [Package] { inventoryKnown ? selection.filter { installed.contains($0.id) } : [] }
    static func removalArguments(_ package: Package) -> [String] {
        ["uninstall"] + (package.cask ? ["--cask"] : ["--formula"]) + [package.token]
    }
    func prepareRemoval() async {
        guard !locked, !selection.isEmpty, brew != nil else { return }
        preparing = true
        defer { preparing = false }
        await refresh()
        guard inventoryKnown else { return }
        removalPlan = removable
        leftovers = []; selectedLeftovers = []; cleanupMessages = []
        if cleanRemoval {
            let packages = removalPlan
            let scanner = scanLeftovers
            leftovers = await Task.detached { scanner(packages) }.value
            selectedLeftovers = Set(leftovers.filter { !$0.dataSensitive }.map(\.id))
        }
        if removalPlan.isEmpty { notice = "None of the selected apps are currently managed by Homebrew." }
        else { showRemovalReview = true }
    }
    func uninstall() async {
        guard !busy, !preparing, showRemovalReview, let brew else { return }
        let queue = removalPlan
        let clean = cleanRemoval
        let cleanupQueue = leftovers.filter { selectedLeftovers.contains($0.id) }
        guard !queue.isEmpty else { return }
        showRemovalReview = false; busy = true; stopRequested = false; completed = 0; total = queue.count; output = ""; statuses = [:]
        defer { busy = false }
        for package in queue { statuses[package.id] = "Waiting" }
        var failures = 0
        for package in queue {
            if stopRequested { break }
            headline = "Uninstalling \(package.name)…"; statuses[package.id] = "Uninstalling"
            appendLog("\n—— Uninstall \(package.name) ——\n")
            let result = await runCommand(brew, Self.removalArguments(package)) { [weak self] chunk in
                Task { @MainActor in self?.appendLog(chunk) }
            }
            if result.0 == 0 {
                statuses[package.id] = "Removed"; installed.remove(package.id); selected.remove(package.id)
                if clean {
                    for item in cleanupQueue where item.packageID == package.id {
                        if !FileManager.default.fileExists(atPath: item.path) { continue }
                        do {
                            try trashLeftover(item)
                            let message = "Moved to Trash: " + item.path
                            cleanupMessages.append(message); appendLog(message + "\n")
                        } catch {
                            statuses[package.id] = "Removed; cleanup incomplete"
                            let message = "Cleanup skipped: " + item.path + " — " + error.localizedDescription
                            cleanupMessages.append(message); appendLog(message + "\n"); failures += 1
                        }
                    }
                }
            }
            else { statuses[package.id] = "Failed"; failures += 1; appendLog("\nExit status: \(result.0)\n") }
            completed += 1
        }
        for package in queue where statuses[package.id] == "Waiting" { statuses[package.id] = "Skipped" }
        headline = stopRequested ? "Stopped after the current operation." : failures == 0 ? "Selected apps were removed." : "Finished with \(failures) removal or cleanup error\(failures == 1 ? "" : "s"). Open details to review."
        await refresh()
    }
    func install() async {
        guard !busy, let brew else { return }
        let queue = actionable; let shouldAdopt = adopt
        guard !queue.isEmpty else { showReview = false; return }
        showReview = false; busy = true; stopRequested = false; completed = 0; total = queue.count; output = ""; statuses = [:]
        defer { busy = false }
        for item in queue { statuses[item.id] = "Waiting" }
        var failures = 0
        for item in queue {
            if stopRequested { break }
            headline = "Installing \(item.package.name)…"
            statuses[item.id] = "Installing"
            var args = ["install"]
            if item.package.cask { args.append("--cask") }
            if shouldAdopt && item.manual && !item.installer { args.append("--adopt") }
            args.append(item.package.token)
            appendLog("\n—— \(item.package.name) ——\n")
            let result = await runCommand(brew, args) { [weak self] chunk in
                Task { @MainActor in self?.appendLog(chunk) }
            }
            if result.0 == 0 { statuses[item.id] = "Installed"; installed.insert(item.id) }
            else { statuses[item.id] = "Failed"; failures += 1; appendLog("\nExit status: \(result.0)\n") }
            completed += 1
        }
        if stopRequested {
            for item in queue where statuses[item.id] == "Waiting" { statuses[item.id] = "Skipped" }
            headline = "Stopped after the current installation."
        } else { headline = failures == 0 ? "Your apps are ready." : "Finished with \(failures) failed installation\(failures == 1 ? "" : "s"). Open details to review." }
        await refresh()
    }
    func exportFile() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Brewfile"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Catalog.export(selection).write(to: url, atomically: true, encoding: .utf8) }
        catch { notice = error.localizedDescription }
    }
    func importFile() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = Catalog.parse(try String(contentsOf: url, encoding: .utf8))
            selected = result.0
            notice = "Imported \(result.0.count) apps." + (result.1.isEmpty ? "" : "\n\nThese entries are outside this app's catalog or unsupported and were not imported:\n" + result.1.joined(separator: "\n"))
        } catch { notice = error.localizedDescription }
    }
}
