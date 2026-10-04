import Foundation
import SwiftUI
import AppKit
import CryptoKit
import Darwin

struct TerminalOption: Identifiable {
    let id: String, title: String, detail: String, group: String
    let packages: [String]
    let detection: [String]
    let rc: String
    let profile: String
    init(_ id: String, _ title: String, _ detail: String, _ group: String = "Developer essentials", packages: [String] = [], detection: [String], rc: String = "", profile: String = "") {
        self.id = id; self.title = title; self.detail = detail; self.group = group; self.packages = packages; self.detection = detection; self.rc = rc; self.profile = profile
    }
    static let all: [TerminalOption] = [
        .init("brew", "Homebrew environment", "Make Homebrew tools available in login and interactive shells.", detection: ["brew shellenv"], rc: #"[[ -n ${HOMEBREW_PREFIX:-} ]] || { [[ ! -x /opt/homebrew/bin/brew ]] || eval "$(/opt/homebrew/bin/brew shellenv)"; [[ -n ${HOMEBREW_PREFIX:-} || ! -x /usr/local/bin/brew ]] || eval "$(/usr/local/bin/brew shellenv)"; }"#, profile: #"if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi"#),
        .init("completion", "Command completion", "Enable Tab completion. Existing frameworks are left in charge.", detection: ["compinit", "oh-my-zsh", "zinit", "antidote", "sheldon", "prezto"], rc: "autoload -Uz compinit\ncompinit"),
        .init("history", "History improvements", "Keep 20,000 entries, avoid consecutive duplicates; do not share sessions.", detection: ["HISTSIZE", "SAVEHIST", "HISTFILE", "setopt.*HIST", "oh-my-zsh", "prezto"], rc: "HISTFILE=\"$HOME/.zsh_history\"\nHISTSIZE=20000\nSAVEHIST=20000\nsetopt APPEND_HISTORY HIST_IGNORE_DUPS HIST_REDUCE_BLANKS"),
        .init("aliases", "Useful aliases", "ll lists hidden files; .. moves up one directory.", detection: ["alias ll=", "alias \\..=", "function ll", "ll\\s*\\(\\)", "oh-my-zsh", "prezto"], rc: "alias ll='ls -lah'\nalias ..='cd ..'"),
        .init("git", "Git shortcuts", "gs: status · gd: diff · gl: recent graph. No destructive shortcuts.", packages: ["git"], detection: ["alias gs=", "alias gd=", "alias gl=", "function gs", "function gd", "function gl", "\\b(gs|gd|gl)\\s*\\(\\)", "oh-my-zsh"], rc: "alias gs='git status -sb'\nalias gd='git diff'\nalias gl='git log --oneline --graph -20'"),
        .init("node", "Node.js with NVM", "Use project-specific Node versions. No Homebrew Node or automatic downloads.", "Languages", packages: ["nvm"], detection: ["NVM_DIR", "nvm.sh", "\\bnvm\\b", "fnm", "volta", "asdf", "mise"], rc: #"""
        export NVM_DIR="$HOME/.nvm"
        if [[ -s "$NVM_DIR/nvm.sh" ]]; then source "$NVM_DIR/nvm.sh"; elif [[ -n ${HOMEBREW_PREFIX:-} && -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ]]; then source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"; fi
        """#),
        .init("python", "Python development", "uv manages your chosen Python version and project virtual environments.", "Languages", packages: ["uv"], detection: ["pyenv", "conda", "mamba", "asdf", "mise", "function ov", "function oa", "alias ov=", "alias oa=", "o[va]\\s*\\(\\)"], rc: #"""
        # Run inside your project. No automatic activation or global pip installs.
        ov() { command uv venv .venv; }
        oa() { if [[ -f .venv/bin/activate ]]; then source .venv/bin/activate; else print 'Create a project environment first with ov.'; fi; }
        """#),
        .init("java", "Java environment", "Use the selected Homebrew JDK; leave system registration untouched.", "Languages", packages: ["openjdk@21"], detection: ["JAVA_HOME", "jenv", "sdkman", "asdf", "mise"], rc: #"""
        if [[ -n ${HOMEBREW_PREFIX:-} && -d "$HOMEBREW_PREFIX/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home" ]]; then
          export JAVA_HOME="$HOMEBREW_PREFIX/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
          typeset -U path; path=("$JAVA_HOME/bin" $path)
        fi
        """#),
        .init("go", "Go development", "Make tools installed with go install available. Keep the default GOPATH.", "Languages", packages: ["go"], detection: ["GOPATH", "go/bin", "asdf", "mise"], rc: #"[[ ! -d "$HOME/go/bin" ]] || { typeset -U path; path=("$HOME/go/bin" $path); }"#),
        .init("rust", "Rust with Rustup", "Use the Rustup toolchain manager; no automatic toolchain download.", "Languages", packages: ["rustup"], detection: ["cargo/env", "rustup", "cargo/bin", "asdf", "mise"], rc: #"""
        if [[ -f "$HOME/.cargo/env" ]]; then source "$HOME/.cargo/env"; elif [[ -n ${HOMEBREW_PREFIX:-} && -d "$HOMEBREW_PREFIX/opt/rustup/bin" ]]; then typeset -U path; path=("$HOMEBREW_PREFIX/opt/rustup/bin" $path); fi
        """#),
        .init("ruby", "Ruby with rbenv", "Initialize rbenv. Ruby versions are chosen and installed separately.", "Languages", packages: ["rbenv"], detection: ["rbenv", "rvm", "chruby", "asdf", "mise"], rc: #"command -v rbenv >/dev/null 2>&1 && eval "$(rbenv init - zsh)""#),
        .init("starship", "Starship prompt", "Git branch and environment information in your prompt.", "Terminal experience", packages: ["starship"], detection: ["starship", "oh-my-zsh", "powerlevel", "p10k", "PROMPT=", "PS1=", "prezto"], rc: #"command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)""#),
        .init("fzf", "Fuzzy history search", "fzf keyboard bindings and completion.", "Terminal experience", packages: ["fzf"], detection: ["fzf", "oh-my-zsh", "zinit", "antidote"], rc: #"command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)"#),
        .init("suggestions", "Command suggestions", "Suggest commands from your shell history.", "Terminal experience", packages: ["zsh-autosuggestions"], detection: ["zsh-autosuggestions", "oh-my-zsh", "zinit", "antidote"], rc: #"[[ -z ${HOMEBREW_PREFIX:-} || ! -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] || source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh""#),
        .init("highlighting", "Syntax highlighting", "Highlight commands as you type. Loaded last in Orbit's block.", "Terminal experience", packages: ["zsh-syntax-highlighting"], detection: ["zsh-syntax-highlighting", "oh-my-zsh", "zinit", "antidote"], rc: #"[[ -z ${HOMEBREW_PREFIX:-} || ! -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] || source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh""#),
        .init("zoxide", "Smarter directory navigation", "Use z to jump to frequently visited folders. Existing cd is preserved.", "Terminal experience", packages: ["zoxide"], detection: ["zoxide"], rc: #"command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)""#),
        .init("cli", "Modern command-line tools", "bat, ripgrep, fd and eza. Standard cat, grep, find and ls stay unchanged.", "Terminal experience", packages: ["bat", "ripgrep", "fd", "eza"], detection: [], rc: "# Optional tools: bat, rg, fd and eza; no built-in aliases are replaced."),
        .init("custom-aliases", "Custom aliases", "Add your own shortcuts. Review commands and collisions before applying.", "Terminal experience", detection: [], rc: ""),
        .init("git-identity", "Git identity", "Set a global name and email with a private backup. Project-local identity stays separate.", "Developer essentials", packages: ["git"], detection: [], rc: "# Git identity is applied separately to ~/.gitconfig after review."),
        .init("prompt-theme", "Prompt theme", "An Orbit-owned Starship configuration; existing theme files are preserved.", "Terminal experience", packages: ["starship"], detection: ["STARSHIP_CONFIG"], rc: #"export STARSHIP_CONFIG="$HOME/.orbit-starship.toml""#)
    ]
    static let essentials: Set<String> = ["brew", "completion", "history", "aliases"]
}

struct ProfileSnapshot: Codable, Equatable {
    let name: String, data: Data?, permissions: Int, inode: UInt64
}
struct ProfileChange {
    let before: ProfileSnapshot
    let after: Data
    let block: String
}
struct TerminalPlan {
    let changes: [ProfileChange]
    let options: Set<String>
    var configuration = TerminalConfiguration()
}
struct ProfileReceipt: Codable {
    let originals: [ProfileSnapshot]
    let applied: [String: String]
    var configuration: TerminalConfiguration? = nil
}
struct ProfileProblem: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Reads files, never executes user profiles. Writes are restricted to reviewed home-directory profiles, Git config and the Orbit theme.
final class ProfileEngine {
    static let begin = "# >>> Orbit Terminal Setup >>>", end = "# <<< Orbit Terminal Setup <<<"
    let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home.standardizedFileURL }
    var backupRoot: URL { home.appendingPathComponent(".orbit-terminal-backups", isDirectory: true) }
    func fail(_ message: String) -> ProfileProblem { ProfileProblem(message: message) }
    func inspect(_ name: String) throws -> ProfileSnapshot {
        guard [".zprofile", ".zshrc", ".zshenv", ".zlogin", ".gitconfig", ".orbit-starship.toml"].contains(name), home.resolvingSymlinksInPath().path == home.path else { throw fail("Unsupported or linked profile location.") }
        let url = home.appendingPathComponent(name)
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return .init(name: name, data: nil, permissions: 0o600, inode: 0) }
            throw fail("Cannot inspect \(name).")
        }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1, info.st_uid == getuid(), info.st_size <= 1_000_000 else { throw fail("\(name) must be a small, owned regular file without links.") }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw fail("Cannot safely open \(name).") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0, opened.st_ino == info.st_ino, opened.st_dev == info.st_dev, opened.st_nlink == 1, opened.st_uid == getuid(), opened.st_mode & S_IFMT == S_IFREG else { throw fail("\(name) changed while scanning.") }
        let data = try handle.read(upToCount: 1_000_001) ?? Data()
        guard data.count <= 1_000_000, data.count == info.st_size, String(data: data, encoding: .utf8) != nil else { throw fail("\(name) is not UTF-8 text.") }
        return .init(name: name, data: data, permissions: Int(info.st_mode & 0o777), inode: UInt64(info.st_ino))
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func split(_ text: String) throws -> (outside: String, block: String) {
        let starts = text.components(separatedBy: begin).count - 1, ends = text.components(separatedBy: end).count - 1
        guard starts == ends, starts <= 1 else { throw ProfileProblem(message: "Orbit markers are incomplete or duplicated. Resolve them before applying.") }
        guard starts == 1 else { return (text, "") }
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.firstIndex(of: begin), let last = lines.firstIndex(of: end), first < last else { throw ProfileProblem(message: "Orbit markers must be on separate lines in the correct order.") }
        return ((Array(lines[..<first]) + Array(lines[(last+1)...])).joined(separator: "\n"), lines[first...last].joined(separator: "\n"))
    }
    func scan() throws -> ([ProfileSnapshot], String, Set<String>) {
        if let directory = ProcessInfo.processInfo.environment["ZDOTDIR"], URL(fileURLWithPath: directory).standardizedFileURL != home { throw fail("A custom ZDOTDIR is active. This version supports home-directory Zsh profiles only.") }
        let snapshots = try [".zprofile", ".zshrc", ".zshenv", ".zlogin"].map(inspect)
        var outside = "", managed = Set<String>()
        for snapshot in snapshots {
            let pieces = try Self.split(String(data: snapshot.data ?? Data(), encoding: .utf8)!)
            if ![".zprofile", ".zshrc"].contains(snapshot.name), !pieces.block.isEmpty { throw fail("Orbit blocks outside .zprofile/.zshrc are unsupported. Review your existing layout manually.") }
            outside += pieces.outside + "\n"
            for option in TerminalOption.all where pieces.block.contains("# orbit-option: \(option.id)\n") { managed.insert(option.id) }
        }
        let active = outside.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
        guard !active.contains("ZDOTDIR") else { throw fail("Your profiles configure ZDOTDIR. Home-directory updates are blocked to avoid modifying the wrong setup.") }
        return (snapshots, active, managed)
    }
    static func conflicts(_ option: TerminalOption, outside: String) -> Bool {
        option.detection.contains { outside.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }
    func plan(_ selected: Set<String>, configuration: TerminalConfiguration = TerminalConfiguration()) throws -> TerminalPlan {
        let options = try configuration.options()
        guard selected.isSubset(of: Set(TerminalOption.all.map(\.id))) else { throw fail("Unknown terminal option.") }
        let (snapshots, outside, _) = try scan()
        for option in options where selected.contains(option.id) && Self.conflicts(option, outside: outside) { throw fail("\(option.title) has existing settings outside Orbit. Leave it unchecked and keep your current configuration.") }
        if selected.contains("node") && outside.range(of: #"(node|node@\S+)/bin"#, options: .regularExpression) != nil { throw fail("An existing Node PATH conflicts with NVM. Review it manually first.") }
        if selected.contains("custom-aliases") {
            for alias in configuration.aliases {
                let escaped = NSRegularExpression.escapedPattern(for: alias.name)
                let pattern = "(?m)(alias\\s+" + escaped + "=|function\\s+" + escaped + "\\b|\\b" + escaped + "\\s*\\(\\))"
                guard outside.range(of: pattern, options: .regularExpression) == nil else { throw fail("Alias " + alias.name + " already exists outside Orbit.") }
            }
        }
        if selected.contains("prompt-theme"), !selected.contains("starship") { throw fail("Select Starship prompt before choosing a theme.") }
        var changes: [ProfileChange] = []
        for name in [".zprofile", ".zshrc"] {
            let snapshot = snapshots.first { $0.name == name }!
            let old = String(data: snapshot.data ?? Data(), encoding: .utf8)!
            let pieces = try Self.split(old)
            let ordered = options.enumerated().sorted { left, right in
                let a = left.element.id == "prompt-theme" ? -1 : left.element.id == "highlighting" ? 1000 : left.offset
                let b = right.element.id == "prompt-theme" ? -1 : right.element.id == "highlighting" ? 1000 : right.offset
                return a < b
            }.map(\.element)
            let snippets = ordered.filter { selected.contains($0.id) }.compactMap { option -> String? in
                let code = name == ".zprofile" ? option.profile : option.rc
                return code.isEmpty ? nil : "# orbit-option: \(option.id)\n" + code
            }
            let block = snippets.isEmpty ? "" : Self.begin + "\n" + snippets.joined(separator: "\n\n") + "\n" + Self.end + "\n"
            var after: String
            if pieces.block.isEmpty { after = old + (old.isEmpty || old.hasSuffix("\n") ? "" : "\n") + block }
            else {
                let start = old.range(of: Self.begin)!, finish = old.range(of: Self.end)!
                let endIndex = old[finish.upperBound...].hasPrefix("\n") ? old.index(after: finish.upperBound) : finish.upperBound
                after = String(old[..<start.lowerBound]) + block + String(old[endIndex...])
            }
            let data = Data(after.utf8)
            guard data.count <= 1_000_000 else { throw fail("\(name) would exceed the supported profile size. No changes were made.") }
            if data != (snapshot.data ?? Data()) { changes.append(.init(before: snapshot, after: data, block: block)) }
        }
        if selected.contains("prompt-theme") {
            let before = try inspect(".orbit-starship.toml")
            let after = Data(configuration.starship.utf8)
            if before.data != after { changes.append(.init(before: before, after: after, block: configuration.starship)) }
        }
        if selected.contains("git-identity") {
            guard !configuration.gitName.trimmingCharacters(in: .whitespaces).isEmpty, configuration.gitEmail.contains("@") else { throw fail("Enter a Git name and valid email before reviewing.") }
            let before = try inspect(".gitconfig")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-git-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            try (before.data ?? Data()).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            for (key, value) in [("user.name", configuration.gitName), ("user.email", configuration.gitEmail)] {
                let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/git"); task.arguments = ["config", "--file", file.path, "--replace-all", key, value]; task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
                try task.run(); task.waitUntilExit(); guard task.terminationStatus == 0 else { throw fail("Could not prepare Git identity. Existing config is preserved.") }
            }
            let after = try Data(contentsOf: file)
            if before.data != after { changes.append(.init(before: before, after: after, block: "user.name = " + configuration.gitName + "\nuser.email = " + configuration.gitEmail)) }
        }
        guard changes.allSatisfy({ $0.after.count <= 1_000_000 }) else { throw fail("A setup file would exceed the supported size.") }
        return .init(changes: changes, options: selected, configuration: configuration)
    }
    func validate(_ plan: TerminalPlan) throws {
        for change in plan.changes {
            guard try inspect(change.before.name) == change.before else { throw fail("\(change.before.name) changed since review. Scan and review again.") }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-profile-" + UUID().uuidString)
            try change.after.write(to: temporary, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/zsh"); task.arguments = ["-f", "-n", temporary.path]
            if change.before.name == ".gitconfig" { task.executableURL = URL(fileURLWithPath: "/usr/bin/git"); task.arguments = ["config", "--file", temporary.path, "--list"] }
            if change.before.name == ".orbit-starship.toml" { continue }
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            try task.run(); task.waitUntilExit()
            guard task.terminationStatus == 0 else { throw fail("\(change.before.name) has a Zsh syntax error. No profile was changed.") }
        }
    }
    func checkBackupRoot(create: Bool) throws {
        var info = stat()
        if lstat(backupRoot.path, &info) != 0 {
            guard errno == ENOENT, create else { throw fail("No Orbit backup is available.") }
            try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } else {
            guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw fail("The backup folder must be private, owned, and not a link.") }
        }
    }
    func write(_ data: Data?, snapshot: ProfileSnapshot) throws {
        let url = home.appendingPathComponent(snapshot.name)
        if let data {
            let temporary = home.appendingPathComponent(".orbit-profile-temp-" + UUID().uuidString)
            let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(snapshot.permissions))
            guard descriptor >= 0 else { throw fail("Cannot create a private profile replacement.") }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
            try handle.write(contentsOf: data)
            guard fchmod(descriptor, mode_t(snapshot.permissions)) == 0, fsync(descriptor) == 0 else { throw fail("Could not save profile contents and permissions.") }
            guard Darwin.rename(temporary.path, url.path) == 0 else { throw fail("Could not replace \(snapshot.name).") }
        } else { try FileManager.default.removeItem(at: url) }
    }
    @discardableResult func apply(_ plan: TerminalPlan) throws -> URL {
        guard !plan.changes.isEmpty else { throw fail("No changes to apply.") }
        let fresh = try self.plan(plan.options, configuration: plan.configuration)
        guard fresh.changes.count == plan.changes.count, zip(fresh.changes, plan.changes).allSatisfy({ $0.before == $1.before && $0.after == $1.after }) else { throw fail("Profiles changed since review. Scan and review again.") }
        try validate(plan); try checkBackupRoot(create: true)
        let directory = backupRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let receipt = ProfileReceipt(originals: plan.changes.map(\.before), applied: Dictionary(uniqueKeysWithValues: plan.changes.map { ($0.before.name, Self.digest($0.after)) }), configuration: plan.configuration)
        let receiptURL = directory.appendingPathComponent("pending.json")
        for original in receipt.originals {
            if let data = original.data {
                let file = directory.appendingPathComponent(original.name + ".backup")
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
        }
        try JSONEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiptURL.path)
        var written: [ProfileChange] = []
        do {
            for change in plan.changes {
                guard try inspect(change.before.name) == change.before else { throw fail("Profile changed during apply.") }
                written.append(change); try write(change.after, snapshot: change.before)
            }
            try FileManager.default.moveItem(at: receiptURL, to: directory.appendingPathComponent("receipt.json"))
        } catch {
            for change in written.reversed() {
                guard let observed = try? inspect(change.before.name), observed.data == change.after else { continue }
                try? write(change.before.data, snapshot: change.before)
            }
            throw fail("Apply could not finish. Backup retained at \(directory.path). \(error.localizedDescription)")
        }
        return directory
    }
    func backupDirectories() -> [URL] {
        guard (try? checkBackupRoot(create: false)) != nil else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: backupRoot.path)) ?? []).filter { UUID(uuidString: $0) != nil }.map { backupRoot.appendingPathComponent($0, isDirectory: true) }.filter { $0.resolvingSymlinksInPath().path == $0.path && FileManager.default.fileExists(atPath: $0.appendingPathComponent("receipt.json").path) }.sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
    }
    func latestReceipt() throws -> (URL, ProfileReceipt) {
        try checkBackupRoot(create: false)
        let directories = try FileManager.default.contentsOfDirectory(atPath: backupRoot.path).filter { UUID(uuidString: $0) != nil }.map { backupRoot.appendingPathComponent($0, isDirectory: true) }.sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
        guard let directory = directories.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("receipt.json").path) }), directory.resolvingSymlinksInPath().path == directory.path else { throw fail("No valid backup is available.") }
        let file = directory.appendingPathComponent("receipt.json")
        guard file.resolvingSymlinksInPath().path == file.path, (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 3_000_000 else { throw fail("Invalid backup receipt.") }
        var info = stat()
        guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw fail("The backup receipt must be a private regular file.") }
        let receipt = try JSONDecoder().decode(ProfileReceipt.self, from: Data(contentsOf: file))
        guard !receipt.originals.isEmpty, receipt.originals.count <= 4, Set(receipt.originals.map(\.name)).count == receipt.originals.count, receipt.originals.allSatisfy({ [".zprofile", ".zshrc", ".gitconfig", ".orbit-starship.toml"].contains($0.name) && $0.permissions >= 0 && $0.permissions <= 0o777 && ($0.data?.count ?? 0) <= 1_000_000 }), Set(receipt.applied.keys) == Set(receipt.originals.map(\.name)) else { throw fail("Invalid backup targets.") }
        return (directory, receipt)
    }
    func restore() throws {
        let (directory, receipt) = try latestReceipt()
        let current = try receipt.originals.map { try inspect($0.name) }
        for snapshot in current {
            guard let data = snapshot.data, Self.digest(data) == receipt.applied[snapshot.name], snapshot.permissions == receipt.originals.first(where: { $0.name == snapshot.name })?.permissions else { throw fail("\(snapshot.name) was edited after Orbit applied it. Restore is blocked to preserve those edits. The backup remains available.") }
        }
        var restored: [ProfileSnapshot] = []
        do {
            for original in receipt.originals {
                guard try inspect(original.name) == current.first(where: { $0.name == original.name }) else { throw fail("Profile changed during restore.") }
                restored.append(original); try write(original.data, snapshot: original)
            }
            try FileManager.default.moveItem(at: directory, to: backupRoot.appendingPathComponent("restored-" + directory.lastPathComponent))
        } catch {
            for original in restored.reversed() {
                guard let observed = try? inspect(original.name), observed.data == original.data else { continue }
                if let snapshot = current.first(where: { $0.name == original.name }) { try? write(snapshot.data, snapshot: snapshot) }
            }
            throw fail("Restore could not finish. Backup retained. \(error.localizedDescription)")
        }
    }
}

@MainActor final class TerminalState: ObservableObject {
    @Published var details: String?
    @Published var aliasName = ""
    @Published var aliasCommand = ""
    @Published var tab = "Environment"
    @Published var configuration = TerminalConfiguration()
    @Published var snapshots: [ProfileSnapshot] = []
    @Published var managed: Set<String> = []
    @Published var tools: [TerminalTool] = []
    @Published var sshKeys: [String] = []
    @Published var project: TerminalProject?
    @Published var runtimeChoices: Set<String> = []
    @Published var runtimeReview: String?
    @Published var runtimeOutput = ""
    @Published var showRuntime = false
    @Published var selected = TerminalOption.essentials
    @Published var outside = ""
    @Published var scanned = false
    @Published var message = "Scan your profiles before choosing settings."
    @Published var plan: TerminalPlan?
    @Published var showRestore = false
    @Published var working = false
    @Published var missing: [String] = []
    @Published var backupURL: URL?
    let engine: ProfileEngine
    let preferences: UserDefaults?
    let packageLoader: (String) async throws -> Package
    init(engine: ProfileEngine = ProfileEngine(), packageLoader: ((String) async throws -> Package)? = nil, preferences: UserDefaults? = nil) {
        self.engine = engine; self.packageLoader = packageLoader ?? Self.fetchPackage; self.preferences = preferences
        if let data = preferences?.data(forKey: "orbit.terminal.configuration"), let saved = try? JSONDecoder().decode(TerminalConfiguration.self, from: data), (try? saved.validate()) != nil { configuration = saved }
    }
    static func fetchPackage(_ token: String) async throws -> Package {
        guard OfficialCatalog.validToken(token) else { throw ProfileProblem(message: "Invalid package token.") }
        var request = URLRequest(url: URL(string: OfficialCatalog.source(token, cask: false))!)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4_000_000 else { throw ProfileProblem(message: "Could not verify \(token) in the official catalog.") }
        let rows = try OfficialCatalog.parse(Data("[".utf8) + data + Data("]".utf8), cask: false)
        guard let package = rows.first, package.token == token, package.installable else { throw ProfileProblem(message: "\(token) is unavailable.") }
        return package
    }
    func refreshBackup() { backupURL = try? engine.latestReceipt().0 }
    func scan() {
        refreshBackup()
        do {
            let (files, text, managed) = try engine.scan(); outside = text; snapshots = files; self.managed = managed
            selected = (scanned ? selected : TerminalOption.essentials.union(managed)).filter { id in !TerminalOption.all.contains { $0.id == id && ProfileEngine.conflicts($0, outside: text) } }
            scanned = true; plan = nil; message = "Profiles scanned. Existing settings outside Orbit will be preserved."
        } catch { scanned = false; plan = nil; message = error.localizedDescription }
    }
    func review() { do { let new = try engine.plan(selected, configuration: configuration); try engine.validate(new); plan = new; tab = "Changes & Backups"; message = new.changes.isEmpty ? "Your profiles already match these choices." : "Review the Orbit blocks below. Nothing has changed yet." } catch { plan = nil; message = error.localizedDescription } }
    func apply() { guard let plan else { return }; guard plan.options == selected, plan.configuration == configuration else { self.plan = nil; message = "Choices changed. Review again before applying."; return }; do { let backup = try engine.apply(plan); if let saved = try? JSONEncoder().encode(plan.configuration) { preferences?.set(saved, forKey: "orbit.terminal.configuration") }; self.plan = nil; managed = selected; refreshBackup(); message = "Applied. Open a new Terminal window to use the settings. Backup: \(backup.path)" } catch { self.plan = nil; message = error.localizedDescription } }
    func restore() { do { try engine.restore(); preferences?.removeObject(forKey: "orbit.terminal.configuration"); configuration = (try? engine.latestReceipt().1.configuration) ?? TerminalConfiguration(); if let data = try? JSONEncoder().encode(configuration) { preferences?.set(data, forKey: "orbit.terminal.configuration") }; selected = []; scanned = false; plan = nil; refreshBackup(); message = "Backup restored. Scan again to review your profiles." } catch { message = error.localizedDescription } }
    func refreshMissing(store: Store) {
        let prefix = store.brew == "/usr/local/bin/brew" ? "/usr/local" : "/opt/homebrew"
        let tokens = Set(((try? configuration.options()) ?? TerminalOption.all).filter { selected.contains($0.id) || runtimeChoices.contains($0.id) }.flatMap(\.packages))
        missing = tokens.filter { token in
            let executable = ["git": "git", "uv": "uv", "go": "go", "rustup": "rustup", "rbenv": "rbenv", "starship": "starship", "fzf": "fzf"][token]
            if let executable, tools.contains(where: { $0.id == executable && !$0.path.hasPrefix("/usr/bin/") }) { return false }
            if token == "nvm", FileManager.default.fileExists(atPath: engine.home.appendingPathComponent(".nvm/nvm.sh").path) { return false }
            if token == "rustup", FileManager.default.fileExists(atPath: engine.home.appendingPathComponent(".cargo/env").path) { return false }
            return !FileManager.default.fileExists(atPath: prefix + "/opt/" + token) && !store.packages.contains { $0.token == token && store.installed.contains($0.id) }
        }.sorted()
    }
    func queuePackages(store: Store) async {
        guard !store.locked, !working, !missing.isEmpty else { return }
        working = true; defer { working = false }
        do {
            var packages: [Package] = []
            for token in missing {
                let package = try await packageLoader(token)
                guard package.token == token, !package.cask, package.installable else { throw ProfileProblem(message: "Invalid package metadata.") }
                packages.append(package)
            }
            guard !store.lockedWithoutTerminal, store.startupReady, store.inventoryKnown else { throw ProfileProblem(message: "Installation state changed. Try adding tools again when Orbit is ready.") }
            for package in packages { store.registerPersonal(package); if store.canInstall(package) { store.selected.insert(package.id) } }
            store.navigate(.install); message = "Tools added to the install selection. Review installation there; return here afterward."
        } catch { message = error.localizedDescription }
    }
}
