import SwiftUI
import AppKit

struct TerminalSetupView: View {
    @ObservedObject var store: Store
    @ObservedObject var state: TerminalState
    private let tabs = ["Environment", "Shell & Appearance", "Changes & Backups"]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 16) {
                Label("Zsh profiles", systemImage: "terminal")
                Label("\(state.tools.count) tools found", systemImage: "shippingbox")
                Label("\(state.missing.count) missing tools", systemImage: "arrow.down.circle")
                Label("\(externalCount) external configurations", systemImage: "person.crop.circle")
                Spacer()
            }.font(.caption).foregroundStyle(.secondary)
            Text(state.message).font(.callout).textSelection(.enabled)
            Picker("Section", selection: $state.tab) { ForEach(tabs, id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if state.tab == "Environment" { environment }
                    else if state.tab == "Shell & Appearance" { shell }
                    else { changes }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            }
            Divider()
            HStack {
                Button("Import setup", systemImage: "square.and.arrow.down") { state.importSetup(store: store) }.disabled(store.preview || !state.scanned)
                Button("Export setup", systemImage: "square.and.arrow.up") { state.exportSetup() }.disabled(store.preview || !state.scanned)
                Spacer()
                if state.working { ProgressView().controlSize(.small) }
                Button("Review changes") { state.refreshMissing(store: store); state.review() }.disabled(!state.scanned || state.working)
                Button("Apply reviewed changes") { state.apply() }.buttonStyle(.borderedProminent).disabled(store.preview || state.plan?.changes.isEmpty != false || state.working)
            }
        }.padding(24).disabled(store.locked || state.working)
        .task { if !store.preview { if !state.scanned { state.scan() }; state.refreshMissing(store: store); await state.inventory(); state.refreshMissing(store: store) } }
        .onChange(of: state.configuration) { _, _ in state.plan = nil; state.runtimeReview = nil; state.refreshMissing(store: store) }
        .onChange(of: state.runtimeChoices) { _, _ in state.runtimeReview = nil; state.refreshMissing(store: store) }
        .onChange(of: state.selected) { _, _ in state.plan = nil; state.runtimeReview = nil; state.refreshMissing(store: store) }
        .sheet(isPresented: Binding(get: { state.details != nil }, set: { if !$0 { state.details = nil } })) {
            VStack(alignment: .leading, spacing: 16) { Text("Configuration details").font(.title2.bold()); Text(state.details ?? "").textSelection(.enabled); HStack { Spacer(); Button("Done") { state.details = nil } } }.padding(24).frame(width: 530)
        }
        .alert("Restore latest setup backup?", isPresented: $state.showRestore) {
            Button("Cancel", role: .cancel) {}; Button("Restore") { state.restore() }
        } message: { Text("Restore the files saved before the latest Orbit change. Any later file edits block restoration. Older backups can be restored in sequence, newest first.") }
        .alert("Run reviewed runtime setup?", isPresented: $state.showRuntime) {
            Button("Cancel", role: .cancel) {}; Button("Run setup") { Task { await state.runRuntimes(store: store) } }
        } message: { Text("The displayed commands download selected runtimes and may install a global package manager inside NVM. No project dependencies are installed. Successful downloads remain if a later step fails.") }
    }
    private var externalCount: Int { TerminalOption.all.filter { ProfileEngine.conflicts($0, outside: state.outside) }.count }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text("Terminal Setup").font(.largeTitle.bold()); Text("Understand your environment. Choose your tools. Review every change.").foregroundStyle(.secondary) }
            Spacer()
            Button("Rescan", systemImage: "arrow.clockwise") { state.scan(); state.refreshMissing(store: store); Task { await state.inventory(); state.refreshMissing(store: store) } }
        }
    }
    private func card<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { Label(title, systemImage: symbol).font(.headline); content() }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func options(_ group: String) -> some View {
        ForEach(TerminalOption.all.filter { $0.group == group }) { option in
            let external = ProfileEngine.conflicts(option, outside: state.outside)
            let packages = ((try? state.configuration.options()) ?? TerminalOption.all).first { $0.id == option.id }?.packages ?? option.packages
            let missing = !Set(packages).intersection(state.missing).isEmpty
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(option.id)).foregroundStyle(.blue).frame(width: 24).padding(.top, 3)
                Toggle(isOn: Binding(get: { state.selected.contains(option.id) }, set: { value in if value { state.selected.insert(option.id) } else { state.selected.remove(option.id) } })) {
                    VStack(alignment: .leading, spacing: 4) { Text(option.title).font(.body.weight(.semibold)); Text(option.detail).font(.caption).foregroundStyle(.secondary) }
                }.toggleStyle(.checkbox).disabled(!state.scanned || external)
                Spacer(minLength: 8)
                Text(external ? "Configured outside Orbit" : missing && state.selected.contains(option.id) ? "Needs installation" : state.managed.contains(option.id) ? "Configured by Orbit" : "Available to configure").font(.caption).foregroundStyle(external ? Color.secondary : missing && state.selected.contains(option.id) ? Color.orange : Color.secondary)
                Button { state.details = external ? "Existing configuration references were found. This does not verify that the tool is installed or working. Orbit preserves these settings.\n\n" + state.configurationDetails(option).joined(separator: "\n") : option.detail + "\n\n" + (option.packages.isEmpty ? "No additional Homebrew packages." : "Related packages: " + option.packages.joined(separator: ", ")) } label: { Image(systemName: "info.circle") }
            }
        }
    }
    private func symbol(_ id: String) -> String {
        switch id { case "node", "python", "java", "go", "rust", "ruby": return "chevron.left.forwardslash.chevron.right"; case "git", "git-identity": return "arrow.triangle.branch"; case "history", "fzf": return "clock"; case "starship", "prompt-theme": return "sparkles"; case "brew": return "shippingbox"; case "custom-aliases", "aliases": return "text.badge.plus"; default: return "terminal" }
    }
    private var environment: some View {
        Group {
            card("Starter selections", symbol: "square.stack.3d.up") {
                HStack { ForEach(["Minimal", "Web Development", "Python Development", "QA & Automation"], id: \.self) { preset in Button(preset) { state.choosePreset(preset) }.disabled(!state.scanned) } }
                Text("A starting point you can customize. Existing Orbit choices are retained; external settings are preserved.").font(.caption).foregroundStyle(.secondary)
            }
            card("Languages & versions", symbol: "chevron.left.forwardslash.chevron.right") {
                options("Languages")
                Divider()
                HStack {
                    VStack(alignment: .leading) { Text("Node version / --lts").font(.caption); TextField("Node version or --lts", text: $state.configuration.nodeVersion) }.frame(maxWidth: 170)
                    VStack(alignment: .leading) { Text("Python version").font(.caption); TextField("Python version", text: $state.configuration.pythonVersion) }.frame(maxWidth: 150)
                    Picker("Java", selection: $state.configuration.javaVersion) { ForEach(["17", "21", "25"], id: \.self) { Text($0) } }.frame(maxWidth: 160)
                    VStack(alignment: .leading) { Text("Ruby version").font(.caption); TextField("Ruby version", text: $state.configuration.rubyVersion) }.frame(maxWidth: 150)
                }
                HStack {
                    Picker("Package manager", selection: $state.configuration.packageManager) { ForEach(["npm", "pnpm", "Yarn"], id: \.self) { Text($0) } }.frame(width: 230)
                    if state.configuration.packageManager != "npm" { TextField("Version or latest", text: $state.configuration.packageManagerVersion).frame(width: 160) }
                }
                Text("npm comes with Node. pnpm/Yarn are optional. Orbit never adds Homebrew Node or Corepack automatically. Existing managers stay in control; runtime downloads are a separate reviewed action.").font(.caption).foregroundStyle(.secondary)
                Text("NVM can be installed through the reviewed Homebrew flow, but upstream NVM does not support Homebrew installations. Existing official NVM installations are detected too.").font(.caption).foregroundStyle(.secondary)
                if !state.missing.isEmpty { Text("Missing packages: " + state.missing.joined(separator: ", ")).font(.callout); Button("Review missing tools in Homebrew Center", systemImage: "shippingbox") { Task { await state.queuePackages(store: store) } }.disabled(store.preview || !store.startupReady || !store.inventoryKnown) }
                HStack {
                    ForEach(["node", "python", "rust", "ruby"], id: \.self) { id in
                        Toggle("Download " + id.capitalized, isOn: Binding(get: { state.runtimeChoices.contains(id) }, set: { value in if value { state.runtimeChoices.insert(id) } else { state.runtimeChoices.remove(id) } })).toggleStyle(.checkbox)
                    }
                }
                Text("Downloads can be selected independently for an existing manager. Profile integrations and downloads are still applied separately.").font(.caption).foregroundStyle(.secondary)
                Button("Review runtime downloads", systemImage: "arrow.down.circle") { state.reviewRuntimes(); state.tab = "Changes & Backups" }.disabled(!state.scanned)
            }
            card("Project requirements", symbol: "folder") {
                HStack { Button("Choose project folder") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; if panel.runModal() == .OK, let url = panel.url { state.inspectProject(url) } }.disabled(store.preview); if state.project != nil { Button("Use suggested versions") { state.useProjectVersions() } } }
                Text("Reads version files, package.json, pyproject.toml and lockfile names. No project commands or dependency installs run.").font(.caption).foregroundStyle(.secondary)
                if let project = state.project { Text(project.folder.lastPathComponent).font(.headline); ForEach(project.findings, id: \.self) { Text($0).font(.callout).textSelection(.enabled) } }
            }
            card("Detected tools", symbol: "checkmark.seal") {
                HStack { Text("Paths found on disk are candidates, not verified active shell versions.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Verify tools") { Task { await state.verifyTools(store: store) } }.disabled(store.preview || state.tools.isEmpty) }
                ForEach(state.tools) { tool in HStack(alignment: .top) { Text(tool.id).font(.body.weight(.semibold)).frame(width: 90, alignment: .leading); VStack(alignment: .leading) { Text(tool.version).font(.callout); Text(tool.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }; Spacer() } }
                if state.tools.isEmpty { Text("Rescan to discover installed tools.").foregroundStyle(.secondary) }
            }
        }
    }
    private var shell: some View {
        Group {
            card("Developer essentials", symbol: "terminal") { options("Developer essentials") }
            card("Git identity & SSH", symbol: "arrow.triangle.branch") {
                HStack { TextField("Git author name", text: $state.configuration.gitName); TextField("Git author email", text: $state.configuration.gitEmail) }
                Text("Enable Git identity above to review a global ~/.gitconfig change. Existing sections are preserved and backed up. Project-local identity is configured separately.").font(.caption).foregroundStyle(.secondary)
                if let project = state.project {
                    Button("Copy project-local identity commands") { let command = "git -C \(TerminalConfiguration.quote(project.folder.path)) config user.name \(TerminalConfiguration.quote(state.configuration.gitName))\ngit -C \(TerminalConfiguration.quote(project.folder.path)) config user.email \(TerminalConfiguration.quote(state.configuration.gitEmail))"; copy(command); state.message = "Copied project-local Git commands. Run them only in the intended repository." }
                }
                Text(state.sshKeys.isEmpty ? "No public SSH key filenames found in ~/.ssh. Private keys are not opened." : "Public SSH key filenames: " + state.sshKeys.joined(separator: ", ") + ". Authentication has not been tested.").font(.caption).foregroundStyle(.secondary)
                Link("GitHub SSH setup guide", destination: URL(string: "https://docs.github.com/en/authentication/connecting-to-github-with-ssh")!)
            }
            card("Terminal experience", symbol: "sparkles") { options("Terminal experience") }
            card("Prompt preview", symbol: "paintpalette") {
                Picker("Starship theme", selection: $state.configuration.theme) { ForEach(["Minimal", "Developer", "Compact"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.configuration.theme == "Developer" ? "~/Projects/example on git:main via Node" : "example git:main").foregroundStyle(.green)
                    Text("❯ git status").foregroundStyle(.white)
                }.font(.system(.body, design: .monospaced)).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.06, green: 0.09, blue: 0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Illustrative preview. Enable Starship prompt and Prompt theme above to apply. Orbit writes ~/.orbit-starship.toml and preserves your existing Starship config. Choose a Nerd Font in your terminal's own font settings for full symbol support.").font(.caption).foregroundStyle(.secondary)
                Link("Browse Nerd Fonts", destination: URL(string: "https://www.nerdfonts.com/font-downloads")!)
            }
            card("Custom shortcuts", symbol: "text.badge.plus") {
                HStack { TextField("Alias name", text: $state.aliasName).frame(width: 160); TextField("Command, e.g. git status -sb", text: $state.aliasCommand); Button("Add") { var next = state.configuration; next.aliases.append(.init(name: state.aliasName, command: state.aliasCommand)); do { try next.validate(); state.configuration = next; state.selected.insert("custom-aliases"); state.aliasName = ""; state.aliasCommand = "" } catch { state.message = error.localizedDescription } } }
                ForEach(Array(state.configuration.aliases.enumerated()), id: \.offset) { index, alias in HStack { Text(alias.name).font(.system(.body, design: .monospaced)).frame(width: 160, alignment: .leading); Text(alias.command).textSelection(.enabled); Spacer(); Button("Remove") { state.configuration.aliases.remove(at: index) } } }
                Text("Aliases run only when you call them. Check the full command before applying; name collisions outside Orbit block the plan.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var changes: some View {
        Group {
            card("Setup plan", symbol: "list.bullet.clipboard") {
                Text("Tools to install: " + (state.missing.isEmpty ? "None detected for selected profile options" : state.missing.joined(separator: ", ")))
                Text("Preserved external configurations: \(externalCount). Review profiles and runtime downloads separately.").font(.caption).foregroundStyle(.secondary)
                if let plan = state.plan {
                    if plan.changes.isEmpty { Text("No file changes needed.") }
                    ForEach(plan.changes, id: \.before.name) { change in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("~/" + change.before.name).font(.headline)
                            Text("Before · Orbit-owned configuration").font(.caption).foregroundStyle(.secondary)
                            Text(previous(change)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text("After · reviewed replacement").font(.caption).foregroundStyle(.secondary)
                            Text(change.block.isEmpty ? "Remove the Orbit block." : change.block).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } else { Text("Choose settings, then Review changes. Existing content outside Orbit's profile block stays untouched.").foregroundStyle(.secondary) }
            }
            card("Runtime downloads", symbol: "arrow.down.circle") {
                Button("Review runtime commands") { state.reviewRuntimes() }
                if let script = state.runtimeReview {
                    Text(script).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    HStack { Button("Copy commands") { copy(script) }; Button("Run reviewed setup") { state.showRuntime = true }.buttonStyle(.borderedProminent).disabled(store.preview) }
                }
                if !state.runtimeOutput.isEmpty { Text(state.runtimeOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                Text("Install missing tools through Homebrew Center first. Runtime downloads are not part of Apply reviewed changes. Existing non-NVM managers should be used through their own setup commands.").font(.caption).foregroundStyle(.secondary)
                Link("Modern Yarn project setup", destination: URL(string: "https://yarnpkg.com/getting-started/install")!)
            }
            card("Backups & verification", symbol: "clock.arrow.circlepath") {
                HStack { Button("Restore latest backup") { state.showRestore = true }.disabled(store.preview || state.backupURL == nil); Button("Open backup folder") { NSWorkspace.shared.open(state.engine.backupRoot) }.disabled(store.preview || state.backupURL == nil); Button("Open Terminal") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration()) } }
                Text("Each apply creates a private backup. Later edits block restore. Undo newest first; restore never uninstalls downloaded tools. Open a new terminal after applying and use Verify tools in Environment.").font(.caption).foregroundStyle(.secondary)
                if !store.preview { ForEach(state.engine.backupDirectories(), id: \.path) { url in HStack { Text(((try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast).formatted(date: .abbreviated, time: .shortened)); Spacer(); Button("Inspect backup") { NSWorkspace.shared.open(url) } } } }
            }
        }
    }
    private func previous(_ change: ProfileChange) -> String {
        guard let data = change.before.data, let text = String(data: data, encoding: .utf8) else { return "File does not exist yet." }
        if [".zprofile", ".zshrc"].contains(change.before.name) { return ((try? ProfileEngine.split(text).block).flatMap { $0.isEmpty ? nil : $0 }) ?? "No Orbit block. Existing content is preserved." }
        // Never show unrelated Git credentials or included configuration.
        if change.before.name == ".gitconfig" { return "Existing Git configuration preserved; user.name and user.email will be replaced." }
        return text
    }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
}
