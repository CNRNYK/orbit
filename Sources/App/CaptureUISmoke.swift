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
        let windowPicker = CaptureWindowScreenPicker()
        let windowFrames = [CaptureWindowCandidate(id:201,frame:CGRect(x:520,y:100,width:100,height:80)),CaptureWindowCandidate(id:202,frame:CGRect(x:100,y:100,width:100,height:80))]
        let windowCancelled = Task { await windowPicker.select(candidates:windowFrames,screens:geometry.map(\.appKitFrame)) { CaptureWindowHighlight.shared.show(frame:$0.frame,id:$0.id) } }
        await Task.yield(); precondition(windowPicker.overlayWindows.count == 2)
        let windowOverlays = windowPicker.overlayWindows
        let escape = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:windowOverlays[0].windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        (windowOverlays[0].contentView as! CaptureWindowSelectionView).keyDown(with:escape)
        let cancelledWindowValue = await windowCancelled.value
        precondition(cancelledWindowValue == nil && windowPicker.overlayWindows.isEmpty && windowOverlays.allSatisfy { !$0.isVisible })
        let pickedWindow = Task { await windowPicker.select(candidates:windowFrames,screens:geometry.map(\.appKitFrame)) { CaptureWindowHighlight.shared.show(frame:$0.frame,id:$0.id) } }
        await Task.yield(); windowPicker.hover(CGPoint(x:540,y:120)); windowPicker.click(CGPoint(x:540,y:120))
        let pickedWindowValue = await pickedWindow.value
        precondition(pickedWindowValue == 201 && windowPicker.overlayWindows.isEmpty)
        let changedWindow = Task { await windowPicker.select(candidates:windowFrames,screens:geometry.map(\.appKitFrame)) { _ in } }
        await Task.yield(); NotificationCenter.default.post(name:NSApplication.didChangeScreenParametersNotification,object:nil); await Task.yield(); await Task.yield()
        let changedWindowValue = await changedWindow.value
        precondition(changedWindowValue == nil && windowPicker.overlayWindows.isEmpty)
        let annotationState = AnnotationState(); annotationState.tool = "Select"
        annotationState.values = [OrbitAnnotation(tool:"Cover",points:[CGPoint(x:0.1,y:0.1),CGPoint(x:0.3,y:0.3)])]
        let annotationWindow = NSWindow(contentRect:CGRect(x:80,y:80,width:400,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
        let annotationCanvas = AnnotationCanvas(frame:CGRect(x:0,y:0,width:400,height:300)); annotationCanvas.state = annotationState; annotationCanvas.editingAllowed = true; annotationCanvas.values = annotationState.values; annotationWindow.contentView = annotationCanvas
        func annotationMouse(_ type:NSEvent.EventType,_ point:CGPoint) -> NSEvent { NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:annotationWindow.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)! }
        annotationCanvas.mouseDown(with:annotationMouse(.leftMouseDown,CGPoint(x:80,y:240)))
        annotationCanvas.mouseDragged(with:annotationMouse(.leftMouseDragged,CGPoint(x:120,y:210)))
        annotationCanvas.mouseUp(with:annotationMouse(.leftMouseUp,CGPoint(x:120,y:210)))
        precondition(annotationState.selected != nil && abs(annotationState.values[0].points[0].x-0.2)<0.0001)
        let delete = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:annotationWindow.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:51)!
        annotationCanvas.keyDown(with:delete); precondition(annotationState.values.isEmpty); annotationState.undo(); precondition(annotationState.values.count == 1)
        annotationWindow.orderOut(nil)
        let receiver = ShortcutRecordingView(); var combination: OrbitShortcut?
        receiver.received = { combination = $0 }
        let key = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.control,.option],timestamp:0,windowNumber:0,context:nil,characters:"c",charactersIgnoringModifiers:"c",isARepeat:false,keyCode:8)!
        precondition(receiver.performKeyEquivalent(with:key) && combination == OrbitShortcut(keyCode:8,modifiers:[.command,.control,.option]))
        print("PASS: native two-overlay Esc cleanup, arrangement cancellation, secondary synthetic drag window picking/hover/Esc/arrangement cleanup, native annotation dragging/deletion/undo and local shortcut recording; no user-screen capture or global registrations")
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
