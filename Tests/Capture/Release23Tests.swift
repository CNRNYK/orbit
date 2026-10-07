import AppKit
import CoreImage
@MainActor enum Release23Tests {
    static func run() async throws {
        let state = AnnotationState(), size = CGSize(width:1000,height:500)
        let cover = OrbitAnnotation(tool:"Cover",points:[CGPoint(x:0.1,y:0.1),CGPoint(x:0.3,y:0.3)])
        let text = OrbitAnnotation(tool:"Text",points:[CGPoint(x:0.5,y:0.5)],text:"Original")
        state.values = [cover,text]
        state.select(at:CGPoint(x:0.2,y:0.2),size:size); precondition(state.selectedID == cover.id)
        state.beginGesture(); state.moveSelected(from:cover,delta:CGPoint(x:0.3,y:0.2),size:size); state.finishGesture()
        precondition(abs(state.selected!.points.first!.x-0.4)<0.0001 && abs(state.selected!.points.first!.y-0.3)<0.0001)
        state.undo(); precondition(state.values[0] == cover)
        state.select(at:CGPoint(x:0.2,y:0.2),size:size); state.beginGesture(); state.moveSelected(from:cover,delta:CGPoint(x:2,y:-2),size:size); state.finishGesture()
        let moved = AnnotationGeometry.bounds(state.values[0],size:size)
        precondition(abs(moved.maxX-1)<0.0001 && abs(moved.minY)<0.0001)
        state.selectedID = text.id; state.editSelectedText("Edited"); precondition(state.values[1].text == "Edited")
        state.deleteSelected(); precondition(state.values.count == 1 && state.values[0].id == cover.id)
        state.undo(); precondition(state.values.count == 2 && state.values[1].text == "Edited")
        state.selectedID = nil; let before = state.values; state.deleteSelected(); precondition(state.values == before)
        let arrow = OrbitAnnotation(tool:"Arrow",points:[CGPoint(x:0.1,y:0.8),CGPoint(x:0.9,y:0.8)])
        precondition(AnnotationGeometry.hit(arrow,point:CGPoint(x:0.5,y:0.8),size:size) && !AnnotationGeometry.hit(arrow,point:CGPoint(x:0.5,y:0.5),size:size))
        let rectangle = OrbitAnnotation(tool:"Rectangle",points:[CGPoint(x:0.1,y:0.1),CGPoint(x:0.4,y:0.4)])
        precondition(!AnnotationGeometry.hit(rectangle,point:CGPoint(x:0.25,y:0.25),size:size))
        precondition(AnnotationGeometry.hit(text,point:CGPoint(x:0.51,y:0.49),size:size))
        state.reset(); precondition(state.values.isEmpty && !state.canUndo)
        let candidates = [CaptureWindowCandidate(id:2,frame:CGRect(x:-900,y:400,width:400,height:200)),CaptureWindowCandidate(id:1,frame:CGRect(x:-1000,y:300,width:800,height:500))]
        precondition(CaptureWindowGeometry.hit(CGPoint(x:-800,y:450),ordered:candidates) == 2)
        precondition(CaptureWindowGeometry.hit(CGPoint(x:-950,y:350),ordered:candidates) == 1)
        precondition(CaptureWindowGeometry.hit(CGPoint(x:0,y:0),ordered:candidates) == nil)
        precondition(CaptureWindowGeometry.appKit(CGRect(x:-900,y:-500,width:400,height:200),primaryTop:1080) == CGRect(x:-900,y:1380,width:400,height:200))
        let cleanup = MaintenanceState()
        cleanup.items = [MaintenanceItem(path:"/Users/test/Library/Caches/Homebrew/downloads",group:"Homebrew cache",bytes:100,inode:0,device:0,removable:true),MaintenanceItem(path:"/Users/test/Library/Caches/com.apple.GeoServices",group:"App caches & logs",bytes:200,inode:0,device:0,removable:true),MaintenanceItem(path:"/Users/test/Downloads/personal",group:"Large files",bytes:500_000_000,inode:0,device:0,removable:false)]
        cleanup.selectRecommended(); precondition(cleanup.selected == [cleanup.items[0].id]); precondition(cleanup.items[1].level == "Advanced")
        cleanup.filter = "Advanced"; precondition(cleanup.items.filter(cleanup.visible).count == 1)
        cleanup.filter = "Large items"; precondition(cleanup.items.filter(cleanup.visible).first?.removable == false)
        let guardStore = Store(preview:true,persistSelection:false)
        guardStore.screenshots.source.choosingWindow = true; precondition(guardStore.locked && !guardStore.recorderState.canBegin()); guardStore.screenshots.source.choosingWindow = false
        guardStore.detachState.working = true; precondition(guardStore.locked && !guardStore.screenshots.canAct()); guardStore.detachState.working = false
        try await detachFixtures()
        print("PASS: annotation hit testing/move/clamp/edit/delete/undo/reset, window z-order and negative origins, conservative cleanup selections, detach policy/backup/rollback/restore")
    }
    static func detachFixtures() async throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("orbit-detach-fixture-" + UUID().uuidString).resolvingSymlinksInPath()
        defer { try? fm.removeItem(at:root) }
        let appURL = root.appendingPathComponent("Fixture.app"), registration = root.appendingPathComponent("Caskroom/fixture"), metadata = registration.appendingPathComponent("installed.json")
        try fm.createDirectory(at:appURL.appendingPathComponent("Contents/MacOS"),withIntermediateDirectories:true)
        let plist: [String:Any] = ["CFBundleIdentifier":"org.orbit.fixture","CFBundleExecutable":"fixture","CFBundlePackageType":"APPL","CFBundleShortVersionString":"1"]
        try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:appURL.appendingPathComponent("Contents/Info.plist"))
        try Data("fixture app contents".utf8).write(to:appURL.appendingPathComponent("Contents/MacOS/fixture"))
        try fm.createDirectory(at:registration,withIntermediateDirectories:true)
        let data = Data("fixture metadata".utf8); try data.write(to:metadata)
        let app = LocalApp(path:appURL.path,name:"Fixture",identifier:"org.orbit.fixture",version:"1",package:nil,identityMatched:true,inode:(try fm.attributesOfItem(atPath:appURL.path)[.systemFileNumber] as! NSNumber).uint64Value)
        let plan = CaskDetachPlan(token:"fixture",app:app,registration:registration,metadata:metadata,metadataData:data,registrationInode:(try fm.attributesOfItem(atPath:registration.path)[.systemFileNumber] as! NSNumber).uint64Value,quitIDs:[])
        let artifact: [String:Any] = ["tap":"homebrew/cask","artifacts":[["app":["Fixture.app"],"target":"/Applications/Fixture.app"],["zap":[["trash":["~/secret"]]]]]]
        let target = try CaskDetachPlan.appArtifact(artifact).0; precondition(target == "/Applications/Fixture.app")
        for extra in [["pkg":["installer.pkg"]],["binary":["cli"]],["postflight":[]],["uninstall":[["launchctl":"helper"]]]] as [[String:Any]] {
            var invalid = artifact; invalid["artifacts"] = (artifact["artifacts"] as! [[String:Any]]) + [extra]
            precondition((try? CaskDetachPlan.appArtifact(invalid)) == nil)
        }
        do { _ = try await CaskDetachTransaction.detach(plan,backupRoot:root.appendingPathComponent("Backups")) { throw RecorderProblem(message:"Injected launch failure") }; preconditionFailure("Failure must roll back") } catch {}
        precondition(plan.unchanged() && fm.fileExists(atPath:appURL.path), "Fixture app=\(app.unchanged) root=\(registration.resolvingSymlinksInPath()) expected=\(registration) metadata=\((try? Data(contentsOf:metadata)) == data)")
        let backup = try await CaskDetachTransaction.detach(plan,backupRoot:root.appendingPathComponent("Backups")) { precondition(!fm.fileExists(atPath:registration.path) && app.unchanged) }
        precondition(app.unchanged && fm.fileExists(atPath:backup.directory.appendingPathComponent("Application.app/Contents/MacOS/fixture").path))
        precondition(CaskDetachBackup.latest(in:root.appendingPathComponent("Backups"),prefix:root.path)?.id == backup.id, "Recovery must rediscover the retained registration")
        precondition(fm.fileExists(atPath:backup.directory.appendingPathComponent("registration-snapshot/installed.json").path))
        try backup.restore(); precondition(plan.unchanged())
        precondition(CaskDetachBackup.latest(in:root.appendingPathComponent("Backups"),prefix:root.path) == nil)
        do { try backup.restore(); preconditionFailure("Must not overwrite existing registration") } catch {}
        try Data("changed".utf8).write(to:metadata)
        do { _ = try await CaskDetachTransaction.detach(plan,backupRoot:root.appendingPathComponent("Backups")) {}; preconditionFailure("Stale metadata must block detach") } catch {}
    }
}
