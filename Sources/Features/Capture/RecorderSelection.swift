import AppKit
import SwiftUI

// Capture coordinates are top-left based points; overlay coordinates use a flipped
// local AppKit view. Never multiply sourceRect by backingScaleFactor.
struct CaptureDisplayGeometry: Equatable {
    let id: UInt32
    let appKitFrame: CGRect
    let captureFrame: CGRect
    let scale: CGFloat
    var localBounds: CGRect { CGRect(origin:.zero,size:appKitFrame.size) }
    func captureRect(_ local: CGRect) -> CGRect {
        let sx = captureFrame.width / appKitFrame.width, sy = captureFrame.height / appKitFrame.height
        return CGRect(x:captureFrame.minX+local.minX*sx,y:captureFrame.minY+local.minY*sy,width:local.width*sx,height:local.height*sy)
    }
    func localRect(_ capture: CGRect) -> CGRect {
        let sx = appKitFrame.width / captureFrame.width, sy = appKitFrame.height / captureFrame.height
        return CGRect(x:(capture.minX-captureFrame.minX)*sx,y:(capture.minY-captureFrame.minY)*sy,width:capture.width*sx,height:capture.height*sy)
    }
    static func current() -> [Self] {
        NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return Self(id:id,appKitFrame:screen.frame,captureFrame:CGDisplayBounds(id),scale:screen.backingScaleFactor)
        }
    }
}
struct CaptureAreaSelection: Equatable {
    let display: CaptureDisplayGeometry
    let rect: CGRect
    var displayID: UInt32 { display.id }
    func sourceRect(in current: [CaptureDisplayGeometry], availableIDs: [UInt32]) throws -> CGRect {
        guard availableIDs.contains(displayID), current.contains(display), display.captureFrame.contains(rect), rect.width >= 8, rect.height >= 8 else {
            throw RecorderProblem(message:"The selected display or its arrangement changed. Select an area again.")
        }
        return CGRect(x:rect.minX-display.captureFrame.minX,y:rect.minY-display.captureFrame.minY,width:rect.width,height:rect.height)
    }
}
// Both capture paths resolve the filter identity and crop from this same request.
struct CaptureDisplayRequest: Equatable {
    let displayID: UInt32
    let sourceRect: CGRect?
    init(displayID: UInt32, selection: CaptureAreaSelection?, areaMode: Bool, current: [CaptureDisplayGeometry], availableIDs: [UInt32]) throws {
        guard availableIDs.contains(displayID), current.contains(where:{ $0.id == displayID }) else { throw RecorderProblem(message:"The selected display is disconnected. Choose another display.") }
        self.displayID = displayID
        if areaMode {
            guard let selection, selection.displayID == displayID else { throw RecorderProblem(message:"Select a capture area again.") }
            sourceRect = try selection.sourceRect(in:current,availableIDs:availableIDs)
        } else { sourceRect = nil }
    }
}
struct CaptureSelectionSession {
    var displays: [CaptureDisplayGeometry]
    private(set) var highlighted: UInt32?
    private(set) var dragging: UInt32?
    mutating func hover(_ id: UInt32?) { if dragging == nil { highlighted = id } }
    mutating func begin(_ id: UInt32) -> Bool { guard dragging == nil, displays.contains(where: { $0.id == id }) else { return false }; dragging = id; highlighted = id; return true }
    mutating func retry() { dragging = nil }
    mutating func cancel() { displays = []; highlighted = nil; dragging = nil }
    func selection(displayID: UInt32, local: CGRect) -> CaptureAreaSelection? {
        guard dragging == displayID, let display = displays.first(where: { $0.id == displayID }) else { return nil }
        let clipped = local.intersection(display.localBounds)
        guard clipped.width >= 8, clipped.height >= 8 else { return nil }
        return CaptureAreaSelection(display:display,rect:display.captureRect(clipped))
    }
}
final class RecorderSelectionWindow: NSWindow { override var canBecomeKey: Bool { true } }
final class RecorderSelectionCanvas: NSView {
    let allowed: CGRect, label: String
    var origin: CGPoint?, selection = CGRect.zero
    var scale: CGFloat = 1
    var review = false
    private var reviewing = false
    private var resizeCorner: CGPoint?
    private var confirmFrame: CGRect {
        CGRect(x:min(max(selection.maxX-120,allowed.minX),max(allowed.minX,allowed.maxX-120)),
               y:selection.maxY+36 <= allowed.maxY ? selection.maxY+4 : max(allowed.minY,selection.minY-36),
               width:120,height:30)
    }
    private var corners: [CGPoint] {
        [CGPoint(x:selection.minX,y:selection.minY),CGPoint(x:selection.maxX,y:selection.minY),
         CGPoint(x:selection.minX,y:selection.maxY),CGPoint(x:selection.maxX,y:selection.maxY)]
    }
    var highlighted = false { didSet { needsDisplay = true } }
    var begin: (() -> Bool)?, hover: ((Bool) -> Void)?, retry: (() -> Void)?
    var complete: ((CGRect?) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, allowed: CGRect, label: String) { self.allowed = allowed; self.label = label; super.init(frame:frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.mouseMoved,.activeAlways,.inVisibleRect],owner:self,userInfo:nil))
    }
    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseMoved(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.42).setFill(); bounds.fill()
        (highlighted ? NSColor.systemBlue : NSColor.white.withAlphaComponent(0.4)).setStroke()
        let limit = NSBezierPath(rect:allowed.insetBy(dx:2,dy:2)); limit.lineWidth = highlighted ? 4 : 1; limit.stroke()
        if selection.width > 0 {
            NSColor.clear.setFill(); selection.fill(using:.copy)
            NSColor.systemBlue.setStroke(); let border = NSBezierPath(rect:selection); border.lineWidth = 2; border.stroke()
            NSColor.white.setFill()
            for point in corners { NSBezierPath(roundedRect:CGRect(x:point.x-4,y:point.y-4,width:8,height:8),xRadius:2,yRadius:2).fill() }
            let dimensions = "\(Int(selection.width)) × \(Int(selection.height)) pt · \(Int(selection.width*scale)) × \(Int(selection.height*scale)) px"
            dimensions.draw(at:CGPoint(x:max(allowed.minX+8,selection.minX),y:max(allowed.minY+42,selection.minY-23)),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:12,weight:.semibold),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black.withAlphaComponent(0.8)])
            if reviewing {
                NSColor.systemBlue.setFill()
                NSBezierPath(roundedRect:confirmFrame,xRadius:8,yRadius:8).fill()
                "Use area ↵".draw(at:CGPoint(x:confirmFrame.minX+19,y:confirmFrame.minY+7),withAttributes:[.font:NSFont.systemFont(ofSize:13,weight:.semibold),.foregroundColor:NSColor.white])
            }
        }
        let text = label + (reviewing ? " · Drag corners to resize · Return to confirm · Esc to cancel" : " · Drag on this display · Esc to cancel")
        text.draw(at:NSPoint(x:max(allowed.minX+18,18),y:max(allowed.minY+18,18)),withAttributes:[.font:NSFont.systemFont(ofSize:17,weight:.semibold),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black.withAlphaComponent(0.65)])
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow,from:nil)
        if reviewing {
            if confirmFrame.contains(p) { complete?(selection); return }
            if let corner = corners.firstIndex(where:{ hypot($0.x-p.x,$0.y-p.y) <= 12 }) {
                origin = corners[3-corner]; resizeCorner = corners[corner]
            }
            return
        }
        guard allowed.contains(p), begin?() != false else { return }
        origin = p; selection = .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin else { return }; let point = convert(event.locationInWindow,from:nil)
        let p = CGPoint(x:min(max(point.x,allowed.minX),allowed.maxX),y:min(max(point.y,allowed.minY),allowed.maxY))
        let next = CGRect(x:min(origin.x,p.x),y:min(origin.y,p.y),width:abs(p.x-origin.x),height:abs(p.y-origin.y))
        if resizeCorner == nil || (next.width >= 8 && next.height >= 8) { selection = next }; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { guard origin != nil else { return }; mouseDragged(with:event); guard selection.width >= 8, selection.height >= 8 else { origin = nil; selection = .zero; retry?(); needsDisplay = true; return }; origin = nil; resizeCorner = nil; if review { reviewing = true; needsDisplay = true } else { complete?(selection) } }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { complete?(nil) } else if event.keyCode == 36, reviewing { complete?(selection) } else { super.keyDown(with:event) } }
}
@MainActor final class RecorderRegionPicker {
    private var windows = [NSWindow](), canvases = [UInt32:RecorderSelectionCanvas]()
    private var continuation: CheckedContinuation<CaptureAreaSelection?,Never>?
    private var session = CaptureSelectionSession(displays:[])
    private var topologyObserver: NSObjectProtocol?
    func selectArea(displayIDs: [UInt32], preferredDisplayID: UInt32) async -> CaptureAreaSelection? {
        await select(displays:CaptureDisplayGeometry.current().filter { displayIDs.contains($0.id) },preferred:preferredDisplayID,within:nil,label:"Select capture area",review:true)
    }
    func select(displayID: CGDirectDisplayID, within source: CGRect? = nil, label: String = "Select recording area") async -> CGRect? {
        await select(displays:CaptureDisplayGeometry.current().filter { $0.id == displayID },preferred:displayID,within:source,label:label)?.rect
    }
    func select(displays: [CaptureDisplayGeometry], preferred: UInt32, within source: CGRect?, label: String, review: Bool = false) async -> CaptureAreaSelection? {
        cancel(); guard !displays.isEmpty else { return nil }; session = CaptureSelectionSession(displays:displays)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            topologyObserver = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.cancel() } }
            for display in displays {
                let allowed = source.map { display.localRect($0).intersection(display.localBounds) } ?? display.localBounds
                guard !allowed.isNull, !allowed.isEmpty else { continue }
                let window = RecorderSelectionWindow(contentRect:display.appKitFrame,styleMask:.borderless,backing:.buffered,defer:false)
                window.isOpaque = false; window.backgroundColor = .clear; window.level = .screenSaver; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; window.isReleasedWhenClosed = false; window.acceptsMouseMovedEvents = true
                let canvas = RecorderSelectionCanvas(frame:display.localBounds,allowed:allowed,label:label)
                canvas.scale = display.scale; canvas.review = review
                canvas.begin = { [weak self] in self?.session.begin(display.id) ?? false }
                canvas.retry = { [weak self] in self?.session.retry() }
                canvas.hover = { [weak self, weak window, weak canvas] inside in
                    guard let self else { return }; if inside { self.session.hover(display.id) } else if self.session.highlighted == display.id { self.session.hover(nil) }
                    self.updateHighlight(); if inside, self.session.dragging == nil { window?.makeKey(); window?.makeFirstResponder(canvas) }
                }
                canvas.complete = { [weak self] rect in guard let self else { return }; self.complete(rect.flatMap { self.session.selection(displayID:display.id,local:$0) }) }
                window.contentView = canvas; windows.append(window); canvases[display.id] = canvas; window.orderFrontRegardless()
            }
            guard !windows.isEmpty else { complete(nil); return }
            let pointer = NSEvent.mouseLocation
            session.hover(displays.first { $0.appKitFrame.contains(pointer) }?.id ?? preferred); updateHighlight()
            NSApp.activate(ignoringOtherApps:true)
            let index = displays.firstIndex { $0.id == session.highlighted } ?? 0
            let key = windows[min(index,windows.count-1)]; key.makeKeyAndOrderFront(nil); key.makeFirstResponder(key.contentView)
        }
    }
    var overlayWindows: [NSWindow] { windows }
    private func updateHighlight() { for (id,canvas) in canvases { canvas.highlighted = session.highlighted == id } }
    private func complete(_ result: CaptureAreaSelection?) {
        windows.forEach { $0.orderOut(nil); $0.close() }; windows.removeAll(); canvases.removeAll(); session.cancel()
        if let topologyObserver { NotificationCenter.default.removeObserver(topologyObserver) }; topologyObserver = nil
        let pending = continuation; continuation = nil; pending?.resume(returning:result)
    }
    func cancel() { complete(nil) }
}

enum CaptureHUDPlacement {
    static func frame(size: CGSize, selection: CGRect?, visible: CGRect) -> CGRect {
        let width = min(size.width,visible.width), height = min(size.height,visible.height)
        let gap: CGFloat = 8
        let center = selection?.midX ?? visible.midX
        let x = min(max(center-width/2,visible.minX),visible.maxX-width)
        guard let selection else { return CGRect(x:x,y:visible.minY+min(gap,visible.height-height),width:width,height:height) }
        let below = selection.minY-gap-height
        let above = selection.maxY+gap
        let y: CGFloat
        if below >= visible.minY { y = below }
        else if above+height <= visible.maxY { y = above }
        else {
            let lowerRoom = selection.minY-visible.minY
            let upperRoom = visible.maxY-selection.maxY
            y = lowerRoom >= upperRoom ? below : above
        }
        return CGRect(x:x,y:min(max(y,visible.minY),visible.maxY-height),width:width,height:height)
    }
}

struct RecorderHUD: View {
    @ObservedObject var state: RecorderState
    @ObservedObject var annotations: AnnotationState
    init(state:RecorderState) { self.state = state; annotations = state.annotations }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if state.phase == .idle { HStack {
                Label("Orbit Recorder",systemImage:"record.circle").font(.subheadline.bold())
                Spacer()
                if state.phase == .idle {
                    Button { state.dockCollapsed.toggle() } label: { Image(systemName:state.dockCollapsed ? "chevron.left" : "chevron.right") }.buttonStyle(.borderless).help(state.dockCollapsed ? "Expand capture dock" : "Collapse capture dock")
                }
                if state.phase == .idle { Button { state.closeControls() } label: { Image(systemName:"xmark") }.buttonStyle(.borderless).help("Close recording controls") }
            }
            }
            if state.phase == .idle && state.dockCollapsed {
                HStack {
                    if let screenshot = state.onScreenshotControls { Button("Screenshot",systemImage:"camera",action:screenshot).labelStyle(.iconOnly) }
                    Button("Record",systemImage:"record.circle") { state.start(compact:true) }.labelStyle(.iconOnly).disabled(!state.canBegin())
                }
            } else if state.phase == .idle {
                Picker("",selection:$state.options.mode) { Text("Full screen").tag("Full screen"); Text("Area").tag("Selected area"); Text("Window").tag("Window") }.pickerStyle(.segmented).labelsHidden().onChange(of:state.options.mode) { _,_ in state.modeChanged() }
                if state.options.mode == "Window" {
                    HStack {
                        CaptureWindowMenu(state:state,startAfterSelection:true)
                        Button("Refresh") { Task { await state.loadSources() } }.disabled(state.busy)
                    }
                } else if !state.displays.isEmpty {
                    Picker("Display",selection:Binding(get:{ state.displayID },set:{ state.displayID = $0; state.modeChanged() })) { ForEach(state.displays,id:\.displayID) { display in Text("Display · \(display.width) × \(display.height)").tag(display.displayID) } }
                }
                HStack {
                    Toggle("Mic",isOn:$state.options.microphone)
                    Toggle("System",isOn:$state.options.systemAudio)
                    Toggle("Camera",isOn:$state.options.webcam)
                    if let settings = state.onCaptureSettings { Button("Settings",systemImage:"gearshape",action:settings).labelStyle(.iconOnly).help("Capture settings") }
                }.disabled(state.busy)
                Button(state.presenting ? "End presentation" : "Present without recording") { state.togglePresentation() }.disabled(state.captureFrame == nil)
                if state.presenting {
                    Toggle("Draw on screen",isOn:$annotations.drawing)
                    if annotations.drawing { AnnotationToolbar(state:annotations) }
                }
                Text(state.outputEstimate).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text("Saves to " + state.outputFolder.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                HStack {
                    if let screenshot = state.onScreenshotControls { Button("Screenshot",systemImage:"camera",action:screenshot).labelStyle(.iconOnly).help("Take screenshot") }
                    Button(state.startLabel,systemImage:"record.circle") { state.start(compact:true) }.buttonStyle(.borderedProminent).tint(.red).disabled(state.busy || !state.canBegin())
                    Spacer()
                    if let url = state.recordingURL { Button("Show last recording") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                }
            } else {
                HStack(spacing:12) {
                    Circle().fill(state.phase == .paused ? .orange : .red).frame(width:8,height:8)
                    Text(state.phase == .countdown ? "Starting in \(state.countdown)…" : state.elapsedLabel).font(.system(.body,design:.monospaced).bold())
                    Spacer()
                    if state.phase == .recording || state.phase == .paused { Button(state.phase == .paused ? "Resume" : "Pause",systemImage:state.phase == .paused ? "play.fill" : "pause.fill") { state.togglePause() }.labelStyle(.iconOnly).help(state.phase == .paused ? "Resume recording" : "Pause recording")
                        RecorderLiveInputButtons(state:state)
                        Button("Draw",systemImage:annotations.drawing ? "pencil.circle.fill" : "pencil.circle") { annotations.drawing.toggle() }.labelStyle(.iconOnly).help("Toggle drawing")
                        Button("Stop",systemImage:"stop.fill") { Task { await state.stop() } }.labelStyle(.iconOnly).buttonStyle(.borderedProminent).tint(.red).help("Stop and save") }
                    else if state.phase == .countdown || state.phase == .preparing { ProgressView().controlSize(.small); Button("Cancel") { state.cancelStart() } }
                    else { ProgressView().controlSize(.small); Text("Saving…") }
                }
            }
            if state.phase == .recording || state.phase == .paused {
                if annotations.drawing { AnnotationToolbar(state:annotations) }
            }
            if let notice = state.notice {
                Text(notice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
                Button("Privacy settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security")!) }
            }
        }.padding(state.phase == .idle ? 14 : 9).frame(width:state.phase == .idle || annotations.drawing || state.notice != nil ? 420 : 340).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius:14))
    }
}

struct RecorderLiveInputButtons: View {
    @ObservedObject var state: RecorderState
    var body: some View {
        HStack(spacing:6) {
            input("System audio","speaker.wave.2","speaker.slash",\.systemAudio)
            input("Microphone","mic","mic.slash",\.microphone)
            input("Camera bubble","video","video.slash",\.webcam)
        }.buttonStyle(.bordered)
    }
    private func input(_ title:String,_ on:String,_ off:String,_ key:WritableKeyPath<RecorderOptions,Bool>) -> some View {
        let enabled = state.liveInputs[keyPath:key]
        let available = state.availableInputs[keyPath:key]
        return Button { state.toggleLiveInput(key) } label: {
            Image(systemName:enabled ? on : off).foregroundStyle(enabled ? Color.accentColor : Color.secondary)
        }.accessibilityLabel(title).accessibilityValue(enabled ? "On" : "Off")
            .help(available ? (enabled ? "Turn off " : "Turn on ") + title : "Enable " + title + " before starting a recording")
            .disabled(!available)
    }
}
