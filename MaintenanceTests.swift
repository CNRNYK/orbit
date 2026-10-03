import Foundation
@MainActor enum MaintenanceTests {
    static func run() throws {
        let json = Data(#"{"token":"figma","generated_date":"2026-10-03","analytics":{"install":{"30d":{"figma":12},"90d":{"figma":30,"figma --language=en":2}}}}"#.utf8)
        let statistics = try InstallStatistics.parse(json, token:"figma")
        precondition(statistics.counts == ["30d":12,"90d":32])
        precondition((try? InstallStatistics.parse(json,token:"other")) == nil)
        precondition((try? InstallStatistics.parse(Data("{}".utf8),token:"figma")) == nil)
        let negative = Data(#"{"name":"git","analytics":{"install":{"30d":{"git":-1}}}}"#.utf8)
        precondition((try? InstallStatistics.parse(negative,token:"git")) == nil)
        let report = try PopularityReport.parse(Data(#"{"end_date":"2026-10-03","items":[{"cask":"figma","count":"1,200"}]}"#.utf8),cask:true)
        precondition(report.0 == ["cask:figma":1200])
        let store = Store(preview:true,persistSelection:false)
        let figma = Catalog.packages.first { $0.token == "figma" }!
        let git = Catalog.packages.first { $0.token == "git" }!
        store.popularity = [figma.id:1200,git.id:5]; store.popularSort = true
        precondition(store.orderedPackages([git,figma]).first == figma)
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("cleanup-tests-" + UUID().uuidString).resolvingSymlinksInPath().path
        defer { try? fm.removeItem(atPath:home) }
        let cache = home + "/Library/Caches/fixture"
        let derived = home + "/Library/Developer/Xcode/DerivedData/fixture"
        for path in [cache,derived] { try fm.createDirectory(atPath:path,withIntermediateDirectories:true); try Data("1234".utf8).write(to:URL(fileURLWithPath:path + "/data")) }
        let initial = MaintenanceScan.scan(home:home)
        precondition(initial.contains { $0.path == cache } && !initial.contains { $0.path == derived })
        precondition(MaintenanceScan.scan(home:home,developer:true).contains { $0.path == derived })
        let item = initial.first { $0.path == cache }!
        precondition(item.bytes == 4 && MaintenanceScan.unchanged(item,home:home))
        precondition(!MaintenanceScan.permitted(home + "/Documents/a",group:"App caches & logs",home:home))
        precondition(!MaintenanceScan.permitted(home + "/Library/Caches",group:"App caches & logs",home:home))
        precondition(!MaintenanceScan.permitted(home + "/Library/Caches/../Documents/a",group:"App caches & logs",home:home))
        var moved = [String]()
        try MaintenanceScan.trash(item,home:home) { moved.append($0.path) }
        precondition(moved == [cache] && fm.fileExists(atPath:cache))
        try fm.moveItem(atPath:cache,toPath:cache + "-old")
        try fm.createSymbolicLink(atPath:cache,withDestinationPath:derived)
        precondition(!MaintenanceScan.unchanged(item,home:home))
        precondition(MaintenanceScan.snapshot(cache,group:"App caches & logs",home:home) == nil)
        do { try MaintenanceScan.trash(item,home:home) { moved.append($0.path) }; preconditionFailure("Changed paths must never be trashed") } catch {}
        precondition(moved.count == 1)
        let discovery = MaintenanceItem(path:home + "/Downloads/large",group:"Large files",bytes:500_000_000,inode:0,device:0,removable:false)
        do { try MaintenanceScan.trash(discovery,home:home) { moved.append($0.path) }; preconditionFailure("Discovery files cannot be deleted") } catch {}
        precondition(moved.count == 1)
        print("PASS: official analytics parsing and sorting, missing/invalid counts, optional developer caches, cleanup scope, symlink/identity protection, exact mocked trash, personal-file deletion blocking")
    }
}
