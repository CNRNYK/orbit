# Testing

Run from the repository root:

```sh
bash test.sh
bash build.sh
dist/Orbit.app/Contents/MacOS/Orbit --self-test
dist/Orbit.app/Contents/MacOS/Orbit --menu-bar-smoke-test
```

The suite uses injected command responses, isolated preferences and temporary app/profile/file fixtures. It never installs or removes your real applications. Capture tests generate frames and tones, encode/export MP4, decode frames and check audio/range editing. These require normal macOS graphics and codec access.

## Automated coverage

- Process argument isolation, separate JSON diagnostics and large pipe output.
- Catalog identity, links, icon decoding, presets, Brewfile parsing and export.
- Install/removal review, adoption, selected cleanup, guarded repair and sensitive defaults.
- Official discovery deduplication, Library filters and persistent installation choices.
- Manual app path/inode/device snapshots, exact leftover matching and installed-cask ownership (including unknown vendor mappings).
- Profile preservation, private backups, syntax-only validation and guarded restore.
- First-launch prerequisites, permission semantics and automatic login loading with existing access.
- Recorder source success/errors, geometry, masks, annotations, pause timestamps, MP4 encoding/audio mix, exclusive save and keep/remove edits.
- PNG rendering/redaction and native player replacement/teardown.
- Menu popover, operation guards, hidden-window compact controls and reopening.

## UI fixture previews

```sh
dist/Orbit.app/Contents/MacOS/Orbit --render-preview /tmp/orbit-library.png --installed-preview
dist/Orbit.app/Contents/MacOS/Orbit --render-preview /tmp/orbit-setup.png --permissions-preview
dist/Orbit.app/Contents/MacOS/Orbit --render-preview /tmp/orbit-screenshot.png --screenshot-preview
```

Preview mode suppresses operations, prompts and device capture. README screenshots use these fixtures.

## Installed-build acceptance

On a test Mac, keep one copy in Applications. Verify optional permission requests and denied/retry behavior. Record full screen, area and window with the selected audio options; pause, stop and confirm preview. Check the visible capture border, menu bar screenshot capture/editor, retained audio after both trim actions, multiple displays and window movement. Test manual removal only on a disposable app after reviewing exact paths. Confirm login refresh after granting access and Add application's initial folder.

Passing generated media tests does not prove the installed app's ScreenCaptureKit/TCC access, microphone/camera behavior or multi-monitor capture. Those remain separate device checks.
