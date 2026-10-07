import SwiftUI
import AppKit
import ScreenCaptureKit

struct CaptureWindowCandidate: Equatable {
    let id: UInt32
    let frame: CGRect
}
enum CaptureWindowGeometry {
    static func appKit(_ rect: CGRect, primaryTop: CGFloat) -> CGRect { CGRect(x:rect.minX,y:primaryTop-rect.maxY,width:rect.width,height:rect.height) }
    static func hit(_ point: CGPoint, ordered: [CaptureWindowCandidate]) -> UInt32? { ordered.first { $0.frame.contains(point) }?.id }
}
@MainActor final class CaptureWindowHighlight {
    static let shared = CaptureWindowHighlight()
    private var panel: NSPanel?
    private var highlighted: UInt32?
    func show(_ window: SCWindow) {
        let frame = CaptureWindowGeometry.appKit(window.frame,primaryTop:CaptureDisplayGeometry.current().first(where: { $0.id == CGMainDisplayID() })?.appKitFrame.maxY ?? 0)
        show(frame:frame,id:window.windowID)
    }
    func show(frame: CGRect, id: UInt32) {
        if highlighted == id, panel?.frame == frame { return }; clear(); highlighted = id
        let panel = NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .screenSaver; panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; panel.hidesOnDeactivate = false
        let view = NSView(frame:CGRect(origin:.zero,size:frame.size)); view.wantsLayer = true; view.layer?.borderWidth = 4; view.layer?.borderColor = NSColor.systemBlue.cgColor; view.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08).cgColor
        panel.contentView = view; panel.orderFrontRegardless(); self.panel = panel
    }
    func clear() { panel?.orderOut(nil); panel = nil; highlighted = nil }
}
@MainActor final class CaptureWindowScreenPicker {
    static let shared = CaptureWindowScreenPicker()
    private var panels = [NSPanel]()
    private var continuation: CheckedContinuation<UInt32?,Never>?
    private var candidates = [CaptureWindowCandidate]()
    private var windows = [UInt32:SCWindow]()
    private var highlight: ((CaptureWindowCandidate) -> Void)?
    var overlayWindows: [NSPanel] { panels }
    private var observer: NSObjectProtocol?
    func select(_ sources: [SCWindow]) async -> UInt32? {
        guard continuation == nil else { return nil }
        let primaryTop = CaptureDisplayGeometry.current().first(where:{ $0.id == CGMainDisplayID() })?.appKitFrame.maxY ?? 0
        windows = Dictionary(uniqueKeysWithValues:sources.map { ($0.windowID,$0) })
        let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []).compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        candidates = order.compactMap { id in windows[id].map { CaptureWindowCandidate(id:id,frame:CaptureWindowGeometry.appKit($0.frame,primaryTop:primaryTop)) } }
        return await select(candidates:candidates,screens:NSScreen.screens.map(\.frame)) { [weak self] candidate in
            if let window = self?.windows[candidate.id] { CaptureWindowHighlight.shared.show(window) }
        }
    }
    func select(candidates: [CaptureWindowCandidate], screens: [CGRect], highlight: @escaping (CaptureWindowCandidate) -> Void) async -> UInt32? {
        guard continuation == nil, !candidates.isEmpty, !screens.isEmpty else { return nil }
        self.candidates = candidates; self.highlight = highlight
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.finish(nil) } }
            for frame in screens {
                let panel = RecorderControlPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
                panel.level = .screenSaver; panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; panel.hidesOnDeactivate = false; panel.acceptsMouseMovedEvents = true
                let view = CaptureWindowSelectionView(frame:CGRect(origin:.zero,size:frame.size)); view.owner = self; panel.contentView = view; panels.append(panel); panel.orderFrontRegardless(); panel.makeKey(); panel.makeFirstResponder(view)
            }
            hover(NSGlobalPoint())
        }
    }
    private func NSGlobalPoint() -> CGPoint { NSEvent.mouseLocation }
    func hover(_ point: CGPoint) { if let id = CaptureWindowGeometry.hit(point,ordered:candidates), let candidate = candidates.first(where:{ $0.id == id }) { highlight?(candidate) } else { CaptureWindowHighlight.shared.clear() } }
    func click(_ point: CGPoint) { finish(CaptureWindowGeometry.hit(point,ordered:candidates)) }
    func finish(_ id: UInt32?) { panels.forEach { $0.orderOut(nil) }; panels = []; CaptureWindowHighlight.shared.clear(); if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil; windows = [:]; candidates = []; highlight = nil; let pending = continuation; continuation = nil; pending?.resume(returning:id) }
}
@MainActor final class CaptureWindowSelectionView: NSView {
    weak var owner: CaptureWindowScreenPicker?
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() { super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect:bounds,options:[.mouseMoved,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)) }
    override func mouseMoved(with event: NSEvent) { owner?.hover(NSEvent.mouseLocation) }
    override func mouseDown(with event: NSEvent) { owner?.click(NSEvent.mouseLocation) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { owner?.finish(nil) } }
    override func draw(_ dirtyRect: NSRect) { NSColor.black.withAlphaComponent(0.015).setFill(); bounds.fill(); let text = "Hover a window, then click to select · Esc to cancel" as NSString; text.draw(at:CGPoint(x:24,y:24),withAttributes:[.font:NSFont.systemFont(ofSize:16,weight:.semibold),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black]) }
}
@MainActor final class CaptureWindowMenuState: ObservableObject { @Published var showing = false }
struct CaptureWindowMenu: View {
    @ObservedObject var state: RecorderState
    @StateObject private var menu = CaptureWindowMenuState()
    var body: some View {
        HStack {
            Button(state.selectedWindow.map { ($0.owningApplication?.applicationName ?? "App") + " · " + ($0.title ?? "Window") } ?? "Choose a window") { menu.showing.toggle() }.lineLimit(1)
                .popover(isPresented:$menu.showing) { VStack(alignment:.leading) { Text("Hover to preview a window").font(.caption).foregroundStyle(.secondary); ScrollView { LazyVStack(alignment:.leading) { ForEach(state.windows,id:\.windowID) { window in Button { state.windowID = window.windowID; state.options.masks = []; CaptureWindowHighlight.shared.clear(); menu.showing = false } label: { Text((window.owningApplication?.applicationName ?? "App") + " · " + (window.title ?? "Window")).frame(maxWidth:.infinity,alignment:.leading).padding(6) }.buttonStyle(.plain).onHover { hovering in if hovering { CaptureWindowHighlight.shared.show(window) } else { CaptureWindowHighlight.shared.clear() } } } } }.frame(width:340,height:220) }.padding(12).onDisappear { CaptureWindowHighlight.shared.clear() } }
            Button("Choose on screen",systemImage:"cursorarrow") { Task { guard !state.preview, !state.busy, state.canBegin() else { return }; guard await state.loadSources() else { return }; state.choosingWindow = true; defer { state.choosingWindow = false }; if let id = await CaptureWindowScreenPicker.shared.select(state.windows) { state.windowID = id; state.options.masks = [] } } }.disabled(state.busy || state.loadingSources)
        }.onDisappear { CaptureWindowHighlight.shared.clear() }
    }
}
