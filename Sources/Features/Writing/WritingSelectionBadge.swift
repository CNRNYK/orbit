import AppKit
import ApplicationServices

private final class WritingBadgeButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class WritingSelectionBadge: NSObject {
    nonisolated static let preferenceKey = "orbit.writing.selection-badge"
    private var timer: Timer?
    private var panel: NSPanel?
    private var target: (pid: pid_t, element: AXUIElement, range: CFTypeRef)?
    private var canShow: () -> Bool = { false }
    private var open: (WritingSelection) -> Void = { _ in }
    private var dismissed = false
    private var fallbackAnchor: CGPoint?

    func start(canShow: @escaping () -> Bool, open: @escaping (WritingSelection) -> Void) {
        guard timer == nil else { return }
        self.canShow = canShow
        self.open = open
        timer = Timer.scheduledTimer(withTimeInterval:0.4,repeats:true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    private func hide() {
        panel?.orderOut(nil)
        target = nil
        fallbackAnchor = nil
        dismissed = false
    }

    private func refresh() {
        guard UserDefaults.standard.bool(forKey:Self.preferenceKey), canShow() else {
            panel?.orderOut(nil); return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let element = WritingSelection.focusedTextElement(from:app),
              let range = WritingSelection.attribute(element,kAXSelectedTextRangeAttribute),
              CFGetTypeID(range) == AXValueGetTypeID() else { hide(); return }
        var selected = CFRange()
        guard AXValueGetValue(range as! AXValue,.cfRange,&selected),
              selected.length > 0, selected.length <= WritingEngine.limit else { hide(); return }
        if let target, target.pid == app.processIdentifier, CFEqual(target.element,element), CFEqual(target.range,range) {
            guard !dismissed else { return }
        } else {
            dismissed = false
            fallbackAnchor = NSEvent.mouseLocation
        }
        target = (app.processIdentifier,element,range)
        let screens = NSScreen.screens
        let bounds = WritingSelection.screenBounds(element:element,range:range)
        let selectionScreen = bounds.flatMap { rect in
            screens.filter { $0.frame.intersects(rect) }
                .max(by:{ area($0.frame.intersection(rect)) < area($1.frame.intersection(rect)) })
        }
        let pointer = fallbackAnchor ?? NSEvent.mouseLocation
        guard let screen = selectionScreen ?? screens.first(where:{ $0.frame.contains(pointer) }),
              let origin = WritingPanelPlacement.badge(
                near: selectionScreen == nil ? CGRect(origin:pointer,size:.zero) : (bounds ?? .zero),
                within:screen.visibleFrame
              ) else { panel?.orderOut(nil); return }
        if panel == nil {
            let window = NSPanel(contentRect:CGRect(origin:origin,size:CGSize(width:26,height:26)),
                                 styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            let button = WritingBadgeButton(frame:CGRect(x:0,y:0,width:26,height:26))
            button.title = ""
            button.image = Bundle.main.url(forResource:"Orbit",withExtension:"png").flatMap { NSImage(contentsOf:$0) } ?? NSImage(systemSymbolName:"pencil.circle.fill",accessibilityDescription:"Orbit Writing Assistant")
            button.imageScaling = .scaleProportionallyUpOrDown
            button.isBordered = false
            button.toolTip = "Open Orbit Writing Assistant"
            button.setAccessibilityLabel("Open Orbit Writing Assistant")
            button.target = self
            button.action = #selector(activate)
            window.contentView = button
            panel = window
        }
        panel?.setFrameOrigin(origin)
        if panel?.isVisible == false { panel?.orderFrontRegardless() }
    }

    private func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }

    @objc private func activate() {
        defer { panel?.orderOut(nil); dismissed = true }
        guard UserDefaults.standard.bool(forKey:Self.preferenceKey), canShow(), let target,
              let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier == target.pid,
              let selection = WritingSelection.read(from:app),
              CFEqual(selection.element,target.element), CFEqual(selection.range,target.range) else { return }
        open(selection)
    }
}
