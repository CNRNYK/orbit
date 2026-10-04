import Foundation
import SwiftUI
import AVKit
import ScreenCaptureKit
import AppKit
import CoreImage
import AVFoundation
import AudioToolbox

@MainActor enum RecorderTests {
    static func run() async throws {
        var captureRequests = 0
        let accessState = RecorderState()
        accessState.notice = "Previous permission warning"
        accessState.requestSources = { captureRequests += 1; return RecorderSourceSnapshot(displays:[],windows:[]) }
        let refreshed = await accessState.loadSources()
        precondition(refreshed && captureRequests == 1 && accessState.notice == nil && !accessState.loadingSources, "Actual source refresh must accept ScreenCaptureKit success without a legacy gate")
        let denied = NSError(domain:SCStreamErrorDomain,code:SCStreamError.Code.userDeclined.rawValue)
        accessState.requestSources = { throw denied }
        accessState.displayID = 99; accessState.windowID = 42; accessState.area = CGRect(x:0,y:0,width:100,height:100); accessState.options.masks = [RecorderMask(rect:CGRect(x:0,y:0,width:0.5,height:0.5),cover:true)]
        let refused = await accessState.loadSources()
        precondition(!refused && !accessState.loadingSources && accessState.displayID == 0 && accessState.windowID == 0 && accessState.area == nil && accessState.options.masks.isEmpty)
        precondition(accessState.notice?.contains("running copy") == true && accessState.notice?.contains("-3801") == true)
        let unrelated = NSError(domain:NSCocoaErrorDomain,code:42,userInfo:[NSLocalizedDescriptionKey:"Source unavailable"])
        accessState.requestSources = { throw unrelated }
        let unavailable = await accessState.loadSources()
        precondition(!unavailable && accessState.notice?.contains("Source unavailable") == true && accessState.notice?.contains("denied screen access") == false, "Source failures must not be mislabeled as denied permission")
        accessState.requestSources = { RecorderSourceSnapshot(displays:[],windows:[]) }
        let retry = await accessState.loadSources()
        precondition(retry && accessState.notice == nil, "Successful retry must clear stale errors")
        print("PASS: actual recorder source refresh, success/retry, denied access diagnostics, non-permission errors and stale-selection clearing")
        let defaults = RecorderOptions()
        precondition(!defaults.microphone && !defaults.systemAudio && !defaults.webcam && !defaults.shortcuts && !defaults.zoom)
        let frame = CGRect(x:-1280,y:50,width:1280,height:720)
        let rect = RecorderGeometry.normalized(CGRect(x:-1200,y:100,width:200,height:100),inside:frame)!
        precondition(abs(rect.minX-0.0625)<0.0001 && abs(rect.minY-50/720.0)<0.0001)
        precondition(RecorderGeometry.normalized(CGRect(x:500,y:500,width:10,height:10),inside:frame) == nil)
        let size = RecorderGeometry.outputSize(CGSize(width:3840,height:2160),maxWidth:1920)
        precondition(size == CGSize(width:1920,height:1080))
        precondition(RecorderGeometry.outputSize(CGSize(width:2160,height:3840),maxWidth:1920).height == 1920)
        let point = RecorderGeometry.point(CGPoint(x:-640,y:410),frame:frame,size:size)!
        precondition(point == CGPoint(x:960,y:540))
        for center in [CGPoint(x:-100,y:-100),CGPoint(x:10000,y:10000)] { let crop = RecorderGeometry.zoomRect(center:center,size:size,factor:1.4); precondition(CGRect(origin:.zero,size:size).contains(crop)) }
        var timeline = RecorderTimeline()
        precondition(timeline.audioTime(at:CMTime(seconds:10,preferredTimescale:600)) == nil)
        precondition(timeline.videoTime(at:CMTime(seconds:10,preferredTimescale:600)) == .zero)
        timeline.pause(at:CMTime(seconds:11,preferredTimescale:600)); precondition(timeline.videoTime(at:CMTime(seconds:12,preferredTimescale:600)) == nil)
        timeline.resume(at:CMTime(seconds:14,preferredTimescale:600)); precondition(timeline.videoTime(at:CMTime(seconds:15,preferredTimescale:600))?.seconds == 2)
        precondition(RecorderKeys.label(code:8,flags:[]) == nil && RecorderKeys.label(code:8,flags:.maskAlternate) == nil)
        precondition(RecorderKeys.label(code:8,flags:.maskCommand) == "⌘C" && RecorderKeys.label(code:9,flags:[.maskCommand,.maskShift]) == "⇧⌘V")
        var options = defaults; options.halo = false; options.clicks = false; options.masks = [RecorderMask(rect:CGRect(x:0.25,y:0.25,width:0.5,height:0.5),cover:true)]
        let bounds = CGRect(x:0,y:0,width:320,height:180), input = CIImage(color:CIColor(red:1,green:0,blue:0)).cropped(to:bounds)
        let hidden = RecorderCompositor(options:options).image(input,frame:bounds,size:bounds.size,pointer:RecorderPointer(),camera:nil,now:0)
        let pixels = rgba(hidden,size:bounds.size)
        precondition(pixels[(90*320+160)*4] < 120 && pixels[(10*320+10)*4] > 200, "Privacy cover must be baked into frames without changing unrelated areas")
        options.webcam = true; let camera = CIImage(color:CIColor(red:0,green:0,blue:1)).cropped(to:CGRect(x:0,y:0,width:100,height:100))
        let bubble = RecorderCompositor(options:options).image(input,frame:bounds,size:bounds.size,pointer:RecorderPointer(),camera:camera,now:0)
        let bubblePixels = rgba(bubble,size:bounds.size)
        precondition(bubblePixels[(140*320+280)*4+2] > 150, "Camera must be composited into the output")
        var effects = RecorderOptions(); effects.halo = true; effects.clicks = false
        var pointer = RecorderPointer(); pointer.location = CGPoint(x:160,y:90)
        let halo = RecorderCompositor(options:effects).image(input,frame:bounds,size:bounds.size,pointer:pointer,camera:nil,now:10)
        precondition(rgba(halo,size:bounds.size)[(90*320+160)*4+2] > 20, "Halo must be visible in the actual frame")
        effects.halo = false; effects.clicks = true; pointer.clickLocation = CGPoint(x:160,y:90); pointer.clickAt = 9.75
        let rings = rgba(RecorderCompositor(options:effects).image(input,frame:bounds,size:bounds.size,pointer:pointer,camera:nil,now:10),size:bounds.size)
        precondition(rings[(90*320+171)*4+2] > 10 && rings[(102*320+172)*4+2] < 10, "Click effect must form a ring without square corners")
        effects.clicks = false; effects.zoom = true; effects.zoomFactor = 2; pointer.location = CGPoint(x:240,y:90)
        let split = CIImage(color:CIColor(red:0,green:1,blue:0)).cropped(to:CGRect(x:160,y:0,width:160,height:180)).composited(over:input)
        let zoom = rgba(RecorderCompositor(options:effects).image(split,frame:bounds,size:bounds.size,pointer:pointer,camera:nil,now:10),size:bounds.size)
        precondition(zoom[(90*320+10)*4+1] > 200 && zoom[(90*320+10)*4] < 20, "Cursor-follow zoom must crop and scale the source")
        effects.zoom = false; effects.shortcuts = true; pointer.shortcut = "⌘C"; pointer.shortcutAt = 10
        let label = rgba(RecorderCompositor(options:effects).image(input,frame:bounds,size:bounds.size,pointer:pointer,camera:nil,now:10),size:bounds.size)
        precondition(label != rgba(input,size:bounds.size), "Shortcut badge must be baked into the actual frame")
        effects.shortcuts = false; effects.masks = [RecorderMask(rect:CGRect(x:0.35,y:0.25,width:0.3,height:0.5),cover:false)]
        let blurred = rgba(RecorderCompositor(options:effects).image(split,frame:bounds,size:bounds.size,pointer:pointer,camera:nil,now:10),size:bounds.size)
        precondition(blurred != rgba(split,size:bounds.size), "Blur must alter the selected region")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitRecorderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]); defer { try? FileManager.default.removeItem(at:folder) }
        let compactFolder = folder.appendingPathComponent("Orbit Recordings",isDirectory:true)
        let compactFirst = try RecorderState.compactDestination(in:compactFolder), compactSecond = try RecorderState.compactDestination(in:compactFolder)
        precondition(compactFirst != compactSecond && compactFirst.pathExtension == "mp4" && FileManager.default.fileExists(atPath:compactFolder.path))
        try Data("previous recording".utf8).write(to:compactFirst)
        let compactThird = try RecorderState.compactDestination(in:compactFolder)
        precondition(compactThird != compactFirst && !FileManager.default.fileExists(atPath:compactThird.path), "Compact recordings must receive distinct, non-overwriting paths")
        let old = folder.appendingPathComponent("existing.mp4"), temporary = folder.appendingPathComponent("ready.mp4")
        try Data("original".utf8).write(to:old); try Data("new".utf8).write(to:temporary)
        do { try RecorderFiles.publish(temporary,to:old); preconditionFailure("Existing output must never be replaced") } catch { let original = try Data(contentsOf:old); precondition(original == Data("original".utf8)) }
        options.webcam = false; options.systemAudio = true; options.microphone = true
        let raw = folder.appendingPathComponent("test.mov"), output = folder.appendingPathComponent("test.mp4"), trimmed = folder.appendingPathComponent("trimmed.mp4")
        let annotationBuffer = AnnotationBuffer()
        annotationBuffer.replace([OrbitAnnotation(tool:"Pen",points:[CGPoint(x:0.1,y:0.1),CGPoint(x:0.9,y:0.1)],color:"Blue",width:20),OrbitAnnotation(tool:"Pen",points:[CGPoint(x:0.1,y:0.5),CGPoint(x:0.9,y:0.5)],color:"Blue",width:20)])
        let engine = try RecorderEngine(url:raw,options:options,size:bounds.size,frame:bounds,tracker:RecorderInputTracker(),annotations:annotationBuffer)
        for index in 0..<30 {
            let time = CMTime(seconds:10+Double(index)/30,preferredTimescale:48000)
            await engine.syntheticFrame(input,at:time)
            await engine.syntheticAudio(try audio(at:time,channels:2,frequency:440),microphone:false)
            await engine.syntheticAudio(try audio(at:time,channels:1,frequency:660),microphone:true)
            try await Task.sleep(nanoseconds:10_000_000)
        }
        try await engine.finish()
        let sourceAudio = try await AVURLAsset(url:raw).loadTracks(withMediaType:.audio); precondition(sourceAudio.count == 2, "Both microphone and system audio must reach the writer")
        try await RecorderFiles.export(raw,to:output,mixAudio:true)
        let asset = AVURLAsset(url:output), duration = try await asset.load(.duration).seconds
        precondition(duration > 0.8 && duration < 1.2)
        let tracks = try await asset.loadTracks(withMediaType:.video); precondition(tracks.count == 1)
        let sound = try await asset.loadTracks(withMediaType:.audio); precondition(sound.count == 1, "Export must mix both audio sources into a single playable track")
        let reader = try AVAssetReader(asset:asset)
        let videoReader = AVAssetReaderTrackOutput(track:tracks[0],outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]); reader.add(videoReader); precondition(reader.startReading())
        guard let sample = videoReader.copyNextSampleBuffer(), let buffer = sample.imageBuffer else { preconditionFailure("MP4 must decode") }
        let decoded = rgba(CIImage(cvPixelBuffer:buffer),size:bounds.size); precondition(decoded[(90*320+160)*4] < 120, "Saved MP4 must contain the privacy cover")
        let decodedCG = try AVAssetImageGenerator(asset:asset).copyCGImage(at:.zero,actualTime:nil)
        let thumbnail = NSBitmapImageRep(cgImage:decodedCG)
        let topLine = thumbnail.colorAt(x:50,y:18)!.usingColorSpace(.deviceRGB)!
        let unrelatedBottom = thumbnail.colorAt(x:50,y:162)!.usingColorSpace(.deviceRGB)!
        precondition(topLine.blueComponent > 0.4 && unrelatedBottom.blueComponent < 0.4, "Saved video annotations must remain at the chosen top-of-frame location")
        precondition(decoded[(90*320+160)*4+2] < 120, "Privacy cover must remain above video annotations")
        reader.cancelReading()
        try await RecorderFiles.export(output,to:trimmed,range:CMTimeRange(start:CMTime(seconds:0.2,preferredTimescale:600),duration:CMTime(seconds:0.5,preferredTimescale:600)))
        let removed = folder.appendingPathComponent("removed.mp4")
        let originalDuration = try await AVURLAsset(url:output).load(.duration).seconds
        let cut = CMTimeRange(start:CMTime(seconds:0.2,preferredTimescale:600),duration:CMTime(seconds:0.3,preferredTimescale:600))
        try await RecorderFiles.export(output,to:removed,removing:cut)
        let removedAsset = AVURLAsset(url:removed)
        let removedDuration = try await removedAsset.load(.duration).seconds
        precondition(abs(removedDuration-(originalDuration-0.3)) < 0.1)
        let originalAudio = try await AVURLAsset(url:output).loadTracks(withMediaType:.audio)
        let removedAudio = try await removedAsset.loadTracks(withMediaType:.audio)
        precondition(originalAudio.count == removedAudio.count && FileManager.default.fileExists(atPath:output.path))
        let removedGenerator = AVAssetImageGenerator(asset:removedAsset)
        _ = try removedGenerator.copyCGImage(at:CMTime(seconds:0.4,preferredTimescale:600),actualTime:nil)
        do { try await RecorderFiles.export(output,to:folder.appendingPathComponent("invalid.mp4"),removing:CMTimeRange(start:.zero,duration:CMTime(seconds:originalDuration,preferredTimescale:600))); preconditionFailure("Removing the complete video must fail") } catch {}
        let trimDuration = try await AVURLAsset(url:trimmed).load(.duration).seconds
        precondition(trimDuration > 0.4 && trimDuration < 0.65 && FileManager.default.fileExists(atPath:output.path))
        let silentRaw = folder.appendingPathComponent("silent.mov"), silentMP4 = folder.appendingPathComponent("silent.mp4")
        let silentEngine = try RecorderEngine(url:silentRaw,options:RecorderOptions(),size:bounds.size,frame:bounds,tracker:RecorderInputTracker())
        for index in 0..<10 { await silentEngine.syntheticFrame(input,at:CMTime(seconds:20+Double(index)/30,preferredTimescale:600)); try await Task.sleep(nanoseconds:10_000_000) }
        try await silentEngine.finish(); try await RecorderFiles.export(silentRaw,to:silentMP4,mixAudio:true)
        let silentTracks = try await AVURLAsset(url:silentMP4).loadTracks(withMediaType:.audio); precondition(silentTracks.isEmpty, "Default recording must export successfully without audio")
        // Exercise the post-recording SwiftUI branch that previously aborted in
        // _AVKit_SwiftUI; codec-only tests never instantiated its player view.
        _ = NSApplication.shared
        let previewState = RecorderState()
        previewState.preview = true
        previewState.tab = "Edit"
        previewState.options = RecorderOptions()
        previewState.player = AVPlayer(url:output)
        previewState.recordingURL = output
        previewState.duration = duration
        previewState.trimEnd = duration
        let hosting = NSHostingView(rootView:RecorderView(state:previewState))
        hosting.frame = NSRect(x:0,y:0,width:1180,height:1100)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:100_000_000)
        func players(in view:NSView) -> [AVPlayerView] { (view as? AVPlayerView).map { [$0] } ?? view.subviews.flatMap { players(in:$0) } }
        let nativePlayers = players(in:hosting)
        precondition(nativePlayers.count == 1 && nativePlayers[0].player === previewState.player, "Completed-recording UI must host its native player")
        precondition(nativePlayers[0].controlsStyle == .inline)
        let originalPlayer = previewState.player!
        for _ in 0..<30 {
            if originalPlayer.currentItem?.status != .unknown { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        precondition(originalPlayer.currentItem?.status == .readyToPlay, "Generated MP4 must become playable in the preview")
        originalPlayer.isMuted = true
        originalPlayer.play()
        try await Task.sleep(nanoseconds:250_000_000)
        precondition(originalPlayer.currentTime().seconds > 0, "Preview playback must advance")
        precondition(previewState.startLabel == "Start recording"); previewState.options.mode = "Selected area"; precondition(previewState.startLabel == "Select area & record")
        previewState.player = AVPlayer(url:trimmed)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:100_000_000)
        precondition(players(in:hosting).first?.player === previewState.player && originalPlayer.rate == 0, "Changing the recording must update the player")
        let detached = players(in:hosting).first!
        RecorderPlayerView.dismantleNSView(detached,coordinator:())
        precondition(detached.player == nil, "Closing preview must release playback")
        let editor = RecorderState()
        await editor.showRecording(output)
        precondition(editor.tab == "Edit" && editor.recordingURL == output && !editor.selectionChanged)
        editor.moveHandle("Start",to:0.2); editor.moveHandle("End",to:0.7)
        precondition(editor.trimStart == 0.2 && editor.trimEnd == 0.7 && editor.selectionChanged)
        try await Task.sleep(nanoseconds:150_000_000)
        precondition(abs(editor.player!.currentTime().seconds - (0.7-editor.minimumRange)) < 0.05, "The end handle must seek the last kept frame")
        editor.moveHandle("Start",to:0.3)
        try await Task.sleep(nanoseconds:150_000_000)
        precondition(abs(editor.player!.currentTime().seconds-0.3) < 0.05, "The start handle must seek the first kept frame")
        editor.moveHandle("Start",to:9); precondition(editor.trimStart < editor.trimEnd)
        editor.moveHandle("End",to:-1); precondition(editor.trimEnd > editor.trimStart)
        editor.resetEdit(); precondition(!editor.selectionChanged)
        editor.moveHandle("Start",to:0.2); editor.moveHandle("End",to:0.7)
        await editor.previewEdit()
        precondition(editor.editPreview && editor.recordingURL == output && editor.editPreviewURL != output)
        let previewFile = editor.editPreviewURL!
        let previewDuration = try await AVURLAsset(url:previewFile).load(.duration).seconds
        precondition(abs(previewDuration-0.5) < 0.08)
        editor.moveHandle("End",to:0.8)
        precondition(!editor.editPreview && !FileManager.default.fileExists(atPath:previewFile.path))
        editor.removeSelection = true; await editor.previewEdit()
        let removalDuration = try await AVURLAsset(url:editor.editPreviewURL!).load(.duration).seconds
        precondition(abs(removalDuration-(editor.duration-0.6)) < 0.08)
        editor.restoreOriginal(); await editor.thumbnailTask?.value
        precondition(!editor.thumbnails.isEmpty, "Generated video must provide real timeline thumbnails")
        precondition(FileManager.default.fileExists(atPath:output.path))
        precondition(RecorderEditPlan.make(duration:1,start:0,end:1,remove:true) == nil)
        precondition(RecorderEditPlan.make(duration:1,start:0.8,end:0.2,remove:false) == nil)
        precondition(RecorderEditPlan.make(duration:.nan,start:0,end:1,remove:false) == nil)
        let short = RecorderState(); short.duration = 0.01; short.trimEnd = 0.01; short.moveHandle("Start",to:1)
        precondition(short.trimStart == 0 && short.trimEnd == 0.01)
        print("PASS: editor tab, both handle seeks, crossing guards, unchanged/invalid selections, real keep/remove previews, temporary cleanup and original preservation")
        print("PASS: completed-recording player UI, native playback controls, recording replacement and playback teardown")
        let store = Store(preview:true,persistSelection:false); store.recorderState.phase = .recording; store.recorderState.elapsed = 65
        precondition(store.locked && MenuBarState(store:store).operating && store.recorderState.elapsedLabel == "01:05")
        store.recorderState.phase = .idle; store.busy = true; precondition(!store.recorderState.canBegin())
        print("PASS: recorder geometry/multi-display coordinates, safe defaults, pause timing, shortcut privacy, baked masks/webcam, exclusive file saving, real MP4 encoding, two-source audio mix, decoding and non-destructive trim")
    }
    static func rgba(_ image: CIImage,size:CGSize) -> [UInt8] { var bytes = [UInt8](repeating:0,count:Int(size.width*size.height)*4); bytes.withUnsafeMutableBytes { CIContext().render(image,toBitmap:$0.baseAddress!,rowBytes:Int(size.width)*4,bounds:CGRect(origin:.zero,size:size),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB()) }; return bytes }
    static func audio(at time: CMTime,channels:Int,frequency:Double) throws -> CMSampleBuffer {
        let count = 1600; var description = AudioStreamBasicDescription(mSampleRate:48000,mFormatID:kAudioFormatLinearPCM,mFormatFlags:kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,mBytesPerPacket:UInt32(channels*4),mFramesPerPacket:1,mBytesPerFrame:UInt32(channels*4),mChannelsPerFrame:UInt32(channels),mBitsPerChannel:32,mReserved:0)
        var format: CMAudioFormatDescription?; guard CMAudioFormatDescriptionCreate(allocator:kCFAllocatorDefault,asbd:&description,layoutSize:0,layout:nil,magicCookieSize:0,magicCookie:nil,extensions:nil,formatDescriptionOut:&format) == noErr else { throw RecorderProblem(message:"Fixture audio format failed") }
        let values = (0..<count*channels).map { index in Float(sin(2*Double.pi*frequency*(time.seconds+Double(index/channels)/48000))*0.15) }
        var block: CMBlockBuffer?; CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:values.count*4,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:values.count*4,flags:0,blockBufferOut:&block)
        values.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with:$0.baseAddress!,blockBuffer:block!,offsetIntoDestination:0,dataLength:values.count*4) }
        var timing = CMSampleTimingInfo(duration:CMTime(value:1,timescale:48000),presentationTimeStamp:time,decodeTimeStamp:.invalid), sample: CMSampleBuffer?
        let result = CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:format,sampleCount:count,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:0,sampleSizeArray:nil,sampleBufferOut:&sample)
        guard result == noErr, let sample else { throw RecorderProblem(message:"Fixture audio sample failed: \(result)") }; return sample
    }
}
