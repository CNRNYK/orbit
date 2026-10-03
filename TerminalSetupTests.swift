import Foundation
import Darwin

@MainActor enum TerminalSetupTests {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("orbit-terminal-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func home(_ name: String) throws -> URL { let url = root.appendingPathComponent(name); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false); return url }
        let directory = try home("roundtrip"), engine = ProfileEngine(home: directory)
        let original = Data("# keep my private setup\nexport CUSTOM_SETTING='unchanged'\n".utf8)
        try original.write(to: directory.appendingPathComponent(".zshrc"))
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: directory.appendingPathComponent(".zshrc").path)
        let selected = Set(TerminalOption.all.map(\.id))
        let plan = try engine.plan(selected)
        precondition(plan.changes.count == 2 && !FileManager.default.fileExists(atPath: directory.appendingPathComponent(".zprofile").path))
        try engine.validate(plan)
        let backup = try engine.apply(plan)
        let rc = try String(contentsOf: directory.appendingPathComponent(".zshrc"), encoding: .utf8)
        precondition(rc.hasPrefix(String(data: original, encoding: .utf8)!))
        precondition(rc.components(separatedBy: ProfileEngine.begin).count == 2)
        precondition(try! engine.plan(selected).changes.isEmpty, "Repeat apply must not duplicate blocks")
        let receiptAttributes = try FileManager.default.attributesOfItem(atPath: backup.appendingPathComponent("receipt.json").path)
        precondition(receiptAttributes[.posixPermissions] as? Int == 0o600)
        try engine.restore()
        precondition(try! Data(contentsOf: directory.appendingPathComponent(".zshrc")) == original)
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".zprofile").path), "Originally absent profiles must be removed on restore")
        precondition(try! engine.inspect(".zshrc").permissions == 0o640)
        _ = try engine.apply(engine.plan(["history"]))
        let changed = try engine.plan(["aliases"])
        _ = try engine.apply(changed)
        let replaced = try String(contentsOf: directory.appendingPathComponent(".zshrc"), encoding: .utf8)
        precondition(!replaced.contains("orbit-option: history") && replaced.contains("orbit-option: aliases"))
        let current = try engine.inspect(".zshrc").data!
        try (current + Data("# user edit\n".utf8)).write(to: directory.appendingPathComponent(".zshrc"))
        precondition((try? engine.restore()) == nil, "Post-apply edits must block restore")
        let staleHome = try home("stale"), stale = ProfileEngine(home: staleHome)
        let stalePlan = try stale.plan(["history"])
        try Data("export KEEP=1\n".utf8).write(to: staleHome.appendingPathComponent(".zshrc"))
        precondition((try? stale.apply(stalePlan)) == nil)
        precondition(try! String(contentsOf: staleHome.appendingPathComponent(".zshrc"), encoding: .utf8) == "export KEEP=1\n")
        let envHome = try home("env-change"), env = ProfileEngine(home: envHome)
        let envPlan = try env.plan(["python"])
        try Data("export ZDOTDIR=/another/place\n".utf8).write(to: envHome.appendingPathComponent(".zshenv"))
        precondition((try? env.apply(envPlan)) == nil)
        let invalidHome = try home("invalid"), invalid = ProfileEngine(home: invalidHome)
        try Data("if then\n".utf8).write(to: invalidHome.appendingPathComponent(".zshrc"))
        precondition((try? invalid.apply(invalid.plan(["history"]))) == nil, "Syntax error must leave files untouched")
        let linkHome = try home("links"), link = ProfileEngine(home: linkHome)
        let target = root.appendingPathComponent("target"); try Data("untouched".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: linkHome.appendingPathComponent(".zshrc"), withDestinationURL: target)
        precondition((try? link.plan(["history"])) == nil)
        try FileManager.default.removeItem(at: linkHome.appendingPathComponent(".zshrc"))
        precondition(Darwin.link(target.path, linkHome.appendingPathComponent(".zshrc").path) == 0)
        precondition((try? link.plan(["history"])) == nil, "Hard-linked profiles must be blocked")
        let backupHome = try home("backup-link"), blocked = ProfileEngine(home: backupHome)
        try FileManager.default.createSymbolicLink(at: blocked.backupRoot, withDestinationURL: root)
        precondition((try? blocked.apply(blocked.plan(["history"]))) == nil)
        precondition((try? ProfileEngine.split(ProfileEngine.begin)) == nil)
        precondition((try? ProfileEngine.split(ProfileEngine.begin + "\n" + ProfileEngine.end + "\n" + ProfileEngine.begin + "\n" + ProfileEngine.end)) == nil)
        let existingHome = try home("existing"), existing = ProfileEngine(home: existingHome)
        try Data("export NVM_DIR=\"$HOME/.nvm\"\neval \"$(starship init zsh)\"\n".utf8).write(to: existingHome.appendingPathComponent(".zshrc"))
        precondition((try? existing.plan(["node"])) == nil && (try? existing.plan(["starship"])) == nil)
        let state = TerminalState(engine: existing); state.scan()
        precondition(state.scanned && !state.selected.contains("node"))
        let runtimeOptions = TerminalOption.all.filter { $0.group == "Languages" }
        precondition(Set(runtimeOptions.map(\.id)) == ["node", "python", "java", "go", "rust", "ruby"])
        precondition(!TerminalOption.all.flatMap(\.packages).contains("node") && !TerminalOption.all.flatMap(\.packages).contains("corepack") && !TerminalOption.all.flatMap(\.packages).contains("ruby-build"))
        let noExecuteHome = try home("no-execution"), noExecute = ProfileEngine(home: noExecuteHome)
        let marker = root.appendingPathComponent("must-not-exist")
        try Data("touch '\(marker.path)'\n".utf8).write(to: noExecuteHome.appendingPathComponent(".zshrc"))
        try noExecute.validate(noExecute.plan(["history"]))
        precondition(!FileManager.default.fileExists(atPath: marker.path), "Syntax validation must never execute user code")
        let model = Store(preview: true); model.navigate(.terminal)
        precondition(model.mode == .terminal)
        let fixture = try OfficialCatalog.parse(Data(#"[{"name":"fixture-terminal","tap":"homebrew/core","desc":"fixture","homepage":"https://example.com","versions":{"stable":"1.0"}}]"#.utf8), cask: false)[0]
        let queueModel = Store(persistSelection: false); queueModel.selected = []; queueModel.appPresent = { _ in false }; queueModel.inventoryKnown = true
        let noCommands = FakeCommands([]); queueModel.commandRunner = noCommands
        let queue = TerminalState(engine: engine, packageLoader: { _ in fixture }); queue.missing = [fixture.token]
        await queue.queuePackages(store: queueModel)
        let commandCalls = await noCommands.recorded(); precondition(commandCalls.isEmpty)
        precondition(queueModel.selected == [fixture.id] && queueModel.packages.contains { $0.id == fixture.id } && queueModel.mode == .install)
        precondition(Catalog.export(queueModel.packages.filter { queueModel.selected.contains($0.id) }).contains("fixture-terminal"))
        let failed = TerminalState(engine: engine, packageLoader: { token in if token == fixture.token { return fixture }; throw ProfileProblem(message: "offline") })
        failed.missing = [fixture.token, "missing-fixture"]
        queueModel.selected = []; queueModel.navigate(.terminal)
        let count = queueModel.packages.count
        await failed.queuePackages(store: queueModel)
        precondition(queueModel.selected.isEmpty && queueModel.packages.count == count && queueModel.mode == .terminal)
        let busy = TerminalState(engine: engine, packageLoader: { _ in queueModel.preparing = true; return fixture }); busy.missing = [fixture.token]
        await busy.queuePackages(store: queueModel)
        precondition(queueModel.selected.isEmpty, "A changing installation state must block package registration")
        queueModel.preparing = false
        if CommandLine.arguments.contains("--live-terminal-metadata") {
            let tokens = Set(TerminalOption.all.flatMap(\.packages)).sorted()
            for token in tokens { let verified = try await TerminalState.fetchPackage(token); precondition(verified.token == token && verified.installable) }
            print("PASS: live official metadata for \(tokens.count) optional terminal tools; no installation")
        }
        print("PASS: terminal plan review, profile preservation, private backups, idempotence, restore, edited/stale/symlink/hardlink/custom-directory protection, syntax-only validation, language choices and no direct dependencies")
    }
}
