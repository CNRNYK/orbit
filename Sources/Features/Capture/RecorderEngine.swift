import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreImage
@preconcurrency import CoreMedia

private struct RecorderSampleTransfer: @unchecked Sendable { let buffer: CMSampleBuffer }

final class RecorderEngine: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label:"io.orbit.recorder.media",qos:.userInitiated)
    let url: URL, options: RecorderOptions, size: CGSize, tracker: RecorderInputTracker
    private let writer: AVAssetWriter, video: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var systemInput: AVAssetWriterInput?, micInput: AVAssetWriterInput?
    private let context = CIContext(options:[.cacheIntermediates:false])
    private let compositor: RecorderCompositor
    private var timeline = RecorderTimeline(), lastTime = CMTime.zero
    private var latest: CIImage?, camera: CIImage?, frame: CGRect
    private var timer: DispatchSourceTimer?, stream: SCStream?, devices: AVCaptureSession?, cameraOutput: AVCaptureVideoDataOutput?, micOutput: AVCaptureAudioDataOutput?
    private var sessionStarted = false, closing = false, reportedError = false
    private var trackWindowFrame = false
    private var runtimeObserver: NSObjectProtocol?
    var onFrameChanged: (@Sendable (CGRect) -> Void)?
    var onFailure: (@Sendable (String) -> Void)?
    init(url: URL, options: RecorderOptions, size: CGSize, frame: CGRect, tracker: RecorderInputTracker, annotations: AnnotationBuffer? = nil) throws {
        self.url = url; self.options = options; self.size = size; self.frame = frame; self.tracker = tracker; compositor = RecorderCompositor(options:options); compositor.annotations = annotations
        writer = try AVAssetWriter(outputURL:url,fileType:.mov)
        video = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:Int(size.width),AVVideoHeightKey:Int(size.height),AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:max(1_500_000,Int(size.width*size.height*3)),AVVideoExpectedSourceFrameRateKey:options.fps,AVVideoMaxKeyFrameIntervalKey:options.fps*2]])
        video.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:video,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:Int(size.width),kCVPixelBufferHeightKey as String:Int(size.height),kCVPixelBufferIOSurfacePropertiesKey as String:[:]])
        super.init()
        guard writer.canAdd(video) else { throw RecorderProblem(message:"Video encoder could not be configured.") }; writer.add(video)
        if options.systemAudio { systemInput = try audioInput(channels:2) }
        if options.microphone { micInput = try audioInput(channels:1) }
        guard writer.startWriting() else { throw writer.error ?? RecorderProblem(message:"Video encoder could not start.") }
    }
    private func audioInput(channels: Int) throws -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:channels,AVEncoderBitRateKey:128000])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderProblem(message:"Audio encoder could not be configured.") }; writer.add(input); return input
    }
    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, trackingWindow: Bool) async throws {
        trackWindowFrame = trackingWindow
        let stream = SCStream(filter:filter,configuration:configuration,delegate:self); self.stream = stream
        try stream.addStreamOutput(self,type:.screen,sampleHandlerQueue:queue)
        if options.systemAudio { try stream.addStreamOutput(self,type:.audio,sampleHandlerQueue:queue) }
        try await setupDevices()
        try await stream.startCapture()
        await withCheckedContinuation { continuation in queue.async { [self] in
            let timer = DispatchSource.makeTimerSource(queue:self.queue); self.timer = timer
            timer.schedule(deadline:.now(),repeating:1.0/Double(self.options.fps)); timer.setEventHandler { [weak self] in self?.tick(at:CMClockGetTime(CMClockGetHostTimeClock())) }; timer.resume(); continuation.resume()
        } }
    }
    private func setupDevices() async throws {
        guard options.webcam || options.microphone else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in queue.async { [self] in
            do {
                let session = AVCaptureSession(); session.beginConfiguration(); session.sessionPreset = .medium
                if self.options.webcam {
                    guard let device = AVCaptureDevice.default(for:.video) else { throw RecorderProblem(message:"No camera is available.") }
                    let input = try AVCaptureDeviceInput(device:device), output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]; output.alwaysDiscardsLateVideoFrames = true; output.setSampleBufferDelegate(self,queue:self.queue)
                    guard session.canAddInput(input), session.canAddOutput(output) else { throw RecorderProblem(message:"Camera could not be configured.") }
                    session.addInput(input); session.addOutput(output); self.cameraOutput = output
                }
                if self.options.microphone {
                    guard let device = AVCaptureDevice.default(for:.audio) else { throw RecorderProblem(message:"No microphone is available.") }
                    let input = try AVCaptureDeviceInput(device:device), output = AVCaptureAudioDataOutput(); output.setSampleBufferDelegate(self,queue:self.queue)
                    guard session.canAddInput(input), session.canAddOutput(output) else { throw RecorderProblem(message:"Microphone could not be configured.") }
                    session.addInput(input); session.addOutput(output); self.micOutput = output
                }
                session.commitConfiguration(); self.devices = session
                self.runtimeObserver = NotificationCenter.default.addObserver(forName:AVCaptureSession.runtimeErrorNotification,object:session,queue:nil) { [weak self] note in
                    let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "The camera or microphone became unavailable."
                    guard let self else { return }; self.queue.async { if !self.closing { self.fail(message) } }
                }
                session.startRunning(); continuation.resume()
            } catch { continuation.resume(throwing:error) }
        } }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { queue.async { if !self.closing { self.fail(error.localizedDescription) } } }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !closing, sampleBuffer.isValid else { return }
        if type == .audio { appendAudio(sampleBuffer,to:systemInput); return }
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]])?.first,
              let raw = info[.status] as? Int, let status = SCFrameStatus(rawValue:raw) else { return }
        if status == .blank || status == .suspended || status == .stopped { fail("The capture source became blank or unavailable."); return }
        guard status == .complete, let image = sampleBuffer.imageBuffer else { return }
        latest = CIImage(cvPixelBuffer:image)
        if trackWindowFrame, let dictionary = info[.screenRect] as? NSDictionary, let rect = CGRect(dictionaryRepresentation:dictionary), rect.width > 0, rect.height > 0 { if frame != rect { frame = rect; onFrameChanged?(rect) } }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !closing else { return }
        if output === cameraOutput, let buffer = sampleBuffer.imageBuffer { camera = CIImage(cvPixelBuffer:buffer) }
        else if output === micOutput { appendAudio(sampleBuffer,to:micInput) }
    }
    private func tick(at hostTime: CMTime) {
        guard !closing, let latest, timeline.pausedAt == nil, video.isReadyForMoreMediaData, let pts = timeline.videoTime(at:hostTime) else { return }
        if !sessionStarted { writer.startSession(atSourceTime:.zero); sessionStarted = true }
        guard let pool = adaptor.pixelBufferPool else { fail("The video buffer pool is unavailable."); return }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer) == kCVReturnSuccess, let buffer else { fail("Could not allocate a recording frame."); return }
        let image = compositor.image(latest,frame:frame,size:size,pointer:tracker.snapshot(),camera:camera,now:ProcessInfo.processInfo.systemUptime)
        context.render(image,to:buffer,bounds:CGRect(origin:.zero,size:size),colorSpace:CGColorSpaceCreateDeviceRGB())
        if !adaptor.append(buffer,withPresentationTime:pts) { fail(writer.error?.localizedDescription ?? "The video encoder stopped accepting frames.") }; lastTime = pts
    }
    private func appendAudio(_ sample: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard !closing, sessionStarted, let input, input.isReadyForMoreMediaData, let pts = timeline.audioTime(at:sample.presentationTimeStamp) else { return }
        var timing = CMSampleTimingInfo(duration:sample.duration,presentationTimeStamp:pts,decodeTimeStamp:.invalid)
        var adjusted: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator:kCFAllocatorDefault,sampleBuffer:sample,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleBufferOut:&adjusted) == noErr, let adjusted else { fail("Audio timing could not be aligned."); return }
        if !input.append(adjusted) { fail(writer.error?.localizedDescription ?? "Audio encoding failed.") }
    }
    private func fail(_ message: String) { guard !reportedError else { return }; reportedError = true; onFailure?(message) }
    func pause(_ paused: Bool) { queue.async { let now = CMClockGetTime(CMClockGetHostTimeClock()); if paused { self.timeline.pause(at:now) } else { self.timeline.resume(at:now) } } }
    func finish() async throws {
        await withCheckedContinuation { continuation in queue.async { self.closing = true; self.timer?.cancel(); self.timer = nil; self.devices?.stopRunning(); self.devices = nil; if let observer = self.runtimeObserver { NotificationCenter.default.removeObserver(observer) }; self.runtimeObserver = nil; continuation.resume() } }
        try? await stream?.stopCapture(); stream = nil
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in queue.async {
            guard self.sessionStarted else { self.writer.cancelWriting(); continuation.resume(throwing:RecorderProblem(message:"No screen frames were received. Check Screen Recording permission and try again.")); return }
            self.writer.endSession(atSourceTime:self.lastTime+CMTime(value:1,timescale:CMTimeScale(self.options.fps)))
            self.video.markAsFinished(); self.systemInput?.markAsFinished(); self.micInput?.markAsFinished()
            self.writer.finishWriting { if self.writer.status == .completed { continuation.resume() } else { continuation.resume(throwing:self.writer.error ?? RecorderProblem(message:"The recording could not be finalized.")) } }
        } }
    }
    // Permission-free integration fixture: exercises the real compositor, encoder and timestamps.
    func syntheticAudio(_ sample: CMSampleBuffer, microphone: Bool) async { let transfer = RecorderSampleTransfer(buffer:sample); await withCheckedContinuation { continuation in queue.async { self.appendAudio(transfer.buffer,to:microphone ? self.micInput : self.systemInput); continuation.resume() } } }
    func syntheticFrame(_ image: CIImage, at time: CMTime) async { await withCheckedContinuation { continuation in queue.async { self.latest = image; self.tick(at:time); continuation.resume() } } }
}
