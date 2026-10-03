import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: Store
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 245).disabled(store.locked)
            Divider()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.updateMode ? "Updates" : store.category == "All Apps" ? (store.uninstallMode ? "Installed" : "All Apps") : store.category).font(.system(size: 28, weight: .bold))
                        Text(store.uninstallMode && store.manualTab ? "Choose existing apps to manage with Homebrew." : store.updateMode || store.category == "All Apps" ? store.headline : Catalog.categoryDescriptions[store.category] ?? store.headline).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        TextField("Search apps", text: $store.search).textFieldStyle(.roundedBorder).frame(width: 230)
                        HStack {
                            Button("Import Brewfile", systemImage: "square.and.arrow.down") { store.importFile() }.disabled(store.updateMode)
                            Button { Task { if store.updateMode { await store.checkUpdates() } else { await store.refresh() } } } label: { Image(systemName: "arrow.clockwise") }.help(store.updateMode ? "Check for updates" : "Refresh installed packages")
                        }.disabled(store.locked)
                    }
                }.padding(24)
                if store.uninstallMode {
                    Picker("Installed apps", selection: $store.manualTab) {
                        Text("Managed by Homebrew · \(Catalog.packages.filter { store.installed.contains($0.id) }.count)").tag(false)
                        Text("Installed manually · \(store.manualApps.count)").tag(true)
                    }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 12).disabled(store.locked)
                }
                if store.updateMode {
                    UpdatesView(store: store)
                } else if store.uninstallMode && store.manualTab {
                    ManualAppsView(store: store)
                } else {
                if store.category != "All Apps" {
                    HStack {
                        if store.uninstallMode { Label("Installed", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
                        Picker("Section", selection: $store.subcategory) {
                            Label("All sections · \(store.count(in: store.category))", systemImage: "square.grid.2x2").tag("All")
                            ForEach(Catalog.subcategories(in: store.category), id: \.self) { section in
                                Label(section + " · " + String(store.count(in: store.category, section: section)), systemImage: Catalog.sectionSymbol(section)).tag(section)
                            }
                        }.frame(maxWidth: 430)
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
                if !store.uninstallMode {
                    Toggle("Not installed", isOn: $store.notInstalledOnly).font(.caption).padding(.horizontal, 24).padding(.top, 5)
                }
                HStack {
                    Text("\(store.visible.count) apps").foregroundStyle(.secondary)
                    if !store.uninstallMode {
                        Picker("Sort", selection: $store.popularSort) { Text("Name").tag(false); Text("Most installed · 30 days").tag(true) }.frame(width: 240)
                        if store.fetchingPopularity { ProgressView().controlSize(.small) }
                        if store.popularSort { Button("Refresh stats") { Task { await store.loadPopularity() } }.disabled(store.fetchingPopularity).help(store.popularityDate.isEmpty ? "Fetch reported Homebrew installation events" : store.popularityDate) }
                    }
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
                    Button("Select all") { store.selected.formUnion(store.visible.filter { store.uninstallMode || store.canInstall($0) }.map(\.id)) }
                    Button("Clear") { store.selected.subtract(store.visible.map(\.id)) }
                }.font(.caption).buttonStyle(.borderless).padding(.horizontal, 24).padding(.vertical, 10).disabled(store.locked)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if store.category == "All Apps" || !store.search.isEmpty {
                            LazyVStack(spacing: 0) {
                                ForEach(store.orderedPackages(store.visible)) { app in
                                    row(app)
                                    Divider().padding(.leading, 48)
                                }
                            }.background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
                        } else { categoryBlock(store.category) }
                        if store.visible.isEmpty {
                            if store.uninstallMode && store.search.isEmpty {
                                ContentUnavailableView("No Homebrew-managed apps in this catalog", systemImage: "shippingbox", description: Text("Refresh or switch to Installed manually to manage existing apps."))
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
                if store.uninstallMode {
                    Text("Installed · Homebrew-managed apps in this catalog").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                    Toggle("Uninstall & Clean — review leftover files", isOn: $store.cleanRemoval).padding(.horizontal, 24).padding(.top, 10).disabled(store.locked)
                }
                HStack {
                    Button("Operation details", systemImage: "text.alignleft") { store.showLog = true }
                    Spacer()
                    Button("Export setup") { store.exportSelected.formUnion(store.selected); store.showSetupExport = true }.disabled(store.locked)
                    Button {
                        Task { if store.uninstallMode { await store.prepareRemoval() } else { await store.prepare() } }
                    } label: {
                        HStack {
                            if store.preparing { ProgressView().controlSize(.small) }
                            Text(store.preparing ? "Checking apps…" : "\(store.uninstallMode ? "Uninstall" : "Install") \((store.uninstallMode ? store.selection.count : store.installSelection.count)) app\((store.uninstallMode ? store.selection.count : store.installSelection.count) == 1 ? "" : "s")")
                        }.frame(minWidth: 130)
                    }.buttonStyle(.borderedProminent).disabled((store.uninstallMode ? store.selection.isEmpty : store.installSelection.isEmpty) || store.locked || store.brew == nil)
                }.padding(18)
                }
            }
            Divider()
            if !store.updateMode && !(store.uninstallMode && store.manualTab) { selectionPanel.frame(width: 255) }
        }.frame(minWidth: 1080, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.popularSort) { _, enabled in if enabled && store.popularity.isEmpty && !store.preview { Task { await store.loadPopularity() } } }
        .task { if !store.preview { await LogoStore.shared.start() } }
        .task { if let error = Catalog.loadError { store.notice = error } else if !store.preview { await store.refresh() } }
        .sheet(isPresented: $store.showAdoptionReview) { AdoptionReviewView(store: store) }
        .sheet(isPresented: $store.showMaintenance) { MaintenanceView(store: store).interactiveDismissDisabled() }
        .sheet(isPresented: $store.showSetupExport) { SetupExportView(store: store) }
        .sheet(item: $store.repairReview) { repair in RemovalRepairView(store: store, repair: repair) }
        .sheet(isPresented: $store.showReview) { ReviewView(store: store) }
        .sheet(isPresented: $store.showUpdateReview) { UpdateReviewView(store: store) }
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
        VStack(alignment: .leading, spacing: 7) {
            Label("Mac Setup", systemImage: "shippingbox.fill").font(.title2.bold()).padding(.bottom, 18).padding(.top, 18)
            destinationButton("All Apps", symbol: "square.grid.2x2", mode: .install, count: String(Catalog.packages.count))
            destinationButton("Installed", symbol: "checkmark.circle", mode: .uninstall, count: store.inventoryKnown ? String(Catalog.packages.filter { store.installed.contains($0.id) }.count + store.manualApps.count) : "—")
            destinationButton("Updates", symbol: "arrow.triangle.2.circlepath", mode: .updates, count: store.updatesChecked ? String(store.updates.count) : "—")
            Button { store.showMaintenance = true } label: { Label("Cleanup", systemImage: "sparkles").font(.system(size: 13, weight: .medium)).padding(9) }.buttonStyle(.plain)
            Divider().padding(.vertical, 10)
            Text("CATEGORIES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Catalog.categories, id: \.self) { category in navigationButton(category) }
                }.padding(.vertical, 6)
            }
            Link(destination: URL(string: "https://formulae.brew.sh")!) { Label("Homebrew catalog", systemImage: "arrow.up.right.square") }.font(.caption).padding(.bottom, 12)
            HStack(spacing: 8) {
                Circle().fill(store.brew == nil ? Color.orange : Color.green).frame(width: 8, height: 8)
                Text(store.brew == nil ? "Homebrew not found" : store.refreshing ? "Checking installed apps…" : "Homebrew ready").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(.thinMaterial)
    }
    func destinationButton(_ title: String, symbol: String, mode: ActionMode, count: String) -> some View {
        let active = store.mode == mode && (mode == .updates || store.category == "All Apps")
        return Button { store.navigate(mode) } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Text(count).font(.caption).monospacedDigit().opacity(0.7)
            }.padding(.horizontal, 9).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).background(active ? Color.accentColor : .clear).foregroundStyle(active ? .white : .primary).clipShape(RoundedRectangle(cornerRadius: 8))
    }
    func navigationButton(_ category: String) -> some View {
        let active = !store.updateMode && store.category == category
        return Button { store.navigate(store.updateMode ? .install : store.mode, category: category) } label: {
            HStack(spacing: 9) {
                Image(systemName: Catalog.symbols[category] ?? "square.grid.2x2").frame(width: 18)
                Text(category).font(.system(size: 12)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(String(store.updateMode ? Catalog.packages.filter { $0.belongs(to: category) }.count : store.count(in: category))).font(.caption2).monospacedDigit().opacity(0.65)
            }.padding(.horizontal, 9).padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain).background(active ? Color.accentColor : .clear).foregroundStyle(active ? .white : .primary).clipShape(RoundedRectangle(cornerRadius: 8))
    }
    @ViewBuilder func categoryBlock(_ category: String) -> some View {
        let apps = store.visible.filter { store.category == "All Apps" ? $0.category == category : $0.belongs(to: category) }
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(category.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Catalog.subcategories(in: category), id: \.self) { section in
                    let entries = apps.filter { store.subcategory == "All" ? $0.section(in: category) == section : section == store.subcategory && $0.belongs(to: category, subcategory: section) }
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Label(section + " · " + String(entries.count), systemImage: Catalog.sectionSymbol(section)).font(.system(size: 13, weight: .semibold))
                            LazyVStack(spacing: 0) {
                                ForEach(store.orderedPackages(entries)) { app in
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
            if !store.uninstallMode && (store.installed.contains(app.id) || store.appPresent(app) || store.localApps.contains { $0.package?.id == app.id }) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 18).help("Already on this Mac; not an installation selection")
            } else {
            Toggle(app.name, isOn: Binding(get: { store.selected.contains(app.id) }, set: { _ in store.toggle(app) })).labelsHidden().toggleStyle(.checkbox).disabled(store.locked || (!store.uninstallMode && !store.canInstall(app))).accessibilityLabel("Select \(app.name)")
            }
            Button { store.detailPackage = app } label: {
                HStack(spacing: 13) {
                    AppIcon(package: app).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 14, weight: .semibold))
                        Text(app.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        if store.category == "All Apps" || !store.search.isEmpty {
                            Text(app.category + " › " + app.section(in: app.category)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("View details for \(app.name)").accessibilityLabel("View details for \(app.name)")
            if !store.uninstallMode, !store.installed.contains(app.id), let local = store.localApps.first(where: { $0.package?.id == app.id }) {
                Button("Manage with Homebrew") { store.navigate(.uninstall); store.manualTab = true; store.selectedManual = [local.id] }.controlSize(.small).disabled(store.locked)
            }
            if !app.installable && !store.uninstallMode {
                Button("Setup details") {
                    store.detailPackage = app
                }.controlSize(.small)
                if let text = app.homepage, let url = URL(string: text), url.scheme == "https" {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help("Open official setup page")
                }
            }
            if store.uninstallMode && store.repairOptions[app.id] != nil {
                Button("Repair & Retry") { Task { await store.prepareRepair(app.id) } }.controlSize(.small).disabled(store.locked)
            }
            if store.uninstallMode, store.repairOptions[app.id] == nil, let message = store.failureMessages[app.id] {
                Button("View error") { store.notice = message }.controlSize(.small)
            }
            let status = store.statuses[app.id] ?? (store.installed.contains(app.id) ? "Installed" : app.manualAppExists ? "On this Mac" : "")
            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle((status == "Failed" || status == "Repair failed") ? Color.red : status == "Installed" ? Color.green : status == "Repair available" ? Color.orange : Color.secondary).padding(.horizontal, 9).padding(.vertical, 5).background(Color.primary.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button { store.detailPackage = app } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }.buttonStyle(.plain).help("App details and links").accessibilityLabel("Details for \(app.name)")
        }.padding(.horizontal, 14).padding(.vertical, 12).help(store.failureMessages[app.id] ?? "View app details")
    }
    var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.uninstallMode ? "Removal selection" : "To install").font(.title2.bold())
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
                    StatisticsView(package: package, preview: store.preview)
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
                if store.mode == .install && store.canInstall(package) {
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
            Text("Apps already on this Mac are not installation candidates. Use Installed → Installed manually to manage them with Homebrew.").font(.caption).foregroundStyle(.secondary)
            Text("Unavailable packages are skipped. Existing apps are never forcibly overwritten by this workflow.").font(.caption).foregroundStyle(.secondary)
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
            if store.cleanRemoval {
                Text("Leftover files (\(store.leftovers.count))").font(.headline)
                Text("Exact app identifiers and reviewed app-specific paths only. Shared vendor folders and unmatched files are left untouched; this does not guarantee every trace is found.").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    if store.leftovers.isEmpty { Text("No matching leftovers found. Some locations may require permission or a vendor uninstaller.").foregroundStyle(.secondary) }
                    ForEach(store.leftovers) { item in
                        Toggle(isOn: Binding(get: { store.selectedLeftovers.contains(item.id) }, set: { value in if value { store.selectedLeftovers.insert(item.id) } else { store.selectedLeftovers.remove(item.id) } })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.appName + " · " + item.kind + " · " + item.size).font(.caption.bold())
                                Text(item.path).font(.caption2).textSelection(.enabled)
                                if item.dataSensitive { Text("May contain settings or user data").font(.caption2).foregroundStyle(.orange) }
                            }
                        }.padding(.vertical, 5)
                    }
                }.frame(maxHeight: 240)
            }
            Text(store.cleanRemoval ? "Selected leftovers will move to Trash only after the app is successfully removed. Settings and user data are unchecked by default. Close the selected apps before continuing." : "Vendor uninstallers may remove app data. Packages needed by other software may refuse removal; see Operation details.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { store.showRemovalReview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.cleanRemoval ? "Uninstall & move selected files to Trash" : "Uninstall \(store.removalPlan.count) apps", role: .destructive) { Task { await store.uninstall() } }.buttonStyle(.borderedProminent).tint(.red)
            }
        }.padding(24).frame(width: 760, height: store.cleanRemoval ? 720 : 470).background(Color(nsColor: .windowBackgroundColor))
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
        alert.informativeText = "Wait for the current operation to finish before quitting. For app operations, you can use Stop after current app."
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
            if CommandLine.arguments.contains("--cleanup-preview") {
                root = AnyView(MaintenanceView(store: previewStore)); size = NSSize(width: 960, height: 700)
            }
            if CommandLine.arguments.contains("--category-preview") {
                previewStore.navigate(.install, category: "Development")
                root = AnyView(ContentView(store: previewStore))
            }
            if CommandLine.arguments.contains("--installed-preview") {
                previewStore.inventoryKnown = true
                previewStore.installed = Set(Catalog.packages.filter { ["google-chrome", "google-drive", "docker", "git"].contains($0.token) }.map(\.id))
                previewStore.navigate(.uninstall)
                root = AnyView(ContentView(store: previewStore))
            }
            if CommandLine.arguments.contains("--updates") {
                previewStore.mode = .updates; previewStore.updatesChecked = true; previewStore.headline = "3 updates available."
                previewStore.updates = Catalog.packages.filter { ["git", "blender", "google-chrome"].contains($0.token) }.map { UpdateItem(package: $0, installedVersion: "1.0", availableVersion: "2.0") }
                root = AnyView(ContentView(store: previewStore))
            }
            if CommandLine.arguments.contains("--manual-preview") {
                previewStore.navigate(.uninstall); previewStore.manualTab = true
                let p = Catalog.packages.first { $0.token == "figma" }!
                previewStore.localApps = [LocalApp(path: "/Applications/Figma.app", name: "Figma", identifier: "com.figma.Desktop", version: "126.9.11", package: p, identityMatched: false, inode: 0), LocalApp(path: "/Applications/Example.app", name: "Example", identifier: "org.example.app", version: "1.0", package: nil, identityMatched: false, inode: 0)]
                root = AnyView(ContentView(store: previewStore))
            }
            if CommandLine.arguments.contains("--export-preview") { root = AnyView(SetupExportView(store: previewStore)); size = NSSize(width: 650, height: 620) }
            if CommandLine.arguments.contains("--repair-preview") {
                let package = Catalog.packages.first { $0.token == "figma" }!
                let repair = RemovalRepair(package: package, caskroom: "/opt/homebrew/Caskroom", source: "/opt/homebrew/Caskroom/figma/126.9.11/Figma.app", inode: 0, device: 0, cleanup: [])
                root = AnyView(RemovalRepairView(store: previewStore, repair: repair)); size = NSSize(width: 700, height: 520)
            }
            if CommandLine.arguments.contains("--clean") {
                let package = Catalog.packages.first { $0.token == "blender" }!
                previewStore.removalPlan = [package]; previewStore.cleanRemoval = true
                previewStore.leftovers = [Leftover(packageID: package.id, appName: package.name, path: NSHomeDirectory() + "/Library/Caches/org.blenderfoundation.blender", kind: "Caches", bytes: 10485760, inode: 0, device: 0, dataSensitive: false), Leftover(packageID: package.id, appName: package.name, path: NSHomeDirectory() + "/Library/Application Support/Blender", kind: "Application Support", bytes: 20971520, inode: 0, device: 0, dataSensitive: true)]
                previewStore.selectedLeftovers = [previewStore.leftovers[0].id]
                root = AnyView(RemovalReviewView(store: previewStore)); size = NSSize(width: 760, height: 720)
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

struct UpdatesView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("App updates").font(.title2.bold())
                    Text("Homebrew-managed apps in this catalog. Updates can also install or repair required dependencies.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.preparing ? "Checking…" : "Check for updates") { Task { await store.checkUpdates() } }.disabled(store.locked || store.brew == nil)
            }
            Toggle("Include apps that update themselves", isOn: $store.includeSelfUpdating)
                .onChange(of: store.includeSelfUpdating) { _, _ in store.updates = []; store.selectedUpdates = []; store.updatesChecked = false }
                .disabled(store.locked)
            Text("Apps without a numbered Homebrew version are excluded. Pinned packages are skipped. Close apps before updating.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                if store.visibleUpdates.isEmpty {
                    ContentUnavailableView(store.preparing ? "Checking Homebrew…" : !store.updates.isEmpty ? "No matching updates" : store.updatesChecked ? "No updates found" : "Check your installed apps", systemImage: "arrow.triangle.2.circlepath", description: Text("Choose Check for updates to refresh the Homebrew catalog."))
                }
                ForEach(store.visibleUpdates) { item in
                    HStack {
                        Toggle(isOn: Binding(get: { store.selectedUpdates.contains(item.id) }, set: { value in if value { store.selectedUpdates.insert(item.id) } else { store.selectedUpdates.remove(item.id) } })) { EmptyView() }.labelsHidden().disabled(store.locked)
                        AppIcon(package: item.package).frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.package.name).bold()
                            Text(item.installedVersion + " → " + item.availableVersion).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let status = store.statuses[item.id] { Text(status).font(.caption) }
                        Button { store.detailPackage = item.package } label: { Image(systemName: "info.circle") }.buttonStyle(.plain)
                    }.padding(10)
                    Divider()
                }
            }
            if store.busy {
                ProgressView(value: Double(store.completed), total: Double(max(store.total, 1)))
                Button(store.stopRequested ? "Stopping after this update…" : "Stop after current app") { store.stopRequested = true }.disabled(store.stopRequested)
            }
            HStack {
                Button("Operation details") { store.showLog = true }
                Button("Select all") { store.selectedUpdates = Set(store.visibleUpdates.map(\.id)) }.disabled(store.locked)
                Button("Clear") { store.selectedUpdates = [] }.disabled(store.locked)
                Spacer()
                Button("Update \(store.selectedUpdates.count) apps") { store.prepareUpdates() }.buttonStyle(.borderedProminent).disabled(store.selectedUpdates.isEmpty || store.locked)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Mac Setup " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.6.0")).bold()
                    Text(store.appReleaseStatus).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.checkingAppRelease ? "Checking…" : "Check app release") { Task { await store.checkAppRelease() } }.disabled(store.checkingAppRelease)
                Link("Open releases", destination: URL(string: "https://github.com/CNRNYK/mac-setup-app/releases")!)
            }
        }.padding(24)
    }
}

struct UpdateReviewView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review selected updates").font(.title2.bold())
            Text("Selected apps will be upgraded through Homebrew. Running apps may close, vendor installers may request administrator permission, and dependencies may be updated. Close these apps before continuing.").foregroundStyle(.secondary)
            ScrollView {
                ForEach(store.updateQueue) { item in
                    HStack {
                        AppIcon(package: item.package).frame(width: 32, height: 32)
                        Text(item.package.name).bold()
                        Spacer()
                        Text(item.installedVersion + " → " + item.availableVersion).font(.caption)
                    }.padding(.vertical, 10)
                    Divider()
                }
            }
            HStack {
                Button("Cancel") { store.showUpdateReview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Update \(store.updateQueue.count) apps") { Task { await store.upgrade() } }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 700, height: 500).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct RemovalRepairView: View {
    @ObservedObject var store: Store
    let repair: RemovalRepair
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Repair removal of " + repair.package.name + "?", systemImage: "wrench.and.screwdriver").font(.title2.bold())
            Text("The app is missing from Applications, but Homebrew still has a stored copy and an installed record.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Conflicting stored app").bold()
                Text(repair.source).font(.caption).textSelection(.enabled)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 9))
            Text("Repair & Retry asks Homebrew to force removal of this app only, including the conflicting stored copy. It does not reinstall the app or bypass formula dependency checks.")
            Text(repair.cleanup.isEmpty ? "No extra data cleanup is selected." : "After verified removal, the \(repair.cleanup.count) leftover items you previously selected will move to Trash. No new paths will be added.").font(.caption).foregroundStyle(.secondary)
            if !repair.cleanup.isEmpty {
                ScrollView { ForEach(repair.cleanup) { item in Text(item.path + " · " + item.size).font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3) } }
            } else { Spacer() }
            HStack {
                Button("Cancel") { store.repairReview = nil }.keyboardShortcut(.cancelAction)
                Button("Operation details") { store.repairReview = nil; store.showLog = true }
                Spacer()
                Button(store.preparing ? "Checking…" : "Repair & Retry", role: .destructive) { Task { await store.repairAndRetry() } }.buttonStyle(.borderedProminent).tint(.red).disabled(store.locked)
            }
        }.padding(24).frame(width: 700, height: 520).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ManualAppsView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Installed manually").font(.title2.bold())
            Text("Choose which apps to manage with Homebrew. Matches use this app's curated catalog; unknown apps remain untouched. Homebrew verifies app contents before adoption.").font(.caption).foregroundStyle(.secondary)
            if store.category != "All Apps" {
                Picker("Section", selection: $store.subcategory) {
                    Label("All sections", systemImage: "square.grid.2x2").tag("All")
                    ForEach(Catalog.subcategories(in: store.category), id: \.self) { section in Label(section, systemImage: Catalog.sectionSymbol(section)).tag(section) }
                }.frame(maxWidth: 430)
            }
            ScrollView {
                ForEach(store.visibleManualApps) { app in
                    HStack(spacing: 12) {
                        Toggle(app.name, isOn: Binding(get: { store.selectedManual.contains(app.id) }, set: { value in if value { store.selectedManual.insert(app.id) } else { store.selectedManual.remove(app.id) } })).labelsHidden().disabled(store.locked || app.package?.installable != true)
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().scaledToFit().frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).bold()
                            Text(app.identifier + " · " + app.version).font(.caption).foregroundStyle(.secondary)
                            Text(app.path).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.adoptionStatuses[app.id] ?? (app.package?.installable == true ? "Review required" : "No supported matching package")).font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                    Divider()
                }
                if store.visibleManualApps.isEmpty { ContentUnavailableView("No manual apps found", systemImage: "app", description: Text("Refresh to scan Applications and your user Applications folder.")) }
            }
            if store.busy {
                ProgressView(value: Double(store.completed), total: Double(max(store.total, 1)))
                Button("Stop after current app") { store.stopRequested = true }.disabled(store.stopRequested)
            }
            HStack {
                Button("Operation details") { store.showLog = true }
                Button("Select supported apps") { store.selectedManual.formUnion(store.visibleManualApps.filter { $0.package?.installable == true }.map(\.id)) }.disabled(store.locked)
                Button("Clear") { store.selectedManual = [] }.disabled(store.locked)
                Spacer()
                Button("Manage \(store.selectedManual.count) with Homebrew") { Task { await store.prepareAdoption() } }.buttonStyle(.borderedProminent).disabled(store.selectedManual.isEmpty || store.locked || store.brew == nil)
            }
        }.padding(24)
    }
}
struct AdoptionReviewView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Homebrew management").font(.title2.bold())
            Text("App bundles are adopted only when their contents match. Vendor installers may update existing apps and request administrator permission. Different contents are not forcibly overwritten.").foregroundStyle(.secondary)
            ScrollView {
                ForEach(store.adoptionPlan) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.app.name).bold()
                        Text(item.action).font(.caption).foregroundStyle(item.problem == nil ? Color.secondary : .red)
                        Text(item.app.path).font(.caption2)
                        if !item.version.isEmpty { Text("Homebrew version: " + item.version).font(.caption2) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    Divider()
                }
            }
            HStack {
                Button("Cancel") { store.showAdoptionReview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Confirm & manage selected apps") { Task { await store.adoptSelected() } }.buttonStyle(.borderedProminent).disabled(!store.adoptionPlan.contains { $0.problem == nil })
            }
        }.padding(24).frame(width: 720, height: 560).background(Color(nsColor: .windowBackgroundColor))
    }
}
struct SetupExportView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export setup for a new Mac").font(.title2.bold())
            Text("This selection only creates a Brewfile. It does not install or remove anything on this Mac.").foregroundStyle(.secondary)
            TextField("Search setup apps", text: $store.exportSearch).textFieldStyle(.roundedBorder)
            HStack {
                Button("Add Homebrew-managed apps") { store.exportSelected.formUnion(Catalog.packages.filter { $0.installable && store.installed.contains($0.id) }.map(\.id)) }
                Button("Clear") { store.exportSelected = [] }
            }
            ScrollView {
                ForEach(Catalog.packages.filter { $0.installable && (store.exportSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(store.exportSearch)) }.sorted { $0.name < $1.name }) { package in
                    Toggle(package.name, isOn: Binding(get: { store.exportSelected.contains(package.id) }, set: { value in if value { store.exportSelected.insert(package.id) } else { store.exportSelected.remove(package.id) } })).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Text("\(store.exportSelected.count) apps in setup").font(.caption)
                Spacer()
                Button("Cancel") { store.showSetupExport = false }.keyboardShortcut(.cancelAction)
                Button("Save Brewfile") { store.exportFile() }.buttonStyle(.borderedProminent).disabled(store.exportSelected.isEmpty)
            }
        }.padding(24).frame(width: 650, height: 620).background(Color(nsColor: .windowBackgroundColor))
    }
}
