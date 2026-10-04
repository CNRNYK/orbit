# Orbit

<img src="Resources/Branding/Orbit.png" alt="Orbit icon" width="104">

**Set up your Mac. Manage your apps. Record your workflow.**

A native macOS app for discovering, installing, updating, and uninstalling Homebrew packages—with reviewed cleanup, reusable Brewfiles and local screen recording. Pick the apps you want, review the plan, and let Homebrew handle the installation.

![Orbit app catalog with categories and installation selections](docs/images/catalog.png)

## One place for your Mac apps

| What you need | What Orbit does |
| --- | --- |
| Set up a new Mac | Browse 432 curated entries, use starter selections, and install the missing apps you choose. |
| Find something new | Search the official Homebrew catalog in **Homebrew Center → Discover → All Homebrew** and save favorites in **My Apps**. |
| Manage existing apps | See Homebrew-managed and manually installed apps; review supported apps for Homebrew adoption. |
| Keep apps current | Check available updates and upgrade only your selected packages. |
| Remove an app | Review removal and optionally select app-specific leftovers to move to Trash. |
| Review clutter | Inspect caches, logs, and optional developer caches before moving selected items to Trash. |
| Prepare your terminal | Choose Zsh essentials and language environments, review changes, and apply with private backups. |
| Check permissions | Review Orbit access in Permission Center, first-launch setup and installation review. |
| Diagnose app setup | Run App Health Check for Homebrew, missing dependencies and known managed app bundles. |
| Manage startup apps | Enable Orbit at login and review standard Open at Login apps. |
| Capture and explain | Record with live annotations or edit a screenshot locally in Screenshot Studio. |
| Reuse your setup | Import or export a Brewfile with a separate selection that can include installed apps. |

## Homebrew Center

Discover, Installed, Updates and My Apps now live together in **Homebrew Center**. In Discover, choose **Curated** for the starter catalog or **All Homebrew** for official formulas and casks. The two catalog sources share the search field, and Discover remembers the last source while you switch tabs.

**To install** stays visible across all four tabs. Installation and removal choices are separate: browsing Installed or selecting an app to uninstall does not erase your pending installation plan. Updates retain their own selection and review flow. Closing and reopening Orbit preserves installation choices, even if you last used Installed.

## Discover apps beyond the starter list

Search official Homebrew formulas and casks by name or description. **Add to My Apps** saves a favorite; **Select to install** adds it to a reviewed installation plan. Only the packages you choose become direct Brewfile entries; dependencies are handled by Homebrew.

![Explore Homebrew with searchable apps and separate favorite and installation actions](docs/images/explore.png)

## Review cleanup before changing anything

Cleanup has its own page in the main window. Scan supported locations, inspect paths and estimated sizes, then choose what to move to Trash. Nothing is selected by default. Select a group or all cleanable items explicitly; personal large files remain outside bulk cleanup. Large files in Downloads and Desktop can be revealed in Finder for your own review.

![Cleanup page with cache groups, estimated sizes, and a reviewed Trash action](docs/images/cleanup.png)

Cleanup does not empty Trash or promise to remove every trace of an application. App-specific settings and data are reviewed separately through **Uninstall & Clean**.

*Screenshots use demonstration data rendered by the app. No real installation or cleanup was performed to create them.*

## Prepare your developer terminal

**Terminal Setup** offers checkbox selections for Homebrew, completion, history, aliases, and optional Node/NVM, Python + uv, Java 21, Go, Rustup, and Ruby/rbenv environments. Starship, fzf, suggestions, and highlighting are optional.

Scan your existing Zsh profiles, review Orbit's proposed blocks, then apply. Existing content is preserved, changes are backed up, and repeating the same selection does not duplicate settings. Missing tools join the ordinary install selection; profile changes never install software. Restore is blocked if you edited a profile after applying it.

![Terminal Setup checkbox groups with developer and language options](docs/images/terminal.png)

## Record what matters

Record a full display, a selected rectangle or a single window from **Screen Recorder** or Orbit's menu bar panel. Menu recording opens compact floating controls without bringing the main window forward; press Start there and save automatically to Movies/Orbit Recordings. Add a colored mouse halo, click rings, optional cursor-follow zoom, shortcut labels and a webcam bubble. Microphone and system audio have separate switches and start off.

A three-second countdown gives you time to prepare. Pause or stop from the floating controls or menu bar; Orbit's own windows are excluded from the video. Add blur areas or solid privacy covers before recording, then preview the MP4, copy the file or save a trimmed copy while keeping the original. Recordings stay local; no account or upload is involved.

![Orbit Screen Recorder with capture source, pointer effects, audio, camera and privacy areas](docs/images/recorder.png)

![Compact floating recorder controls](docs/images/recorder-controls.png)

## Capture, annotate and check your Mac

**Screenshot Studio** captures a display, window or selected area. Draw arrows, rectangles, freehand lines, highlights or text; use Blur or an opaque Cover for selected regions. Undo and Clear let you revise edits, then copy or save the flattened PNG. Saved files do not overwrite an existing file. Blur can leave recognizable detail; use Cover for secrets and check the exported result before sharing.

![Screenshot Studio with a demonstration image and annotation tools](docs/images/screenshot-studio.png)

During recording, a thin red border marks the captured region, including a moving window. The border and floating controls are excluded from capture. Enable **Draw on recording** to add arrows, rectangles, pen strokes, highlights and text to the saved video. Drawing intercepts clicks inside the region; switch it off to interact with your apps. Annotations are applied before the recording's privacy masks and zoom.

**Permission Center** shows Orbit's screen, microphone, camera, input monitoring, accessibility and System Events access. First-launch setup, Setup check and installation review also expose access status. Passive checks do not open permission prompts; explicit Request or Verify buttons do. Screen access is verified with ScreenCaptureKit rather than a legacy permission hint. macOS can require reopening Orbit after a permission change. Installed applications request their own access; Orbit cannot grant it on their behalf.

**App Health Check** runs diagnostic Homebrew commands and checks Orbit's packaged helper and known app bundles. Results do not run repairs or remove files. A missing app in the standard Applications folders may be in a custom location and needs review.

**Login Items** can enable Orbit at login, load standard Open at Login applications, add an existing app or remove the specific entry you confirm. Removing a login item does not uninstall the app. Other background services stay in the native macOS Login Items settings.

## Orbit, one click away

Orbit lives in the macOS menu bar with a small monochrome orbit icon. Open its compact panel to start a screen recording, check available updates, jump to Cleanup or review operation details. During app operations it shows the current app, processed and remaining counts, and **Stop after current app**.

Closing the main window keeps Orbit in the menu bar. **Open Orbit** or its Dock icon brings the same window back; **Quit Orbit** exits. Active operations must finish before quitting. Update checks run on request; installing, updating and cleaning still use the normal reviewed flows.

<img src="docs/images/menu-bar.png" alt="Orbit menu bar panel with status and quick actions" width="340">

## Get started

Requires **macOS 14 or later**. Homebrew must be installed to perform package operations; the first-launch setup check links to the official setup guide when it is missing. You can browse before completing setup.

**[Download Orbit for Apple Silicon (.dmg)](https://github.com/CNRNYK/orbit/releases/download/v0.18.0/Orbit-0.18.0-macOS-arm64.dmg)** · [Release notes](https://github.com/CNRNYK/orbit/releases/tag/v0.18.0)

Open the DMG and drag **Orbit.app** to **Applications**. Downloads require access to this private repository. This release is ad-hoc signed and has not been notarized, so macOS may require approval in Privacy & Security. Only approve a download you trust.

To build from source, install Apple Command Line Tools, clone this repository, then run:

```sh
git clone https://github.com/CNRNYK/orbit.git
cd orbit
bash build.sh
open "dist/Orbit.app"
```

The repository is currently private, so cloning requires access. Builds target your Mac's architecture. Local builds use ad-hoc signing; a notarized public installer and a Homebrew cask for Orbit are not currently published. The DMG is available to repository members through Releases.

## You choose the changes

- Installation, updates, removal, and adoption have review steps before execution.
- Installed apps cannot accidentally join a new installation selection.
- Cleanup moves selected, validated paths to Trash; it does not automatically delete personal files.
- Homebrew runs as your user. Individual vendor installers may request administrator permission through the bundled native password dialog.
- **Operation details** shows progress and errors; **Stop after current app** lets the current operation finish.

App licenses, subscriptions, and vendor sign-in are separate. Orbit does not restore application settings or install App Store products.

## More details

- [Feature behavior, permissions, and cleanup scope](docs/FEATURES.md)
- [Catalog mapping and unavailable entries](CATALOG-NOTES.md)
- [Install Homebrew](https://brew.sh)
- [Homebrew documentation](https://docs.brew.sh/Manpage)

To package a local build as a DMG, run `bash package-dmg.sh` after building. The script creates a compressed image with Orbit, an Applications shortcut, installation notes, and a SHA-256 checksum.

For automated validation, run `bash test.sh`. Tests use simulated commands and temporary fixtures; they do not install or remove your applications.

## License

[MIT](LICENSE) for the source code. Third-party apps, icons, and trademarks retain their respective owners' terms. Orbit is independent of Homebrew and application vendors.
