import AppKit
import SwiftUI

final class RecorderSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
final class RecorderSelectionCanvas: NSView {
    let allowed: CGRect, label: String
    var origin: CGPoint?, selection = CGRect.zero
    var complete: ((CGRect?) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, allowed: CGRect, label: String) { self.allowed = allowed; self.label = label; super.init(frame:frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.42).setFill(); bounds.fill()
        NSColor.white.withAlphaComponent(0.4).setStroke(); let limit = NSBezierPath(rect:allowed); limit.lineWidth = 1; limit.stroke()
        if selection.width > 0 {
            NSColor.clear.setFill(); selection.fill(using:.copy)
            NSColor.systemBlue.setStroke(); let border = NSBezierPath(rect:selection); border.lineWidth = 2; border.stroke()
        }
        let text = label + " · Drag to select · Esc to cancel"
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:17,weight:.semibold),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black.withAlphaComponent(0.65)]
        text.draw(at:NSPoint(x: max(allowed.minX+18,18),y:max(allowed.minY+18,18)),withAttributes:attributes)
    }
    override func mouseDown(with event: NSEvent) { let p = convert(event.locationInWindow,from:nil); guard allowed.contains(p) else { return }; origin = p; selection = .zero }
    override func mouseDragged(with event: NSEvent) { guard let origin else { return }; let p = convert(event.locationInWindow,from:nil); selection = CGRect(x:min(origin.x,p.x),y:min(origin.y,p.y),width:abs(p.x-origin.x),height:abs(p.y-origin.y)).intersection(allowed); needsDisplay = true }
    override func mouseUp(with event: NSEvent) { mouseDragged(with:event); guard selection.width >= 8, selection.height >= 8 else { origin = nil; selection = .zero; needsDisplay = true; return }; complete?(selection) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { complete?(nil) } else { super.keyDown(with:event) } }
}
@MainActor final class RecorderRegionPicker {
    private var window: NSWindow?, continuation: CheckedContinuation<CGRect?,Never>?
    func select(displayID: CGDirectDisplayID, within source: CGRect? = nil, label: String = "Select recording area") async -> CGRect? {
        cancel()
        guard let screen = NSScreen.screens.first(where:{ ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) else { return nil }
        let display = CGDisplayBounds(displayID), capture = source ?? display
        let allowed = CGRect(x:capture.minX-display.minX,y:capture.minY-display.minY,width:capture.width,height:capture.height).intersection(CGRect(origin:.zero,size:screen.frame.size))
        guard !allowed.isNull else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let window = RecorderSelectionWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            window.isOpaque = false; window.backgroundColor = .clear; window.level = .screenSaver; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; window.isReleasedWhenClosed = false
            let canvas = RecorderSelectionCanvas(frame:CGRect(origin:.zero,size:screen.frame.size),allowed:allowed,label:label)
            canvas.complete = { [weak self] rect in self?.complete(rect.map { CGRect(x:display.minX+$0.minX,y:display.minY+$0.minY,width:$0.width,height:$0.height) }) }
            window.contentView = canvas; self.window = window; NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas)
        }
    }
    private func complete(_ rect: CGRect?) { window?.orderOut(nil); window = nil; let pending = continuation; continuation = nil; pending?.resume(returning:rect) }
    func cancel() { complete(nil) }
}

struct RecorderHUD: View {
    @ObservedObject var state: RecorderState
    @ObservedObject var annotations: AnnotationState
    init(state:RecorderState) { self.state = state; annotations = state.annotations }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Orbit Recorder",systemImage:"record.circle").font(.subheadline.bold())
                Spacer()
                if state.phase == .idle { Button { state.closeControls() } label: { Image(systemName:"xmark") }.buttonStyle(.borderless).help("Close recording controls") }
            }
            if state.phase == .idle {
                Picker("",selection:$state.options.mode) { Text("Full screen").tag("Full screen"); Text("Area").tag("Selected area"); Text("Window").tag("Window") }.pickerStyle(.segmented).labelsHidden().onChange(of:state.options.mode) { _,_ in state.modeChanged() }
                if state.options.mode == "Window" {
                    HStack {
                        Picker("Window",selection:$state.windowID) { Text("Choose a window").tag(UInt32(0)); ForEach(state.windows,id:\.windowID) { window in Text((window.owningApplication?.applicationName ?? "App") + " · " + (window.title ?? "Window")).tag(window.windowID) } }.labelsHidden()
                        Button("Refresh") { Task { await state.loadSources() } }.disabled(state.busy)
                    }
                } else if !state.displays.isEmpty {
                    Picker("Display",selection:$state.displayID) { ForEach(state.displays,id:\.displayID) { display in Text("Display · \(display.width) × \(display.height)").tag(display.displayID) } }.onChange(of:state.displayID) { _,_ in state.modeChanged() }
                }
                Text("Saves to Movies/Orbit Recordings").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(state.startLabel,systemImage:"record.circle") { state.start(compact:true) }.buttonStyle(.borderedProminent).tint(.red).disabled(state.busy || !state.canBegin() || (state.options.mode == "Window" && state.selectedWindow == nil))
                    Spacer()
                    if let url = state.recordingURL { Button("Show last recording") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                }
            } else {
                HStack(spacing:12) {
                    Circle().fill(state.phase == .paused ? .orange : .red).frame(width:8,height:8)
                    Text(state.phase == .countdown ? "Starting in \(state.countdown)…" : state.elapsedLabel).font(.system(.body,design:.monospaced).bold())
                    Spacer()
                    if state.phase == .recording || state.phase == .paused { Button(state.phase == .paused ? "Resume" : "Pause") { state.togglePause() }; Button("Stop") { Task { await state.stop() } }.tint(.red) }
                    else if state.phase == .countdown || state.phase == .preparing { ProgressView().controlSize(.small); Button("Cancel") { state.cancelStart() } }
                    else { ProgressView().controlSize(.small); Text("Saving…") }
                }
            }
            if state.phase == .recording || state.phase == .paused {
                Toggle("Draw on recording",isOn:$annotations.drawing)
                if state.annotations.drawing { AnnotationToolbar(state:state.annotations) }
                Text("Red border marks the captured area. Drawing mode intercepts clicks; turn it off to use your apps.").font(.caption).foregroundStyle(.secondary)
            }
            if let notice = state.notice {
                Text(notice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
                Button("Privacy settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security")!) }
            }
        }.padding(14).frame(width:420).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius:14))
    }
}
