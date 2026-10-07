# Orbit 0.23 acceptance and limitations

This release addresses GitHub requests #34–#37 together.

## Screenshot annotation editing

Use Select (pointer icon) to pick an existing annotation, drag it, edit selected text or Delete selected. Delete/Forward Delete applies only to the selection. Undo restores drawing, move, text and deletion changes; Clear is also undoable. A new screenshot starts a fresh undo history. Selection outlines are editor-only and are not composited into Copy/Save PNG. Blur and Cover remain above other drawing in exported images.

Selection uses the screenshot's normalized coordinates. Text selection bounds use the displayed font metrics; very long labels should be kept within the image. The first version supports moving rather than resizing existing shapes.

## Shared window selection

Window mode now has a compact list with hover outlines and Choose on screen. On-screen picking uses visible ScreenCaptureKit window IDs and the front-to-back order from CoreGraphics. Hover outlines the frontmost eligible window under the pointer; click selects it. Esc and display arrangement changes cancel and remove all panels. Orbit's own windows are excluded. Screenshot and recorder use this same selector, including the menu bar and floating controls. Highlights close before capture starts and are not part of capture filters.

The selector does not require Accessibility or Input Monitoring. Screen Recording permission is still necessary to enumerate and capture supported windows. Minimized, desktop and nonstandard window layers are not candidates. A window that closes before capture is refreshed/rejected rather than silently substituted.

## Explained cleanup

Cleanup retains its existing cache/log/build-cache scope and filesystem identity checks. It does not delete personal Downloads/Desktop files. Results have Recommended, Review or Advanced labels, explanations and estimated byte totals. App identity matching uses scanned application bundle IDs and Orbit catalog references. Known apps have names/icons; unknown entries retain their technical names and are Advanced. An expandable path list shows up to 100 non-hidden entries without traversing symlinks.

Select recommended only selects Homebrew's download cache; other files need deliberate selection. Filters are All, Recommended, Large items (500 MB or larger), Apps, Developer and Advanced. Confirmation summarizes selected items, likely effects, affected apps and how to restore from Trash. Known running apps block cleanup of matching caches/logs. Unknown/system effects cannot be verified; close affected apps and review those entries individually. No result guarantees universal cleanup safety.

## Stop managing with Homebrew

Library's Stop managing… first checks eligibility. Only official homebrew/cask installations with one standard /Applications app artifact, installed JSON metadata and no installer, command wrapper, binary, hook, service or embedded background component qualify. Optional quit-only metadata and zap definitions are read but never executed. Unsupported cases say Cannot detach safely and explain the restriction.

The app and its data remain in place. Orbit privately backs up the bundle and registration before atomically moving only that cask's Caskroom registration out of Homebrew. A complete registration snapshot exists before removal; backup and registration must be on the same filesystem. It obtains the same advisory cask lock used by Homebrew, rechecks app and metadata identity, verifies that Homebrew no longer lists the cask, and opens the app once without activating it to verify launch. Verification failure restores registration; rollback failures disclose the backup path. No uninstall or zap command runs. Restore cannot overwrite recreated registration. The most recent recoverable registration is rediscovered after restarting Orbit; restore requires closing the app and refuses changed app metadata. Older backups remain available in the backup folder.

This is a conservative operation against Homebrew's installed metadata layout, not a public Homebrew detach command. New/legacy layouts fail closed. Homebrew updates, listing and uninstall stop for the detached app; vendor updates may become available, but are not guaranteed. Keep backups until the result has been checked. The backup contains the app bundle and Homebrew metadata, not the user's app data. Changes made by an independently running process are outside Homebrew's advisory lock; close the app and avoid simultaneous package/file operations.

## Automated verification

Synthetic annotation model/geometry tests cover selection, move bounds, text edits, selected-only deletion, undo/reset and drawing hit tests. Window fixtures verify z-order, off-window rejection and coordinate conversion for negative origins and displays above the primary. Existing capture tests continue to verify multi-display propagation, cancellation and recording/screenshot filters. Cleanup fixtures verify conservative recommended selection, unknown/system classification and personal-file restrictions. Temporary app/registration fixtures verify eligibility rejection, app preservation, backup creation, rollback on injected launch failure, restore collision refusal and stale metadata refusal.

Native UI previews and smoke checks use generated images/video and fake shortcut registration. They do not record the user's screen, modify privacy permissions, detach a real installed app or change unrelated shortcuts.

## Manual acceptance still required

- On two physical displays with mixed scaling, choose a window on each display from the list and directly on screen. Check the border matches; Esc cancels; rearranging/disconnecting a display cancels.
- Capture a screenshot and record the selected window from the app, menu bar and background shortcuts. Verify no selection outline/overlay in output and no substitution when the window closes.
- On a generated screenshot, select/move each annotation tool, edit text, delete, undo, copy and save. Verify Cover still conceals its selected area.
- Review Cleanup filters, totals and unknown Apple cache labels. Recommended selection must leave unknown/system entries unchecked; personal files must not be selectable. Close known apps before cleaning their caches; verify Trash Put Back before emptying Trash.
- On a disposable standard single-app cask, review and detach, verify app launch/data/vendor updater, Homebrew absence, retained backup and restore. Confirm installer/helper casks are refused. Test an unavailable Homebrew command/launch failure and verify rollback. Do not use a valuable app as the first acceptance test.
- With Screen Recording denied, window selection should show the existing permission guidance; it must not create a misleading fallback capture.

Physical display capture and real cask detach remain manual acceptance items; synthetic tests do not establish those hardware/vendor outcomes. Distribution remains an ad-hoc-signed, non-notarized early-access beta.
