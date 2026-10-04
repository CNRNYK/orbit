import Foundation
import AppKit
import AVFoundation
import CoreImage
import CoreMedia
import Darwin

struct RecorderOptions: Codable, Equatable {
    var mode = "Full screen"
    var microphone = false, systemAudio = false, webcam = false
    var halo = true, clicks = true, shortcuts = false, zoom = false
    var haloColor = "Blue", haloRadius = 28.0, zoomFactor = 1.4
    var fps = 30, maxWidth = 1920
    var masks = [RecorderMask]()
}
struct RecorderMask: Identifiable, Codable, Equatable {
    var id = UUID()
    var rect: CGRect // Normalized, top-left origin within captured content.
    var cover = false
}
struct RecorderProblem: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
enum RecorderGeometry {
    static func normalized(_ rect: CGRect, inside frame: CGRect) -> CGRect? {
        let clipped = rect.standardized.intersection(frame)
        guard frame.width > 0, frame.height > 0, !clipped.isNull, clipped.width >= 8, clipped.height >= 8 else { return nil }
        return CGRect(x: (clipped.minX-frame.minX)/frame.width, y: (clipped.minY-frame.minY)/frame.height, width: clipped.width/frame.width, height: clipped.height/frame.height)
    }
    static func pixels(_ rect: CGRect, size: CGSize) -> CGRect {
        CGRect(x: rect.minX*size.width, y: (1-rect.maxY)*size.height, width: rect.width*size.width, height: rect.height*size.height).intersection(CGRect(origin: .zero, size: size))
    }
    static func point(_ point: CGPoint, frame: CGRect, size: CGSize) -> CGPoint? {
        guard frame.width > 0, frame.height > 0, frame.contains(point) else { return nil }
        return CGPoint(x: (point.x-frame.minX)/frame.width*size.width, y: (1-(point.y-frame.minY)/frame.height)*size.height)
    }
    static func outputSize(_ source: CGSize, maxWidth: Int) -> CGSize {
        let scale = min(1, Double(maxWidth)/max(max(source.width, source.height), 1))
        return CGSize(width: max(2, floor(source.width*scale/2)*2), height: max(2, floor(source.height*scale/2)*2))
    }
    static func zoomRect(center: CGPoint, size: CGSize, factor: Double) -> CGRect {
        let width = size.width/max(factor, 1), height = size.height/max(factor, 1)
        return CGRect(x: min(max(center.x-width/2, 0), size.width-width), y: min(max(center.y-height/2, 0), size.height-height), width: width, height: height)
    }
}
struct RecorderTimeline {
    var start: CMTime?, pausedAt: CMTime?, offset = CMTime.zero
    mutating func pause(at time: CMTime) { if pausedAt == nil { pausedAt = time } }
    mutating func resume(at time: CMTime) { if let pausedAt { offset = offset + max(time-pausedAt, .zero); self.pausedAt = nil } }
    mutating func videoTime(at time: CMTime) -> CMTime? {
        guard pausedAt == nil else { return nil }
        if start == nil { start = time }
        let result = time-start!-offset
        return result >= .zero ? result : nil
    }
    func audioTime(at time: CMTime) -> CMTime? {
        guard pausedAt == nil, let start else { return nil }
        let result = time-start-offset
        return result >= .zero ? result : nil
    }
}
struct RecorderPointer {
    var location = CGPoint.zero
    var clickLocation = CGPoint.zero, clickAt = -100.0
    var shortcut = "", shortcutAt = -100.0
}

enum RecorderKeys {
    // Physical key labels only; never read characters, clipboard or typed text.
    static func label(code: Int64, flags: CGEventFlags) -> String? {
        guard flags.contains(.maskCommand) || flags.contains(.maskControl) else { return nil }
        let keys: [Int64:String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",36:"↩",48:"⇥",49:"Space",51:"⌫",53:"Esc",123:"←",124:"→",125:"↓",126:"↑"]
        guard let key = keys[code] else { return nil }
        return (flags.contains(.maskControl) ? "⌃" : "") + (flags.contains(.maskAlternate) ? "⌥" : "") + (flags.contains(.maskShift) ? "⇧" : "") + (flags.contains(.maskCommand) ? "⌘" : "") + key
    }
}

final class RecorderInputTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var value = RecorderPointer()
    private var monitors = [Any]()
    private var tap: CFMachPort?, tapSource: CFRunLoopSource?
    func snapshot() -> RecorderPointer { lock.lock(); defer { lock.unlock() }; var copy = value; copy.location = CGEvent(source: nil)?.location ?? copy.location; return copy }
    @MainActor func start(shortcuts: Bool) throws {
        stop()
        let click: (NSEvent) -> Void = { [weak self] _ in self?.clicked() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown,.rightMouseDown], handler: click) { monitors.append(m) }
        if shortcuts {
            guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else { throw RecorderProblem(message: "Allow Input Monitoring for shortcut labels, or turn Shortcut labels off. No typed text is collected.") }
            let callback: CGEventTapCallBack = { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let tracker = Unmanaged<RecorderInputTracker>.fromOpaque(info).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap = tracker.tap { CGEvent.tapEnable(tap: tap, enable: true) } }
                else if type == .keyDown, let label = RecorderKeys.label(code: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags) { tracker.lock.lock(); tracker.value.shortcut = label; tracker.value.shortcutAt = ProcessInfo.processInfo.systemUptime; tracker.lock.unlock() }
                return Unmanaged.passUnretained(event)
            }
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { throw RecorderProblem(message: "Shortcut monitoring could not start. Check Input Monitoring permission or turn Shortcut labels off.") }
            tap = port; tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes); CGEvent.tapEnable(tap: port, enable: true)
        }
    }
    func clear() { lock.lock(); value = RecorderPointer(); lock.unlock() }
    private func clicked() { lock.lock(); value.clickLocation = CGEvent(source: nil)?.location ?? .zero; value.clickAt = ProcessInfo.processInfo.systemUptime; lock.unlock() }
    @MainActor func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }; monitors.removeAll()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil; tapSource = nil; lock.lock(); value = RecorderPointer(); lock.unlock()
    }
}

final class RecorderCompositor {
    var annotations: AnnotationBuffer?
    private var annotationRevision = -1
    private var annotationImage: CIImage?
    private var annotationSize = CGSize.zero
    let options: RecorderOptions
    private var center: CGPoint?
    private var cachedLabel = "", cachedImage: CIImage?
    init(options: RecorderOptions) { self.options = options }
    func image(_ source: CIImage, frame: CGRect, size: CGSize, pointer: RecorderPointer, camera: CIImage?, now: Double) -> CIImage {
        let bounds = CGRect(origin: .zero, size: size)
        var result = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY)).transformed(by: CGAffineTransform(scaleX: size.width/source.extent.width, y: size.height/source.extent.height)).cropped(to: bounds)
        if let annotations {
            let (values,revision) = annotations.snapshot()
            if revision != annotationRevision || annotationSize != size {
                annotationImage = AnnotationRenderer.image(values,size:size).map { CIImage(cgImage:$0) }; annotationRevision = revision; annotationSize = size
            }
            if let annotationImage { result = annotationImage.composited(over:result) }
        }
        for mask in options.masks {
            let rect = RecorderGeometry.pixels(mask.rect, size: size)
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { continue }
            let hidden = mask.cover ? CIImage(color: CIColor(red: 0.08, green: 0.09, blue: 0.12)).cropped(to: rect) : result.cropped(to: rect).clampedToExtent().applyingFilter("CIPixellate", parameters: ["inputScale": max(24, min(rect.width,rect.height)*0.1)]).applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 18]).cropped(to: rect)
            result = hidden.composited(over: result)
        }
        let radius = CGFloat(options.haloRadius)*size.width/1920
        let color: CIColor
        switch options.haloColor { case "Mint": color = CIColor(red: 0.2, green: 1, blue: 0.7, alpha: 0.28); case "Orange": color = CIColor(red: 1, green: 0.6, blue: 0.15, alpha: 0.3); case "Pink": color = CIColor(red: 1, green: 0.25, blue: 0.65, alpha: 0.3); default: color = CIColor(red: 0.15, green: 0.6, blue: 1, alpha: 0.3) }
        if let point = RecorderGeometry.point(pointer.location, frame: frame, size: size), options.halo { result = circle(point, radius: max(radius, 8), color: color).composited(over: result) }
        let age = now-pointer.clickAt
        if options.clicks, age >= 0, age < 0.6, let point = RecorderGeometry.point(pointer.clickLocation, frame: frame, size: size) {
            let ringRadius = max(radius, 12)*(0.5+age*2)
            let ring = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(cgPoint: point), "inputRadius0": ringRadius-3, "inputRadius1": ringRadius, "inputColor0": CIColor.clear, "inputColor1": CIColor(red: 0.2,green: 0.65,blue: 1,alpha: 1-age/0.6)])!.outputImage!.cropped(to: CGRect(x:point.x-ringRadius,y:point.y-ringRadius,width:ringRadius*2,height:ringRadius*2))
            let clippedRing = ring.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: ring.extent), kCIInputMaskImageKey: circle(point, radius: ringRadius+1, color: .white)])
            result = clippedRing.composited(over: result)
        }
        if options.zoom {
            let target = RecorderGeometry.point(pointer.location, frame: frame, size: size) ?? center ?? CGPoint(x:size.width/2,y:size.height/2)
            if let old = center { center = CGPoint(x: old.x+(target.x-old.x)*0.16,y: old.y+(target.y-old.y)*0.16) } else { center = target }
            let crop = RecorderGeometry.zoomRect(center:center!,size:size,factor:options.zoomFactor)
            result = result.cropped(to:crop).transformed(by:CGAffineTransform(translationX:-crop.minX,y:-crop.minY)).transformed(by:CGAffineTransform(scaleX:size.width/crop.width,y:size.height/crop.height)).cropped(to:bounds)
        }
        if options.webcam, let camera {
            let diameter = max(72,size.width*0.16), margin = size.width*0.018
            let edge = min(camera.extent.width,camera.extent.height)
            let crop = CGRect(x:camera.extent.midX-edge/2,y:camera.extent.midY-edge/2,width:edge,height:edge)
            let rect = CGRect(x:size.width-diameter-margin,y:margin,width:diameter,height:diameter)
            let bubble = camera.cropped(to:crop).transformed(by:CGAffineTransform(translationX:-crop.minX,y:-crop.minY)).transformed(by:CGAffineTransform(scaleX:diameter/edge,y:diameter/edge)).transformed(by:CGAffineTransform(translationX:rect.minX,y:rect.minY))
            let alpha = circle(CGPoint(x:rect.midX,y:rect.midY),radius:diameter/2,color:CIColor.white)
            result = bubble.applyingFilter("CIBlendWithAlphaMask",parameters:[kCIInputBackgroundImageKey:result,kCIInputMaskImageKey:alpha]).cropped(to:bounds)
        }
        if options.shortcuts, !pointer.shortcut.isEmpty, now-pointer.shortcutAt >= 0, now-pointer.shortcutAt < 1.5, let label = shortcutImage(pointer.shortcut) {
            let scale = size.width/1920
            let transform = CGAffineTransform(scaleX:scale,y:scale).concatenating(CGAffineTransform(translationX:24*scale,y:24*scale))
            result = label.transformed(by:transform).composited(over:result)
        }
        return result.cropped(to: bounds)
    }
    private func circle(_ center: CGPoint, radius: CGFloat, color: CIColor) -> CIImage {
        CIFilter(name:"CIRadialGradient",parameters:["inputCenter":CIVector(cgPoint:center),"inputRadius0":max(radius-1,0),"inputRadius1":radius,"inputColor0":color,"inputColor1":CIColor.clear])!.outputImage!
    }
    private func shortcutImage(_ label: String) -> CIImage? {
        if label == cachedLabel { return cachedImage }
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:30,weight:.semibold),.foregroundColor:NSColor.white]
        let text = NSAttributedString(string:label,attributes:attributes), textSize = text.size()
        let image = NSImage(size:NSSize(width:textSize.width+36,height:54),flipped:false) { rect in
            NSColor(calibratedWhite:0.05,alpha:0.85).setFill(); NSBezierPath(roundedRect:rect,xRadius:12,yRadius:12).fill(); text.draw(at:NSPoint(x:18,y:9)); return true
        }
        var rect = CGRect(origin:.zero,size:image.size)
        cachedLabel = label; cachedImage = image.cgImage(forProposedRect:&rect,context:nil,hints:nil).map { CIImage(cgImage:$0) }; return cachedImage
    }
}

enum RecorderFiles {
    static func publish(_ temporary: URL, to destination: URL) throws {
        // Exclusive hard link in the same chosen folder: never overwrite a file created during recording.
        guard link(temporary.path,destination.path) == 0 else { throw RecorderProblem(message:"Could not save without replacing an existing file: \(String(cString:strerror(errno))). The finished recording is kept at \(temporary.path).") }
        try? FileManager.default.removeItem(at:temporary)
    }
    static func export(_ source: URL, to destination: URL, range: CMTimeRange? = nil, mixAudio: Bool = false) async throws {
        let asset = AVURLAsset(url:source)
        guard let session = AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetHighestQuality) else { throw RecorderProblem(message:"Could not prepare MP4 export.") }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".orbit-\(UUID().uuidString).mp4")
        session.shouldOptimizeForNetworkUse = true
        if let range { session.timeRange = range }
        if mixAudio {
            let tracks = try await asset.loadTracks(withMediaType:.audio)
            if !tracks.isEmpty {
                let mix = AVMutableAudioMix()
                mix.inputParameters = tracks.map { track in let p = AVMutableAudioMixInputParameters(track:track); p.setVolume(tracks.count > 1 ? 0.7 : 1,at:.zero); return p }; session.audioMix = mix
            }
        }
        do {
            if #available(macOS 15.0, *) { try await session.export(to:temporary,as:.mp4) }
            else { session.outputURL = temporary; session.outputFileType = .mp4; await session.export(); guard session.status == .completed else { throw session.error ?? RecorderProblem(message:"MP4 export did not finish.") } }
        } catch { try? FileManager.default.removeItem(at:temporary); throw error }
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:temporary.path)
        try publish(temporary,to:destination)
    }
}
