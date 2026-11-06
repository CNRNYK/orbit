import AppKit
import ApplicationServices
import SwiftUI

private final class SpellingMarkButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.withAlphaComponent(0.82).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.move(to:CGPoint(x:1,y:2))
        for x in stride(from:3,through:max(3,Int(bounds.width)-1),by:2) {
            path.line(to:CGPoint(x:CGFloat(x),y:x % 4 == 3 ? 3.5 : 2))
        }
        path.stroke()
    }
}

@MainActor final class WritingSpellingMarks: NSObject {
    private var timer: Timer?
    private var allowed: () -> Bool = { false }
    private var language: () -> String = { "auto" }
    private var element: AXUIElement?
    private var pid: pid_t?
    private var text = ""
    private var context = ""
    private var edits: [(NSRange,String)] = []
    private var ignored = Set<String>()
    private var marks: [Int:NSPanel] = [:]
    private var card: NSPanel?
    private var active: Int?

    func start(allowed: @escaping () -> Bool, language: @escaping () -> String) {
        guard timer == nil else { return }
        self.allowed = allowed; self.language = language
        timer = Timer.scheduledTimer(withTimeInterval:0.65,repeats:true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        reset()
    }

    private func closeCard() { card?.orderOut(nil); card = nil; active = nil }
    private func reset() {
        for panel in marks.values { panel.orderOut(nil) }
        marks.removeAll(); closeCard(); element = nil; pid = nil
        text = ""; context = ""; edits = []; ignored = []
    }

    private func field() -> (NSRunningApplication, AXUIElement, String)? {
        let keys = ["com.apple.TextEdit":"orbit.writing.live.textedit","com.apple.Notes":"orbit.writing.live.notes",
                    "com.google.Chrome":"orbit.writing.live.chrome","com.openai.chat":"orbit.writing.live.chatgpt",
                    "com.openai.codex":"orbit.writing.live.chatgpt"]
        guard allowed(), let app = NSWorkspace.shared.frontmostApplication,
              let bundle = app.bundleIdentifier, let key = keys[bundle], UserDefaults.standard.bool(forKey:key),
              let field = WritingSelection.focusedTextElement(from:app),
              (bundle == "com.apple.TextEdit" || bundle == "com.apple.Notes" ||
               WritingSelection.attribute(field,kAXRoleAttribute) as? String == kAXTextAreaRole),
              let value = WritingSelection.attribute(field,kAXValueAttribute) as? String,
              WritingEngine.valid(value) else { return nil }
        return (app,field,value)
    }

    private func rangeValue(_ range: NSRange) -> AXValue? {
        var value = CFRange(location:range.location,length:range.length)
        return AXValueCreate(.cfRange,&value)
    }

    private func word(_ index: Int) -> String { (text as NSString).substring(with:edits[index].0) }

    private func refresh() {
        guard let (app,field,value) = field() else { reset(); return }
        let preference = language()
        guard let locale = preference == "auto" ? WritingLanguage.detect(value) : preference else { reset(); return }
        let dictionary = UserDefaults.standard.string(forKey:"orbit.writing.dictionary") ?? ""
        let settings = locale + "\n" + dictionary
        let sameField = pid == app.processIdentifier && element.map { CFEqual($0,field) } == true
        if !sameField || !text.utf16.elementsEqual(value.utf16) || context != settings {
            let keep = sameField ? ignored : []
            reset(); ignored = keep
            element = field; pid = app.processIdentifier; text = value; context = settings
            let terms = Set(dictionary.split(whereSeparator:\.isNewline).prefix(100).map {
                String($0.prefix(80)).trimmingCharacters(in:.whitespaces).lowercased(with:Locale(identifier:locale))
            })
            edits = Array(WritingEngine.spellingCorrections(value,language:locale,dictionary:terms).prefix(12))
        }
        var visible = Set<Int>()
        for index in edits.indices where !ignored.contains(word(index)) {
            guard let range = rangeValue(edits[index].0),
                  let bounds = WritingSelection.screenBounds(element:field,range:range),
                  bounds.width >= 4, bounds.height <= 70,
                  let screen = NSScreen.screens.first(where:{ $0.visibleFrame.contains(bounds) }) else { continue }
            let frame = CGRect(x:bounds.minX,y:max(screen.visibleFrame.minY,bounds.minY-2),width:bounds.width,height:6)
            visible.insert(index)
            let panel: NSPanel
            if let existing = marks[index] { panel = existing }
            else {
                panel = makePanel(frame:frame)
                let button = SpellingMarkButton(frame:CGRect(origin:.zero,size:frame.size))
                button.title = ""; button.isBordered = false; button.autoresizingMask = [.width,.height]
                button.tag = index; button.target = self; button.action = #selector(showCard(_:))
                button.setAccessibilityLabel("Review spelling suggestion")
                panel.contentView = button
                marks[index] = panel
            }
            if panel.frame != frame { panel.setFrame(frame,display:true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
            if active == index, let card {
                card.setFrameOrigin(WritingPanelPlacement.origin(size:card.frame.size,near:bounds,within:screen.visibleFrame))
            }
        }
        for index in Array(marks.keys) where !visible.contains(index) { marks.removeValue(forKey:index)?.orderOut(nil) }
        if let active, !visible.contains(active) { closeCard() }
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        return panel
    }

    @objc private func showCard(_ sender: NSButton) {
        let index = sender.tag
        guard edits.indices.contains(index), let anchor = marks[index]?.frame,
              let screen = NSScreen.screens.first(where:{ $0.frame.intersects(anchor) }) else { return }
        closeCard()
        let size = CGSize(width:256,height:126)
        let panel = makePanel(frame:CGRect(origin:WritingPanelPlacement.origin(size:size,near:anchor,within:screen.visibleFrame),size:size))
        panel.hasShadow = true
        let view = VStack(alignment:.leading,spacing:9) {
            HStack {
                Label("Spelling suggestion",systemImage:"text.badge.checkmark").font(.caption.weight(.medium))
                Spacer()
                Button { [weak self] in self?.closeCard() } label: { Image(systemName:"xmark") }.buttonStyle(.borderless).accessibilityLabel("Close")
            }.foregroundStyle(.secondary)
            Text(word(index)).strikethrough().foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Button(edits[index].1) { [weak self] in self?.apply(index) }
                    .buttonStyle(.borderedProminent).help("Apply this spelling correction")
                Spacer()
                Button("Ignore") { [weak self] in self?.ignore(index) }.buttonStyle(.borderless)
            }
        }.padding(14).frame(width:size.width,height:size.height)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
        panel.contentView = NSHostingView(rootView:view)
        active = index; card = panel; panel.orderFrontRegardless()
    }

    private func ignore(_ index: Int) {
        guard edits.indices.contains(index) else { return }
        ignored.insert(word(index)); closeCard(); refresh()
    }

    private func apply(_ index: Int) {
        defer { reset() }
        guard active == index, edits.indices.contains(index), let (app,field,value) = field(),
              pid == app.processIdentifier, element.map({ CFEqual($0,field) }) == true,
              text.utf16.elementsEqual(value.utf16), let target = rangeValue(edits[index].0) else { return }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(field,kAXSelectedTextAttribute as CFString,&settable) == .success,
              settable.boolValue,
              let original = WritingSelection.attribute(field,kAXSelectedTextRangeAttribute),
              AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,target) == .success else { return }
        let selected = WritingSelection.read(from:app)
        guard let selected, CFEqual(selected.element,field), CFEqual(selected.range,target),
              selected.text.utf16.elementsEqual(word(index).utf16),
              (WritingSelection.attribute(field,kAXValueAttribute) as? String)?.utf16.elementsEqual(text.utf16) == true,
              selected.replace(with:edits[index].1) else {
            if let current = WritingSelection.attribute(field,kAXSelectedTextRangeAttribute), CFEqual(current,target) {
                _ = AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,original)
            }
            return
        }
    }
}
