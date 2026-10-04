import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import CoreServices
import ServiceManagement

struct OrbitPermission: Identifiable, Equatable {
    let id: String, title: String, purpose: String, status: String, settings: String
    var allowed: Bool { status == "Allowed" || status == "Verified" }
}
@MainActor final class PermissionState: ObservableObject {
    @Published var items = [OrbitPermission]()
    @Published var working = false
    @Published var message = "Permissions belong to Orbit. Installed apps request their own permissions when opened."
    var preview = false
    var canAct: () -> Bool = { true }
    var verifyScreen: () async -> Bool = { false }
    var screenVerified = false
    var screenFailure: () -> String? = { nil }
    static func automation(ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier:"com.apple.systemevents")
        return AEDeterminePermissionToAutomateTarget(target.aeDesc,AEEventClass(kCoreEventClass),AEEventID(kAEGetData),ask)
    }
    static func mediaStatus(_ value: AVAuthorizationStatus) -> String {
        switch value { case .authorized: return "Allowed"; case .denied: return "Denied"; case .restricted: return "Restricted"; default: return "Not requested" }
    }
    func refresh() {
        guard !preview else { return }
        let automation = Self.automation(ask:false)
        items = [
            OrbitPermission(id:"screen",title:"Screen & system audio",purpose:"Record or capture the screen you choose. A legacy permission hint alone is not proof of access.",status:screenVerified ? "Verified" : "Needs verification",settings:"Privacy_ScreenCapture"),
            OrbitPermission(id:"microphone",title:"Microphone",purpose:"Add your voice to a recording.",status:Self.mediaStatus(AVCaptureDevice.authorizationStatus(for:.audio)),settings:"Privacy_Microphone"),
            OrbitPermission(id:"camera",title:"Camera",purpose:"Add a webcam bubble to a recording.",status:Self.mediaStatus(AVCaptureDevice.authorizationStatus(for:.video)),settings:"Privacy_Camera"),
            OrbitPermission(id:"input",title:"Input Monitoring",purpose:"Show Command/Control shortcut labels, never typed text.",status:CGPreflightListenEventAccess() ? "Allowed" : "Needs verification",settings:"Privacy_ListenEvent"),
            OrbitPermission(id:"accessibility",title:"Accessibility",purpose:"Optional access for Mac automation. Drawing and basic recording do not require it.",status:AXIsProcessTrusted() ? "Allowed" : "Not enabled",settings:"Privacy_Accessibility"),
            OrbitPermission(id:"automation",title:"System Events automation",purpose:"Read and manage standard Open at Login applications.",status:automation == noErr ? "Allowed" : automation == -1743 ? "Denied" : "Needs verification",settings:"Privacy_Automation")
        ]
    }
    func request(_ id: String) async {
        guard !preview, !working, canAct() else { return }
        working = true; defer { working = false }
        switch id {
        case "screen": screenVerified = await verifyScreen(); message = screenVerified ? "ScreenCaptureKit access verified. No image or recording was taken." : (screenFailure() ?? "Screen access could not be verified. Open Privacy settings and reopen Orbit if macOS requests it.")
        case "microphone": _ = await AVCaptureDevice.requestAccess(for:.audio)
        case "camera": _ = await AVCaptureDevice.requestAccess(for:.video)
        case "input": _ = CGRequestListenEventAccess()
        case "accessibility": _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
        case "automation": let result = Self.automation(ask:true); message = result == noErr ? "System Events access allowed." : result == -1743 ? "System Events access denied. You can allow Orbit in Automation settings." : "System Events access could not be verified (macOS code \(result))."
        default: break
        }
        refresh()
    }
    func openSettings(_ suffix: String) { if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?"+suffix) { NSWorkspace.shared.open(url) } }
}
struct PermissionCards: View {
    @ObservedObject var state: PermissionState
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(state.message).font(.caption).foregroundStyle(.secondary)
            ForEach(state.items) { item in
                HStack(alignment:.top) {
                    Image(systemName:item.allowed ? "checkmark.shield.fill" : "shield.lefthalf.filled").foregroundStyle(item.allowed ? .green : .orange)
                    VStack(alignment:.leading,spacing:4) { Text(item.title).bold(); Text(item.purpose).font(.caption).foregroundStyle(.secondary); Text(item.status).font(.caption.bold()) }
                    Spacer()
                    Button(item.id == "screen" ? "Verify access" : "Request") { Task { await state.request(item.id) } }.disabled(state.working || !state.canAct())
                    Button("Settings") { state.openSettings(item.settings) }
                }.padding(12).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:10))
            }
        }
    }
}
struct PermissionCenterView: View {
    @ObservedObject var state: PermissionState
    var body: some View { VStack(alignment:.leading,spacing:18) { HStack { Text("Setup Center").font(.largeTitle.bold()); Spacer(); Button("Refresh status") { state.refresh() }.disabled(state.working) }; ScrollView { PermissionCards(state:state) }; Text("Access is checked on setup and before package installation. Request buttons are optional; permission is required only for its associated feature.").font(.caption).foregroundStyle(.secondary) }.padding(24).task { state.refresh() } }
}

struct HealthFinding: Identifiable, Equatable { let id: String, title: String, detail: String; let healthy: Bool }
@MainActor final class HealthState: ObservableObject {
    @Published var findings = [HealthFinding]()
    @Published var working = false
    @Published var checked: Date?
    var preview = false
    var canAct: () -> Bool = { true }
    func scan(brew: String?, commands: any CommandExecuting, packages: [Package] = Catalog.packages, appExists: (Package) -> Bool = { $0.manualAppExists }) async {
        guard !preview, !working, canAct() else { return }; working = true; defer { working = false }
        var result = [HealthFinding]()
        if let brew {
            for (id,title,args) in [("version","Homebrew",["--version"]),("dependencies","Missing dependencies",["missing"]),("doctor","Homebrew doctor",["doctor"])] {
                let response = await commands.run(brew,args,log:{ _ in })
                result.append(HealthFinding(id:id,title:title,detail:response.1.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? (response.0 == 0 ? "No issues reported." : "Check failed with exit status \(response.0).") : String(response.1.prefix(16000)),healthy:response.0 == 0))
            }
            let casks = await commands.run(brew,["list","--cask","-1"],log:{ _ in })
            if casks.0 == 0 {
                let installed = Set(casks.1.split(whereSeparator:\.isNewline).map(String.init))
                let absent = packages.filter { $0.cask && $0.appName != nil && installed.contains($0.token) && !appExists($0) }
                result.append(HealthFinding(id:"apps",title:"Managed app bundles",detail:absent.isEmpty ? "Known installed app bundles were found in standard app locations." : "Not found in standard locations: " + absent.map(\.name).joined(separator:", ") + ". A custom app directory may be valid; review before repairing.",healthy:absent.isEmpty))
            } else { result.append(HealthFinding(id:"apps",title:"Managed app bundles",detail:"Installed cask inventory could not be read.",healthy:false)) }
        } else { result.append(HealthFinding(id:"brew",title:"Homebrew",detail:"Not found. Open Setup check for installation guidance.",healthy:false)) }
        let path = Bundle.main.bundleURL.path
        result.append(HealthFinding(id:"location",title:"Orbit location",detail:path,healthy:URL(fileURLWithPath:path).deletingLastPathComponent().path == "/Applications"))
        let resources = Bundle.main.resourceURL
        // Check the packaged helper directly; no executable is launched.
        let helper = resources.map { FileManager.default.isExecutableFile(atPath:$0.appendingPathComponent("OrbitAskpass").path) && FileManager.default.isExecutableFile(atPath:$0.appendingPathComponent("askpass.sh").path) } ?? false
        result.append(HealthFinding(id:"helper",title:"Administrator helper",detail:helper ? "Available." : "Missing. Download a fresh Orbit build.",healthy:helper))
        findings = result; checked = Date()
    }
}
struct HealthView: View {
    @ObservedObject var store: Store
    @ObservedObject var state: HealthState
    var body: some View { VStack(alignment:.leading,spacing:18) {
        HStack { Text("App Health Check").font(.largeTitle.bold()); Spacer(); Button(state.working ? "Checking…" : "Run health check") { Task { await state.scan(brew:store.brew,commands:store.commandRunner,packages:store.packages,appExists:store.appPresent) } }.disabled(state.working || !state.canAct()) }
        Text("Read-only checks for Homebrew, dependencies and Orbit setup. Findings are suggestions; no repairs or removals run automatically.").foregroundStyle(.secondary)
        if state.working { ProgressView() }
        ScrollView { VStack(alignment:.leading,spacing:12) { ForEach(state.findings) { finding in GroupBox { HStack(alignment:.top) { Image(systemName:finding.healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(finding.healthy ? .green : .orange); VStack(alignment:.leading,spacing:6) { Text(finding.title).bold(); Text(finding.detail).font(.system(.caption,design:.monospaced)).textSelection(.enabled) }; Spacer() }.frame(maxWidth:.infinity,alignment:.leading).padding(8) } } } }
        if let date = state.checked { Text("Last checked: \(date.formatted())").font(.caption).foregroundStyle(.secondary) }
    }.padding(24) }
}

struct LoginEntry: Codable, Identifiable, Equatable { let name: String, path: String, hidden: Bool; var id: String { name+"\n"+path } }
enum LoginScripts {
    static func literal(_ value: String) -> String { String(data:try! JSONEncoder().encode(value),encoding:.utf8)! }
    static let list = "JSON.stringify(Application('System Events').loginItems().map(function(x){return {name:x.name(),path:x.path(),hidden:x.hidden()};}))"
    static func add(_ entry: LoginEntry) -> String { "var a=Application('System Events');var p=\(literal(entry.path));if(a.loginItems().some(function(x){return x.path()===p;}))throw Error('Already present');a.loginItems.push(a.LoginItem({name:\(literal(entry.name)),path:p,hidden:false}));" }
    static func remove(_ entry: LoginEntry) -> String { "var a=Application('System Events');var matches=a.loginItems().filter(function(x){return x.name()===\(literal(entry.name))&&x.path()===\(literal(entry.path));});if(matches.length!==1)throw Error('The login item changed; refresh first');a.delete(matches[0]);" }
    static func parse(_ string: String) throws -> [LoginEntry] { let entries = try JSONDecoder().decode([LoginEntry].self,from:Data(string.utf8)); return entries.filter { !$0.name.isEmpty && $0.path.hasPrefix("/") }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
}
@MainActor final class LoginState: ObservableObject {
    @Published var entries = [LoginEntry]()
    @Published var working = false
    @Published var message = "Standard Open at Login apps are managed through System Events. Background services are managed in macOS Settings."
    @Published var orbitStatus = "Not checked"
    @Published var pendingRemoval: LoginEntry?
    var preview = false
    var canAct: () -> Bool = { true }
    var automationAccess: (Bool) -> OSStatus = { PermissionState.automation(ask:$0) }
    func refreshStatus() { if !preview { switch SMAppService.mainApp.status { case .enabled: orbitStatus = "Enabled"; case .requiresApproval: orbitStatus = "Needs approval in Settings"; case .notRegistered: orbitStatus = "Disabled"; default: orbitStatus = "Unavailable" } } }
    func orbit(_ enabled: Bool) async {
        guard !preview, !working, canAct() else { return }; working = true; defer { working = false; refreshStatus() }
        do { if enabled { try SMAppService.mainApp.register() } else { try await SMAppService.mainApp.unregister() } } catch { message = error.localizedDescription }
    }
    func loadOnOpen(commands: any CommandExecuting) async {
        guard !preview, !working, canAct() else { return }; refreshStatus()
        guard automationAccess(false) == noErr else { message = "Allow System Events access to load login apps. Open Setup Center or choose Allow access below."; return }
        await refresh(commands:commands)
    }
    func authorizeAndLoad(commands: any CommandExecuting) async {
        guard !preview, !working, canAct() else { return }
        guard automationAccess(true) == noErr else { message = "System Events access is unavailable. Allow Orbit in Setup Center → Permissions."; return }
        await refresh(commands:commands)
    }
    static func applicationDirectory(home: String = NSHomeDirectory(), exists: (String) -> Bool = { FileManager.default.fileExists(atPath:$0) }) -> URL {
        URL(fileURLWithPath:exists("/Applications") ? "/Applications" : home + "/Applications",isDirectory:true)
    }
    func refresh(commands: any CommandExecuting) async {
        guard !preview, !working, canAct() else { return }; working = true; defer { working = false }; refreshStatus()
        let response = await commands.run("/usr/bin/osascript",["-l","JavaScript","-e",LoginScripts.list],log:{ _ in })
        do { guard response.0 == 0 else { throw RecorderProblem(message:response.1) }; entries = try LoginScripts.parse(response.1); message = "\(entries.count) standard login apps. Removing a login item does not uninstall the app." } catch { entries = []; message = "Login apps could not be loaded. Allow System Events in Setup Center. \(error.localizedDescription)" }
    }
    func change(_ entry: LoginEntry, add: Bool, commands: any CommandExecuting) async {
        guard !preview, !working, canAct() else { return }; if add && (!entry.path.hasSuffix(".app") || !FileManager.default.fileExists(atPath:entry.path)) { message = "Choose an existing application."; return }
        working = true
        let response = await commands.run("/usr/bin/osascript",["-l","JavaScript","-e",add ? LoginScripts.add(entry) : LoginScripts.remove(entry)],log:{ _ in })
        working = false
        if response.0 == 0 { await refresh(commands:commands) } else { message = response.1 }
    }
    func chooseApp(commands: any CommandExecuting) {
        guard !preview, !working, canAct() else { return }
        let panel = NSOpenPanel(); panel.directoryURL = Self.applicationDirectory(); panel.canChooseDirectories = false; panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let entry = LoginEntry(name:url.deletingPathExtension().lastPathComponent,path:url.path,hidden:false)
        Task { await change(entry,add:true,commands:commands) }
    }
}
struct LoginView: View {
    @ObservedObject var store: Store
    @ObservedObject var state: LoginState
    var body: some View { VStack(alignment:.leading,spacing:18) {
        Text("Login Items").font(.largeTitle.bold())
        Text(state.message).font(.caption).foregroundStyle(.secondary)
        HStack { Button("Refresh / Retry",systemImage:"arrow.clockwise") { Task { await state.loadOnOpen(commands:store.commandRunner) } }; Button("Allow access") { Task { await state.authorizeAndLoad(commands:store.commandRunner) } }; Button("Add application") { state.chooseApp(commands:store.commandRunner) }; Spacer(); Button("Background items in Settings") { SMAppService.openSystemSettingsLoginItems() } }
        ScrollView { VStack { ForEach(state.entries) { entry in HStack { VStack(alignment:.leading) { Text(entry.name).bold(); Text(entry.path).font(.caption).foregroundStyle(.secondary); if entry.hidden { Text("Starts hidden").font(.caption) } }; Spacer(); Button("Remove from login") { state.pendingRemoval = entry } }.padding(12).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:10)) } } }
    }.padding(24).disabled(state.working).task { await state.loadOnOpen(commands:store.commandRunner) }.confirmationDialog("Remove this app from Open at Login?",isPresented:Binding(get:{ state.pendingRemoval != nil },set:{ if !$0 { state.pendingRemoval = nil } }),titleVisibility:.visible) { if let entry = state.pendingRemoval { Button("Remove \(entry.name)",role:.destructive) { state.pendingRemoval = nil; Task { await state.change(entry,add:false,commands:store.commandRunner) } } }; Button("Cancel",role:.cancel) { state.pendingRemoval = nil } } }
}
