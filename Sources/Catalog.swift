import Foundation

struct Placement: Codable, Hashable {
    let category: String
    let subcategory: String
}

struct Package: Identifiable, Hashable, Codable {
    let token: String
    let name: String
    let detail: String
    let cask: Bool
    let appName: String?
    let placements: [Placement]
    let homepage: String?
    let availability: String
    let sourceNumbers: [Int]
    let formulaLicense: String?
    let github: String?
    let githubSource: String?
    let githubPurpose: String?
    let homepageSource: String?
    let version: String?
    let logoURL: String?
    let logoSource: String?
    let logoAsset: String?
    var officialLogoURL: URL? {
        guard let url = Self.webURL(logoURL), url.scheme == "https" else { return nil }
        return url
    }
    var logoFilename: String? {
        guard let logoAsset, logoAsset.range(of: #"^[a-f0-9]{24}\.(png|ico|jpg)$"#, options: .regularExpression) != nil else { return nil }
        return logoAsset
    }
    static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    var websiteURL: URL? { Self.webURL(homepage) }
    var githubURL: URL? {
        guard let url = Self.webURL(github), url.scheme == "https", url.host?.lowercased() == "github.com",
              url.pathComponents.count == 3 else { return nil }
        return url
    }
    var catalogURL: URL? {
        guard !token.hasPrefix("manual-") else { return nil }
        return URL(string: "https://formulae.brew.sh/\(cask ? "cask" : "formula")/\(token)")
    }
    var id: String { (token.hasPrefix("manual-") ? "manual:" : cask ? "cask:" : "brew:") + token }
    var installable: Bool { availability.isEmpty && !token.hasPrefix("manual-") }
    var category: String { placements.first?.category ?? "Other" }
    var symbol: String { Catalog.symbols[category] ?? "shippingbox" }
    var brewLine: String { "\(cask ? "cask" : "brew") \"\(token)\"" }
    func belongs(to category: String, subcategory: String = "All") -> Bool {
        placements.contains { $0.category == category && (subcategory == "All" || $0.subcategory == subcategory) }
    }
    func section(in category: String) -> String {
        placements.first { $0.category == category }?.subcategory ?? "General"
    }
    var manualAppExists: Bool {
        guard let appName else { return false }
        return ["/Applications", NSHomeDirectory() + "/Applications"].contains {
            FileManager.default.fileExists(atPath: $0 + "/" + appName + ".app")
        }
    }
}

struct CatalogData: Decodable {
    let verifiedDate: String
    let sourceEntryCount: Int
    let categories: [String]
    let symbols: [String: String]
    let packages: [Package]
    let presets: [String: [String]]
    let categoryDescriptions: [String: String]?
    let subcategorySymbols: [String: String]?
    let subcategoryOrder: [String: [String]]?
}

enum Catalog {
    private static let loaded: Result<CatalogData, Error> = Result {
        let url = Bundle.main.url(forResource: "catalog", withExtension: "json") ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/catalog.json")
        return try JSONDecoder().decode(CatalogData.self, from: Data(contentsOf: url))
    }
    static var loadError: String? {
        if case .failure(let error) = loaded { return "The application catalog could not be loaded: " + error.localizedDescription }
        return nil
    }
    static var data: CatalogData? { try? loaded.get() }
    static var categories: [String] { data?.categories ?? [] }
    static var symbols: [String: String] { data?.symbols ?? [:] }
    static var packages: [Package] { data?.packages ?? [] }
    static var categoryDescriptions: [String: String] { data?.categoryDescriptions ?? [:] }
    static func sectionSymbol(_ section: String) -> String { data?.subcategorySymbols?[section] ?? "square.grid.2x2" }
    static var presets: [String: [String]] { data?.presets ?? [:] }
    static func subcategories(in category: String) -> [String] {
        var seen = Set<String>()
        let sections = packages.flatMap(\.placements).filter { $0.category == category }.map(\.subcategory).filter { seen.insert($0).inserted }
        let order = data?.subcategoryOrder?[category] ?? []
        return sections.sorted {
            let left = order.firstIndex(of: $0) ?? Int.max; let right = order.firstIndex(of: $1) ?? Int.max
            return left == right ? $0 < $1 : left < right
        }
    }
    static func export(_ packages: [Package]) -> String {
        var seen = Set<String>()
        return "# Created with Mac Setup\n# Install with: brew bundle --file=./Brewfile\n\n" + packages.filter { $0.installable && seen.insert($0.id).inserted }.map(\.brewLine).joined(separator: "\n") + "\n"
    }
    static func parse(_ text: String, packages: [Package] = Catalog.packages) -> (Set<String>, [String]) {
        let regex = try! NSRegularExpression(pattern: #"^\s*(brew|cask)\s+[\"]([a-z0-9@+._/-]+)[\"]\s*(?:#.*)?$"#)
        var selected = Set<String>(); var unsupported = [String]()
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               let package = packages.first(where: { $0.installable && $0.token == ns.substring(with: match.range(at: 2)) && $0.cask == (ns.substring(with: match.range(at: 1)) == "cask") }) {
                selected.insert(package.id)
            } else { unsupported.append(trimmed) }
        }
        return (selected, unsupported)
    }
}
