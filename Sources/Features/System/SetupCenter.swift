import SwiftUI
import AppKit
import ServiceManagement

enum SetupSection: String, CaseIterable { case requirements = "Requirements", permissions = "Permissions", startup = "Startup"
    var symbol: String { switch self { case .requirements: return "checklist"; case .permissions: return "checkmark.shield"; case .startup: return "power" } }
}
struct SetupCenterView: View {
    @ObservedObject var store: Store
    var onboarding = false
    var ready: Bool { !store.startupChecks.isEmpty && store.startupChecks.allSatisfy { !$0.required || $0.ready } }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Label { Text(onboarding ? "Welcome to Orbit" : "Setup Center") } icon: { OrbitBrandIcon(size:40) }.font(.largeTitle.bold()); Spacer(); Button("Check again",systemImage:"arrow.clockwise") { Task { await store.checkStartup(); store.permissions.refresh(); store.login.refreshStatus() } }.disabled(store.locked) }
            Text("Requirements, Orbit permissions and launch preferences in one place.").foregroundStyle(.secondary)
            HStack { ForEach(SetupSection.allCases,id:\.self) { tab in Button { store.setupSection = tab } label: { Label(tab.rawValue,systemImage:tab.symbol).padding(8).background(store.setupSection == tab ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:8)) }.buttonStyle(.plain) }; Spacer() }
            if store.checkingStartup { ProgressView("Checking your Mac…") }
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    switch store.setupSection {
                    case .requirements: SetupRequirements(store:store)
                    case .permissions: PermissionCards(state:store.permissions)
                    case .startup:
                        GroupBox("Window & menu bar") {
                            VStack(alignment:.leading,spacing:8) {
                                Toggle("Keep Orbit in the menu bar when the window closes",isOn:$store.keepInMenuBar)
                                Text("When enabled, closing the window hides Orbit from the Dock. Open Orbit from its menu to bring the window and Dock icon back. Recording and other operations continue; Quit Orbit exits the app.").font(.caption).foregroundStyle(.secondary)
                            }.padding(12)
                        }
                        OrbitStartupCard(state:store.login)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            Text("Status checks do not change your Mac. Optional permissions are requested only through Request or Verify; installed apps manage their own access.").font(.caption).foregroundStyle(.secondary)
            if onboarding { HStack { Spacer(); Button(ready ? "Continue" : "Browse apps for now") { Task { await store.finishStartup() } }.buttonStyle(.borderedProminent).disabled(store.checkingStartup || store.startupChecks.isEmpty) } }
        }.padding(24).background(Color(nsColor:.windowBackgroundColor)).task { if !onboarding { await store.checkStartup() }; store.permissions.refresh(); store.login.refreshStatus() }
    }
}
struct SetupRequirements: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            ForEach(store.startupChecks) { check in
                HStack(alignment:.top,spacing:12) {
                    Image(systemName:check.ready ? "checkmark.circle.fill" : check.required ? "exclamationmark.circle.fill" : "info.circle.fill").foregroundStyle(check.ready ? .green : check.required ? .orange : .secondary)
                    VStack(alignment:.leading,spacing:5) {
                        Text(check.title).font(.headline)
                        Text(check.detail).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                        if check.id == "brew" && !check.ready { Link("Open official Homebrew setup",destination:URL(string:"https://brew.sh")!) }
                        if check.id == "tools" && !check.ready {
                            HStack { Button("Copy tools setup command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("xcode-select --install",forType:.string) }; Button("Open Terminal") { if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.Terminal") { NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration()) } } }
                            Text("Run the copied command in Terminal to open Apple's installer.").font(.caption).foregroundStyle(.secondary)
                        }
                    }; Spacer(minLength:0)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:10))
            }
        }
    }
}
struct OrbitStartupCard: View {
    @ObservedObject var state: LoginState
    var body: some View {
        GroupBox("Orbit at login") {
            VStack(alignment:.leading,spacing:12) {
                Text("Open Orbit automatically when you sign in. macOS may require approval in Login Items settings.").foregroundStyle(.secondary)
                HStack {
                    Label(state.orbitStatus,systemImage:"power"); Spacer()
                    Button("Enable") { Task { await state.orbit(true) } }
                    Button("Disable") { Task { await state.orbit(false) } }
                }
                Button("Open Login Items settings") { SMAppService.openSystemSettingsLoginItems() }
            }.padding(12)
        }.disabled(state.working || !state.canAct())
    }
}
