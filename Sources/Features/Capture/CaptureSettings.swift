import SwiftUI
import AVKit
import Vision
import IOKit.pwr_mgt

struct CapturePreferences: Codable {
    var countdown = true
    var hideControls = false
    var sounds = false
    var cursor = true
    var leftColor = "Orange"
    var rightColor = "Blue"
    var cameraCorner = "Bottom right"
    var cameraCircle = true
    var microphone = ""
    var camera = ""
    var awake = false
    var trashOriginal = false
    static func load() -> Self {
        UserDefaults.standard.data(forKey:"orbit.capture.preferences").flatMap { try? JSONDecoder().decode(Self.self,from:$0) } ?? Self()
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self),forKey:"orbit.capture.preferences") }
    static func devices(_ type: AVMediaType) -> [AVCaptureDevice] {
        AVCaptureDevice.devices(for:type)
    }
    static func device(_ type: AVMediaType, id: String) -> AVCaptureDevice? {
        id.isEmpty ? AVCaptureDevice.default(for:type) : devices(type).first { $0.uniqueID == id }
    }
}

final class CapturePreviewSurface: NSView {
    let label = NSTextField(labelWithString:"Preview unavailable")
    var preview: AVCaptureVideoPreviewLayer?
    override init(frame frameRect: NSRect) { super.init(frame:frameRect); addSubview(label) }
    convenience init() { self.init(frame:.zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        label.frame = bounds
        let edge = min(bounds.width,bounds.height)
        if let preview {
            let circular = preview.cornerRadius == 65
            preview.frame = CGRect(x:bounds.midX-edge/2,y:bounds.midY-edge/2,width:edge,height:edge)
            preview.mask = circular ? circleMask(edge) : nil
        }
    }
    private func circleMask(_ edge: CGFloat) -> CAShapeLayer {
        let mask = CAShapeLayer(); mask.frame = CGRect(x:0,y:0,width:edge,height:edge)
        mask.path = CGPath(ellipseIn:mask.bounds,transform:nil)
        return mask
    }
}

struct CaptureInputPreview: NSViewRepresentable {
    let preferences: CapturePreferences
    let video: Bool
    final class Coordinator {
        let session = AVCaptureSession()
        var player: AVCaptureVideoPreviewLayer?
        var timer: Timer?
        deinit { timer?.invalidate(); let session = session; DispatchQueue.global().async { session.stopRunning() } }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> CapturePreviewSurface {
        let view = CapturePreviewSurface()
        let label = view.label
        let coordinator = context.coordinator
        let type: AVMediaType = video ? .video : .audio
        guard AVCaptureDevice.authorizationStatus(for:type) == .authorized,
              let device = CapturePreferences.device(type,id:video ? preferences.camera : preferences.microphone),
              let input = try? AVCaptureDeviceInput(device:device), coordinator.session.canAddInput(input) else { return view }
        coordinator.session.addInput(input)
        if video {
            label.stringValue = ""; view.wantsLayer = true
            let layer = AVCaptureVideoPreviewLayer(session:coordinator.session)
            layer.videoGravity = .resizeAspectFill
            layer.cornerRadius = preferences.cameraCircle ? 65 : 12
            layer.masksToBounds = true
            coordinator.player = layer; view.preview = layer; view.layer?.addSublayer(layer)
        } else {
            let output = AVCaptureAudioDataOutput()
            guard coordinator.session.canAddOutput(output) else { return view }
            coordinator.session.addOutput(output)
            coordinator.timer = Timer.scheduledTimer(withTimeInterval:0.15,repeats:true) { [weak label, weak output] _ in
                let level = output?.connections.first?.audioChannels.first?.averagePowerLevel ?? -60
                let bars = min(12,max(0,Int((level.isFinite ? level + 60 : 0) / 5)))
                label?.stringValue = "Mic level  " + String(repeating:"▮",count:bars) + String(repeating:"▯",count:12-bars)
            }
        }
        DispatchQueue.global(qos:.userInitiated).async { coordinator.session.startRunning() }
        return view
    }
    func updateNSView(_ view: CapturePreviewSurface, context: Context) { view.needsLayout = true }
}

@MainActor final class CapturePreviewState: ObservableObject { @Published var input: String? }

struct CaptureSettingsView: View {
    @ObservedObject var state: RecorderState
    @StateObject private var previewState = CapturePreviewState()
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            GroupBox("General") {
                VStack(alignment:.leading) {
                    Toggle("Disable countdown",isOn:Binding(get:{ !state.capturePreferences.countdown },set:{ state.capturePreferences.countdown = !$0 }))
                    Toggle("Hide floating controls while recording",isOn:$state.capturePreferences.hideControls)
                    Toggle("Play start and stop sounds",isOn:$state.capturePreferences.sounds)
                    Toggle("Keep Mac awake while recording",isOn:$state.capturePreferences.awake)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(8)
            }
            GroupBox("Audio & camera inputs") {
                VStack(alignment:.leading) {
                    Picker("Microphone",selection:$state.capturePreferences.microphone) {
                        Text("System default").tag("")
                        ForEach(CapturePreferences.devices(.audio),id:\.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    }
                    Picker("Camera",selection:$state.capturePreferences.camera) {
                        Text("System default").tag("")
                        ForEach(CapturePreferences.devices(.video),id:\.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    }
                    Toggle("Circular camera bubble",isOn:$state.capturePreferences.cameraCircle)
                    Picker("Camera position",selection:$state.capturePreferences.cameraCorner) {
                        ForEach(["Bottom right","Bottom left","Top right","Top left"],id:\.self) { Text($0) }
                    }
                    HStack {
                        Button("Preview microphone") { preview(.audio) }
                        Button("Preview camera") { preview(.video) }
                        if previewState.input != nil { Button("Close preview") { previewState.input = nil } }
                    }
                    if let inputPreview = previewState.input { CaptureInputPreview(preferences:state.capturePreferences,video:inputPreview == "camera").frame(width:260,height:inputPreview == "camera" ? 260 : 30).id(inputPreview + state.capturePreferences.camera + state.capturePreferences.microphone + String(state.capturePreferences.cameraCircle)) }
                }.padding(8)
            }
            GroupBox("Cursor effects") {
                VStack(alignment:.leading) {
                    Toggle("Show pointer in recording",isOn:$state.capturePreferences.cursor)
                    Picker("Left click",selection:$state.capturePreferences.leftColor) { colors }
                    Picker("Right click",selection:$state.capturePreferences.rightColor) { colors }
                    HStack(spacing:18) {
                        if state.options.halo { Circle().fill(Color(nsColor:Self.color(state.options.haloColor)).opacity(0.28)).frame(width:min(60,state.options.haloRadius),height:min(60,state.options.haloRadius)).overlay { Image(systemName:"cursorarrow") } }
                        if state.options.clicks { Circle().stroke(Color(nsColor:Self.color(state.capturePreferences.leftColor)),lineWidth:2).frame(width:25,height:25); Circle().stroke(Color(nsColor:Self.color(state.capturePreferences.rightColor)),lineWidth:2).frame(width:25,height:25) }
                        Button("Reset effects") { state.resetCaptureEffects() }
                    }
                }.padding(8)
            }
        }.disabled(state.busy).onChange(of:state.busy) { _, busy in if busy { previewState.input = nil } }
    }
    private var colors: some View { ForEach(["Blue","Mint","Orange","Pink"],id:\.self) { Text($0) } }
    private func preview(_ type: AVMediaType) {
        guard !state.preview else { return }
        Task { if await AVCaptureDevice.requestAccess(for:type), !state.busy { previewState.input = type == .video ? "camera" : "microphone" } }
    }
    static func color(_ name: String) -> NSColor {
        switch name { case "Mint": return .systemMint; case "Orange": return .systemOrange; case "Pink": return .systemPink; default: return .systemBlue }
    }
}

enum CaptureImageTools {
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage:image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n")
        }.value
    }
    static func color(_ image: CGImage, x: Int, y: Int) -> String? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to:CGRect(x:x,y:y,width:1,height:1)),
              let context = CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = context.data else { return nil }
        context.draw(pixel,in:CGRect(x:0,y:0,width:1,height:1))
        let rgb = data.assumingMemoryBound(to:UInt8.self)
        return String(format:"#%02X%02X%02X · RGB %d, %d, %d",rgb[0],rgb[1],rgb[2],rgb[0],rgb[1],rgb[2])
    }
}

struct CaptureAreaDimensions: View {
    @ObservedObject var state: RecorderState
    var body: some View {
        if let selection = state.selectedArea, state.options.mode == "Selected area" {
            HStack {
                dimension("Width", selection:selection, horizontal:true)
                dimension("Height", selection:selection, horizontal:false)
                Text("points").foregroundStyle(.secondary)
            }.disabled(state.busy)
        }
    }
    private func dimension(_ title: String, selection: CaptureAreaSelection, horizontal: Bool) -> some View {
        let rect = selection.rect, limit = selection.display.captureFrame
        let maxValue = max(8,Int(horizontal ? limit.maxX-rect.minX : limit.maxY-rect.minY))
        return Stepper(value:Binding(get:{ Int(horizontal ? rect.width : rect.height) },set:{ value in
            guard let current = state.selectedArea, current.display == selection.display else { return }
            var updated = current.rect
            if horizontal { updated.size.width = min(CGFloat(value),limit.maxX-updated.minX) }
            else { updated.size.height = min(CGFloat(value),limit.maxY-updated.minY) }
            state.applyArea(.init(display:selection.display,rect:updated))
        }),in:8...maxValue) { Text(title + ": " + String(Int(horizontal ? rect.width : rect.height))) }
    }
}
