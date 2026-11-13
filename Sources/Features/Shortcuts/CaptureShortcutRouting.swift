import Foundation

enum CaptureShortcutRoute: Equatable {
    case pauseRecording, ignore, open, selector, writing, screenshot(String), startRecording(String), stopRecording
    static func resolve(_ action: OrbitShortcutAction, phase: RecorderState.Phase, blocked: Bool, dispatching: Bool, screenshotMode: String, recordingMode: String) -> Self {
        if action == .pauseRecording { return phase == .recording || phase == .paused ? .pauseRecording : .ignore }
        if action == .open { return .open }
        if action == .recording, phase == .recording || phase == .paused { return .stopRecording }
        guard !blocked, !dispatching else { return .ignore }
        switch action { case .pauseRecording: return .ignore; case .writing: return .writing; case .open: return .open; case .selector: return .selector; case .screenshot: return .screenshot(screenshotMode); case .recording: return .startRecording(recordingMode) }
    }
}
