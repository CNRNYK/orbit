import AppKit
import SwiftUI

// Native fixture-only tests: no ScreenCaptureKit requests or real hotkey registrations.
@MainActor enum CaptureUISmoke {
    static func run() async {
        let picker = RecorderRegionPicker()
        let geometry = [
            CaptureDisplayGeometry(id:101,appKitFrame:CGRect(x:80,y:80,width:400,height:300),captureFrame:CGRect(x:0,y:0,width:400,height:300),scale:2),
            CaptureDisplayGeometry(id:102,appKitFrame:CGRect(x:500,y:80,width:400,height:300),captureFrame:CGRect(x:400,y:0,width:400,height:300),scale:1)
        ]
        let cancelled = Task { await picker.select(displays:geometry,preferred:101,within:nil,label:"Orbit synthetic selection test") }
        await Task.yield()
        precondition(picker.overlayWindows.count == 2)
        let windows = picker.overlayWindows
        let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:windows[1].windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        (windows[1].contentView as! RecorderSelectionCanvas).keyDown(with:event)
        let cancelledValue = await cancelled.value
        precondition(cancelledValue == nil && picker.overlayWindows.isEmpty && windows.allSatisfy { !$0.isVisible })
        let disconnected = Task { await picker.select(displays:geometry,preferred:101,within:nil,label:"Orbit synthetic arrangement test") }
        await Task.yield(); precondition(picker.overlayWindows.count == 2)
        NotificationCenter.default.post(name:NSApplication.didChangeScreenParametersNotification,object:nil)
        await Task.yield(); await Task.yield()
        let disconnectedValue = await disconnected.value
        precondition(disconnectedValue == nil && picker.overlayWindows.isEmpty)
        let selected = Task { await picker.select(displays:geometry,preferred:101,within:nil,label:"Orbit synthetic drag test") }
        await Task.yield()
        let canvas = picker.overlayWindows[1].contentView as! RecorderSelectionCanvas
        canvas.hover?(true); precondition(canvas.highlighted)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent { NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:canvas.window!.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)! }
        canvas.mouseDown(with:mouse(.leftMouseDown,CGPoint(x:20,y:280)))
        canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:120,y:180)))
        canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:120,y:180)))
        let selection = await selected.value
        precondition(selection?.displayID == 102 && selection?.rect == CGRect(x:420,y:20,width:100,height:100) && picker.overlayWindows.isEmpty)
        let receiver = ShortcutRecordingView(); var combination: OrbitShortcut?
        receiver.received = { combination = $0 }
        let key = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.control,.option],timestamp:0,windowNumber:0,context:nil,characters:"c",charactersIgnoringModifiers:"c",isARepeat:false,keyCode:8)!
        precondition(receiver.performKeyEquivalent(with:key) && combination == OrbitShortcut(keyCode:8,modifiers:[.command,.control,.option]))
        print("PASS: native two-overlay Esc cleanup, arrangement cancellation, secondary synthetic drag and local shortcut recording; no user-screen capture or global registrations")
    }
}

@MainActor final class FakeSmokeShortcutRegistrar: ShortcutRegistering {
    var event: ((OrbitShortcutAction,Bool) -> Void)?
    var next: UInt32 = 1, closed = false
    func register(_ shortcut: OrbitShortcut, action: OrbitShortcutAction) throws -> UInt32 { defer { next += 1 }; return next }
    func unregister(_ token: UInt32) {}
    func reassign(_ token: UInt32, to action: OrbitShortcutAction) {}
    func shutdown() { closed = true; event = nil }
}
