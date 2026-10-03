import SwiftUI

struct InstallStatistics {
    let counts: [String: Int]
    let generated: String
    static func parse(_ data: Data, token: String) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["token"] as? String ?? root["name"] as? String) == token,
              let analytics = root["analytics"] as? [String: Any],
              let installs = analytics["install"] as? [String: Any] else {
            throw NSError(domain: "Statistics", code: 1, userInfo: [NSLocalizedDescriptionKey: "Statistics unavailable for this package."])
        }
        var counts = [String: Int]()
        for period in ["30d", "90d", "365d"] {
            if let rows = installs[period] as? [String: NSNumber] {
                let values = rows.values.map { $0.intValue }
                if values.allSatisfy({ $0 >= 0 }) {
                    var total = 0; var valid = true
                    for value in values { let sum = total.addingReportingOverflow(value); if sum.overflow { valid = false; break }; total = sum.partialValue }
                    if valid { counts[period] = total }
                }
            }
        }
        guard !counts.isEmpty else { throw NSError(domain: "Statistics", code: 2, userInfo: [NSLocalizedDescriptionKey: "No published installation statistics."]) }
        return Self(counts: counts, generated: root["generated_date"] as? String ?? "Not supplied")
    }
}
@MainActor final class StatisticsState: ObservableObject {
    @Published var statistics: InstallStatistics?
    @Published var loading = false
    @Published var message = ""
    @Published var fetched: Date?
}
struct StatisticsView: View {
    let package: Package
    var preview = false
    @StateObject private var state = StatisticsState()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Homebrew installs").font(.headline); Spacer(); Button("Refresh") { Task { await load() } }.disabled(state.loading) }
            if state.loading { ProgressView().controlSize(.small) }
            if let statistics = state.statistics {
                HStack(spacing: 26) {
                    ForEach(["30d", "90d", "365d"], id: \.self) { period in
                        VStack(alignment: .leading) { Text(statistics.counts[period].map { $0.formatted() } ?? "Unavailable").font(.title3.bold()); Text("Last " + period.dropLast() + " days").font(.caption) }
                    }
                }
                Text("Source generated: \(statistics.generated)").font(.caption).foregroundStyle(.secondary)
            }
            if let fetched = state.fetched { Text("Fetched: " + fetched.formatted()).font(.caption).foregroundStyle(.secondary) }
            if !state.message.isEmpty { Text(state.message).font(.caption).foregroundStyle(.secondary) }
            Text("Anonymous reported installation events; not total downloads or unique users.").font(.caption).foregroundStyle(.secondary)
        }.task { if preview { state.statistics = InstallStatistics(counts: ["30d": 1794, "90d": 10405, "365d": 39925], generated: "Preview data"); state.fetched = Date() } else { await load() } }
    }
    func load() async {
        guard !preview, !state.loading else { return }; state.loading = true; defer { state.loading = false }
        do {
            let url = URL(string: "https://formulae.brew.sh/api/\(package.cask ? "cask" : "formula")/\(package.token).json")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("Orbit/0.9", forHTTPHeaderField: "User-Agent")
            let (data,response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000 else { throw URLError(.badServerResponse) }
            state.statistics = try InstallStatistics.parse(data, token: package.token); state.fetched = Date(); state.message = ""
        } catch { state.message = "Could not refresh statistics. " + error.localizedDescription }
    }
}

enum PopularityReport {
    static func parse(_ data: Data, cask: Bool) throws -> ([String:Int],String) {
        guard let root = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let rows = root["items"] as? [[String:Any]], let end = root["end_date"] as? String else { throw URLError(.cannotParseResponse) }
        var counts = [String:Int]()
        for row in rows {
            guard let token = row[cask ? "cask" : "formula"] as? String,
                  let raw = row["count"] as? String, let count = Int(raw.replacingOccurrences(of:",",with:"")), count >= 0 else { continue }
            let id = (cask ? "cask:" : "brew:") + token
            let sum = (counts[id] ?? 0).addingReportingOverflow(count)
            guard !sum.overflow else { throw URLError(.cannotParseResponse) }
            counts[id] = sum.partialValue
        }
        return (counts,end)
    }
}
@MainActor extension Store {
    func orderedPackages(_ packages: [Package]) -> [Package] {
        packages.sorted {
            if popularSort, popularity[$0.id] != popularity[$1.id] { return (popularity[$0.id] ?? -1) > (popularity[$1.id] ?? -1) }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    func loadPopularity() async {
        guard !fetchingPopularity else { return }; fetchingPopularity = true; defer { fetchingPopularity = false }
        do {
            var counts = [String:Int](); var dates = [String]()
            for cask in [true,false] {
                let category = cask ? "cask-install" : "install"
                let url = URL(string:"https://formulae.brew.sh/api/analytics/\(category)/30d.json")!
                let (data,response) = try await URLSession.shared.data(for:URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:20))
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 10_000_000 else { throw URLError(.badServerResponse) }
                let report = try PopularityReport.parse(data,cask:cask)
                counts.merge(report.0,uniquingKeysWith:+); dates.append(report.1)
            }
            popularity = counts
            popularityDate = "Anonymous installation events. Period ends: " + dates.joined(separator:", ") + ". Fetched: " + Date().formatted()
        } catch { notice = "Could not refresh installation statistics. Existing statistics are retained; otherwise apps are sorted by name." }
    }
}
