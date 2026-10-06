# Multi-display capture and keyboard shortcuts

## Capture a secondary display

Full screen retains the explicit display picker. Window mode retains its window picker. Area mode now opens an overlay on every display available to ScreenCaptureKit and AppKit. Move the pointer to highlight a display, then begin dragging there. A drag stays inside that display even if the pointer crosses its edge; spanning multiple displays is not supported. Esc removes every overlay and cancels the action.

The shared screenshot/recording picker returns a display ID and a top-left-based rectangle in display points. AppKit overlay frames remain in bottom-left global coordinates; flipped local rectangles are mapped through the chosen display's CoreGraphics bounds. Pixel scaling is applied by the capture filter only when configuring output dimensions. Negative origins and displays above/below the main display do not use the main display as an implicit fallback.

A disconnected display or changed arrangement cancels an active area picker. A stale area is rejected before capture; recording checks again after countdown and stops/saves if its display geometry changes during recording. A missing explicit full-screen source requires another selection. Source-enumeration failures retain the requested display identity for retry. Window capture remains tied to its selected window.

## Configure global shortcuts

Open **Setup Center → Keyboard Shortcuts**, **Orbit → Keyboard Shortcuts…**, or **Keyboard Shortcuts** in the menu-bar panel.

| Action | Default | Behavior |
| --- | --- | --- |
| Take a screenshot | Control–Option–Command–3 | Uses Screenshot Studio's last mode. Area opens overlays; Window uses a valid selection or opens a compact picker. |
| Open capture mode selector | Control–Option–Command–4 | Opens the menu-bar Screen Capture panel with Full screen, Area and Window. |
| Start or stop recording | Control–Option–Command–5 | Uses the recorder's last mode; Area opens overlays and a missing Window opens floating controls. Stops either active or paused recording. |
| Open Orbit | Control–Option–Command–O | Restores the window and its Dock icon. |

Click **Change…**, press a combination containing Command or Control, or press Esc to cancel. **Disable** removes the registration immediately. **Restore defaults** changes all assignments together; failed registration keeps the previous working assignments. Choices persist between launches. The same menu-bar mode choice updates both capture modes, while changes within Screenshot Studio and Screen Recorder retain their respective last modes.

Orbit uses Carbon `RegisterEventHotKey`, not a global keystroke monitor. These shortcuts do not request Accessibility or Input Monitoring. The separate optional recording effect **Shortcut labels** still uses its existing Input Monitoring permission. Shortcuts stay active while Orbit is running, including with its main window closed and Dock icon hidden, and unregister on quit.

Held-key repeats are ignored until release. Capture triggers are blocked during selection, source loading, countdown, startup, saving and other incompatible Orbit operations. Open Orbit remains available; the recording shortcut can stop an active/paused recording. Capture start does not bring the main window forward; existing post-capture editors and error/permission handling are reused. Recordings retain their automatic destination and filename behavior.

## Conflict detection limits

Orbit rejects duplicates within its own assignments, common reserved macOS combinations and registration failures. A failed edit preserves the previous assignment. There is no universal macOS inventory of shortcuts used by all apps, and a successful registration does not prove that every other application avoids that combination. App-specific conflicts may require choosing another shortcut in Orbit or the other app. Key names reflect the current keyboard layout; shortcuts are stored as physical key codes.

## Automated verification

`bash test.sh` uses synthetic display geometry and fake shortcut registrars for negative/vertical origins, mixed scale factors, clipping, pointer/drag display locking, selected display propagation, stale/disconnected display rejection, cancellation state, independent modes, preferences, duplicates, reserved combinations, registration rollback/default swaps, press/release repeat suppression, operation guards and unregister lifecycle. No automated test captures the user's screen, resets permissions or registers real global hotkeys.

After `bash build.sh`, run:

```sh
dist/Orbit.app/Contents/MacOS/Orbit --capture-ui-smoke-test
dist/Orbit.app/Contents/MacOS/Orbit --menu-bar-smoke-test
dist/Orbit.app/Contents/MacOS/Orbit --render-preview /tmp/orbit-shortcuts.png --shortcuts-preview
dist/Orbit.app/Contents/MacOS/Orbit --render-preview /tmp/orbit-menu.png --menu-bar-preview
```

Native smoke tests use synthetic overlay windows and a fake registrar: secondary drag, Esc/all-window teardown, topology notification cancellation, local shortcut recording, background Open Orbit/Dock restoration, settings navigation and registration cleanup. Preview rendering inspects native SwiftUI layout with fixture data.

## Manual acceptance checklist — physical hardware required

- Connect two displays, including one Retina and one non-Retina or differently scaled display. Test arrangements left, right, above and below, including negative origins.
- In both screenshots and recordings, choose Area, move between displays and verify the highlighted border follows the pointer. Drag on the secondary display and confirm the output matches that rectangle, with correct size and origin. Cross an edge while dragging and confirm clipping to the initial display.
- Press Esc before/during dragging. Confirm all overlays disappear, no capture starts, and the next attempt works. Disconnect/rearrange displays during selection/countdown and confirm cancellation or a clear error; disconnect during recording and confirm a saved interrupted recording rather than a primary-display fallback.
- Verify explicit Full screen selection on both displays and Window capture on a secondary display. Repeat after a source-enumeration failure and reconnect.
- Close the main window with menu-bar background mode enabled. From another app, use all four shortcuts; verify Open restores Dock/window, capture start does not foreground the main window, screenshot opens its editor afterward, and Stop opens the saved recording editor.
- Change screenshot and recording modes independently; trigger their shortcuts and confirm each mode is remembered. Choose a mode in the menu panel and confirm both actions use it. In Window mode remove the selected window and verify a compact picker appears.
- Hold/repeat shortcuts through selection, countdown and saving; verify no duplicate captures. Verify the recording shortcut stops paused recording and does not cancel countdown or interrupt saving.
- Change, disable, restore and relaunch. Test an Orbit duplicate, a common reserved combination and an unavailable combination; verify warning/rollback. Try the chosen bindings in your usual apps to check application-specific conflicts.
- Deny Screen Recording, microphone or camera when relevant; confirm existing permission guidance appears and no silent alternate capture occurs. Allow access and retry without a permission reset script. Confirm ordinary shortcuts alone require neither Accessibility nor Input Monitoring.
- Quit Orbit and confirm its shortcuts are inactive. Check fresh launches and keyboard-layout changes.

Physical multi-monitor output, real background hotkey delivery, other-app conflicts and privacy-denied hardware capture require this manual acceptance; fixtures cannot establish them. Builds remain ad-hoc signed and not notarized, so macOS may require Screen Recording permission to be re-granted after replacement until a stable Developer ID distribution is established.
