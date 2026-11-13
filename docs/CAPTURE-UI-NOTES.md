# Recorder and Screenshot Studio design notes

These are design notes, not current product instructions. See [build 45 behavior](CAPTURE-PREVIEW.md) for release scope. Use the supplied Movavi screenshots as interaction references. Keep Orbit's visual style and use the existing recorder, screenshot and shortcut flows.

## Capture selection and controls

- Share a capture dock between Screenshot and Record. Keep the mode, primary action, Settings and Cancel visible. Make it collapsible and optional; the menu bar and shortcuts remain available.
- Show a steady, high-contrast outline and resize handles for an area. Display the selected app/window name when available. Show width × height in points and the estimated output in pixels; use the selected display's scale and the chosen output limit. For area capture, consider editable dimensions that clamp to that display. Do not imply that changing output resolution resizes the source window.
- Anchor compact controls outside the capture frame when possible: microphone, system audio, camera, Settings, Start and Cancel before recording; elapsed time, Pause/Resume and Stop during recording. On a full display or near an edge, clamp controls to the visible screen or use the menu bar. Keep controls and selection outlines out of exported media.
- Keep advanced effects in a secondary row or popover. The optional edge dock can switch modes without reopening the main window; test this after the selection toolbar works well.

## Settings

- **General:** optional countdown, control visibility and start/stop sounds. Keep Start at Login in Setup Center.
- **Files:** independent screenshot and recording destinations; PNG/JPEG and JPEG quality. Keep the original video and export a separate copy without a deletion prompt.
- **Shortcuts:** use Orbit's existing settings and conflict handling; add Pause/Resume.
- **Video:** show estimated output resolution and FPS; offer native resolution and a clear size cap.
- **Audio and Camera:** choose the input, preview microphone level and camera placement. Treat separate audio tracks and noise reduction as later work.
- **Effects:** preview cursor visibility, halo color/size and separate left/right click colors. Consider click sounds as an optional later effect. Provide a reset for effects. Keyboard labels are off by default; show shortcut combinations only, without recording typed text.
- **Sharing:** start with Copy, Show in Finder and the macOS share menu. Scheduling is separate pending decisions on unattended and locked-screen recording.

## Suggested delivery order

1. Shared selection outline, dimensions and compact toolbar; countdown toggle, Pause/Resume and screenshot format.
2. Live effect preview, microphone meter and camera preview.
3. Optional collapsible edge dock and additional capture tools.

Validate on mixed-scale displays, including a secondary 4K screen, a selection at the screen edge and a full-display capture. Confirm controls remain reachable and absent from saved media, and compare the reported output dimensions with the saved file.

See [Capture Tools release](CAPTURE-PREVIEW.md) for the current implementation and acceptance checks.
