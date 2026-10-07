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
    @Published var values = [OrbitAnnotation]() { didSet {
        if !restoring && gesture == nil && oldValue != values { history.append(oldValue); history = Array(history.suffix(50)) }
        if let selectedID, !values.contains(where:{ $0.id == selectedID }) { self.selectedID = nil }
        buffer.replace(values)
    } }
    @Published var selectedID: UUID?
    private var history = [[OrbitAnnotation]](), gesture: [OrbitAnnotation]?, restoring = false
    var selected: OrbitAnnotation? { values.first { $0.id == selectedID } }
    var canUndo: Bool { !history.isEmpty }
    func beginGesture() { gesture = values }
    func finishGesture() { if let gesture, gesture != values { history.append(gesture); history = Array(history.suffix(50)) }; gesture = nil }
    func moveSelected(from original: OrbitAnnotation, delta: CGPoint, size: CGSize) {
        guard let index = values.firstIndex(where:{ $0.id == selectedID }), values[index].id == original.id else { return }
        let bounds = AnnotationGeometry.bounds(original,size:size)
        let dx = min(max(delta.x,-bounds.minX),max(-bounds.minX,1-bounds.maxX))
        let dy = min(max(delta.y,-bounds.minY),max(-bounds.minY,1-bounds.maxY))
        values[index].points = original.points.map { CGPoint(x:$0.x+dx,y:$0.y+dy) }
    }
    func editSelectedText(_ text: String) { guard let index = values.firstIndex(where:{ $0.id == selectedID && $0.tool == "Text" }) else { return }; values[index].text = String(text.prefix(500)) }
    func deleteSelected() { guard let selectedID else { return }; values.removeAll { $0.id == selectedID }; self.selectedID = nil }
    func select(at point: CGPoint, size: CGSize) { selectedID = values.reversed().first { AnnotationGeometry.hit($0,point:point,size:size) }?.id }

    @Published var tool = "Arrow"
    @Published var color = "Red"
    @Published var text = "Note"
    @Published var width = 4.0
    @Published var drawing = false
    let buffer = AnnotationBuffer()
    func undo() { guard let previous = history.popLast() else { return }; restoring = true; values = previous; restoring = false; selectedID = nil }
    func clear() { values.removeAll(); selectedID = nil }
    func reset() { restoring = true; values = []; selectedID = nil; history = []; gesture = nil; restoring = false }
}
enum AnnotationGeometry {
    static func bounds(_ value: OrbitAnnotation, size: CGSize) -> CGRect {
        guard let first = value.points.first else { return .zero }
        if value.tool == "Text" {
            let font = NSFont.systemFont(ofSize:max(14,size.width/50),weight:.semibold)
            let text = NSAttributedString(string:String(value.text.prefix(500)),attributes:[.font:font]).size()
            return CGRect(x:first.x,y:first.y-text.height/max(1,size.height),width:max(12,text.width)/max(1,size.width),height:text.height/max(1,size.height))
        }
        let xs = value.points.map(\.x), ys = value.points.map(\.y)
        return CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
    }
    static func hit(_ value: OrbitAnnotation, point: CGPoint, size: CGSize) -> Bool {
        let padding = CGPoint(x:8/max(1,size.width),y:8/max(1,size.height))
        let box = bounds(value,size:size)
        if ["Text","Cover","Blur"].contains(value.tool) { return box.insetBy(dx:-padding.x,dy:-padding.y).contains(point) }
        if value.tool == "Rectangle" { return box.insetBy(dx:-padding.x,dy:-padding.y).contains(point) && !box.insetBy(dx:padding.x,dy:padding.y).contains(point) }
        let pixels = value.points.map { CGPoint(x:$0.x*size.width,y:$0.y*size.height) }, p = CGPoint(x:point.x*size.width,y:point.y*size.height)
        for (a,b) in zip(pixels,pixels.dropFirst()) {
            let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
            let t = length == 0 ? 0 : min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/length))
            if hypot(p.x-a.x-t*dx,p.y-a.y-t*dy) <= (value.tool == "Highlight" ? max(12,size.width/40)/2+6 : max(8,value.width/2+6)) { return true }
        }
        return false
    }
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
    var editingAllowed = false
    private var dragOrigin: CGPoint?, original: OrbitAnnotation?
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
        if editingAllowed, let selected = state?.selected {
            let box = AnnotationGeometry.bounds(selected,size:bounds.size)
            let rect = CGRect(x:box.minX*bounds.width,y:box.minY*bounds.height,width:box.width*bounds.width,height:box.height*bounds.height).insetBy(dx:-5,dy:-5)
            NSColor.systemBlue.setStroke(); let outline = NSBezierPath(rect:rect); outline.lineWidth = 2; outline.setLineDash([5,3],count:2,phase:0); outline.stroke()
            NSColor.systemBlue.setFill(); for point in [CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)] { NSBezierPath(ovalIn:CGRect(x:point.x-3,y:point.y-3,width:6,height:6)).fill() }
        }
        if border { NSColor.systemRed.setStroke(); let path = NSBezierPath(rect:bounds.insetBy(dx:2,dy:2)); path.lineWidth = 3; path.stroke() }
    }
    func point(_ event: NSEvent) -> CGPoint { let p = convert(event.locationInWindow,from:nil); return CGPoint(x:min(1,max(0,p.x/max(1,bounds.width))),y:min(1,max(0,p.y/max(1,bounds.height)))) }
    override func mouseDown(with event:NSEvent) {
        guard let state else { return }
        window?.makeFirstResponder(self)
        let p = point(event)
        if editingAllowed, state.tool == "Select" {
            state.select(at:p,size:bounds.size); dragOrigin = p; original = state.selected; state.beginGesture(); needsDisplay = true; return
        }
        state.selectedID = nil; draft = OrbitAnnotation(tool:state.tool,points:[p,p],text:state.text,color:state.color,width:state.width); needsDisplay = true
    }
    override func mouseDragged(with event:NSEvent) {
        let p = point(event)
        if editingAllowed, let original, let dragOrigin { state?.moveSelected(from:original,delta:CGPoint(x:p.x-dragOrigin.x,y:p.y-dragOrigin.y),size:bounds.size); values = state?.values ?? []; needsDisplay = true; return }
        guard draft != nil else { return }
        if draft?.tool == "Pen" || draft?.tool == "Highlight" { if (draft?.points.count ?? 0) < 5000 { draft?.points.append(p) } } else { draft?.points[1] = p }
        needsDisplay = true
    }
    override func mouseUp(with event:NSEvent) { mouseDragged(with:event); if editingAllowed, state?.tool == "Select" { state?.finishGesture(); original = nil; dragOrigin = nil } else if let draft { changed?(draft) }; draft = nil; needsDisplay = true }
    override func keyDown(with event:NSEvent) {
        if editingAllowed, [51,117].contains(event.keyCode) { state?.deleteSelected(); values = state?.values ?? []; needsDisplay = true }
        else if editingAllowed, event.keyCode == 53 { state?.selectedID = nil; needsDisplay = true }
        else { super.keyDown(with:event) }
    }
}
struct AnnotationEditor: NSViewRepresentable {
    var image: CGImage?
    @ObservedObject var state: AnnotationState
    func makeNSView(context:Context) -> AnnotationCanvas { AnnotationCanvas() }
    func updateNSView(_ view:AnnotationCanvas,context:Context) { view.image = image; view.editingAllowed = image != nil; view.state = state; view.values = state.values; view.changed = { if state.values.count < 500 { state.values.append($0) } }; view.needsDisplay = true }
}
struct AnnotationToolbar: View {
    static func symbol(_ tool: String) -> String { ["Select":"cursorarrow","Arrow":"arrow.up.right","Rectangle":"rectangle","Pen":"pencil.tip","Highlight":"highlighter","Text":"textformat","Blur":"drop.halffull","Cover":"rectangle.fill"][tool] ?? "pencil" }
    @ObservedObject var state: AnnotationState
    var screenshot = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                ForEach((screenshot ? ["Select"] : []) + ["Arrow","Rectangle","Pen","Highlight","Text"] + (screenshot ? ["Blur","Cover"] : []),id:\.self) { tool in
                    Button { state.tool = tool } label: { Image(systemName:Self.symbol(tool)).frame(width:25,height:25).background(state.tool == tool ? Color.accentColor.opacity(0.2) : .clear).clipShape(RoundedRectangle(cornerRadius:5)) }.help(tool).accessibilityLabel(tool)
                }
            }
            HStack {
                Picker("Color",selection:$state.color) { ForEach(["Red","Blue","Yellow","Green"],id:\.self) { Text($0).tag($0) } }.frame(maxWidth:130)
                Button("Undo",systemImage:"arrow.uturn.backward") { state.undo() }.disabled(!state.canUndo)
                Button("Clear",systemImage:"trash") { state.clear() }.disabled(state.values.isEmpty)
            }
            if screenshot, state.selected != nil { HStack { Text("Selected " + (state.selected?.tool ?? "annotation")).font(.caption).foregroundStyle(.secondary); Button("Delete selected",systemImage:"trash") { state.deleteSelected() } } }
            if screenshot, state.selected?.tool == "Text" { TextField("Edit selected text",text:Binding(get:{ state.selected?.text ?? "" },set:{ state.editSelectedText($0) })).textFieldStyle(.roundedBorder) }
            else if state.tool == "Text" { TextField("Annotation text",text:$state.text).textFieldStyle(.roundedBorder) }
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
