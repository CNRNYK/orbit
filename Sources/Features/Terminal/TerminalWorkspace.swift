import Foundation
import AppKit
import Darwin

struct TerminalAlias: Codable, Equatable, Identifiable {
    var name = "", command = ""
    var id: String { name }
}
struct TerminalConfiguration: Codable, Equatable {
    var nodeVersion = "--lts", pythonVersion = "3.13", javaVersion = "21", rubyVersion = "3.3.6"
    var packageManager = "npm", packageManagerVersion = "latest"
    var theme = "Minimal", gitName = "", gitEmail = ""
    var aliases: [TerminalAlias] = []
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: #"'"'"'"#) + "'" }
    static func version(_ value: String) -> Bool { value.range(of: #"^[0-9]+(\.[0-9]+){0,2}$"#, options: .regularExpression) != nil }
    func validate() throws {
        guard nodeVersion == "--lts" || Self.version(nodeVersion), Self.version(pythonVersion), ["17", "21", "25"].contains(javaVersion), Self.version(rubyVersion), ["npm", "pnpm", "Yarn"].contains(packageManager), packageManagerVersion == "latest" || Self.version(packageManagerVersion), ["Minimal", "Developer", "Compact"].contains(theme) else { throw ProfileProblem(message: "Choose valid runtime versions and a supported package manager/theme.") }
        guard aliases.count <= 30, Set(aliases.map(\.name)).count == aliases.count else { throw ProfileProblem(message: "Use up to 30 unique alias names.") }
        for alias in aliases {
            guard alias.name.range(of: #"^[a-zA-Z][a-zA-Z0-9_-]{0,31}$"#, options: .regularExpression) != nil, !["ll", "gs", "gd", "gl", "ov", "oa"].contains(alias.name), !alias.command.isEmpty, alias.command.utf8.count <= 2000, !alias.command.contains("\n"), !alias.command.contains("\r"), !alias.command.contains("\0") else { throw ProfileProblem(message: "Alias names must be unique simple words; commands must be a single nonempty line. Orbit's built-in names are reserved.") }
        }
        guard [gitName, gitEmail].allSatisfy({ !$0.contains("\n") && !$0.contains("\r") && !$0.contains("\0") && $0.utf8.count <= 300 }) else { throw ProfileProblem(message: "Git identity must be a single line.") }
    }
    func options() throws -> [TerminalOption] {
        try validate()
        return TerminalOption.all.map { option in
            var rc = option.rc, packages = option.packages
            if option.id == "python" { rc = rc.replacingOccurrences(of: "uv venv .venv", with: "uv venv --python \(Self.quote(pythonVersion)) .venv") }
            if option.id == "java" { rc = rc.replacingOccurrences(of: "openjdk@21", with: "openjdk@" + javaVersion); packages = ["openjdk@" + javaVersion] }
            if option.id == "custom-aliases" { rc = aliases.map { "alias \($0.name)=\(Self.quote($0.command))" }.joined(separator: "\n") }
            return .init(option.id, option.title, option.detail, option.group, packages: packages, detection: option.detection, rc: rc, profile: option.profile)
        }
    }
    var starship: String {
        switch theme {
        case "Developer": return "add_newline = true\n[character]\nsuccess_symbol = '[➜](bold green)'\n[git_branch]\nsymbol = 'git:'\n"
        case "Compact": return "add_newline = false\nformat = '$directory$git_branch$character'\n[directory]\ntruncation_length = 2\n"
        default: return "add_newline = false\nformat = '$directory$git_branch$character'\n[git_branch]\nsymbol = 'git:'\n"
        }
    }
}
struct TerminalTransfer: Codable {
    var format = "orbit-terminal", version = 1
    let selected: [String]
    let configuration: TerminalConfiguration
    var runtimeChoices: [String]? = nil
    static func portable(selected: Set<String>, configuration: TerminalConfiguration, runtimes: Set<String> = []) -> Self {
        var clean = configuration; clean.gitName = ""; clean.gitEmail = ""; clean.aliases = []
        return Self(selected: selected.subtracting(["git-identity", "custom-aliases"]).sorted(), configuration: clean, runtimeChoices: runtimes.sorted())
    }
    func validate() throws {
        guard format == "orbit-terminal", version == 1, selected.count <= TerminalOption.all.count, Set(selected).isSubset(of: Set(TerminalOption.all.map(\.id))) else { throw ProfileProblem(message: "Unsupported Terminal Setup file.") }
        try configuration.validate()
        guard Set(runtimeChoices ?? []).isSubset(of: ["node", "python", "rust", "ruby"]) else { throw ProfileProblem(message: "Unknown runtime download choice.") }
    }
}
struct TerminalTool: Identifiable {
    let id: String, path: String, version: String
}
struct TerminalProject {
    let folder: URL
    var node = "", python = "", manager = "", managerVersion = "", findings: [String] = []
    static func read(_ folder: URL) throws -> Self {
        var project = Self(folder: folder)
        func text(_ name: String) throws -> String? {
            let file = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 500_000 else { throw ProfileProblem(message: "Project metadata must be small regular files: \(name).") }
            return try String(contentsOf: file, encoding: .utf8)
        }
        for name in [".nvmrc", ".node-version"] {
            if let raw = try text(name) {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "v", with: "", options: .anchored)
                if TerminalConfiguration.version(value) { project.node = value; project.findings.append("\(name): Node \(value)") }
                else { project.findings.append("\(name): symbolic/custom version; review manually") }
            }
        }
        if let raw = try text(".python-version") {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if TerminalConfiguration.version(value) { project.python = value; project.findings.append(".python-version: Python \(value)") }
            else { project.findings.append(".python-version: custom version; review manually") }
        }
        if let raw = try text("package.json"), let json = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] {
            if let engines = json["engines"] as? [String: String], let node = engines["node"] { project.findings.append("package.json requires Node: " + String(node.prefix(200))) }
            if let manager = json["packageManager"] as? String {
                let parts = manager.split(separator: "@", maxSplits: 1).map(String.init)
                if parts.count == 2, ["npm", "pnpm", "yarn"].contains(parts[0]), TerminalConfiguration.version(parts[1].components(separatedBy: "+")[0]) {
                    project.manager = parts[0] == "yarn" ? "Yarn" : parts[0]; project.managerVersion = parts[1].components(separatedBy: "+")[0]; project.findings.append("package.json: " + manager)
                } else { project.findings.append("packageManager: unsupported/custom specification; review manually") }
            }
        }
        if let raw = try text("pyproject.toml") {
            for line in raw.components(separatedBy: "\n") where line.trimmingCharacters(in: .whitespaces).hasPrefix("requires-python") { project.findings.append(String(line.prefix(200))) }
        }
        for name in ["pnpm-lock.yaml", "yarn.lock", "package-lock.json", "uv.lock"] where FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) { project.findings.append("Found " + name) }
        if project.findings.isEmpty { project.findings = ["No supported project version files found."] }
        return project
    }
}

extension TerminalState {
    func inspectProject(_ folder: URL) {
        do { project = try TerminalProject.read(folder); plan = nil; message = "Project requirements inspected. No project commands were run." } catch { message = error.localizedDescription }
    }
    func useProjectVersions() {
        guard let project else { return }
        if !project.node.isEmpty { configuration.nodeVersion = project.node }
        if !project.python.isEmpty { configuration.pythonVersion = project.python }
        if !project.manager.isEmpty { configuration.packageManager = project.manager; configuration.packageManagerVersion = project.managerVersion }
        plan = nil; runtimeReview = nil; message = "Project versions copied into the setup choices. Review before applying."
    }
    func choosePreset(_ name: String) {
        let additions: Set<String>
        switch name {
        case "Web Development": additions = ["git", "node", "fzf", "suggestions", "highlighting"]
        case "Python Development": additions = ["git", "python", "fzf", "suggestions"]
        case "QA & Automation": additions = ["git", "node", "python", "fzf"]
        default: additions = []
        }
        selected = TerminalOption.essentials.union(additions).union(managed).filter { id in !TerminalOption.all.contains { $0.id == id && ProfileEngine.conflicts($0, outside: outside) } }
        plan = nil; runtimeReview = nil; message = "\(name) selected. Existing Orbit settings are retained; adjust individual choices below."
    }
    func configurationDetails(_ option: TerminalOption) -> [String] {
        snapshots.compactMap { snapshot in
            guard let raw = snapshot.data, let text = String(data: raw, encoding: .utf8), let split = try? ProfileEngine.split(text) else { return nil }
            let lines = split.outside.components(separatedBy: "\n").enumerated().filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("#") && ProfileEngine.conflicts(option, outside: $0.element) }.map { String($0.offset + 1) }
            return lines.isEmpty ? nil : "~/\(snapshot.name) · configuration references near lines \(lines.joined(separator: ", "))"
        }
    }
    func inventory() async {
        guard !working else { return }; working = true; defer { working = false }
        var results: [TerminalTool] = []
        let names = ["brew", "git", "node", "npm", "pnpm", "yarn", "uv", "python3", "java", "go", "rustup", "rustc", "rbenv", "ruby", "starship", "fzf", "fnm", "volta", "mise", "pyenv"]
        var directories = ["/opt/homebrew/bin", "/usr/local/bin", engine.home.appendingPathComponent(".cargo/bin").path, engine.home.appendingPathComponent(".local/bin").path, engine.home.appendingPathComponent(".volta/bin").path, "/usr/bin", "/bin"]
        let nvmRoot = engine.home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot.path) { directories.insert(contentsOf: versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { nvmRoot.appendingPathComponent($0).appendingPathComponent("bin").path }, at: 0) }
        for name in names {
            guard let path = directories.map({ $0 + "/" + name }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { continue }
            // Discovery is file-only. Executable probes run only via the explicit Verify tools action.
            results.append(.init(id: name, path: path, version: "Found · not yet verified"))
        }
        tools = results
        sshKeys = ((try? FileManager.default.contentsOfDirectory(atPath: engine.home.appendingPathComponent(".ssh").path)) ?? []).filter { $0.hasSuffix(".pub") }.sorted()
    }
    func verifyTools(store: Store) async {
        guard !store.preview, !store.locked, !working else { return }; working = true; defer { working = false }
        var checked: [TerminalTool] = []
        for tool in tools {
            // Avoid macOS java/ruby launchers prompting for installation.
            if tool.path == "/usr/bin/java" || tool.path == "/usr/bin/ruby" { checked.append(.init(id: tool.id, path: tool.path, version: "System launcher · runtime not verified")); continue }
            let result = await Self.probe(tool.path, arguments: tool.id == "java" ? ["-version"] : ["--version"])
            checked.append(.init(id: tool.id, path: tool.path, version: result.0 == 0 ? String(result.1.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)) : "Needs attention · version check failed"))
        }
        tools = checked; message = "Tool checks finished. User profiles were not executed; open a new terminal to check its effective environment."
    }
    static func probe(_ executable: String, arguments: [String]) async -> (Int32, String) {
        await Task.detached {
            let process = Process(), file = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-version-" + UUID().uuidString)
            guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]), let output = try? FileHandle(forWritingTo: file) else { return (-1, "Could not capture version") }
            defer { try? output.close(); try? FileManager.default.removeItem(at: file) }
            process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments; process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = output
            process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
            do {
                try process.run(); let deadline = Date().addingTimeInterval(5)
                while process.isRunning && Date() < deadline { usleep(50_000) }
                if process.isRunning { process.terminate(); usleep(100_000); if process.isRunning { kill(process.processIdentifier, SIGKILL) }; process.waitUntilExit(); return (-1, "Version check timed out") }
                process.waitUntilExit()
                let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
                return (process.terminationStatus, String(decoding: try input.read(upToCount: 16_000) ?? Data(), as: UTF8.self))
            } catch { return (-1, error.localizedDescription) }
        }.value
    }
    func runtimeScript() throws -> String {
        try configuration.validate()
        let downloads = runtimeChoices
        var lines = ["set -e", "# Explicit downloads only; no project install scripts or user profiles.", "export PATH=\(TerminalConfiguration.quote(engine.home.appendingPathComponent(".cargo/bin").path)):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
        if downloads.contains("node") {
            guard outside.range(of: #"\b(fnm|volta|asdf|mise)\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { throw ProfileProblem(message: "An existing Node manager controls this environment. Use its version installation commands; Orbit will not introduce a competing manager.") }
            lines += ["export NVM_DIR=\(TerminalConfiguration.quote(engine.home.appendingPathComponent(".nvm").path))", #"if [[ -s "$NVM_DIR/nvm.sh" ]]; then source "$NVM_DIR/nvm.sh"; elif [[ -s /opt/homebrew/opt/nvm/nvm.sh ]]; then source /opt/homebrew/opt/nvm/nvm.sh; elif [[ -s /usr/local/opt/nvm/nvm.sh ]]; then source /usr/local/opt/nvm/nvm.sh; else print 'Install NVM first, or keep your existing Node manager and run its setup separately.'; exit 1; fi"#]
            lines.append(#"mkdir -p "$NVM_DIR""#)
            if downloads.contains("node") { lines.append("nvm install \(configuration.nodeVersion == "--lts" ? "--lts" : TerminalConfiguration.quote(configuration.nodeVersion))") }
        }
        if configuration.packageManager != "npm" {
            if !downloads.contains("node") {
                guard let node = tools.first(where: { $0.id == "node" }), let npm = tools.first(where: { $0.id == "npm" }) else { throw ProfileProblem(message: "Install or discover Node/npm first, or select Node with NVM.") }
                let paths = Set([URL(fileURLWithPath: node.path).deletingLastPathComponent().path, URL(fileURLWithPath: npm.path).deletingLastPathComponent().path]).sorted().joined(separator: ":")
                lines.append("export PATH=\(TerminalConfiguration.quote(paths)):$PATH")
            }
            let package = configuration.packageManager == "Yarn" ? (configuration.packageManagerVersion.hasPrefix("1.") ? "yarn" : "@yarnpkg/cli-dist") : "pnpm"
            lines.append("npm install --global \(TerminalConfiguration.quote(package + "@" + configuration.packageManagerVersion))")
        }
        if downloads.contains("python") { lines.append("\((tools.first { $0.id == "uv" }.map { TerminalConfiguration.quote($0.path) } ?? "uv")) python install \(TerminalConfiguration.quote(configuration.pythonVersion))") }
        if downloads.contains("rust") { lines.append("\((tools.first { $0.id == "rustup" }.map { TerminalConfiguration.quote($0.path) } ?? "rustup")) default stable") }
        if downloads.contains("ruby") { lines.append("\((tools.first { $0.id == "rbenv" }.map { TerminalConfiguration.quote($0.path) } ?? "rbenv")) install -s \(TerminalConfiguration.quote(configuration.rubyVersion))") }
        guard lines.count > 3 else { throw ProfileProblem(message: "Select Node, Python, Rust or Ruby for runtime downloads. Java and Go use the reviewed Homebrew installation.") }
        return lines.joined(separator: "\n") + "\n"
    }
    func reviewRuntimes() { do { runtimeReview = try runtimeScript(); message = "Review runtime commands below. Downloads run only when you choose Run reviewed setup." } catch { runtimeReview = nil; message = error.localizedDescription } }
    func runRuntimes(store: Store) async {
        guard !store.preview, !store.locked, !working, let reviewed = runtimeReview else { return }
        do { guard try runtimeScript() == reviewed else { throw ProfileProblem(message: "Choices changed. Review runtime commands again.") } } catch { runtimeReview = nil; message = error.localizedDescription; return }
        working = true; message = "Downloading selected runtimes…"; runtimeOutput = "Running reviewed runtime setup…\n"; defer { working = false; runtimeReview = nil }
        let result = await store.runCommand("/bin/zsh", ["-f", "-c", reviewed], log: { [weak self] chunk in Task { @MainActor in guard let self, self.working else { return }; self.runtimeOutput = String((self.runtimeOutput + chunk).suffix(50_000)) } })
        runtimeOutput = String(result.1.suffix(50_000)); message = result.0 == 0 ? "Runtime setup finished. Rescan and verify tools." : "Runtime setup stopped (exit \(result.0)). Completed downloads remain installed; review the output before retrying."
    }
    func exportSetup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Orbit-terminal.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let export = TerminalTransfer.portable(selected: selected, configuration: configuration, runtimes: runtimeChoices)
            try export.validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(export).write(to: url, options: .atomic)
            message = "Exported choices and versions. Git identity, custom aliases, profiles, history and keys are excluded."
        } catch { message = error.localizedDescription }
    }
    func importSetup(store: Store) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]); guard values.isRegularFile == true, (values.fileSize ?? Int.max) < 100_000 else { throw ProfileProblem(message: "Setup file is too large or invalid.") }
            let transfer = try JSONDecoder().decode(TerminalTransfer.self, from: Data(contentsOf: url)); try transfer.validate()
            configuration = transfer.configuration; runtimeChoices = Set(transfer.runtimeChoices ?? []); selected = Set(transfer.selected).filter { id in !TerminalOption.all.contains { $0.id == id && ProfileEngine.conflicts($0, outside: outside) } }; plan = nil; runtimeReview = nil; refreshMissing(store: store)
            message = "Imported choices for review. Nothing installed or applied. Custom alias commands, if supplied, require your review."
        } catch { message = error.localizedDescription }
    }
}
