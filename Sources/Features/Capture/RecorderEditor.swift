import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct RecorderEditPlan {
    let duration: Double, start: Double, end: Double
    let remove: Bool
    var changed: Bool { start > 0.0001 || end < duration - 0.0001 }
    var resultDuration: Double { remove ? duration - (end-start) : end-start }
    var range: CMTimeRange { CMTimeRange(start:CMTime(seconds:start,preferredTimescale:60000),duration:CMTime(seconds:end-start,preferredTimescale:60000)) }
    static func make(duration:Double,start:Double,end:Double,remove:Bool) -> Self? {
        guard duration.isFinite, start.isFinite, end.isFinite, duration > 0, start >= 0, end <= duration, end > start else { return nil }
        let plan = Self(duration:duration,start:start,end:end,remove:remove)
        return plan.resultDuration > 0.0001 ? plan : nil
    }
}

@MainActor extension RecorderState {
    var editPlan: RecorderEditPlan? { RecorderEditPlan.make(duration:duration,start:trimStart,end:trimEnd,remove:removeSelection) }
    var selectionChanged: Bool { editPlan?.changed == true }
    var minimumRange: Double { min(1/max(frameRate,1),duration) }
    static func timeLabel(_ seconds:Double) -> String { String(format:"%02d:%05.2f",max(0,Int(seconds)/60),max(0,seconds).truncatingRemainder(dividingBy:60)) }
    func clearEditPreview() {
        player?.pause(); player?.replaceCurrentItem(with:nil)
        if let editPreviewURL { try? FileManager.default.removeItem(at:editPreviewURL) }
        editPreviewURL = nil; editPreview = false
    }
    func restoreOriginal() {
        guard editPreview else { return }; clearEditPreview()
        if let recordingURL { player = AVPlayer(url:recordingURL) }
    }
    func moveHandle(_ handle:String,to seconds:Double) {
        guard !busy, duration > 0 else { return }
        restoreOriginal(); focusedHandle = handle
        if handle == "Start" { trimStart = min(max(seconds,0),max(0,trimEnd-minimumRange)) }
        else { trimEnd = max(min(seconds,duration),min(duration,trimStart+minimumRange)) }
        player?.pause(); player?.currentItem?.cancelPendingSeeks()
        // Seek to the last included frame for an exclusive end boundary.
        let point = handle == "Start" ? trimStart : max(trimStart,trimEnd-minimumRange)
        player?.seek(to:CMTime(seconds:point,preferredTimescale:60000),toleranceBefore:.zero,toleranceAfter:.zero)
    }
    func resetEdit() { guard !busy else { return }; restoreOriginal(); trimStart = 0; trimEnd = duration; moveHandle("Start",to:0) }
    func previewEdit() async {
        guard !preview, !busy, let recordingURL, let plan = editPlan, plan.changed else { return }
        editing = true; restoreOriginal(); player?.pause(); defer { editing = false }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("Orbit-edit-preview-\(UUID().uuidString).mp4")
        do {
            try await RecorderFiles.export(recordingURL,to:target,range:plan.remove ? nil : plan.range,removing:plan.remove ? plan.range : nil)
            editPreviewURL = target; editPreview = true; player = AVPlayer(url:target); player?.play()
        } catch { try? FileManager.default.removeItem(at:target); notice = error.localizedDescription }
    }
    func openVideo() {
        guard !busy, !preview else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = "Open video to edit"
        if panel.runModal() == .OK, let url = panel.url { editing = true; Task { await showRecording(url); editing = false } }
    }
    func chooseOutputFolder() {
        guard !busy, !preview else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.directoryURL = outputFolder
        if panel.runModal() == .OK, let url = panel.url { outputFolder = url; UserDefaults.standard.set(url.path,forKey:"orbit.recorder.folder") }
    }
}

struct RecorderEditor: View {
    @ObservedObject var state: RecorderState
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label("Video editor",systemImage:"scissors").font(.title2.bold()); Spacer(); Button("Open video",systemImage:"folder") { state.openVideo() }.disabled(state.busy) }
            if let player = state.player, let url = state.recordingURL {
                Group {
                    if state.preview, let poster = state.thumbnails.first { Image(nsImage:poster).resizable().scaledToFit().frame(maxWidth:.infinity).background(Color.black) }
                    else { RecorderPlayerView(player:player) }
                }.frame(height:220)
                HStack { Text(url.lastPathComponent).lineLimit(1); Spacer(); Text(state.editPreview ? "Edited preview" : "Original video").font(.caption).foregroundStyle(.secondary); Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }; Button("Copy file") { state.copyFile() } }
                Picker("Edit action",selection:$state.removeSelection) { Text("Keep selected range").tag(false); Text("Remove selected range").tag(true) }.pickerStyle(.segmented).disabled(state.busy).onChange(of:state.removeSelection) { _,_ in state.restoreOriginal() }
                RecorderRangeTimeline(state:state).frame(height:84).disabled(state.busy)
                HStack {
                    Text("Start \(RecorderState.timeLabel(state.trimStart)) · End \(RecorderState.timeLabel(state.trimEnd))").monospacedDigit()
                    Spacer()
                    Text("Result: \(RecorderState.timeLabel(state.editPlan?.resultDuration ?? 0))").bold().monospacedDigit()
                }.font(.caption)
                Text(state.removeSelection ? "The selected red range will be removed. The blue parts will be joined." : "The blue range will be kept. Everything outside it will be removed.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("Adjust",selection:$state.focusedHandle) { Text("Start").tag("Start"); Text("End").tag("End") }.frame(width:160)
                    Button { nudge(-1) } label: { Label("Previous frame",systemImage:"backward.frame") }.keyboardShortcut(.leftArrow,modifiers:[])
                    Button { nudge(1) } label: { Label("Next frame",systemImage:"forward.frame") }.keyboardShortcut(.rightArrow,modifiers:[])
                    Spacer(); Button("Reset selection") { state.resetEdit() }
                }.disabled(state.busy || state.duration <= 0)
                Text("Your original video stays unchanged.").font(.caption).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("No video yet",systemImage:"film",description:Text("Record a video or open an existing one to preview and trim it."))
            }
        }
    }
    func nudge(_ direction:Double) { state.moveHandle(state.focusedHandle,to:(state.focusedHandle == "Start" ? state.trimStart : state.trimEnd)+direction/max(state.frameRate,1)) }
}

struct RecorderEditActions: View {
    @ObservedObject var state: RecorderState
    var body: some View {
        HStack {
            if state.editPreview { Button("Back to original") { state.restoreOriginal() }.disabled(state.busy) }
            Button("Preview edit",systemImage:"play.rectangle") { Task { await state.previewEdit() } }.disabled(state.busy || !state.selectionChanged)
            Spacer()
            Button("Save edited copy",systemImage:"square.and.arrow.down") { Task { await state.trim(remove:state.removeSelection) } }.buttonStyle(.borderedProminent).disabled(state.busy || !state.selectionChanged)
        }
    }
}

struct RecorderRangeTimeline: View {
    @ObservedObject var state: RecorderState
    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width-28,1)
            let start = width*state.trimStart/max(state.duration,0.001)
            let end = width*state.trimEnd/max(state.duration,0.001)
            ZStack(alignment:.topLeading) {
                HStack(spacing:0) {
                    if state.thumbnails.isEmpty { Rectangle().fill(Color.secondary.opacity(0.15)) }
                    else { ForEach(Array(state.thumbnails.enumerated()),id:\.offset) { _,image in Image(nsImage:image).resizable().scaledToFill().frame(width:width/Double(state.thumbnails.count),height:56).clipped() } }
                }.frame(width:width,height:56).clipShape(RoundedRectangle(cornerRadius:6)).offset(x:14,y:20)
                Rectangle().fill(state.removeSelection ? Color.blue.opacity(0.2) : Color.black.opacity(0.5)).frame(width:start,height:56).offset(x:14,y:20)
                Rectangle().fill(state.removeSelection ? Color.red.opacity(0.4) : Color.blue.opacity(0.22)).frame(width:max(0,end-start),height:56).overlay(Rectangle().stroke(state.removeSelection ? Color.red : Color.blue,lineWidth:2)).offset(x:14+start,y:20)
                Rectangle().fill(state.removeSelection ? Color.blue.opacity(0.2) : Color.black.opacity(0.5)).frame(width:max(0,width-end),height:56).offset(x:14+end,y:20)
                if !state.editPreview {
                    Rectangle().fill(Color.white).frame(width:2,height:56).shadow(radius:2).offset(x:14+width*min(max(state.playhead,0),state.duration)/max(state.duration,0.001),y:20)
                }
                handle("Start",x:start,width:width)
                handle("End",x:end,width:width)
            }
        }.coordinateSpace(name:"recorderTimeline").accessibilityElement(children:.contain)
    }
    func handle(_ name:String,x:Double,width:Double) -> some View {
        VStack(spacing:3) {
            Text(name).font(.caption2.bold())
            RoundedRectangle(cornerRadius:5).fill(state.removeSelection ? Color.red : Color.blue).frame(width:18,height:64).overlay(Image(systemName:"line.3.horizontal").rotationEffect(.degrees(90)).font(.caption2).foregroundStyle(.white))
        }.frame(width:40).offset(x:x-6)
        .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("recorderTimeline")).onChanged { value in
            // Both handles use the same fixed timeline coordinates while dragging.
            state.moveHandle(name,to:((value.location.x-14)/width)*state.duration)
        })
        .accessibilityLabel("\(name) trim handle")
        .accessibilityValue(RecorderState.timeLabel(name == "Start" ? state.trimStart : state.trimEnd))
        .accessibilityAdjustableAction { direction in state.moveHandle(name,to:(name == "Start" ? state.trimStart : state.trimEnd)+(direction == .increment ? 1 : -1)/max(state.frameRate,1)) }
    }
}
