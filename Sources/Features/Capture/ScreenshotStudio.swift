import SwiftUI
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import CoreImage

@MainActor final class ScreenshotPickerDelegate: NSObject, NSWindowDelegate {
    let cancel: () -> Void
    init(cancel: @escaping () -> Void) { self.cancel = cancel }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
}
@MainActor final class ScreenshotState: ObservableObject {
    let source = RecorderState()
    let annotations = AnnotationState()
    @Published var image: CGImage?
    @Published var working = false
    @Published var selectingWindow = false
    @Published var message = "Capture a display, selected area or window. Screenshots stay on your Mac."
    var onCaptured: (() -> Void)?
    var onCaptureFailed: (() -> Void)?
    private var quickPanel: NSPanel?
    private var quickPanelDelegate: ScreenshotPickerDelegate?
    var preview = false
    var canAct: () -> Bool = { true }
    func capture() async {
        guard !preview, !working, canAct() else { return }; working = true; var captured = false, failed = false; defer { working = false; if captured { quickPanel?.orderOut(nil); quickPanel = nil; quickPanelDelegate = nil; selectingWindow = false; onCaptured?() } else if failed { closeQuickPicker(); onCaptureFailed?() } }
        guard await source.loadSources() else { message = source.notice ?? "Screen access unavailable."; failed = true; return }
        if source.options.mode == "Selected area" { source.area = nil; await source.chooseArea() }
        guard let frame = source.captureFrame else { message = source.notice ?? "Choose a window, display or area before capturing."; return }
        let captureDisplay = source.options.mode == "Window" ? nil : source.displayGeometry().first { $0.id == source.displayID }
        do {
            let filter: SCContentFilter
            if source.options.mode == "Window", let window = source.selectedWindow { filter = SCContentFilter(desktopIndependentWindow:window) }
            else {
                guard source.selectedDisplay != nil else { throw RecorderProblem(message:"Display unavailable.") }
                let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
                let request = try source.displayRequest(availableIDs:content.displays.map(\.displayID))
                guard let currentDisplay = content.displays.first(where: { $0.displayID == request.displayID }) else { throw RecorderProblem(message:"The selected display is disconnected. Choose another display.") }
                filter = SCContentFilter(display:currentDisplay,excludingApplications:content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier },exceptingWindows:[])
            }
            let configuration = SCStreamConfiguration(), scale = CGFloat(filter.pointPixelScale)
            let size = RecorderGeometry.outputSize(CGSize(width:frame.width*scale,height:frame.height*scale),maxWidth:5120)
            configuration.width = Int(size.width); configuration.height = Int(size.height); configuration.showsCursor = false
            if #available(macOS 14.2, *) { configuration.ignoreShadowsSingleWindow = true }
            if source.options.mode != "Window" { try source.validateDisplay(); guard let captureDisplay, source.displayGeometry().contains(captureDisplay) else { throw RecorderProblem(message:"The display arrangement changed. Choose the source again.") } }
            if source.options.mode == "Selected area" { configuration.sourceRect = try source.validatedAreaSourceRect() }
            let capturedImage = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:configuration)
            if let captureDisplay, !source.displayGeometry().contains(captureDisplay) { throw RecorderProblem(message:"The display arrangement changed during capture. Capture again.") }
            image = capturedImage
            annotations.clear(); captured = true; message = "Captured. Add annotations or redactions, then copy or save a PNG."
        } catch { message = RecorderCaptureAccess.message(error); failed = true }
    }
    func quickCapture(_ mode: String) async {
        guard !preview, !working, !source.loadingSources, canAct() else { return }
        if source.options.mode != mode { source.options.mode = mode; source.modeChanged() }
        if mode != "Window" { await capture(); return }
        guard await source.loadSources() else { message = source.notice ?? "Screen access unavailable."; showWindowPicker(); return }
        if source.selectedWindow != nil { await capture() } else { showWindowPicker() }
    }
    private func showWindowPicker() {
        selectingWindow = true
        if let quickPanel { quickPanel.orderFrontRegardless(); return }
        let panel = RecorderControlPanel(contentRect:CGRect(x:0,y:0,width:440,height:240),styleMask:[.titled,.closable,.nonactivatingPanel],backing:.buffered,defer:false)
        let delegate = ScreenshotPickerDelegate { [weak self] in self?.closeQuickPicker() }; quickPanelDelegate = delegate; panel.delegate = delegate
        panel.title = "Orbit · Capture window"; panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView:ScreenshotWindowPicker(state:self,source:source)); panel.center(); panel.orderFrontRegardless(); quickPanel = panel
    }
    func closeQuickPicker() { quickPanel?.orderOut(nil); quickPanel = nil; quickPanelDelegate = nil; selectingWindow = false }
    func composed() -> CGImage? {
        guard let image else { return nil }
        let rendered = AnnotationRenderer.render(CIImage(cgImage:image),values:annotations.values)
        return CIContext().createCGImage(rendered,from:rendered.extent)
    }
    static func png(_ image: CGImage) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else { throw RecorderProblem(message:"PNG encoding failed.") }; return data
    }
    func copy() {
        guard let image = composed(), let data = try? Self.png(image) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data,forType:.png); message = "Edited screenshot copied to the clipboard."
    }
    func save() {
        guard !preview, !working, let image = composed() else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Orbit-Screenshot-\(RecorderState.timestamp()).png"; panel.message = "Choose a new filename. Existing files are kept."
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            let data = try Self.png(image)
            let temporary = target.deletingLastPathComponent().appendingPathComponent(".orbit-screenshot-\(UUID().uuidString).png")
            try data.write(to:temporary,options:.withoutOverwriting); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:temporary.path)
            defer { try? FileManager.default.removeItem(at:temporary) }
            try RecorderFiles.publish(temporary,to:target); message = "Saved \(target.lastPathComponent)."
        } catch { message = error.localizedDescription }
    }
}
struct ScreenshotView: View {
    @ObservedObject var state: ScreenshotState
    @ObservedObject var source: RecorderState
    init(state:ScreenshotState) { self.state = state; source = state.source }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Screenshot Studio").font(.largeTitle.bold())
            HStack {
                Picker("Capture",selection:$source.options.mode) { Text("Full screen").tag("Full screen"); Text("Area").tag("Selected area"); Text("Window").tag("Window") }.pickerStyle(.segmented).labelsHidden().onChange(of:source.options.mode) { _,_ in source.modeChanged() }.frame(maxWidth:420)
                Button("Refresh sources") { Task { guard !state.preview, state.canAct() else { return }; await source.loadSources(); if let notice = source.notice { state.message = notice } } }.disabled(state.working || source.loadingSources)
                Spacer(); Button("Capture") { Task { await state.capture() } }.buttonStyle(.borderedProminent).disabled(state.working || !state.canAct())
            }
            if source.options.mode == "Window" { Picker("Window",selection:$source.windowID) { Text("Choose a window").tag(UInt32(0)); ForEach(source.windows,id:\.windowID) { window in Text((window.owningApplication?.applicationName ?? "App")+" · "+(window.title ?? "Window")).tag(window.windowID) } } }
            else if !source.displays.isEmpty { Picker("Display",selection:Binding(get:{ source.displayID },set:{ source.displayID = $0; source.modeChanged() })) { ForEach(source.displays,id:\.displayID) { display in Text("Display · \(display.width) × \(display.height)").tag(display.displayID) } } }
            Text(state.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let image = state.image {
                AnnotationToolbar(state:state.annotations,screenshot:true)
                GeometryReader { proxy in
                    let ratio = CGFloat(image.width)/CGFloat(image.height)
                    let width = min(proxy.size.width,proxy.size.height*ratio)
                    AnnotationEditor(image:image,state:state.annotations).frame(width:width,height:width/ratio).background(Color.black).frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                HStack { Text("Blur can leave recognizable detail. Use Cover for secrets; verify before sharing.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Copy PNG") { state.copy() }; Button("Save PNG") { state.save() }.buttonStyle(.borderedProminent) }
            } else { ContentUnavailableView("Capture your screen",systemImage:"camera.viewfinder",description:Text("Then draw arrows, boxes, highlights or text, and redact selected areas.")) }
            if state.working { ProgressView() }
        }.padding(24)
    }
}

struct ScreenshotWindowPicker: View {
    @ObservedObject var state: ScreenshotState
    @ObservedObject var source: RecorderState
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Choose a window").font(.title2.bold())
            Picker("Window",selection:$source.windowID) { Text("Choose a window").tag(UInt32(0)); ForEach(source.windows,id:\.windowID) { window in Text((window.owningApplication?.applicationName ?? "App") + " · " + (window.title ?? "Window")).tag(window.windowID) } }
            Text(state.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            HStack { Button("Cancel") { state.closeQuickPicker() }; Button("Refresh") { Task { await source.loadSources(); state.message = source.notice ?? "Choose a window to capture." } }.disabled(source.loadingSources); Spacer(); Button("Capture window") { Task { await state.capture() } }.buttonStyle(.borderedProminent).disabled(state.working || source.windowID == 0) }
        }.padding(20).frame(width:440,height:240)
    }
}
