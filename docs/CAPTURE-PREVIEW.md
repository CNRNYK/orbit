# Capture Tools — 0.25.0, build 45

This page describes the Capture Tools features in Orbit 0.25.0.

## Capture

Open **Screen Capture → Open capture dock** from the menu bar. The dock can collapse to screenshot and recording actions; expand it for source selection, microphone, system audio, camera and settings. Drag to select an area, resize with the corner handles and press Return or **Use area**. The selector shows dimensions in points and estimated source pixels. Recorder separately estimates output resolution and frame rate after the configured size limit.

Starting a window recording without a selected window opens the picker and proceeds when a window is chosen. Esc cancels. The recording toolbar follows the capture frame: below if there is space, otherwise above, with a visible-edge fallback. It shows elapsed time, Pause/Resume, Draw and Stop. Unassigned shortcuts have no badge in the menu bar. Assign Pause/Resume in Keyboard Shortcuts if it is absent from existing preferences.

Recorder settings include **Disable countdown**, floating control visibility, start/stop sounds, an awake assertion during recording, microphone and camera selection and explicit previews, cursor effects, camera shape and position, and resolution limits. System audio, microphone and camera bubble can be toggled during recording if enabled at the start. Muted audio is excluded from the saved recording; hiding the camera bubble does not power off the camera. Presentation mode draws over the screen without producing a video. Start later counts down to a confirmation rather than starting unattended capture.

## Editors and export

After capture, the Recording Editor or Screenshot Studio opens in its own window without the main sidebar. The video preview grows with the editor window. The camera preview is sized to contain the full bubble. New recordings use readable timestamps with numeric suffixes for name collisions; existing files are not overwritten.

**Original** is the default video export. It copies an unchanged MP4 without re-encoding and uses passthrough for edits, whose cuts may align to keyframes. **Balanced** uses the former High encoding preset and does not guarantee a smaller file. Export reports the actual output size and keeps the original without a deletion prompt. New recorder settings default to native dimensions; previously saved resolution caps still apply until changed. Recording encodes video at capture time; two enabled audio sources require a mixed export.

Screenshot Studio captures at native pixel dimensions. PNG export is lossless; JPEG has a quality control. The studio supports a separate destination, local OCR of the composed image, pixel color sampling and coordinate-based measurement. Review OCR and redactions before sharing. Saved files can be shown in Finder or shared through macOS.

## Verification

Build 45 passed the native regression suite and DMG verification. Hardware behavior remains a manual acceptance check:

- On mixed-scale displays, resize and confirm an area; compare estimated and actual dimensions. Move a recorded window and check that the toolbar follows it and stays out of the recording.
- Start Window recording without a selection, choose a window and verify the flow proceeds without reopening the menu. Repeat with Esc and with **Disable countdown** on and off.
- Verify Pause/Resume with hidden controls. Toggle prepared system audio, microphone and camera bubble during a recording and check the saved output. Check camera/microphone previews with real devices, denied permissions and disconnection.
- Verify that timer expiry does not begin capture and that presentation mode creates no file.
- Compare Original and Balanced exports on the same video, including a trim. Verify the source file remains intact and no deletion prompt appears.
- Export annotated PNG and JPEG files and check native dimensions, OCR, color sampling, redactions and share actions.

Separate exported audio tracks, noise reduction, mouse-click sounds and unattended recording are outside this release.
