import SwiftUI
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import CoreImage

@MainActor final class ScreenshotState: ObservableObject {
    let source = RecorderState()
    let annotations = AnnotationState()
    @Published var image: CGImage?
    @Published var working = false
    @Published var message = "Capture a display, selected area or window. Screenshots stay on your Mac."
    var preview = false
    var canAct: () -> Bool = { true }
    func capture() async {
        guard !preview, !working, canAct() else { return }; working = true; defer { working = false }
        guard await source.loadSources() else { message = source.notice ?? "Screen access unavailable."; return }
        if source.options.mode == "Selected area" { source.area = nil; await source.chooseArea() }
        guard let frame = source.captureFrame else { message = "Choose a window or area before capturing."; return }
        do {
            let filter: SCContentFilter
            if source.options.mode == "Window", let window = source.selectedWindow { filter = SCContentFilter(desktopIndependentWindow:window) }
            else {
                guard let display = source.selectedDisplay else { throw RecorderProblem(message:"Display unavailable.") }
                let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
                filter = SCContentFilter(display:display,excludingApplications:content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier },exceptingWindows:[])
            }
            let configuration = SCStreamConfiguration(), scale = CGFloat(filter.pointPixelScale)
            let size = RecorderGeometry.outputSize(CGSize(width:frame.width*scale,height:frame.height*scale),maxWidth:5120)
            configuration.width = Int(size.width); configuration.height = Int(size.height); configuration.showsCursor = false
            if #available(macOS 14.2, *) { configuration.ignoreShadowsSingleWindow = true }
            if source.options.mode == "Selected area", let display = source.selectedDisplay { let bounds = CGDisplayBounds(display.displayID); configuration.sourceRect = CGRect(x:frame.minX-bounds.minX,y:frame.minY-bounds.minY,width:frame.width,height:frame.height) }
            image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:configuration)
            annotations.clear(); message = "Captured. Add annotations or redactions, then copy or save a PNG."
        } catch { message = RecorderCaptureAccess.message(error) }
    }
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
            else if !source.displays.isEmpty { Picker("Display",selection:$source.displayID) { ForEach(source.displays,id:\.displayID) { display in Text("Display · \(display.width) × \(display.height)").tag(display.displayID) } }.onChange(of:source.displayID) { _,_ in source.modeChanged() } }
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
