import SwiftUI
import AppKit
import Darwin

struct CaskDetachPlan: Identifiable {
    let token: String
    let app: LocalApp
    let registration: URL
    let metadata: URL
    let metadataData: Data
    let registrationInode: UInt64
    let quitIDs: [String]
    var id: String { token }
    static func appArtifact(_ cask: [String:Any]) throws -> (String,[String]) {
        guard cask["tap"] as? String == "homebrew/cask", let artifacts = cask["artifacts"] as? [[String:Any]] else { throw RecorderProblem(message:"Cannot detach safely: only verified official cask metadata is supported.") }
        if let dependencies = cask["depends_on"] as? [String:Any], dependencies.keys.contains(where:{ $0 != "macos" }) { throw RecorderProblem(message:"Cannot detach safely: external package dependencies.") }
        if let caveats = cask["caveats"] as? String, !caveats.isEmpty { throw RecorderProblem(message:"Cannot detach safely: extra setup instructions require manual review.") }
        var apps = [String](), quit = [String]()
        for artifact in artifacts {
            if let values = artifact["app"] as? [Any] {
                guard Set(artifact.keys).isSubset(of:["app","target"]), values.count == 1, let name = values.first as? String, name.hasSuffix(".app"), URL(fileURLWithPath:name).lastPathComponent == name, let target = artifact["target"] as? String, target == "/Applications/" + name else { throw RecorderProblem(message:"Cannot detach safely: nonstandard app destination.") }; apps.append(target)
            } else if artifact.keys.count == 1, artifact["zap"] != nil { continue } // Never executed.
            else if artifact.keys.count == 1, let values = artifact["uninstall"] as? [[String:Any]], values.count == 1, Set(values[0].keys) == ["quit"] {
                if let id = values[0]["quit"] as? String { quit.append(id) } else if let ids = values[0]["quit"] as? [String] { quit += ids } else { throw RecorderProblem(message:"Cannot detach safely: invalid quit metadata.") }
            } else { throw RecorderProblem(message:"Cannot detach safely: installer, helper, service, extra component or hook.") }
        }
        guard apps.count == 1 else { throw RecorderProblem(message:"Cannot detach safely: exactly one app bundle is required.") }; return (apps[0],quit)
    }
    static func inspect(token: String, prefix: String, apps: [LocalApp]) throws -> Self {
        guard token.range(of:#"^[a-z0-9][a-z0-9@+._-]*$"#,options:.regularExpression) != nil, !token.contains("..") else { throw RecorderProblem(message:"Invalid cask token.") }
        let root = URL(fileURLWithPath:prefix).appendingPathComponent("Caskroom/" + token)
        guard root.resolvingSymlinksInPath().path == root.path, let inode = (try FileManager.default.attributesOfItem(atPath:root.path)[.systemFileNumber] as? NSNumber)?.uint64Value else { throw RecorderProblem(message:"Cannot detach safely: registration path is unavailable or linked.") }
        let metaRoot = root.appendingPathComponent(".metadata")
        guard let enumerator = FileManager.default.enumerator(at:metaRoot,includingPropertiesForKeys:nil) else { throw RecorderProblem(message:"Cannot detach safely: installed metadata unavailable.") }
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.lastPathComponent == token + ".json" && $0.deletingLastPathComponent().lastPathComponent == "Casks" }.sorted { $0.path < $1.path }
        guard files.count == 1, let file = files.first, file.resolvingSymlinksInPath().path == file.path else { throw RecorderProblem(message:"Cannot detach safely: ambiguous or legacy installed metadata.") }
        let data = try Data(contentsOf:file)
        guard let cask = try JSONSerialization.jsonObject(with:data) as? [String:Any], cask["token"] as? String == token else { throw RecorderProblem(message:"Cannot detach safely: installed metadata does not match.") }
        let (target,quit) = try appArtifact(cask)
        guard let app = apps.first(where:{ $0.path == target }), app.unchanged, let bundle = Bundle(path:app.path), bundle.executableURL.map({ FileManager.default.isExecutableFile(atPath:$0.path) }) == true else { throw RecorderProblem(message:"Cannot detach safely: installed app identity cannot be verified.") }
        for name in ["SystemExtensions","LaunchServices","LaunchAgents","LaunchDaemons","LoginItems","PrivilegedHelperTools"] where FileManager.default.fileExists(atPath:app.path + "/Contents/Library/" + name) { throw RecorderProblem(message:"Cannot detach safely: embedded background components.") }
        guard bundle.object(forInfoDictionaryKey:"SMPrivilegedExecutables") == nil, (bundle.object(forInfoDictionaryKey:"LSBackgroundOnly") as? Bool) != true else { throw RecorderProblem(message:"Cannot detach safely: background or privileged application.") }
        return Self(token:token,app:app,registration:root,metadata:file,metadataData:data,registrationInode:inode,quitIDs:quit)
    }
    func unchanged() -> Bool { app.unchanged && registration.resolvingSymlinksInPath().path == registration.path && (try? Data(contentsOf:metadata)) == metadataData && (try? FileManager.default.attributesOfItem(atPath:registration.path)[.systemFileNumber] as? NSNumber)?.uint64Value == registrationInode }
}
final class CaskDetachLock {
    private let fd: Int32
    init(prefix: String,token: String) throws {
        let path = prefix + "/var/homebrew/locks/" + token + ".cask.lock"
        let descriptor = open(path,O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,0o644)
        guard descriptor >= 0 else { throw RecorderProblem(message:"Homebrew lock could not be opened.") }
        guard flock(descriptor,LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw RecorderProblem(message:"Homebrew is using this cask. Try again later.") }
        var opened = stat(), current = stat()
        guard fstat(descriptor,&opened) == 0, lstat(path,&current) == 0, opened.st_ino == current.st_ino else { flock(descriptor,LOCK_UN); close(descriptor); throw RecorderProblem(message:"Homebrew lock changed. Try again.") }
        fd = descriptor
    }
    deinit { flock(fd,LOCK_UN); close(fd) }
}
struct CaskDetachBackup: Identifiable {
    let directory: URL
    let registration: URL
    var id: String { directory.path }
    var storedRegistration: URL { directory.appendingPathComponent("registration") }
    static func latest(in root: URL, prefix: String) -> Self? {
        let fm = FileManager.default
        let directories = (try? fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.creationDateKey])) ?? []
        return directories.sorted { ((try? $0.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) }.compactMap { entry in
            let directory = entry.resolvingSymlinksInPath()
            guard (try? entry.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == false, directory.deletingLastPathComponent().resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path, UUID(uuidString:directory.lastPathComponent) != nil,
                  let data = try? Data(contentsOf:directory.appendingPathComponent("manifest.json")), let manifest = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let token = manifest["token"] as? String,
                  token.range(of:#"^[a-z0-9][a-z0-9@+._-]*$"#,options:.regularExpression) != nil, !token.contains(".."), let path = manifest["registration"] as? String, path == prefix + "/Caskroom/" + token else { return nil }
            let backup = Self(directory:directory,registration:URL(fileURLWithPath:path))
            return fm.fileExists(atPath:backup.storedRegistration.path) || (!fm.fileExists(atPath:backup.registration.path) && fm.fileExists(atPath:directory.appendingPathComponent("registration-snapshot").path)) ? backup : nil
        }.first
    }
    func restore() throws {
        let source = FileManager.default.fileExists(atPath:storedRegistration.path) ? storedRegistration : directory.appendingPathComponent("registration-snapshot")
        guard !FileManager.default.fileExists(atPath:registration.path), source.resolvingSymlinksInPath().path == source.path, FileManager.default.fileExists(atPath:source.path) else { throw RecorderProblem(message:"Registration changed or was recreated. Restore cannot overwrite it.") }
        let data = try Data(contentsOf:directory.appendingPathComponent("manifest.json"))
        guard let manifest = try JSONSerialization.jsonObject(with:data) as? [String:Any], let app = manifest["app"] as? String,
              URL(fileURLWithPath:app).resolvingSymlinksInPath().path == app,
              let currentInfo = try? Data(contentsOf:URL(fileURLWithPath:app).appendingPathComponent("Contents/Info.plist")), let backupInfo = try? Data(contentsOf:directory.appendingPathComponent("Application.app/Contents/Info.plist")), currentInfo == backupInfo else { throw RecorderProblem(message:"The app changed since backup. Review the backup manually; registration was not restored.") }
        try FileManager.default.moveItem(at:source,to:registration)
    }
}
enum CaskDetachTransaction {
    static func detach(_ plan: CaskDetachPlan, backupRoot: URL, verify: () async throws -> Void) async throws -> CaskDetachBackup {
        guard plan.unchanged() else { throw RecorderProblem(message:"The app or registration changed. Review again.") }
        let directory = backupRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let backup = CaskDetachBackup(directory:directory,registration:plan.registration)
        // Copy the app first; its original path, data and permissions are never changed.
        try FileManager.default.copyItem(at:URL(fileURLWithPath:plan.app.path),to:directory.appendingPathComponent("Application.app"))
        let manifest: [String:Any] = ["token":plan.token,"app":plan.app.path,"identifier":plan.app.identifier,"registration":plan.registration.path,"created":ISO8601DateFormatter().string(from:Date())]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("manifest.json"),options:.withoutOverwriting)
        try FileManager.default.copyItem(at:plan.registration,to:directory.appendingPathComponent("registration-snapshot"))
        let originalDevice = try FileManager.default.attributesOfItem(atPath:plan.registration.path)[.systemNumber] as? NSNumber
        let backupDevice = try FileManager.default.attributesOfItem(atPath:directory.path)[.systemNumber] as? NSNumber
        guard originalDevice != nil, originalDevice == backupDevice else { throw RecorderProblem(message:"Backup and registration must be on the same filesystem for atomic detach. Nothing was detached.") }
        guard plan.unchanged() else { throw RecorderProblem(message:"The app changed while backing up. Nothing was detached.") }
        try FileManager.default.moveItem(at:plan.registration,to:backup.storedRegistration)
        do { guard plan.app.unchanged, !FileManager.default.fileExists(atPath:plan.registration.path) else { throw RecorderProblem(message:"Detach verification failed.") }; try await verify(); return backup }
        catch {
            do { try backup.restore() } catch { throw RecorderProblem(message:"Rollback could not restore registration. Recoverable backup: " + directory.path + ". " + error.localizedDescription) }
            throw RecorderProblem(message:"Detach failed; Homebrew registration was restored. " + error.localizedDescription)
        }
    }
}
@MainActor final class CaskDetachState: ObservableObject {
    @Published var plan: CaskDetachPlan?
    @Published var working = false
    @Published var unsupported = [String:String]()
    @Published var backup: CaskDetachBackup?
}
@MainActor extension Store {
    func reviewDetach(_ package: Package) async {
        guard !preview, !locked, package.cask, installed.contains(package.id), let brew else { return }
        preparing = true; defer { preparing = false }
        do {
            let prefix = URL(fileURLWithPath:brew).deletingLastPathComponent().deletingLastPathComponent().path
            detachState.plan = try await Task.detached { try CaskDetachPlan.inspect(token:package.token,prefix:prefix,apps:AppScanner.scan()) }.value
        } catch { detachState.unsupported[package.id] = error.localizedDescription; notice = error.localizedDescription }
    }
    func detachApp() async {
        guard !preview, !locked, let plan = detachState.plan, let brew else { return }
        detachState.working = true; defer { detachState.working = false }
        do {
            guard !NSWorkspace.shared.runningApplications.contains(where:{ $0.bundleURL?.path == plan.app.path || plan.quitIDs.contains($0.bundleIdentifier ?? "") }) else { throw RecorderProblem(message:"Quit the app and its background processes before detaching.") }
            let prefix = URL(fileURLWithPath:brew).deletingLastPathComponent().deletingLastPathComponent().path
            let lock = try CaskDetachLock(prefix:prefix,token:plan.token)
            defer { withExtendedLifetime(lock) {} }
            let backupRoot = URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/Orbit/Homebrew Backups")
            detachState.backup = try await CaskDetachTransaction.detach(plan,backupRoot:backupRoot) {
                let result = await self.runJSONCommand(brew,["list","--cask"])
                guard result.0 == 0, !result.1.split(whereSeparator:\.isNewline).contains(Substring(plan.token)) else { throw RecorderProblem(message:"Homebrew still reports the cask, or verification failed.") }
                let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
                let app = try await NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:plan.app.path),configuration:configuration)
                guard app.bundleIdentifier == plan.app.identifier, plan.app.unchanged else { throw RecorderProblem(message:"App launch identity verification failed.") }
            }
            detachState.plan = nil; appendLog("Stopped Homebrew management for " + plan.app.name + ". Backup: " + detachState.backup!.directory.path + "\n")
            notice = "The app remains installed. Homebrew management stopped; recoverable backup saved."
        } catch { notice = error.localizedDescription }
        await refresh()
    }
    func restoreDetach() async {
        guard !preview, !locked, let backup = detachState.backup, let brew else { return }
        detachState.working = true; defer { detachState.working = false }
        do { guard let data = try? Data(contentsOf:backup.directory.appendingPathComponent("manifest.json")), let manifest = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let path = manifest["app"] as? String, !NSWorkspace.shared.runningApplications.contains(where:{ $0.bundleURL?.path == path }) else { throw RecorderProblem(message:"Quit the app before restoring management.") }; let prefix = URL(fileURLWithPath:brew).deletingLastPathComponent().deletingLastPathComponent().path; let lock = try CaskDetachLock(prefix:prefix,token:backup.registration.lastPathComponent); defer { withExtendedLifetime(lock) {} }; try backup.restore(); detachState.backup = nil; await refresh() } catch { notice = error.localizedDescription }
    }
}
