import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: Store
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 215)
            Divider()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.category == "All Apps" ? (store.uninstallMode ? "Manage installed apps" : "Set up your Mac") : store.category).font(.system(size: 28, weight: .bold))
                        Text(store.headline).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        TextField("Search apps", text: $store.search).textFieldStyle(.roundedBorder).frame(width: 230)
                        HStack {
                            Button("Import Brewfile", systemImage: "square.and.arrow.down") { store.importFile() }
                            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh installed packages")
                        }.disabled(store.locked)
                    }
                }.padding(24)
                Picker("Action", selection: $store.uninstallMode) {
                    Text("Install apps").tag(false)
                    Text("Uninstall apps").tag(true)
                }.pickerStyle(.segmented).frame(width: 300).padding(.horizontal, 24).padding(.bottom, 12).disabled(store.locked)
                .onChange(of: store.uninstallMode) { _, removing in
                    store.selected.removeAll()
                    store.statuses.removeAll()
                    store.headline = removing ? "Select Homebrew-managed apps to remove." : "Choose your apps. Make it yours."
                }
                if store.category != "All Apps" {
                    HStack {
                        Picker("Section", selection: $store.subcategory) {
                            Text("All sections").tag("All")
                            ForEach(Catalog.subcategories(in: store.category), id: \.self) { Text($0).tag($0) }
                        }.frame(maxWidth: 350)
                        Spacer()
                    }.padding(.horizontal, 24).padding(.bottom, 8)
                }
                if store.brew == nil {
                    HStack {
                        Image(systemName: "shippingbox")
                        Text("Homebrew is needed to install apps.")
                        Spacer()
                        Link("Set up Homebrew", destination: URL(string: "https://brew.sh")!)
                    }.padding().background(Color.orange.opacity(0.12)).padding(.horizontal, 24)
                }
                HStack {
                    Text("\(store.visible.count) apps").foregroundStyle(.secondary)
                    Spacer()
                    if !store.uninstallMode {
                        Menu("Starter selections") {
                            ForEach(Catalog.presets.keys.sorted(), id: \.self) { title in
                                Button(title) { store.selectPreset(title) }
                            }
                            Divider()
                            Button("Add entire Core Mac Stack") {
                                for title in Catalog.presets.keys where title.hasPrefix("Core") { store.selectPreset(title) }
                            }
                        }
                    }
                    Button("Select all") { store.selected.formUnion(store.visible.filter { store.uninstallMode || $0.installable }.map(\.id)) }
                    Button("Clear") { store.selected.subtract(store.visible.map(\.id)) }
                }.font(.caption).buttonStyle(.borderless).padding(.horizontal, 24).padding(.vertical, 10).disabled(store.locked)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(Catalog.categories, id: \.self) { category in
                            if store.category == "All Apps" || store.category == category { categoryBlock(category) }
                        }
                        if store.visible.isEmpty {
                            if store.uninstallMode && store.search.isEmpty {
                                ContentUnavailableView("No managed apps in this catalog", systemImage: "shippingbox", description: Text("Refresh to check Homebrew. Manually installed apps are not included."))
                            } else { ContentUnavailableView.search(text: store.search) }
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
                if store.busy {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(store.completed), total: Double(max(store.total, 1)))
                        HStack {
                            Text("\(store.completed) of \(store.total) completed").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(store.stopRequested ? "Stopping after this app…" : "Stop after current app") { store.stopRequested = true }.disabled(store.stopRequested)
                        }
                    }.padding(.horizontal, 24).padding(.vertical, 12)
                }
                Divider()
                HStack {
                    Button("Operation details", systemImage: "text.alignleft") { store.showLog = true }
                    Spacer()
                    Button("Export Brewfile") { store.exportFile() }.disabled(store.selection.isEmpty || store.locked)
                    Button {
                        Task { if store.uninstallMode { await store.prepareRemoval() } else { await store.prepare() } }
                    } label: {
                        HStack {
                            if store.preparing { ProgressView().controlSize(.small) }
                            Text(store.preparing ? "Checking apps…" : "\(store.uninstallMode ? "Uninstall" : "Install") \(store.selection.count) app\(store.selection.count == 1 ? "" : "s")")
                        }.frame(minWidth: 130)
                    }.buttonStyle(.borderedProminent).disabled(store.selection.isEmpty || store.locked || store.brew == nil)
                }.padding(18)
            }
            Divider()
            selectionPanel.frame(width: 255)
        }.frame(minWidth: 1080, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await LogoStore.shared.start() }
        .task { if let error = Catalog.loadError { store.notice = error } else { await store.refresh() } }
        .sheet(isPresented: $store.showReview) { ReviewView(store: store) }
        .sheet(isPresented: $store.showRemovalReview) { RemovalReviewView(store: store) }
        .sheet(item: $store.detailPackage) { package in PackageDetailView(package: package, store: store) }
        .sheet(isPresented: $store.showLog) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Operation details").font(.title2.bold())
                    Spacer()
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.output, forType: .string) }
                    Button("Done") { store.showLog = false }.keyboardShortcut(.cancelAction)
                }
                ScrollView { Text(store.output.isEmpty ? "No operation has run yet." : store.output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(24).frame(width: 780, height: 520)
        }
        .alert("Mac Setup", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Mac Setup", systemImage: "shippingbox.fill").font(.title2.bold()).padding(.bottom, 25).padding(.top, 18)
            navigationButton("All Apps")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Catalog.categories, id: \.self) { category in
                        DisclosureGroup {
                            ForEach(Catalog.subcategories(in: category), id: \.self) { section in
                                navigationButton(category, section: section).padding(.leading, 6)
                            }
                        } label: { navigationButton(category) }
                    }
                }.padding(.vertical, 8)
            }
            Link(destination: URL(string: "https://formulae.brew.sh")!) { Label("Homebrew catalog", systemImage: "arrow.up.right.square") }.padding(.bottom, 15)
            HStack(spacing: 8) {
                Circle().fill(store.brew == nil ? Color.orange : Color.green).frame(width: 8, height: 8)
                Text(store.brew == nil ? "Homebrew not found" : store.refreshing ? "Checking installed apps…" : "Homebrew ready").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(.thinMaterial)
    }
    func navigationButton(_ category: String, section: String = "All") -> some View {
        let active = store.category == category && store.subcategory == section
        return Button { store.category = category; store.subcategory = section } label: {
            HStack(spacing: 8) {
                if section == "All" { Image(systemName: Catalog.symbols[category] ?? "square.grid.2x2").frame(width: 18) }
                Text(section == "All" ? category : section).font(.system(size: section == "All" ? 12 : 11)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).background(active ? Color.accentColor : .clear).foregroundStyle(active ? .white : .primary).clipShape(RoundedRectangle(cornerRadius: 8))
    }
    @ViewBuilder func categoryBlock(_ category: String) -> some View {
        let apps = store.visible.filter { store.category == "All Apps" ? $0.category == category : $0.belongs(to: category) }
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(category.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Catalog.subcategories(in: category), id: \.self) { section in
                    let entries = apps.filter { $0.section(in: category) == section }
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(section).font(.system(size: 13, weight: .semibold))
                            LazyVStack(spacing: 0) {
                                ForEach(entries) { app in
                                    row(app)
                                    if app.id != entries.last?.id { Divider().padding(.leading, 48) }
                                }
                            }.background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
                        }
                    }
                }
            }
        }
    }
    func row(_ app: Package) -> some View {
        HStack(spacing: 13) {
            Toggle(app.name, isOn: Binding(get: { store.selected.contains(app.id) }, set: { _ in store.toggle(app) })).labelsHidden().toggleStyle(.checkbox).disabled(store.locked || (!store.uninstallMode && !app.installable)).accessibilityLabel("Select \(app.name)")
            Button { store.detailPackage = app } label: {
                HStack(spacing: 13) {
                    AppIcon(package: app).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 14, weight: .semibold))
                        Text(app.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("View details for \(app.name)").accessibilityLabel("View details for \(app.name)")
            if !app.installable && !store.uninstallMode {
                Button("Setup details") {
                    store.detailPackage = app
                }.controlSize(.small)
                if let text = app.homepage, let url = URL(string: text), url.scheme == "https" {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help("Open official setup page")
                }
            }
            let status = store.statuses[app.id] ?? (store.installed.contains(app.id) ? "Installed" : app.manualAppExists ? "On this Mac" : "")
            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(status == "Failed" ? Color.red : status == "Installed" ? Color.green : Color.secondary).padding(.horizontal, 9).padding(.vertical, 5).background(Color.primary.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button { store.detailPackage = app } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }.buttonStyle(.plain).help("App details and links").accessibilityLabel("Details for \(app.name)")
        }.padding(.horizontal, 14).padding(.vertical, 12)
    }
    var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your selection").font(.title2.bold())
            Text("\(store.selection.count) apps selected").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    ForEach(store.selection) { app in
                        HStack(spacing: 10) {
                            AppIcon(package: app).frame(width: 27, height: 27)
                            Button(app.name) { store.detailPackage = app }.font(.system(size: 13)).buttonStyle(.plain)
                            Spacer()
                            Button { store.selected.remove(app.id) } label: { Image(systemName: "xmark").font(.caption2).foregroundStyle(.secondary) }.buttonStyle(.plain).disabled(store.locked).help("Remove \(app.name)")
                        }
                    }
                    if store.selection.isEmpty { Text(store.uninstallMode ? "Select installed apps to remove." : "Select apps to build your setup.").font(.subheadline).foregroundStyle(.secondary).padding(.top, 20) }
                }.padding(.top, 12)
            }
            Spacer()
            Divider()
            Label(store.uninstallMode ? "Homebrew-managed apps in this catalog only. Removal requires confirmation." : "Some apps require sign-in or a paid license after installation.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            Text("Selections are saved on this Mac.").font(.caption2).foregroundStyle(.secondary)
        }.padding(22)
    }
}

struct AppIcon: View {
    let package: Package
    @ObservedObject private var logos = LogoStore.shared
    var localIcon: NSImage? {
        guard let name = package.appName else { return nil }
        for base in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let path = base + "/" + name + ".app"
            if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        }
        return nil
    }
    var body: some View {
        if let icon = localIcon ?? logos.image(for: package) { Image(nsImage: icon).resizable().scaledToFit() }
        else { Image(systemName: package.symbol).font(.system(size: 21)).foregroundStyle(Color.accentColor).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.accentColor.opacity(0.09)).clipShape(RoundedRectangle(cornerRadius: 8)) }
    }
}

struct PackageDetailView: View {
    let package: Package
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppIcon(package: package).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(package.name).font(.title.bold())
                    Text(store.installed.contains(package.id) ? "Installed with Homebrew" : package.manualAppExists ? "Already on this Mac" : package.installable ? "Available to install" : "Manual setup or unavailable").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { store.detailPackage = nil }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(package.detail).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Categories").font(.headline)
                        ForEach(package.placements, id: \.self) { place in
                            Text(place.category + " › " + place.subcategory).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Installation").font(.headline)
                        Text(package.installable ? (package.cask ? "Vendor package, managed by Homebrew." : "Command-line tool, managed by Homebrew.") : package.availability)
                        if let version = package.version { Text("Catalog version: " + version).font(.subheadline).foregroundStyle(.secondary) }
                        if let license = package.formulaLicense { Text("Package license: " + license).font(.subheadline).foregroundStyle(.secondary) }
                        Text("Vendor licenses, subscriptions, sign-in and additional setup may apply.").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Official links").font(.headline)
                        if let url = package.websiteURL {
                            detailLink("Official website / project page", symbol: "globe", url: url)
                        } else { Text("Official website not verified.").foregroundStyle(.secondary) }
                        if let url = package.githubURL {
                            detailLink("GitHub" + (package.githubPurpose.map { " · " + $0 } ?? ""), symbol: "chevron.left.forwardslash.chevron.right", url: url)
                        } else { Text("No verified public GitHub repository link.").font(.subheadline).foregroundStyle(.secondary) }
                        if let url = package.catalogURL { detailLink("Homebrew package", symbol: "shippingbox", url: url) }
                        if let url = package.officialLogoURL { detailLink("Official site icon", symbol: "photo", url: url) }
                        if let date = Catalog.data?.verifiedDate { Text("Catalog metadata checked: " + date + ". Live availability is checked before installation.").font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(.vertical, 6)
            }
            Divider()
            HStack {
                Text("Opening links or viewing details does not install or remove apps.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.uninstallMode && package.installable {
                    Button(store.selected.contains(package.id) ? "Remove from selection" : "Add to selection") { store.toggle(package) }.disabled(store.locked)
                }
            }
        }.padding(26).frame(width: 680, height: 620)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    func detailLink(_ title: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                    Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
            }.padding(12).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}

struct ReviewView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review installation").font(.title2.bold())
            Text("Already managed apps are skipped. Vendor installers may update existing apps and request your administrator password.").font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.review) { item in
                        HStack(alignment: .top) {
                            AppIcon(package: item.package).frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.package.name).bold()
                                Text(item.action(adopt: store.adopt)).font(.caption).foregroundStyle(item.problem == nil ? Color.secondary : .red)
                                if item.installer { Text("Administrator access may be requested in a Mac Setup password dialog.").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(item.version).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                        Divider()
                    }
                }
            }
            Toggle("Adopt existing apps when their contents match", isOn: $store.adopt)
            Text("Adoption applies to app bundles. It does not prevent vendor package installers from running. Unavailable packages are skipped.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { store.showReview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.actionable.isEmpty ? "Nothing to install" : "Install \(store.actionable.count) apps") { Task { await store.install() } }.buttonStyle(.borderedProminent).disabled(store.actionable.isEmpty)
            }
        }.padding(24).frame(width: 680, height: 560)
    }
}

struct RemovalReviewView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Uninstall selected apps?", systemImage: "trash").font(.title2.bold())
            Text("These apps will be removed from your Mac. Vendor uninstallers may run and request administrator permission.").foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.removalPlan) { package in
                        HStack {
                            AppIcon(package: package).frame(width: 30, height: 30)
                            Text(package.name).bold()
                            Spacer()
                            Text("Remove").font(.caption).foregroundStyle(.red)
                        }.padding(.vertical, 12)
                        Divider()
                    }
                }
            }
            Text("Extra data cleanup is not requested. Vendor uninstallers may still remove app data. Packages needed by other software may refuse removal; see Operation details.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { store.showRemovalReview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Uninstall \(store.removalPlan.count) apps", role: .destructive) { Task { await store.uninstall() } }.buttonStyle(.borderedProminent).tint(.red)
            }
        }.padding(24).frame(width: 650, height: 470)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard MacSetupApp.store.busy else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "An operation is running"
        alert.informativeText = "Use Stop after current app and wait for the current operation to finish before quitting."
        alert.addButton(withTitle: "Continue"); alert.runModal()
        return .terminateCancel
    }
}

struct MacSetupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = store
    static let store = Store()
    var body: some Scene {
        WindowGroup("Mac Setup") { ContentView(store: model) }.defaultSize(width: 1180, height: 780)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@main enum Entry {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let previewStore = Store(preview: true)
            var root = AnyView(ContentView(store: previewStore))
            var size = NSSize(width: 1180, height: 780)
            if let detailIndex = CommandLine.arguments.firstIndex(of: "--details"), CommandLine.arguments.count > detailIndex + 1,
               let package = Catalog.packages.first(where: { $0.token == CommandLine.arguments[detailIndex + 1] }) {
                root = AnyView(PackageDetailView(package: package, store: previewStore))
                size = NSSize(width: 680, height: 620)
            }
            let view = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = view
            window.title = "Mac Setup"
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    print("Rendered application view")
                }
            }
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            let packages = Catalog.packages
            precondition(Set(packages.map(\.id)).count == packages.count)
            precondition(!packages.isEmpty && Catalog.loadError == nil)
            precondition(Catalog.parse(Catalog.export(packages)).0 == Set(packages.filter(\.installable).map(\.id)))
            precondition(Set(packages.flatMap(\.sourceNumbers)) == Set(1...437))
            precondition(packages.flatMap(\.sourceNumbers).count == 437)
            let malicious = "system(\"touch /tmp/should-not-exist\")\ncask \"slack\"; system(\"whoami\")\n"
            precondition(Catalog.parse(malicious).0.isEmpty)
            precondition(Catalog.parse(malicious).1.count == 2)
            precondition(Catalog.parse("# comment\ncask \"slack\"\ncask \"slack\"\nbrew \"not-a-package\"").0.count == 1)
            let item = ReviewItem(package: packages[0], managed: false, manual: true, installer: true, version: "1", problem: nil)
            precondition(item.action(adopt: true).contains("vendor installer"))
            print("PASS: unique catalog, all 437 source entries, available-package Brewfile round trip, unsafe input rejection, installer disclosure")
            return
        }
        MacSetupApp.main()
    }
}
