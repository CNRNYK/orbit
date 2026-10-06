import SwiftUI
import AppKit
import ScreenCaptureKit
import AVFoundation
import AVKit
import Combine
import UniformTypeIdentifiers

final class RecorderControlPanel: NSPanel { override var canBecomeKey: Bool { true } }

@MainActor final class RecorderState: ObservableObject {
    enum Phase: String { case idle, preparing, countdown, recording, paused, finishing }
    let annotations = AnnotationState()
    private lazy var recordingOverlay = RecordingOverlay(state:annotations)
    var onRecordingSaved: (() -> Void)?
    var onSourcesVerified: ((Bool) -> Void)?
    @Published var tab = "Record"
    @Published var options = RecorderOptions() { didSet { onOptionsChanged?(options) } }
    var onOptionsChanged: ((RecorderOptions) -> Void)?
    var selectedArea: CaptureAreaSelection?
    var displayGeometry: () -> [CaptureDisplayGeometry] = { CaptureDisplayGeometry.current() }
    @Published var outputFolder = FileManager.default.urls(for:.moviesDirectory,in:.userDomainMask).first!.appendingPathComponent("Orbit Recordings",isDirectory:true)
    @Published var thumbnails = [NSImage]()
    @Published var removeSelection = false
    @Published var focusedHandle = "Start"
    @Published var frameRate = 30.0
    @Published var editPreview = false
    var editPreviewURL: URL?
    var thumbnailTask: Task<Void,Never>?
    @Published var phase = Phase.idle
    @Published var displays = [SCDisplay]()
    @Published var windows = [SCWindow]()
    private var requestedDisplayID: UInt32?
    @Published var displayID: UInt32 = 0 { didSet { if displayID != 0 { requestedDisplayID = displayID } } }
    @Published var windowID: UInt32 = 0
    @Published var area: CGRect?
    @Published var loadingSources = false
    @Published var editing = false
    @Published var status = "Record a demo, explain a bug, or share a workflow."
    @Published var notice: String?
    @Published var countdown = 3
    @Published var elapsed = 0.0
    @Published var recordingURL: URL?
    @Published var recoveryURL: URL?
    @Published var recent = [URL]()
    @Published var playhead = 0.0
    private var playbackObserver: Any?
    @Published var player: AVPlayer? {
        didSet {
            if let playbackObserver { oldValue?.removeTimeObserver(playbackObserver) }; playbackObserver = nil; playhead = 0
            playbackObserver = player?.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.05,preferredTimescale:600),queue:.main) { [weak self] time in
                Task { @MainActor in let seconds = time.seconds; if seconds.isFinite { self?.playhead = seconds } }
            }
        }
    }
    @Published var duration = 0.0
    @Published var trimStart = 0.0
    @Published var trimEnd = 0.0
    @Published var coverMask = false
    @Published var compactControls = false
    private var annotationSubscription: AnyCancellable?
    init() { if let data = UserDefaults.standard.data(forKey:"orbit.recorder.options"), let saved = try? JSONDecoder().decode(RecorderOptions.self,from:data) { options = saved; options.masks = [] }; if let path = UserDefaults.standard.string(forKey:"orbit.recorder.folder") { outputFolder = URL(fileURLWithPath:path,isDirectory:true) }; annotationSubscription = annotations.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }
    private var hudSubscription: AnyCancellable?
    private var hudHost: NSHostingController<RecorderHUD>?
    var controlsVisible: Bool { hud?.isVisible == true }
    var canBegin: () -> Bool = { true }
    var preview = false
    var requestSources: () async throws -> RecorderSourceSnapshot = {
        let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
        return RecorderSourceSnapshot(displays:content.displays,windows:content.windows)
    }
    private var engine: RecorderEngine?, destination: URL?, directory: URL?
    private var startTask: Task<Void,Never>?, token = UUID(), ticker: Timer?, hud: NSPanel?
    private let tracker = RecorderInputTracker(), picker = RecorderRegionPicker()
    private var began: Date?, pausedAt: Date?, pausedDuration = 0.0
    private var sleepObserver: NSObjectProtocol?
    private var displayObserver: NSObjectProtocol?
    var active: Bool { phase != .idle }
    var busy: Bool { active || loadingSources || editing }
    var canPause: Bool { phase == .recording || phase == .paused }
    var elapsedLabel: String { let value = max(0,Int(elapsed)); return value >= 3600 ? String(format:"%02d:%02d:%02d",value/3600,value/60%60,value%60) : String(format:"%02d:%02d",value/60,value%60) }
    var selectedDisplay: SCDisplay? { displays.first { $0.displayID == displayID } }
    var selectedWindow: SCWindow? { windows.first { $0.windowID == windowID } }
    var captureFrame: CGRect? {
        if options.mode == "Window" { return selectedWindow?.frame }
        guard let display = selectedDisplay else { return nil }
        return options.mode == "Selected area" ? area : CGDisplayBounds(display.displayID)
    }
    var sourceLabel: String {
        if options.mode == "Window" { return selectedWindow.map { ($0.owningApplication?.applicationName ?? "App") + " · " + ($0.title ?? "Window") } ?? "Choose a window" }
        if options.mode == "Selected area" { return area.map { "\(Int($0.width)) × \(Int($0.height)) pt selected" } ?? "Choose an area" }
        return selectedDisplay.map { "Display · \($0.width) × \($0.height)" } ?? "Your main display"
    }
    @discardableResult func loadSources() async -> Bool {
        guard !preview, !loadingSources else { return false }
        loadingSources = true; defer { loadingSources = false }
        do {
            notice = nil
            let content = try await requestSources()
            displays = content.displays
            windows = content.windows.filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.frame.width >= 40 && $0.frame.height >= 40 && $0.windowLayer == 0 }.sorted { ($0.owningApplication?.applicationName ?? "").localizedCaseInsensitiveCompare($1.owningApplication?.applicationName ?? "") == .orderedAscending }
            if displayID == 0 { displayID = requestedDisplayID ?? displays.first(where:{ $0.displayID == CGMainDisplayID() })?.displayID ?? displays.first?.displayID ?? 0 }
            if displayID != 0 && selectedDisplay == nil { area = nil; selectedArea = nil; notice = "The selected display is disconnected. Choose another display." }
            if selectedWindow == nil { windowID = 0 }
            status = "Choose your capture source and effects. Audio and camera are optional."; onSourcesVerified?(true); return true
        } catch {
            displays = []; windows = []; displayID = 0; windowID = 0; area = nil; options.masks = []
            onSourcesVerified?(false); notice = RecorderCaptureAccess.message(error); status = "Screen sources could not be refreshed."; return false
        }
    }
    func modeChanged() { area = nil; selectedArea = nil; options.masks = [] }
    func chooseArea() async {
        guard !preview, !busy else { return }
        if displays.isEmpty { await loadSources() }
        phase = .preparing; defer { phase = .idle }
        if let selection = await picker.selectArea(displayIDs:displays.map(\.displayID),preferredDisplayID:displayID) { applyArea(selection) }
    }
    func applyArea(_ selection: CaptureAreaSelection) {
        displayID = selection.displayID; area = selection.rect; selectedArea = selection; options.masks = []
    }
    func displayRequest(availableIDs: [UInt32]? = nil) throws -> CaptureDisplayRequest {
        if options.mode == "Selected area", selectedArea?.rect != area { throw RecorderProblem(message:"Select a capture area again.") }
        return try CaptureDisplayRequest(displayID:displayID,selection:selectedArea,areaMode:options.mode == "Selected area",current:displayGeometry(),availableIDs:availableIDs ?? displays.map(\.displayID))
    }
    func validatedAreaSourceRect() throws -> CGRect {
        guard let selectedArea, selectedArea.displayID == displayID, selectedArea.rect == area else { throw RecorderProblem(message:"Select a capture area again.") }
        guard let crop = try displayRequest().sourceRect else { throw RecorderProblem(message:"Select a capture area again.") }; return crop
    }
    func validateDisplay() throws {
        guard displayGeometry().contains(where: { $0.id == displayID }) else { throw RecorderProblem(message:"The selected display is disconnected. Choose another display.") }
        if options.mode == "Selected area" { _ = try validatedAreaSourceRect() }
    }
    func addMask() async {
        guard !preview, !busy, let frame = captureFrame else { return }
        let id = options.mode == "Window" ? displays.first(where:{ CGDisplayBounds($0.displayID).intersects(frame) })?.displayID : displayID
        guard let id else { return }
        phase = .preparing; defer { phase = .idle }
        if let rect = await picker.select(displayID:id,within:frame,label:coverMask ? "Select solid privacy cover" : "Select blur area"), let normalized = RecorderGeometry.normalized(rect,inside:frame) { options.masks.append(RecorderMask(rect:normalized,cover:coverMask)) }
    }
    func start(compact: Bool = false) {
        guard !preview, !busy, canBegin() else { return }
        compactControls = compact
        phase = .preparing; notice = nil; recoveryURL = nil; if compactControls { showHUD() }; let ticket = UUID(); token = ticket
        startTask = Task { await begin(ticket:ticket) }
    }
    func cancelStart() {
        guard phase == .preparing || phase == .countdown else { return }
        token = UUID(); startTask?.cancel(); picker.cancel(); tracker.stop(); recordingOverlay.close(); hud?.orderOut(nil); hud = nil; hudHost = nil; hudSubscription = nil; if startTask == nil { phase = .idle }; status = "Cancelling recording…"
    }
    private func begin(ticket: UUID) async {
        defer { startTask = nil }
        do {
            guard await loadSources() else { throw RecorderProblem(message:notice ?? "Capture sources could not be loaded.") }
            try check(ticket)
            guard !displays.isEmpty else { throw RecorderProblem(message:"No screen is available. Refresh sources after allowing Screen Recording.") }
            if options.mode == "Selected area", area == nil {
                guard let selection = await picker.selectArea(displayIDs:displays.map(\.displayID),preferredDisplayID:displayID) else { throw CancellationError() }; applyArea(selection)
            }
            try check(ticket)
            guard let frame = captureFrame else { throw RecorderProblem(message:notice ?? (options.mode == "Window" ? "Choose a window before starting a window recording." : "Choose a capture source first.")) }
            let captureDisplay = options.mode == "Window" ? nil : displayGeometry().first { $0.id == displayID }
            let capturedOptions = options
            if capturedOptions.microphone { guard await AVCaptureDevice.requestAccess(for:.audio) else { throw RecorderProblem(message:"Microphone access was denied. Allow it in System Settings or turn Microphone off.") } }
            if capturedOptions.webcam { guard await AVCaptureDevice.requestAccess(for:.video) else { throw RecorderProblem(message:"Camera access was denied. Allow it in System Settings or turn Webcam off.") } }
            try check(ticket)
            try tracker.start(shortcuts:capturedOptions.shortcuts)

            let target = try Self.compactDestination(in:outputFolder)
            try check(ticket)
            destination = target
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Orbit-Recording-\(UUID().uuidString)",isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]); directory = folder
            let raw = folder.appendingPathComponent("Recording.mov")
            let filter: SCContentFilter
            if capturedOptions.mode == "Window" { guard let window = selectedWindow else { throw RecorderProblem(message:"The selected window is no longer available.") }; filter = SCContentFilter(desktopIndependentWindow:window) }
            else {
                guard selectedDisplay != nil else { throw RecorderProblem(message:"The selected display is no longer available.") }
                let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let request = try displayRequest(availableIDs:content.displays.map(\.displayID))
                guard let currentDisplay = content.displays.first(where: { $0.displayID == request.displayID }) else { throw RecorderProblem(message:"The selected display is disconnected. Choose another display.") }
                filter = SCContentFilter(display:currentDisplay,excludingApplications:ownApps,exceptingWindows:[])
            }
            try check(ticket)
            let scale = CGFloat(filter.pointPixelScale)
            let size = RecorderGeometry.outputSize(CGSize(width:frame.width*scale,height:frame.height*scale),maxWidth:capturedOptions.maxWidth)
            let config = SCStreamConfiguration(); config.width = Int(size.width); config.height = Int(size.height); config.pixelFormat = kCVPixelFormatType_32BGRA; config.minimumFrameInterval = CMTime(value:1,timescale:CMTimeScale(capturedOptions.fps)); config.queueDepth = 3; config.preservesAspectRatio = false; config.showsCursor = true; config.capturesAudio = capturedOptions.systemAudio; config.excludesCurrentProcessAudio = true; config.sampleRate = 48000; config.channelCount = 2
            if #available(macOS 14.2, *) { config.ignoreShadowsSingleWindow = true }
            if capturedOptions.mode == "Selected area" { config.sourceRect = try validatedAreaSourceRect() }
            annotations.clear(); recordingOverlay.show(frame:frame); phase = .countdown; showHUD(); for count in (1...3).reversed() { countdown = count; try await Task.sleep(nanoseconds:1_000_000_000); try check(ticket) }
            if capturedOptions.mode != "Window" { try validateDisplay(); guard let captureDisplay, displayGeometry().contains(captureDisplay) else { throw RecorderProblem(message:"The display arrangement changed. Choose the source again.") } }
            let engine = try RecorderEngine(url:raw,options:capturedOptions,size:size,frame:frame,tracker:tracker,annotations:annotations.buffer); self.engine = engine
            engine.onFrameChanged = { [weak self] frame in Task { @MainActor in guard let self, self.phase == .countdown || self.phase == .recording || self.phase == .paused else { return }; self.recordingOverlay.show(frame:frame) } }
            engine.onFailure = { [weak self] message in Task { @MainActor in guard let self else { return }; if self.phase == .recording || self.phase == .paused { await self.stop(interruption:message) } else if self.phase == .countdown || self.phase == .preparing { self.notice = message; self.cancelStart() } } }
            tracker.clear()
            try await engine.start(filter:filter,configuration:config,trackingWindow:capturedOptions.mode == "Window")
            try check(ticket)
            if let captureDisplay, !displayGeometry().contains(captureDisplay) { throw RecorderProblem(message:"The display arrangement changed while capture was starting. Choose the source again.") }
            phase = .recording; began = Date(); pausedDuration = 0; elapsed = 0; status = "Recording \(sourceLabel). Orbit controls are excluded."
            ticker = Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in Task { @MainActor in guard let self, self.phase == .recording, let began = self.began else { return }; self.elapsed = max(0,Date().timeIntervalSince(began)-self.pausedDuration) } }
            if let ticker { RunLoop.main.add(ticker,forMode:.common) }
            displayObserver = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in guard let self, let captureDisplay, !self.displayGeometry().contains(captureDisplay) else { return }; await self.stop(interruption:"The captured display disconnected or changed arrangement.") }
            }
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in await self?.stop(interruption:"The Mac is going to sleep.") } }
        } catch {
            if let engine { try? await engine.finish() }; engine = nil
            tracker.stop(); recordingOverlay.close(); ticker?.invalidate(); ticker = nil; hud?.orderOut(nil); hud = nil; hudHost = nil; hudSubscription = nil
            if !(error is CancellationError) { notice = error.localizedDescription }
            if let directory { try? FileManager.default.removeItem(at:directory) }; directory = nil; phase = .idle; status = error is CancellationError ? "Recording cancelled." : "Recording did not start."; if compactControls { showHUD() }
        }
    }
    private func check(_ ticket: UUID) throws { if Task.isCancelled || token != ticket { throw CancellationError() } }
    func togglePause() {
        guard let engine, canPause else { return }
        tracker.clear()
        if phase == .recording { pausedAt = Date(); phase = .paused; engine.pause(true) }
        else { if let pausedAt { pausedDuration += Date().timeIntervalSince(pausedAt) }; pausedAt = nil; phase = .recording; engine.pause(false) }
    }
    func stop(interruption: String? = nil) async {
        guard phase == .recording || phase == .paused, let engine, let destination else { return }
        phase = .finishing; recordingOverlay.close(); ticker?.invalidate(); ticker = nil; tracker.stop(); player?.pause(); status = "Finalizing video and mixing selected audio…"
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }; sleepObserver = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }; displayObserver = nil
        var saved = false
        defer { self.engine = nil; self.destination = nil; phase = .idle; hud?.orderOut(nil); hud = nil; hudHost = nil; hudSubscription = nil; compactControls = false; if saved { onRecordingSaved?() } }
        do {
            try await engine.finish(); recoveryURL = engine.url
            try await RecorderFiles.export(engine.url,to:destination,mixAudio:true)
            await showRecording(destination); saved = true
            if let directory { try? FileManager.default.removeItem(at:directory) }; directory = nil; recoveryURL = nil
            status = interruption == nil ? "Recording saved locally. Preview before sharing." : "Recording saved after interruption: \(interruption!)"
        } catch { notice = "\(error.localizedDescription)\nIf a finalized source is available, use Show recovery file."; recoveryURL = FileManager.default.fileExists(atPath:engine.url.path) ? engine.url : nil; status = "Recording could not be saved as MP4." }
    }
    func showRecording(_ url: URL) async {
        let asset = AVURLAsset(url:url)
        do {
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds > 0, let track = try await asset.loadTracks(withMediaType:.video).first else { throw RecorderProblem(message:"Choose a video with a playable video track.") }
            player?.pause(); clearEditPreview(); thumbnailTask?.cancel()
            frameRate = Double((try? await track.load(.nominalFrameRate)) ?? 30); if frameRate <= 0 { frameRate = 30 }
            recordingURL = url; recent.removeAll { $0 == url }; recent.insert(url,at:0); recent = Array(recent.prefix(8)); player = AVPlayer(url:url)
            duration = seconds; trimStart = 0; trimEnd = duration; removeSelection = false; tab = "Edit"; thumbnails = []
            thumbnailTask = Task { [weak self] in
                let generator = AVAssetImageGenerator(asset:asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width:160,height:90)
                var images = [NSImage]()
                for index in 0..<12 {
                    if Task.isCancelled { return }
                    if let result = try? await generator.image(at:CMTime(seconds:seconds*Double(index)/12,preferredTimescale:600)) { images.append(NSImage(cgImage:result.image,size:.zero)) }
                }
                guard !Task.isCancelled, self?.recordingURL == url else { return }; self?.thumbnails = images
            }
        } catch { notice = error.localizedDescription }
    }
    var startLabel: String { options.mode == "Selected area" && area == nil ? "Select area & record" : "Start recording" }
    func trim(remove: Bool = false) async {
        guard !preview, !busy, let recordingURL, let plan = editPlan, plan.changed, let target = savePanel(name:"Orbit-\(Self.timestamp())-edited.mp4") else { return }
        editing = true; player?.pause(); defer { editing = false }
        do { try await RecorderFiles.export(recordingURL,to:target,range:remove ? nil : plan.range,removing:remove ? plan.range : nil); await showRecording(target); status = "Edited copy saved. The original is unchanged." } catch { notice = error.localizedDescription }
    }
    func openRecent(_ url: URL) { guard !busy else { return }; editing = true; Task { await showRecording(url); editing = false } }
    func copyFile() { guard let recordingURL else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([recordingURL as NSURL]) }
    private func savePanel(name: String) -> URL? {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.nameFieldStringValue = name; panel.title = "Save Orbit recording"; panel.message = "Choose a new filename. Existing files are kept."; panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for:.moviesDirectory,in:.userDomainMask).first
        NSApp.activate(ignoringOtherApps:true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard !FileManager.default.fileExists(atPath:url.path) else { notice = "Choose a new filename; Orbit does not replace existing files."; return nil }; return url
    }
    func showCompactControls(preserveNotice: Bool = false) {
        guard !busy, canBegin() else { return }
        compactControls = true; if !preserveNotice { notice = nil }; if options.mode == "Selected area" { area = nil }; showHUD()
    }
    func closeControls() {
        guard !active, !editing else { return }
        hud?.orderOut(nil); hud = nil; hudHost = nil; hudSubscription = nil; compactControls = false
    }
    static func compactDestination(in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        return folder.appendingPathComponent("Orbit-\(timestamp())-\(UUID().uuidString).mp4")
    }
    private func resizeHUD() {
        guard let hud, let host = hudHost else { return }
        let size = host.sizeThatFits(in:NSSize(width:420,height:700))
        if size.height > 0 { hud.setContentSize(size) }
    }
    private func showHUD() {
        if let hud { resizeHUD(); hud.orderFrontRegardless(); return }
        let panel = RecorderControlPanel(contentRect:CGRect(x:0,y:0,width:420,height:100),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title = "Orbit Recording Controls"; panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        let host = NSHostingController(rootView:RecorderHUD(state:self)); hudHost = host; panel.contentViewController = host
        hud = panel; resizeHUD()
        if let screen = NSScreen.screens.first(where:{ ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) ?? NSScreen.main { panel.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX-panel.frame.width/2,y:screen.visibleFrame.minY+20)) }
        hudSubscription = objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.resizeHUD() } }
        panel.orderFrontRegardless()
    }
    static func timestamp() -> String { let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"; return formatter.string(from:Date()) }
}

struct RecorderView: View {
    @ObservedObject var state: RecorderState
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { VStack(alignment:.leading,spacing:5) { Text("Screen Recorder").font(.largeTitle.bold()); Text("Show your workflow. Keep the recording on your Mac.").foregroundStyle(.secondary) }; Spacer(); if state.active { Label(state.phase == .paused ? "Paused · \(state.elapsedLabel)" : "\(state.phase.rawValue.capitalized) · \(state.elapsedLabel)",systemImage:"record.circle").foregroundStyle(.red) } }
            Picker("Section",selection:$state.tab) { ForEach(["Record","Edit","Settings"],id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if state.tab == "Edit" { RecorderEditor(state:state) }
                    if state.tab == "Record" {
                        Text("\(state.options.maxWidth) px · \(state.options.fps) FPS · Microphone \(state.options.microphone ? "on" : "off") · System audio \(state.options.systemAudio ? "on" : "off")").font(.caption).foregroundStyle(.secondary)
                    GroupBox("Capture") {
                        VStack(alignment:.leading,spacing:12) {
                            Picker("Record",selection:$state.options.mode) { ForEach(["Full screen","Selected area","Window"],id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented).onChange(of:state.options.mode) { _,_ in state.modeChanged() }
                            HStack {
                                if state.options.mode == "Window" { Picker("Window",selection:$state.windowID) { Text("Choose a window").tag(UInt32(0)); ForEach(state.windows,id:\.windowID) { window in Text((window.owningApplication?.applicationName ?? "App") + " · " + (window.title ?? "Window")).tag(window.windowID) } }.onChange(of:state.windowID) { _,_ in state.options.masks = [] } }
                                else { Picker("Display",selection:Binding(get:{ state.displayID },set:{ state.displayID = $0; state.modeChanged() })) { if state.displays.isEmpty { Text("Main display · refresh to choose").tag(UInt32(0)) }; ForEach(state.displays,id:\.displayID) { display in Text("Display \(state.displays.firstIndex(where: { $0.displayID == display.displayID })!+1) · \(display.width) × \(display.height)").tag(display.displayID) } } }
                                Button("Refresh sources") { Task { await state.loadSources() } }
                                if state.loadingSources { ProgressView().controlSize(.small) }
                            }
                            if state.options.mode == "Selected area" { HStack { Text(state.area == nil ? "Move to any display and drag a rectangle." : state.sourceLabel).foregroundStyle(.secondary); Spacer(); Button("Select area") { Task { await state.chooseArea() } } } }

                        }.padding(10)
                    }.disabled(state.busy)
                    }
                    if state.tab == "Settings" {
                    GroupBox("Video & destination") {
                        VStack(alignment:.leading,spacing:12) {
                            HStack { Picker("Max dimension",selection:$state.options.maxWidth) { Text("1920 px").tag(1920); Text("2560 px").tag(2560); Text("3840 px").tag(3840) }; Picker("Frame rate",selection:$state.options.fps) { Text("30 fps").tag(30); Text("60 fps").tag(60) } }
                            HStack { Text(state.outputFolder.path).lineLimit(2); Spacer(); Button("Choose folder") { state.chooseOutputFolder() } }
                            Text("Recordings start automatically and are saved here. The original is kept when you save an edited copy.").font(.caption).foregroundStyle(.secondary)
                        }.padding(10)
                    }.disabled(state.busy)
                    HStack(alignment:.top,spacing:16) {
                        GroupBox("Pointer & presentation") {
                            VStack(alignment:.leading,spacing:12) {
                                Toggle("Mouse halo",isOn:$state.options.halo)
                                HStack { Picker("Color",selection:$state.options.haloColor) { ForEach(["Blue","Mint","Orange","Pink"],id:\.self) { Text($0).tag($0) } }; Slider(value:$state.options.haloRadius,in:12...60); Text("\(Int(state.options.haloRadius)) px").font(.caption).monospacedDigit() }.disabled(!state.options.halo)
                                Toggle("Click rings",isOn:$state.options.clicks)
                                Toggle("Shortcut labels",isOn:$state.options.shortcuts)
                                Text("⌘/Control combinations with physical key labels; no typed text. Input Monitoring permission is needed for this option.").font(.caption).foregroundStyle(.secondary)
                                Toggle("Cursor-follow zoom",isOn:$state.options.zoom)
                                HStack { Slider(value:$state.options.zoomFactor,in:1.1...2); Text(String(format:"%.1f×",state.options.zoomFactor)).monospacedDigit() }.disabled(!state.options.zoom)
                            }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                        }
                        GroupBox("Audio & camera") {
                            VStack(alignment:.leading,spacing:12) {
                                Toggle("Microphone",isOn:$state.options.microphone)
                                Toggle("System audio",isOn:$state.options.systemAudio)
                                Toggle("Webcam bubble",isOn:$state.options.webcam)
                                Text("Audio is off by default; your choices are remembered. Camera and microphone access is requested only when enabled for recording. The camera appears in the bottom-right corner of the video.").font(.caption).foregroundStyle(.secondary)
                                Label("Effects are included in the saved video.",systemImage:"checkmark.seal").font(.caption).foregroundStyle(.secondary)
                            }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }.disabled(state.busy)
                    Text("Live annotation tools — pen, arrow, shape and text — are available in the floating controls during recording.").font(.caption).foregroundStyle(.secondary)
                    GroupBox("Privacy areas") {
                        VStack(alignment:.leading,spacing:10) {
                            HStack { Toggle("Use a solid cover instead of blur",isOn:$state.coverMask); Spacer(); Button("Add area") { Task { await state.addMask() } }.disabled(state.captureFrame == nil) }
                            Text("Areas stay fixed relative to the capture frame. Blur can leave recognizable details; use a solid cover for secrets. Verify the video before sharing.").font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(state.options.masks.enumerated()),id:\.element.id) { index,mask in HStack { Label("\(mask.cover ? "Cover" : "Blur") area \(index+1)",systemImage:mask.cover ? "rectangle.fill" : "eye.slash"); Spacer(); Button("Remove") { state.options.masks.removeAll { $0.id == mask.id } } } }
                        }.padding(10)
                    }.disabled(state.busy)
                    }
                    if !state.recent.isEmpty { GroupBox("This session") { ForEach(state.recent,id:\.self) { url in Button(url.lastPathComponent) { state.openRecent(url) }.buttonStyle(.borderless).disabled(state.busy).frame(maxWidth:.infinity,alignment:.leading).padding(5) } } }
                }
            }
            if state.tab == "Edit", state.recordingURL != nil { RecorderEditActions(state:state) }
            HStack {
                Text(state.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                if let recovery = state.recoveryURL { Button("Show recovery file") { NSWorkspace.shared.activateFileViewerSelecting([recovery]) } }
                Spacer()
                if state.phase == .recording || state.phase == .paused { Button(state.phase == .paused ? "Resume" : "Pause") { state.togglePause() }; Button("Stop & save") { Task { await state.stop() } }.buttonStyle(.borderedProminent).tint(.red) }
                else if state.phase == .countdown || state.phase == .preparing { Button("Cancel") { state.cancelStart() } }
                else if state.phase == .finishing || state.editing { ProgressView().controlSize(.small); Text("Saving…") }
                else if state.tab == "Record" { Button(state.startLabel) { state.start() }.buttonStyle(.borderedProminent).disabled(state.busy || !state.canBegin()) }
            }
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
        .alert("Screen Recorder",isPresented:Binding(get:{ !state.compactControls && state.notice != nil },set:{ if !$0 { state.notice = nil } })) { Button("OK") { state.notice = nil }; if state.tab != "Edit" { Button("Privacy settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security")!) } } } message: { Text(state.notice ?? "") }
    }
}

// Avoid the SwiftUI AVKit overlay: its VideoPlayer superclass metadata can abort
// on macOS 27. Host the native macOS player directly and retain standard controls.
struct RecorderPlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player?.pause(); view.player = player }
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

// ScreenCaptureKit is the authority for this capture path. A legacy CoreGraphics
// preflight must not reject access before ScreenCaptureKit is queried.
struct RecorderSourceSnapshot { var displays: [SCDisplay]; var windows: [SCWindow] }
enum RecorderCaptureAccess {
    static func message(_ error: Error) -> String {
        let native = error as NSError
        let diagnostic = "macOS error: \(native.domain) (\(native.code))."
        if native.domain == SCStreamErrorDomain && native.code == SCStreamError.Code.userDeclined.rawValue {
            return "macOS denied screen access to this running copy of Orbit. If Orbit is already enabled in Screen & System Audio Recording, quit Orbit completely and reopen the copy in Applications. If it still fails, remove only Orbit from that permission list and add /Applications/Orbit.app again.\n" + diagnostic
        }
        return "ScreenCaptureKit could not load capture sources: \(native.localizedDescription)\n" + diagnostic
    }
}
