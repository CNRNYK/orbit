import AppKit
import SwiftUI
import Carbon

// Registration, not a global keyboard event monitor. No Accessibility/Input Monitoring.
enum OrbitShortcutAction: String, CaseIterable, Codable, Identifiable {
    case screenshot, selector, recording, open
    var id: String { rawValue }
    var title: String { switch self { case .screenshot: return "Take a screenshot"; case .selector: return "Open capture mode selector"; case .recording: return "Start or stop recording"; case .open: return "Open Orbit" } }
    var defaultShortcut: OrbitShortcut { let code: UInt32 = switch self { case .screenshot: 20; case .selector: 21; case .recording: 23; case .open: 31 }; return OrbitShortcut(keyCode:code,modifiers:[.command,.option,.control]) }
}
struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt32
    static let command = Self(rawValue:1), option = Self(rawValue:2), control = Self(rawValue:4), shift = Self(rawValue:8)
    init(rawValue: UInt32) { self.rawValue = rawValue }
    init(_ flags: NSEvent.ModifierFlags) {
        var value: Self = []
        if flags.contains(.command) { value.insert(.command) }; if flags.contains(.option) { value.insert(.option) }; if flags.contains(.control) { value.insert(.control) }; if flags.contains(.shift) { value.insert(.shift) }; self = value
    }
    var carbon: UInt32 { (contains(.command) ? UInt32(cmdKey) : 0) | (contains(.option) ? UInt32(optionKey) : 0) | (contains(.control) ? UInt32(controlKey) : 0) | (contains(.shift) ? UInt32(shiftKey) : 0) }
    var label: String { (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "") }
}
struct OrbitShortcut: Codable, Hashable {
    let keyCode: UInt32
    let modifiers: ShortcutModifiers
    var label: String { modifiers.label + Self.keyLabel(keyCode) }
    static func keyLabel(_ code: UInt32) -> String {
        let special: [UInt32:String] = [36:"Return",48:"Tab",49:"Space",51:"Delete",53:"Esc",123:"←",124:"→",125:"↓",126:"↑",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"]
        if let label = special[code] { return label }
        // Resolve the current keyboard layout, so recorded shortcuts do not assume US letters.
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(), let pointer = TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to:UCKeyboardLayout.self)
            var dead: UInt32 = 0, count = 0; var chars = [UniChar](repeating:0,count:8)
            let status = UCKeyTranslate(layout,UInt16(code),UInt16(kUCKeyActionDisplay),0,UInt32(LMGetKbdType()),OptionBits(kUCKeyTranslateNoDeadKeysMask),&dead,8,&count,&chars)
            if status == noErr, count > 0 { let label = String(utf16CodeUnits:chars,count:count).uppercased(); if !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return label } }
        }
        return [36:"Return",48:"Tab",49:"Space",51:"Delete",53:"Esc",123:"←",124:"→",125:"↓",126:"↑" ][code] ?? "Key \(code)"
    }
    var problem: String? {
        guard keyCode < 128, ![54,55,56,57,58,59,60,61,62,63].contains(keyCode), modifiers.rawValue & ~15 == 0 else { return "Choose a regular key with modifiers." }
        guard modifiers.contains(.command) || modifiers.contains(.control) else { return "Include Command or Control to avoid intercepting normal typing." }
        let system: Set<OrbitShortcut> = [
            Self(keyCode:49,modifiers:.command), Self(keyCode:49,modifiers:.control), Self(keyCode:49,modifiers:[.command,.option]),
            Self(keyCode:12,modifiers:.command), Self(keyCode:13,modifiers:.command), Self(keyCode:4,modifiers:.command), Self(keyCode:43,modifiers:.command), Self(keyCode:12,modifiers:[.command,.shift]), Self(keyCode:4,modifiers:[.command,.option]),
            Self(keyCode:48,modifiers:.command), Self(keyCode:48,modifiers:[.command,.shift]), Self(keyCode:53,modifiers:[.command,.option]),
            Self(keyCode:12,modifiers:[.command,.control]), Self(keyCode:12,modifiers:[.command,.option]),
            Self(keyCode:123,modifiers:.control), Self(keyCode:124,modifiers:.control), Self(keyCode:125,modifiers:.control), Self(keyCode:126,modifiers:.control)
        ]
        if system.contains(self) || ([20,21,23].contains(keyCode) && (modifiers == [.command,.shift] || modifiers == [.command,.shift,.control])) { return "This combination is commonly reserved by macOS. Choose another shortcut." }
        return nil
    }
}
@MainActor protocol ShortcutRegistering: AnyObject {
    var event: ((OrbitShortcutAction,Bool) -> Void)? { get set }
    func register(_ shortcut: OrbitShortcut, action: OrbitShortcutAction) throws -> UInt32
    func unregister(_ token: UInt32)
    func reassign(_ token: UInt32, to action: OrbitShortcutAction)
    func shutdown()
}
@MainActor final class CarbonShortcutRegistrar: ShortcutRegistering {
    var event: ((OrbitShortcutAction,Bool) -> Void)?
    private var handler: EventHandlerRef?
    private var references = [UInt32:EventHotKeyRef](), actions = [UInt32:OrbitShortcutAction]()
    private var next: UInt32 = 1
    init() {
        var events = [EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotkey = EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&hotkey) == noErr else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<CarbonShortcutRegistrar>.fromOpaque(context).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // Carbon invokes this handler on the application event loop.
            MainActor.assumeIsolated { if let action = owner.actions[hotkey.id] { owner.event?(action,pressed) } }
            return noErr
        },events.count,&events,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    func register(_ shortcut: OrbitShortcut, action: OrbitShortcutAction) throws -> UInt32 {
        guard handler != nil else { throw RecorderProblem(message:"macOS could not install the shortcut handler.") }
        let token = next; next += 1; var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode,shortcut.modifiers.carbon,EventHotKeyID(signature:0x4F524254,id:token),GetApplicationEventTarget(),0,&reference)
        guard status == noErr, let reference else { throw RecorderProblem(message:"macOS could not register this shortcut (\(status)). It may already be in use.") }
        references[token] = reference; actions[token] = action; return token
    }
    func unregister(_ token: UInt32) { if let reference = references.removeValue(forKey:token) { UnregisterEventHotKey(reference) }; actions.removeValue(forKey:token) }
    func reassign(_ token: UInt32, to action: OrbitShortcutAction) { actions[token] = action }
    func shutdown() { for token in Array(references.keys) { unregister(token) }; if let handler { RemoveEventHandler(handler) }; handler = nil; event = nil }
}
@MainActor final class KeyboardShortcutState: ObservableObject {
    @Published private(set) var assignments = [OrbitShortcutAction:OrbitShortcut]()
    @Published var warning: String?
    @Published var recording: OrbitShortcutAction?
    var perform: ((OrbitShortcutAction) -> Void)?
    private var preferences: UserDefaults?
    private var registrar: (any ShortcutRegistering)?
    private var tokens = [OrbitShortcutAction:UInt32](), held = Set<OrbitShortcutAction>()
    private(set) var running = false
    init(preferences: UserDefaults? = nil) {
        self.preferences = preferences
        if let data = preferences?.data(forKey:"orbit.keyboard-shortcuts.v1"), let saved = try? JSONDecoder().decode([String:OrbitShortcut].self,from:data) {
            // An empty dictionary deliberately disables all shortcuts.
            for action in OrbitShortcutAction.allCases { if let shortcut = saved[action.rawValue], shortcut.problem == nil, !assignments.values.contains(shortcut) { assignments[action] = shortcut } }
        } else { for action in OrbitShortcutAction.allCases { assignments[action] = action.defaultShortcut } }
    }
    func start(_ registrar: any ShortcutRegistering) {
        guard !running else { return }; self.registrar = registrar; running = true
        registrar.event = { [weak self] action,pressed in self?.receive(action,pressed:pressed) }
        resumeRegistrations()
    }
    func receive(_ action: OrbitShortcutAction, pressed: Bool) {
        if !pressed { held.remove(action); return }
        guard running, tokens[action] != nil, held.insert(action).inserted else { return }
        if recording != nil { finishRecording(assignments[action]); return }; perform?(action)
    }
    @discardableResult func assign(_ shortcut: OrbitShortcut?, to action: OrbitShortcutAction) -> Bool {
        if let shortcut {
            if let problem = shortcut.problem { warning = problem; return false }
            if assignments.contains(where: { $0.key != action && $0.value == shortcut }) { warning = "This shortcut is already assigned to another Orbit action."; return false }
        }
        if shortcut == assignments[action], !running || shortcut == nil || tokens[action] != nil { warning = nil; return true }
        var newToken: UInt32?
        do { if running, recording == nil, let shortcut, let registrar { newToken = try registrar.register(shortcut,action:action) } }
        catch { warning = error.localizedDescription + " The previous assignment has been kept."; return false }
        if let old = tokens.removeValue(forKey:action) { registrar?.unregister(old) }; if let newToken { tokens[action] = newToken }
        assignments[action] = shortcut; held.remove(action); warning = nil; save(); return true
    }
    func beginRecording(_ action: OrbitShortcutAction) { guard recording == nil else { return }; recording = action; held.removeAll(); warning = nil }
    func finishRecording(_ shortcut: OrbitShortcut?) {
        guard let action = recording else { return }
        // Existing registrations remain live; their events can also supply a recorded combination.
        recording = nil; if let shortcut { _ = assign(shortcut,to:action) }
    }
    func restoreDefaults() {
        guard recording == nil else { return }
        let defaults = Dictionary(uniqueKeysWithValues:OrbitShortcutAction.allCases.map { ($0,$0.defaultShortcut) })
        var replacements = [OrbitShortcutAction:UInt32](), created = [UInt32]()
        if running, let registrar {
            do {
                for action in OrbitShortcutAction.allCases {
                    let shortcut = defaults[action]!
                    if let existing = assignments.first(where:{ $0.value == shortcut }), let token = tokens[existing.key] { replacements[action] = token }
                    else { let token = try registrar.register(shortcut,action:action); replacements[action] = token; created.append(token) }
                }
            } catch { created.forEach { registrar.unregister($0) }; warning = error.localizedDescription + " Previous assignments have been kept."; return }
            for token in tokens.values where !replacements.values.contains(token) { registrar.unregister(token) }
            for (action,token) in replacements { registrar.reassign(token,to:action) }
        }
        tokens = replacements; assignments = defaults; held.removeAll(); warning = nil; save()
    }
    func stop() { recording = nil; suspendRegistrations(); registrar?.shutdown(); registrar = nil; running = false }
    private func suspendRegistrations() { for token in tokens.values { registrar?.unregister(token) }; tokens.removeAll(); held.removeAll() }
    private func resumeRegistrations() {
        guard running, let registrar else { return }
        for action in OrbitShortcutAction.allCases {
            guard tokens[action] == nil, let shortcut = assignments[action] else { continue }
            do { tokens[action] = try registrar.register(shortcut,action:action) } catch { warning = "\(action.title): \(error.localizedDescription) Choose another shortcut." }
        }
    }
    private func save() { preferences?.set(try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues:assignments.map { ($0.key.rawValue,$0.value) })),forKey:"orbit.keyboard-shortcuts.v1") }
    func label(_ action: OrbitShortcutAction) -> String { assignments[action]?.label ?? "Disabled" }
}
final class ShortcutRecordingView: NSView {
    var received: ((OrbitShortcut?) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }; if event.keyCode == 53 { received?(nil); return }
        received?(OrbitShortcut(keyCode:UInt32(event.keyCode),modifiers:ShortcutModifiers(event.modifierFlags)))
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { keyDown(with:event); return true }
}
struct ShortcutRecorder: NSViewRepresentable {
    let received: (OrbitShortcut?) -> Void
    func makeNSView(context: Context) -> ShortcutRecordingView { let view = ShortcutRecordingView(); view.received = received; return view }
    func updateNSView(_ view: ShortcutRecordingView, context: Context) { view.received = received }
}
struct KeyboardShortcutsView: View {
    @ObservedObject var state: KeyboardShortcutState
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Label("Keyboard Shortcuts",systemImage:"keyboard").font(.title2.bold()); Spacer(); Button("Restore defaults") { state.restoreDefaults() } }
            Text("Capture from any app while Orbit is running. Screenshot and recording use their own most recently selected mode.").foregroundStyle(.secondary)
            ForEach(OrbitShortcutAction.allCases) { action in
                HStack { Text(action.title).font(.headline); Spacer(); Text(state.label(action)).font(.system(.body,design:.monospaced)).padding(8).background(Color.primary.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius:6)); Button("Change…") { state.beginRecording(action) }; Button("Disable") { _ = state.assign(nil,to:action) }.disabled(state.assignments[action] == nil) }.padding(12).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:10))
            }
            if let warning = state.warning { Label(warning,systemImage:"exclamationmark.triangle").foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
            Text("Orbit checks its own duplicates, common macOS reserved combinations and registration errors. macOS provides no complete inventory of shortcuts in other apps; a successful registration cannot guarantee that another app never uses the same combination. Shortcuts stop when you quit Orbit.").font(.caption).foregroundStyle(.secondary)
        }.sheet(item:$state.recording,onDismiss:{ state.finishRecording(nil) }) { action in
            VStack(spacing:18) { Image(systemName:"keyboard").font(.largeTitle); Text(action.title).font(.title2.bold()); Text("Press a key combination with Command or Control.\nPress Esc to cancel.").multilineTextAlignment(.center); ShortcutRecorder { state.finishRecording($0) }.frame(width:1,height:1); Button("Cancel") { state.finishRecording(nil) } }.padding(32).frame(width:460)
        }
    }
}
