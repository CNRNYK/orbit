import AppKit
import SwiftUI
import Combine
import CoreImage
import CoreText

struct OrbitAnnotation: Identifiable, Equatable {
    var id = UUID()
    var tool: String
    var points: [CGPoint]
    var text = ""
    var color = "Red"
    var width = 4.0
}
final class AnnotationBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [OrbitAnnotation](), revision = 0
    func replace(_ values: [OrbitAnnotation]) { lock.lock(); self.values = values; revision += 1; lock.unlock() }
    func snapshot() -> ([OrbitAnnotation],Int) { lock.lock(); defer { lock.unlock() }; return (values,revision) }
}
@MainActor final class AnnotationState: ObservableObject {
    @Published var values = [OrbitAnnotation]() { didSet { buffer.replace(values) } }
    @Published var tool = "Arrow"
    @Published var color = "Red"
    @Published var text = "Note"
    @Published var width = 4.0
    @Published var drawing = false
    let buffer = AnnotationBuffer()
    func undo() { if !values.isEmpty { values.removeLast() } }
    func clear() { values.removeAll() }
}
enum AnnotationRenderer {
    static func color(_ value: String) -> CGColor { switch value { case "Blue": return NSColor.systemBlue.cgColor; case "Yellow": return NSColor.systemYellow.cgColor; case "Green": return NSColor.systemGreen.cgColor; default: return NSColor.systemRed.cgColor } }
    static func image(_ values: [OrbitAnnotation],size:CGSize) -> CGImage? {
        guard size.width > 0, size.height > 0, let context = CGContext(data:nil,width:Int(size.width),height:Int(size.height),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for value in values {
            let points = value.points.map { CGPoint(x:$0.x*size.width,y:(1-$0.y)*size.height) }
            guard let first = points.first else { continue }
            context.saveGState(); context.setStrokeColor(color(value.color)); context.setFillColor(color(value.color)); context.setLineWidth(value.width * max(0.5,size.width/1000)); context.setLineCap(.round); context.setLineJoin(.round)
            let last = points.last ?? first
            if value.tool == "Text" {
                let string = NSAttributedString(string:String(value.text.prefix(500)),attributes:[.font:NSFont.systemFont(ofSize:max(14,size.width/50),weight:.semibold),.foregroundColor:NSColor(cgColor:color(value.color)) ?? .systemRed])
                context.textPosition = first; CTLineDraw(CTLineCreateWithAttributedString(string),context)
            } else if value.tool == "Rectangle" || value.tool == "Cover" || value.tool == "Blur" {
                let rect = CGRect(x:min(first.x,last.x),y:min(first.y,last.y),width:abs(last.x-first.x),height:abs(last.y-first.y))
                if value.tool == "Cover" { context.setFillColor(NSColor.black.cgColor); context.fill(rect) }
                else if value.tool == "Rectangle" { context.stroke(rect) }
            } else {
                if value.tool == "Highlight" { context.setAlpha(0.35); context.setLineWidth(max(12,size.width/40)) }
                context.beginPath(); context.move(to:first)
                for point in points.dropFirst() { context.addLine(to:point) }; context.strokePath()
                if value.tool == "Arrow" && points.count > 1 {
                    let angle = atan2(last.y-first.y,last.x-first.x), length = max(12,size.width/55)
                    context.beginPath(); context.move(to:CGPoint(x:last.x-length*cos(angle-0.5),y:last.y-length*sin(angle-0.5))); context.addLine(to:last); context.addLine(to:CGPoint(x:last.x-length*cos(angle+0.5),y:last.y-length*sin(angle+0.5))); context.strokePath()
                }
            }
            context.restoreGState()
        }
        return context.makeImage()
    }
    static func render(_ source: CIImage,values:[OrbitAnnotation]) -> CIImage {
        let bounds = CGRect(origin:.zero,size:source.extent.size)
        var result = source.transformed(by:CGAffineTransform(translationX:-source.extent.minX,y:-source.extent.minY))
        if let overlay = image(values,size:bounds.size) { result = CIImage(cgImage:overlay).composited(over:result) }
        // Redaction is applied last so labels cannot accidentally expose covered content.
        for value in values where value.tool == "Blur" || value.tool == "Cover" {
            guard let first = value.points.first, let last = value.points.last else { continue }
            let normalized = CGRect(x:min(first.x,last.x),y:min(first.y,last.y),width:abs(last.x-first.x),height:abs(last.y-first.y))
            let rect = RecorderGeometry.pixels(normalized,size:bounds.size)
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { continue }
            let patch = value.tool == "Cover" ? CIImage(color:.black).cropped(to:rect) : result.clampedToExtent().applyingFilter("CIPixellate",parameters:[kCIInputScaleKey:24]).applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:12]).cropped(to:rect)
            result = patch.composited(over:result)
        }
        return result.cropped(to:bounds)
    }
}
final class AnnotationCanvas: NSView {
    var image: CGImage?
    var state: AnnotationState?
    var border = false
    var values = [OrbitAnnotation](), draft: OrbitAnnotation?
    var changed: ((OrbitAnnotation) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        let edits = values + (draft.map { [$0] } ?? [])
        if let image {
            let edited = AnnotationRenderer.render(CIImage(cgImage:image),values:edits)
            if let rendered = CIContext().createCGImage(edited,from:edited.extent) { NSImage(cgImage:rendered,size:bounds.size).draw(in:bounds) }
        } else if let overlay = AnnotationRenderer.image(edits,size:bounds.size) { NSImage(cgImage:overlay,size:bounds.size).draw(in:bounds) }
        if border { NSColor.systemRed.setStroke(); let path = NSBezierPath(rect:bounds.insetBy(dx:2,dy:2)); path.lineWidth = 3; path.stroke() }
    }
    func point(_ event: NSEvent) -> CGPoint { let p = convert(event.locationInWindow,from:nil); return CGPoint(x:min(1,max(0,p.x/max(1,bounds.width))),y:min(1,max(0,p.y/max(1,bounds.height)))) }
    override func mouseDown(with event:NSEvent) {
        guard let state else { return }
        let p = point(event); draft = OrbitAnnotation(tool:state.tool,points:[p,p],text:state.text,color:state.color,width:state.width); needsDisplay = true
    }
    override func mouseDragged(with event:NSEvent) {
        guard draft != nil else { return }; let p = point(event)
        if draft?.tool == "Pen" || draft?.tool == "Highlight" { if (draft?.points.count ?? 0) < 5000 { draft?.points.append(p) } } else { draft?.points[1] = p }
        needsDisplay = true
    }
    override func mouseUp(with event:NSEvent) { mouseDragged(with:event); if let draft { changed?(draft) }; draft = nil; needsDisplay = true }
}
struct AnnotationEditor: NSViewRepresentable {
    var image: CGImage?
    @ObservedObject var state: AnnotationState
    func makeNSView(context:Context) -> AnnotationCanvas { AnnotationCanvas() }
    func updateNSView(_ view:AnnotationCanvas,context:Context) { view.image = image; view.state = state; view.values = state.values; view.changed = { if state.values.count < 500 { state.values.append($0) } }; view.needsDisplay = true }
}
struct AnnotationToolbar: View {
    @ObservedObject var state: AnnotationState
    var screenshot = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Picker("Tool",selection:$state.tool) { ForEach(["Arrow","Rectangle","Pen","Highlight","Text"] + (screenshot ? ["Blur","Cover"] : []),id:\.self) { Text($0).tag($0) } }.frame(maxWidth:200)
                Picker("Color",selection:$state.color) { ForEach(["Red","Blue","Yellow","Green"],id:\.self) { Text($0).tag($0) } }.frame(maxWidth:130)
                Button("Undo") { state.undo() }.disabled(state.values.isEmpty)
                Button("Clear") { state.clear() }.disabled(state.values.isEmpty)
            }
            if state.tool == "Text" { TextField("Annotation text",text:$state.text).textFieldStyle(.roundedBorder) }
        }
    }
}
@MainActor final class RecordingOverlay {
    private var panel: NSPanel?, canvas: AnnotationCanvas?, subscription: AnyCancellable?
    let state: AnnotationState
    init(state:AnnotationState) { self.state = state }
    static func appKitFrame(_ quartz:CGRect,primaryTop:CGFloat) -> CGRect { CGRect(x:quartz.minX,y:primaryTop-quartz.maxY,width:quartz.width,height:quartz.height) }
    func show(frame:CGRect) {
        if panel == nil {
            let panel = NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .floating; panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
            let canvas = AnnotationCanvas(); canvas.state = state; canvas.border = true; canvas.changed = { [weak state] value in if let state, state.values.count < 500 { state.values.append(value) } }; panel.contentView = canvas
            self.panel = panel; self.canvas = canvas
            subscription = state.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
        }
        let primary = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID() }
        panel?.setFrame(Self.appKitFrame(frame,primaryTop:primary?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0),display:true)
        refresh(); panel?.orderFrontRegardless()
    }
    func refresh() { canvas?.values = state.values; canvas?.needsDisplay = true; panel?.ignoresMouseEvents = !state.drawing }
    func close() { panel?.orderOut(nil); panel = nil; canvas = nil; subscription = nil; state.drawing = false }
}
