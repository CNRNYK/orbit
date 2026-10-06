# Data handling

Orbit has no account, recording upload service or analytics telemetry implementation in its current source. This does not mean it never connects to the internet.

## Network requests

- Homebrew metadata and aggregate installation-event statistics come from formulae.brew.sh. These statistics describe Homebrew usage, not tracking implemented by Orbit.
- App release checks use the GitHub API.
- Official application icons may refresh from recorded vendor/GitHub URLs; bundled icons remain available offline. Icon refresh can run when Orbit opens.
- Explicit Terminal Setup runtime downloads contact the selected runtime/package registries. Tool discovery is file-only; version checks run only when requested. Project inspection reads local metadata without running project scripts.
- Homebrew package operations contact Homebrew and vendor download services. Opening website or settings links is a user action.

These services can receive normal request metadata such as your IP address. Orbit does not add recordings or profile contents to these requests.

## Local data

Selections, favorites and setup completion use local preferences. Catalog/icon data is cached under Library/Caches/io.macsetup.desktop. Recordings default to Movies/Orbit Recordings; screenshots are copied or saved when requested. Temporary recording sources can remain available for recovery after export failures. Terminal setup creates private backups under ~/.orbit-terminal-backups and stores applied choices locally, including custom aliases and Git identity when supplied. Its portable export excludes those personal fields and never exports profiles, history or keys. Imported independently authored setup files may contain custom commands, which require review before applying.

The app displays operation logs and diagnostics. They can contain usernames, local paths, package names or installer output. Review and redact before copying into an issue. Orbit does not automatically send those logs to a server.

Administrator passwords entered into the native helper are written directly to sudo's askpass channel. The helper does not persist them or add them to Orbit logs. Permission requests are feature-specific macOS prompts; optional access is not blanket authorization.

This document summarizes current source behavior. It does not describe data handling by apps installed through Homebrew or by external services.

## Global keyboard shortcuts

Configurable capture shortcuts use macOS hotkey registration and process only the combinations assigned to Orbit while it is running. They do not request Accessibility or Input Monitoring and do not collect other keystrokes. The optional recording effect that displays shortcut labels retains its separate Input Monitoring requirement.
