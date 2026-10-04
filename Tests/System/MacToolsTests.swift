import Foundation
import AppKit
import CoreImage
@MainActor enum MacToolsTests {
    static func run() async throws {
        precondition(LoginScripts.literal("a\"; $('secret')\n") == "\"a\\\"; $('secret')\\n\"")
        let items = try LoginScripts.parse("[{\"name\":\"App\",\"path\":\"/Applications/App.app\",\"hidden\":false}]")
        precondition(items.count == 1 && LoginScripts.remove(items[0]).contains("matches.length!==1"))
        let source = CIImage(color:CIColor(red:1,green:1,blue:1)).cropped(to:CGRect(x:0,y:0,width:320,height:180))
        let arrow = OrbitAnnotation(tool:"Arrow",points:[CGPoint(x:0.1,y:0.1),CGPoint(x:0.8,y:0.8)])
        let cover = OrbitAnnotation(tool:"Cover",points:[CGPoint(x:0.4,y:0.3),CGPoint(x:0.6,y:0.7)])
        let edited = AnnotationRenderer.render(source,values:[arrow,cover])
        let pixels = RecorderTests.rgba(edited,size:source.extent.size)
        precondition(pixels[(90*320+160)*4] == 0 && pixels[(10*320+300)*4] > 240, "Redaction must cover only its selected pixels")
        guard let image = CIContext().createCGImage(edited,from:edited.extent) else { preconditionFailure("Screenshot output must render") }
        let png = try ScreenshotState.png(image)
        precondition(NSBitmapImageRep(data:png)?.pixelsWide == 320, "Screenshot output must be a decodable PNG")
        var options = RecorderOptions(); options.halo = false; options.clicks = false
        let buffer = AnnotationBuffer(); buffer.replace([arrow]); let compositor = RecorderCompositor(options:options); compositor.annotations = buffer
        let annotated = compositor.image(source,frame:source.extent,size:source.extent.size,pointer:RecorderPointer(),camera:nil,now:0)
        precondition(RecorderTests.rgba(annotated,size:source.extent.size) != RecorderTests.rgba(source,size:source.extent.size), "Annotations must reach encoded video frames")
        buffer.replace([]); let clear = compositor.image(source,frame:source.extent,size:source.extent.size,pointer:RecorderPointer(),camera:nil,now:0)
        precondition(RecorderTests.rgba(clear,size:source.extent.size) == RecorderTests.rgba(source,size:source.extent.size), "Undo/clear must invalidate cached annotation pixels")
        let border = RecordingOverlay.appKitFrame(CGRect(x:-1280,y:200,width:1280,height:720),primaryTop:1080)
        precondition(border == CGRect(x:-1280,y:160,width:1280,height:720))
        let store = Store(preview:true,persistSelection:false)
        for mode in [ActionMode.permissions,.health,.login,.screenshots] { store.navigate(mode); precondition(store.mode == mode) }
        store.screenshots.working = true; precondition(store.locked && !store.recorderState.canBegin() && MenuBarState(store:store).status == "Preparing screenshot…"); store.screenshots.working = false
        store.permissions.working = true; precondition(store.locked); store.permissions.working = false
        precondition(PermissionState.mediaStatus(.authorized) == "Allowed" && PermissionState.mediaStatus(.denied) == "Denied")
        let health = HealthState()
        let commands = FakeCommands([(0,"Homebrew fixture"),(1,"missing dependency"),(1,"doctor warning"),(0,"figma\n")])
        await health.scan(brew:"/fixture/brew",commands:commands,appExists:{ _ in false })
        let calls = await commands.recorded()
        precondition(calls == [["--version"],["missing"],["doctor"],["list","--cask","-1"]], "Health must use only diagnostic commands")
        precondition(health.findings.contains { $0.id == "dependencies" && !$0.healthy })
        precondition(health.findings.contains { $0.id == "apps" && !$0.healthy && $0.detail.contains("custom app directory") })
        let login = LoginState()
        let removal = FakeCommands([(0,""),(0,"[]")])
        await login.change(items[0],add:false,commands:removal)
        let loginCalls = await removal.recorded()
        precondition(loginCalls.count == 2 && loginCalls[0] == ["-l","JavaScript","-e",LoginScripts.remove(items[0])] && login.entries.isEmpty)
        login.canAct = { false }; await login.change(items[0],add:false,commands:removal)
        let guarded = await removal.recorded(); precondition(guarded.count == 2)
        let automatic = LoginState(); var asked = [Bool](); automatic.automationAccess = { ask in asked.append(ask); return noErr }
        let list = FakeCommands([(0,"[]")]); await automatic.loadOnOpen(commands:list)
        let listCalls = await list.recorded(); precondition(asked == [false] && listCalls.count == 1)
        automatic.automationAccess = { ask in asked.append(ask); return -1743 }
        await automatic.loadOnOpen(commands:list); let deniedCalls = await list.recorded(); precondition(deniedCalls.count == 1 && automatic.message.contains("Allow"))
        automatic.preview = true; await automatic.authorizeAndLoad(commands:list); precondition(asked == [false,false])
        precondition(LoginState.applicationDirectory(home:"/fixture",exists:{ _ in false }).path == "/fixture/Applications")
        precondition(LoginState.applicationDirectory(exists:{ _ in true }).path == "/Applications")
        print("PASS: permission status semantics, login script injection protection/identity checks, screenshot redaction/PNG, baked video annotations/cache clearing, border coordinates and shared operation guards")
    }
}
