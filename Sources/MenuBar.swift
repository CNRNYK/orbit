import SwiftUI
import AppKit
import Combine

@MainActor struct MenuBarState {
    let store: Store
    var operating: Bool { store.locked || store.maintenanceState.working || store.terminalState.working || store.recorderState.busy }
    var canNavigate: Bool { !operating }
    var canCheckUpdates: Bool { canNavigate && store.startupReady && store.brew != nil }
    var canStop: Bool { store.busy && store.total > 0 && !store.maintenanceState.working && !store.terminalState.working }
    var updateCount: Int { store.updates.filter { store.installed.contains($0.id) }.count }
    var updatesLabel: String { store.updatesChecked ? (updateCount == 0 ? "Updates · up to date" : "Updates · \(updateCount) available") : "Updates · not checked" }
    var status: String {
        if store.recorderState.busy { return store.recorderState.phase == .recording || store.recorderState.phase == .paused ? "\(store.recorderState.phase == .paused ? "Paused" : "Recording") · \(store.recorderState.elapsedLabel)" : "Preparing or saving recording…" }
        if store.permissions.working { return "Checking permission access…" }
        if store.health.working { return "Running App Health Check…" }
        if store.login.working { return "Managing login items…" }
        if store.screenshots.working || store.screenshots.source.loadingSources { return "Preparing screenshot…" }
        if store.maintenanceState.working { return "Cleanup in progress" }
        if store.terminalState.working { return "Preparing developer setup" }
        if store.busy { return store.headline }
        if store.preparing || store.refreshing { return "Checking Homebrew…" }
        if store.checkingStartup { return "Checking setup…" }
        return store.startupReady && store.brew != nil ? "Ready when you are" : "Setup needs attention"
    }
}

enum MenuBarAction { case open, updates, checkUpdates, cleanup, details, quit, record, recorder, pauseRecord, stopRecord, screenshots, permissions, health, login }

struct MenuBarPanel: View {
    @ObservedObject var store: Store
    @ObservedObject var maintenance: MaintenanceState
    @ObservedObject var terminal: TerminalState
    @ObservedObject var recorder: RecorderState
    let action: (MenuBarAction) -> Void
    init(store: Store, action: @escaping (MenuBarAction) -> Void) {
        self.store = store; maintenance = store.maintenanceState; terminal = store.terminalState; recorder = store.recorderState; self.action = action
    }
    var state: MenuBarState { MenuBarState(store: store) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                OrbitBrandIcon(size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Orbit").font(.title3.bold())
                    HStack(spacing: 5) { Circle().fill(state.operating ? Color.orange : store.startupReady && store.brew != nil ? Color.green : Color.orange).frame(width: 6, height: 6); Text(state.status).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer()
            }
            if state.operating && !recorder.busy {
                VStack(alignment: .leading, spacing: 8) {
                    if state.canStop {
                        ProgressView(value: Double(store.completed), total: Double(max(store.total, 1)))
                        Text(store.progressSummary).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Button(store.stopRequested ? "Stopping after this app…" : "Stop after current app") { store.stopRequested = true }.disabled(store.stopRequested)
                    } else { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("You can follow the operation in Orbit.").font(.caption).foregroundStyle(.secondary) } }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.accentColor.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Button { action(.open) } label: { HStack { Text("Open Orbit"); Spacer(); Image(systemName: "arrow.up.forward") }.padding(.vertical, 5).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Label("Screen Recorder", systemImage: "record.circle").font(.subheadline.bold()); Spacer(); Button("Settings") { action(.recorder) }.font(.caption).buttonStyle(.borderless) }
                if recorder.phase == .recording || recorder.phase == .paused {
                    HStack { Circle().fill(recorder.phase == .paused ? .orange : .red).frame(width: 7, height: 7); Text(recorder.elapsedLabel).monospacedDigit().bold(); Spacer(); Button(recorder.phase == .paused ? "Resume" : "Pause") { action(.pauseRecord) }; Button("Stop") { action(.stopRecord) }.tint(.red) }
                } else if recorder.active {
                    HStack { ProgressView().controlSize(.small); Text(recorder.phase == .countdown ? "Starting in \(recorder.countdown)…" : "Preparing or saving…").font(.caption); Spacer(); if recorder.phase == .preparing || recorder.phase == .countdown { Button("Cancel") { recorder.cancelStart() } } }
                } else {
                    Picker("", selection: $recorder.options.mode) { Text("Full screen").tag("Full screen"); Text("Area").tag("Selected area"); Text("Window").tag("Window") }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:.infinity).fixedSize(horizontal:false,vertical:true).onChange(of: recorder.options.mode) { _, _ in recorder.modeChanged() }.disabled(state.operating)
                    Button("Recording controls", systemImage: "record.circle") { action(.record) }.buttonStyle(.bordered).frame(maxWidth:.infinity, alignment:.leading).disabled(state.operating)
                }
            }.padding(12).background(Color.red.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius:12))
            VStack(spacing: 2) {
                row(state.updatesLabel, symbol: "arrow.triangle.2.circlepath", enabled: state.canNavigate) { action(.updates) }
                row("Check for updates", symbol: "arrow.clockwise", enabled: state.canCheckUpdates) { action(.checkUpdates) }
                row("Screenshot Studio", symbol: "camera.viewfinder", enabled: state.canNavigate) { action(.screenshots) }
                row("Permission Center", symbol: "checkmark.shield", enabled: state.canNavigate) { action(.permissions) }
                row("App Health Check", symbol: "stethoscope", enabled: state.canNavigate) { action(.health) }
                row("Login Items", symbol: "power", enabled: state.canNavigate) { action(.login) }
                row("Cleanup", symbol: "sparkles", enabled: state.canNavigate) { action(.cleanup) }
                row("Operation details", symbol: "text.alignleft", enabled: true) { action(.details) }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Runs here when its window is closed.")
                    Text(store.lastUpdateCheck.map { "Updates checked " + $0.formatted(date: .omitted, time: .shortened) } ?? "Updates are checked on request.")
                }.font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Quit Orbit") { action(.quit) }.buttonStyle(.borderless).font(.caption)
            }
        }.padding(18).frame(width: 340).background(Color(nsColor: .windowBackgroundColor))
    }
    func row(_ title: String, symbol: String, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { HStack(spacing: 11) { Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 20); Text(title); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }.padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle()) }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }
}

// Preserve SwiftUI's window delegate for every event except closing the main window.
final class OrbitWindowDelegate: NSObject, NSWindowDelegate {
    let original: NSWindowDelegate?
    init(original: NSWindowDelegate?) { self.original = original }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || (original?.responds(to: selector) ?? false) }
    override func forwardingTarget(for selector: Selector!) -> Any? { original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector) }
}

@MainActor final class MenuBarController: NSObject {
    let store: Store
    let popover = NSPopover()
    private(set) var statusItem: NSStatusItem?
    private var panelHost: NSHostingController<MenuBarPanel>?
    private var subscriptions = Set<AnyCancellable>()
    private var eventMonitors = [Any]()
    private var windowDelegates = [ObjectIdentifier: OrbitWindowDelegate]()
    private weak var mainWindow: NSWindow?
    init(store: Store) { self.store = store; super.init() }
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); statusItem = item
        item.button?.target = self; item.button?.action = #selector(togglePanel)
        item.button?.setAccessibilityLabel("Orbit menu")
        popover.behavior = .applicationDefined; popover.animates = true
        let host = NSHostingController(rootView: MenuBarPanel(store: store) { [weak self] action in self?.perform(action) })
        host.sizingOptions = [.preferredContentSize]
        panelHost = host; popover.contentViewController = host
        for publisher in [store.objectWillChange, store.maintenanceState.objectWillChange, store.terminalState.objectWillChange, store.recorderState.objectWillChange] {
            publisher.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshIcon() } }.store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification).sink { [weak self] note in
            guard let window = note.object as? NSWindow else { return }; DispatchQueue.main.async { self?.remember(window) }
        }.store(in: &subscriptions)
        // Keep progress-driven size changes from dismissing the panel; dismiss on user input instead.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in DispatchQueue.main.async { self?.popover.close() } }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown { if event.keyCode == 53 { self.popover.close(); return nil }; return event }
            if event.window !== self.popover.contentViewController?.view.window && event.window !== self.statusItem?.button?.window { self.popover.close() }
            return event
        }) { eventMonitors.append(monitor) }
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification).sink { [weak self] _ in self?.popover.close() }.store(in: &subscriptions)
        NSApp.windows.forEach { remember($0) }; refreshIcon()
    }
    func remember(_ window: NSWindow) {
        guard window.title == "Orbit", window.styleMask.contains(.titled), window.sheetParent == nil else { return }
        mainWindow = window
        let key = ObjectIdentifier(window)
        if windowDelegates[key] == nil { let bridge = OrbitWindowDelegate(original: window.delegate); windowDelegates[key] = bridge; window.delegate = bridge }
    }
    func openWindow() {
        popover.close()
        if mainWindow == nil { NSApp.windows.forEach { remember($0) } }
        NSApp.activate(ignoringOtherApps: true); if mainWindow?.isMiniaturized == true { mainWindow?.deminiaturize(nil) }; mainWindow?.makeKeyAndOrderFront(nil)
    }
    func perform(_ action: MenuBarAction) {
        let state = MenuBarState(store: store)
        switch action {
        case .open: openWindow()
        case .updates, .cleanup:
            guard state.canNavigate else { return }; store.search = ""; store.navigate(action == .updates ? .updates : .cleanup); openWindow()
        case .checkUpdates:
            guard state.canCheckUpdates else { return }; store.search = ""; store.navigate(.updates); openWindow(); Task { await store.checkUpdates() }
        case .screenshots, .permissions, .health, .login:
            guard state.canNavigate else { return }
            let mode: ActionMode = action == .screenshots ? .screenshots : action == .permissions ? .permissions : action == .health ? .health : .login
            store.navigate(mode); openWindow()
        case .recorder:
            if state.operating && !store.recorderState.busy { return }; if store.recorderState.busy { store.revealActiveRecorder() } else { store.navigate(.recorder) }; openWindow()
        case .record:
            guard !state.operating else { return }; popover.close(); store.recorderState.showCompactControls(); mainWindow?.orderOut(nil)
        case .pauseRecord: store.recorderState.togglePause()
        case .stopRecord: Task { await store.recorderState.stop() }
        case .details: openWindow(); store.showLog = true
        case .quit: popover.close(); NSApp.terminate(nil)
        }
    }
    @objc func togglePanel() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.close() }
        else { resizePanel(); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); popover.contentViewController?.view.window?.makeKey() }
    }
    func resizePanel() {
        guard let host = panelHost else { return }
        let size = host.sizeThatFits(in: NSSize(width: 340, height: 1000))
        if size.height > 0 && popover.contentSize != size { popover.contentSize = size }
    }
    func refreshIcon() {
        resizePanel()
        statusItem?.button?.image = Self.icon(active: MenuBarState(store: store).operating)
        let recorder = store.recorderState
        statusItem?.length = recorder.active ? NSStatusItem.variableLength : NSStatusItem.squareLength
        statusItem?.button?.contentTintColor = recorder.active ? .systemRed : nil
        statusItem?.button?.title = recorder.phase == .recording || recorder.phase == .paused ? recorder.elapsedLabel : ""
        statusItem?.button?.font = NSFont.monospacedDigitSystemFont(ofSize:11,weight:.medium)
        statusItem?.button?.toolTip = "Orbit · " + MenuBarState(store: store).status
    }
    static func icon(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            NSColor.black.setStroke(); NSColor.black.setFill()
            let orbit = NSBezierPath(ovalIn: NSRect(x: 2, y: 6, width: 18, height: 10))
            let transform = AffineTransform(translationByX: 11, byY: 11); var rotation = AffineTransform(); rotation.rotate(byDegrees: 32); var center = AffineTransform(translationByX: -11, byY: -11)
            center.append(rotation); center.append(transform); orbit.transform(using: center); orbit.lineWidth = 1.7; orbit.stroke()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 6, height: 6)).fill()
            if active { NSBezierPath(ovalIn: NSRect(x: 17, y: 17, width: 4, height: 4)).fill() }
            return true
        }
        image.isTemplate = true; return image
    }
    func remove() { popover.close(); eventMonitors.forEach { NSEvent.removeMonitor($0) }; eventMonitors.removeAll(); subscriptions.removeAll(); if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }; statusItem = nil }
}
