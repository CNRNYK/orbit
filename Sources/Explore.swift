import SwiftUI
import AppKit

struct ExploreSnapshot: Codable {
    let packages: [Package]
    let fetched: Date
}
extension Package {
    var operationToken: String { OfficialCatalog.validSaved(self) ? "homebrew/\(cask ? "cask" : "core")/\(token)" : token }
}
enum OfficialCatalog {
    static func validToken(_ token: String) -> Bool { token.count < 180 && token.range(of: #"^[a-z0-9][a-z0-9+_.@-]*$"#, options: .regularExpression) != nil }
    static func source(_ token: String, cask: Bool) -> String { "https://formulae.brew.sh/api/\(cask ? "cask" : "formula")/\(token).json" }
    static func validSaved(_ package: Package) -> Bool {
        (package.appName == nil || (package.appName?.contains("/") == false && package.appName?.contains("\\") == false && package.appName?.isEmpty == false)) && validToken(package.token) && !package.token.hasPrefix("manual-") && package.sourceNumbers.isEmpty && package.homepageSource == source(package.token,cask:package.cask)
    }
    static func saved(_ data: Data?) -> [Package] {
        guard let data, data.count < 5_000_000, let decoded = try? JSONDecoder().decode([Package].self,from:data), decoded.count <= 2000 else { return [] }
        var seen = Set<String>()
        return decoded.filter { validSaved($0) && seen.insert($0.id).inserted }
    }
    static func parse(_ data: Data, cask: Bool) throws -> [Package] {
        guard data.count < 80_000_000, let rows = try JSONSerialization.jsonObject(with:data) as? [[String:Any]], rows.count <= 30_000 else { throw URLError(.cannotParseResponse) }
        var seen = Set<String>()
        let packages: [Package] = rows.compactMap { row in
            guard row["tap"] as? String == (cask ? "homebrew/cask" : "homebrew/core"), let token = row[cask ? "token" : "name"] as? String, validToken(token), !token.hasPrefix("manual-"), seen.insert(token).inserted else { return nil }
            let name = cask ? (row["name"] as? [String])?.first ?? token : token
            let homepage = Package.webURL(row["homepage"] as? String)?.absoluteString
            let artifacts = row["artifacts"] as? [[String:Any]] ?? []
            let app = artifacts.compactMap { $0["app"] as? [Any] }.first
            let target = (app?.last as? [String:Any])?["target"] as? String ?? app?.first as? String
            let appName = target.flatMap { value -> String? in
                guard value.hasSuffix(".app"), !value.contains("/"), !value.contains("\\"), value != ".app" else { return nil }
                return String(value.dropLast(4))
            }
            let disabled = row["disabled"] as? Bool == true || row["deprecated"] as? Bool == true
            let version = row["version"] as? String ?? (row["versions"] as? [String:Any])?["stable"] as? String
            let github = homepage.flatMap { url -> String? in
                guard let u = URL(string:url), u.host == "github.com", u.pathComponents.count == 3 else { return nil }; return url
            }
            return Package(token:token,name:name,detail:row["desc"] as? String ?? "Official Homebrew package.",cask:cask,appName:appName,placements:[Placement(category:"My apps",subcategory:cask ? "Applications" : "Command-line tools")],homepage:homepage,availability:disabled ? "Disabled or deprecated by Homebrew" : "",sourceNumbers:[],formulaLicense:row["license"] as? String,github:github,githubSource:github == nil ? nil : source(token,cask:cask),githubPurpose:github == nil ? nil : "Project",homepageSource:source(token,cask:cask),version:version,logoURL:nil,logoSource:nil,logoAsset:nil)
        }
        guard !packages.isEmpty else { throw URLError(.cannotParseResponse) }
        return packages
    }
    static func fetch(_ cask: Bool) async throws -> [Package] {
        let url = URL(string:"https://formulae.brew.sh/api/\(cask ? "cask" : "formula").json")!
        let (data,response) = try await URLSession.shared.data(for:URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:45))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try await Task.detached { try parse(data,cask:cask) }.value
    }
    static func fetchAll() async throws -> ExploreSnapshot {
        async let casks = fetch(true)
        async let formulas = fetch(false)
        return try await ExploreSnapshot(packages: casks + formulas, fetched:Date())
    }
}
@MainActor extension Store {
    var packages: [Package] {
        let curated = Set(Catalog.packages.map(\.id))
        return Catalog.packages + personalPackages.filter { !curated.contains($0.id) }
    }
    var exploreMatches: [Package] {
        explorePackages.filter {
            (exploreKind == "All" || (exploreKind == "Apps" ? $0.cask : !$0.cask)) &&
            (!exploreAvailableOnly || $0.installable) &&
            (exploreSearch.isEmpty || ($0.token + " " + $0.name + " " + $0.detail).localizedCaseInsensitiveContains(exploreSearch))
        }.sorted {
            let left = $0.token == exploreSearch.lowercased(); let right = $1.token == exploreSearch.lowercased()
            if left != right { return left }
            return $0.name == $1.name ? $0.id < $1.id : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    var exploreCacheURL: URL? {
        guard personalPersistence else { return nil }
        return FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first?.appendingPathComponent("io.macsetup.desktop/explore.json")
    }
    func loadExplore(force: Bool = false) async {
        guard !loadingExplore, !preview else { return }
        if !force, explorePackages.isEmpty, let url = exploreCacheURL, let data = try? Data(contentsOf:url), data.count < 40_000_000, let snapshot = try? JSONDecoder().decode(ExploreSnapshot.self,from:data), snapshot.packages.count <= 30_000, snapshot.packages.allSatisfy(OfficialCatalog.validSaved) {
            explorePackages = snapshot.packages; exploreFetched = snapshot.fetched
        }
        if !force, !explorePackages.isEmpty, let fetched = exploreFetched, Date().timeIntervalSince(fetched) >= 0, Date().timeIntervalSince(fetched) < 86400 { return }
        loadingExplore = true; defer { loadingExplore = false }; exploreMessage = ""
        do {
            let snapshot = try await exploreLoader()
            guard !snapshot.packages.isEmpty, snapshot.packages.allSatisfy(OfficialCatalog.validSaved) else { throw URLError(.cannotParseResponse) }
            explorePackages = snapshot.packages; exploreFetched = snapshot.fetched
            if let url = exploreCacheURL {
                try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
                if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to:url,options:.atomic) }
            }
        } catch { exploreMessage = "Could not refresh the Homebrew catalog. " + (explorePackages.isEmpty ? "Check your connection and try again." : "Showing the last downloaded catalog.") }
    }
    func registerPersonal(_ package: Package, favorite: Bool = false) {
        guard !locked, package.installable else { return }
        if !Catalog.packages.contains(where: { $0.id == package.id }), OfficialCatalog.validSaved(package) {
            if let index = personalPackages.firstIndex(where: { $0.id == package.id }) { personalPackages[index] = package } else { personalPackages.append(package) }
        }
        if favorite, packages.contains(where: { $0.id == package.id }) { myAppIDs.insert(package.id) }
    }
    func removeFavorite(_ package: Package) { guard !locked else { return }; myAppIDs.remove(package.id) }
}
struct ExploreView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { VStack(alignment:.leading,spacing:5) { Text("Explore Homebrew").font(.largeTitle.bold()); Text("Find apps and tools beyond the starter catalog.").foregroundStyle(.secondary) }; Spacer(); Button("Refresh catalog") { Task { await store.loadExplore(force:true) } }.disabled(store.loadingExplore) }
            HStack {
                TextField("Search names and descriptions",text:$store.exploreSearch).textFieldStyle(.roundedBorder)
                Picker("Packages",selection:$store.exploreKind) { Text("All").tag("All"); Text("Apps").tag("Apps"); Text("CLI tools").tag("Tools") }.frame(width:190)
                Toggle("Available only",isOn:$store.exploreAvailableOnly)
            }
            if store.loadingExplore { ProgressView("Refreshing official Homebrew catalog…") }
            if store.preparing || store.refreshing { ProgressView("Checking Homebrew…") }
            if let date = store.exploreFetched { Text("Catalog fetched: " + date.formatted()).font(.caption).foregroundStyle(.secondary) }
            if !store.exploreMessage.isEmpty { Text(store.exploreMessage).font(.caption).foregroundStyle(.orange) }
            let matches = store.exploreMatches
            Text("\(matches.count) matches · showing up to 150. Narrow your search for more results.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing:0) {
                    ForEach(Array(matches.prefix(150))) { package in
                        HStack(spacing:12) {
                            Toggle("Select " + package.name, isOn: Binding(get: { store.selected.contains(package.id) }, set: { _ in store.toggle(package) })).labelsHidden().toggleStyle(.checkbox).disabled(store.locked || !store.canInstall(package)).accessibilityLabel("Select " + package.name)
                            AppIcon(package: package).frame(width: 32, height: 32)
                            Button { store.detailPackage = package } label: {
                                VStack(alignment:.leading,spacing:4) { Text(package.name).font(.headline); Text(package.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2); Text("\(package.cask ? "App" : "CLI") · \(package.token) · \(package.version ?? "Unknown version")").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading)
                            }.buttonStyle(.plain)
                            if store.installed.contains(package.id) { Text("Installed").font(.caption).foregroundStyle(.green) }
                            else if store.appPresent(package) { Text("On this Mac").font(.caption).foregroundStyle(.secondary) }
                            if let status = store.statuses[package.id], status != "Installed" { Text(status).font(.caption).foregroundStyle(status == "Failed" ? .orange : .secondary) }
                            if !package.installable { Text(package.availability).font(.caption).foregroundStyle(.orange) }
                            Button(store.myAppIDs.contains(package.id) ? "Saved" : "Add to My apps") { store.registerPersonal(package,favorite:true) }.disabled(store.locked || !package.installable || store.myAppIDs.contains(package.id))
                            Button(store.selected.contains(package.id) ? "Selected" : "Select to install") { store.toggle(package) }.disabled(store.locked || !store.canInstall(package))
                        }.padding(.vertical,12)
                        Divider()
                    }
                    if matches.isEmpty && !store.loadingExplore { ContentUnavailableView("No packages found",systemImage:"magnifyingglass",description:Text(store.explorePackages.isEmpty ? "Refresh the catalog to browse official Homebrew apps and tools." : "Try a different search or package filter.")) }
                }
            }
            DisclosureGroup("Selected apps · \(store.installSelection.count)", isExpanded: $store.showExploreSelection) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if store.installSelection.isEmpty { Text("Check apps above to build your installation selection.").foregroundStyle(.secondary) }
                        ForEach(store.installSelection) { package in HStack { Text(package.name); Spacer(); Button("Remove") { store.toggle(package) }.disabled(store.locked) } }
                    }.padding(.vertical, 8)
                }.frame(maxHeight: 140)
            }
            if store.busy {
                ProgressView(value:Double(store.completed),total:Double(max(store.total,1)))
                HStack { Text(store.progressSummary + " · " + store.headline).font(.caption).foregroundStyle(.secondary); Spacer(); Button(store.stopRequested ? "Stopping after this app…" : "Stop after current app") { store.stopRequested = true }.disabled(store.stopRequested) }
            }
            HStack {
                Button("Operation details") { store.showLog = true }
                Text("Official Homebrew only.").font(.caption).foregroundStyle(.secondary).help("Homebrew/core and Homebrew/cask")
                Spacer()
                Button("My apps") { store.navigate(.install,category:"My apps") }
                Button("Export setup") { store.exportSelected.formUnion(store.selected); store.showSetupExport = true }.disabled(store.locked)
                Button("Review \(store.installSelection.count) selected apps") { Task { await store.prepare() } }.buttonStyle(.borderedProminent).disabled(store.locked || store.installSelection.isEmpty || !store.startupReady || store.brew == nil)
            }
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor)).task { await store.loadExplore() }
    }
}
