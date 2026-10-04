# Architecture

Orbit is a native SwiftUI/AppKit macOS application. A shared main-actor Store connects the window and menu bar, keeps installation/removal selections separate, and guards concurrent operations. Homebrew runs as the current user with argument arrays, never by evaluating imported Ruby or shell text.

```text
Sources/
  App/                 Application entry point, window and catalog/detail views
  Core/                Shared Store, command execution and operation coordination
  Features/
    Homebrew/          Catalog, discovery, Library, adoption, lifecycle and repair
    Cleanup/           Reviewed cache/log cleanup
    Capture/           Screen recording, screenshots, annotations and media export
    System/            Setup, permissions, health and login items
    Terminal/          Reviewed Zsh profile planning, backup and restore
  UI/                  Menu bar, icons and operation details
Tests/
  Runner.swift         Test entry point
  Homebrew/            Catalog and lifecycle fixture tests
  Capture/             Geometry, compositing, codecs and editing
  System/              Setup, permissions, login, cleanup and terminal tests
  Core/                Shared UI and menu workflow tests
Resources/             Catalog, identifiers, logos and branding
Helpers/               Native administrator password helper
Scripts/               Catalog and asset maintenance tools
docs/                  Behavior, architecture, development and release guidance
```

## App management

Discover merges curated matches and official cached results by package identity. Personal packages are validated before tracking. Library shows installed packages, manual bundles and saved favorites. Homebrew-managed removal stays with Homebrew. Manual removal checks bundle path/inode/device/identifier, rejects running apps, checks every installed cask including packages outside the catalog, and reviews exact identifier leftovers; settings are unchecked by default. No vendor-wide matching or automatic dependency cleanup is introduced.

## Capture

ScreenCaptureKit provides source enumeration and screen media. Each recording owns an engine, private temporary source, floating controls and capture border. Effects and annotations are rendered into video frames. AVFoundation exports MP4 and range edits; exclusive publication prevents overwrites. Main and menu captures share state and completion callbacks. Native AVPlayerView handles preview.

Screenshots share capture-source selection and annotation rendering. PNG copy/save uses the rendered result, including redactions. No cloud upload is performed.

## System features

Setup Center shares first-launch requirements and permission controls. Passive checks do not grant access. Login Items uses System Events only after permission; Orbit launch registration uses SMAppService. App Health Check diagnoses without repairing. Terminal changes are reviewed, syntax-checked and backed up without executing profile content.

## Build boundaries

The root build/test scripts recursively collect Swift sources. Tests exclude the app's @main file and include their own runner. Resource fallback paths remain rooted at the repository working directory; bundled resources take precedence. No package manager or new third-party runtime dependency is introduced.
