# Recorder editor update (v0.20)

Screen Recorder uses Record, Edit and Settings tabs. Edit opens automatically after saving or opening a video. A single thumbnail timeline has draggable Start/End handles that pause playback and seek precisely; the End preview shows the last included frame before the exclusive end boundary. Arrow-key buttons adjust the selected handle by one source-frame interval. Blue marks kept content; red marks removed content. Keep/Remove mode displays the resulting duration. Unchanged or empty-result edits cannot be exported. Preview edit creates a temporary local MP4, removed when the original is restored or another video is opened; Save edited copy never replaces the original. Recorder preferences and the chosen output directory are remembered locally. Annotation tools remain in the floating recording controls.

# Current workflow (0.19.0)

Homebrew Center now uses Discover, Library and Updates. Discover combines recommended matches with deduplicated official Homebrew results. Library combines installed apps and saved favorites with All/Installed/Saved filters, explicit save/unsave actions and reviewed manual Uninstall & Clean. Manual removal rechecks app identity and Homebrew ownership, refuses running apps and uses exact bundle-identifier leftovers with sensitive data unchecked.

All recording starts use unique automatic destinations in Movies/Orbit Recordings. Successful finalization opens the preview, where Keep selection or Remove selection exports a new copy. Menu screenshots support full screen, selected area and window before opening the editor. Annotation tools now have icons and accessible tool labels.

Setup Center combines Requirements, Permissions and Startup, including Orbit at login. Login Items automatically loads when System Events access is already allowed and otherwise offers explicit access request. Add application starts in Applications.

The sections below retain historical feature details and version milestones; labels or flows superseded above describe those earlier versions. See the [README](../README.md) for the current overview and [changelog](CHANGELOG.md) for milestones.

---

# Orbit feature reference

A native SwiftUI application for selecting, installing, and uninstalling Homebrew packages on macOS. English interface; MIT licensed source code.

## Use

Open **Orbit.app**. Browse categories, search, select apps, then choose **Install**. Review the plan before running it. Each package is checked against Homebrew's official JSON catalog before installation. Disabled, deprecated, and unverified packages are skipped.

The catalog integrates the supplied Mac Power User / Developer / Designer / Creator toolkit. It contains 432 unique catalog entries across 10 purpose-based categories, with icon-based section filters: 373 active Homebrew packages (246 casks and 127 formulas) and 59 manual or unavailable entries. All 437 numbered source entries are represented, including duplicates through shared category placements. The original application catalog is retained. It uses local application icons when available and native category icons otherwise. Selection is saved locally.

Homebrew must already be installed at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`. If it is missing, the application links to the official Homebrew setup instructions. After setting it up, use Refresh. The app does not install Homebrew automatically.

Already managed packages and detected local apps cannot be selected for installation. Manage selected existing apps through **Installed → Installed manually → Manage with Homebrew**. App-bundle adoption requires identical contents; verified vendor installers are disclosed separately in review. Licenses, subscriptions, and sign-in are handled separately by each vendor.

Homebrew runs as your user, not as root. For individual installers requiring administrator access, Homebrew uses the bundled `SUDO_ASKPASS` helper. This is a native AppKit secure-text dialog labeled **Orbit · Administrator permission**, not a system authorization sheet. Its password output goes directly to sudo, is not saved or included in the application's logs. Canceling the dialog causes that installation to fail. The helper does not use System Events or request Automation permission.

Installation is sequential. Logs are visible in **Operation details**. A failed package does not stop subsequent packages. **Stop after current app** waits for the running installer to finish instead of terminating it. Quitting during an installation is blocked. No extra cleanup, forced reinstall, automatic adoption, or automatic upgrade commands are used. Dependencies and vendor installers may still make changes as part of normal installation.

## App details and links

Click an app's icon, name, description, or info button to open its detail sheet. It shows a description, every category placement, installation availability, catalog version, package license when provided by Homebrew, and official links. Viewing details never starts installation or removal. The checkbox remains a separate selection control.

All 432 entries include an official website or project page. 314 have evidence-backed GitHub links. Source mirrors, extension collections, and issue trackers are labeled separately from source repositories. Unverified GitHub links are not guessed. GitHub links do not imply that the installed application itself is open source. Homebrew package pages are also linked when available.

Link provenance is stored in the catalog. `Scripts/update_package_links.py --metadata-dir /path/to/cache` can refresh links from official Homebrew API snapshots and package homepages; reviewed repository links are stored in `Scripts/verified_github_links.json`. External links open in the default browser; only HTTP(S) URLs without embedded credentials are accepted.

## Categories and starter selections

Choose a sidebar category, then use the icon-based section picker in the content area. Category and section counts follow the current installed/search filter. Search includes package names, descriptions, categories, and subcategories. In All Apps, each package appears once; inside a category, repeated tools appear in their relevant category placement but share one selection and installation ID.

**Starter selections** includes the supplied Core Mac Stack groups (Mac, AI, Development, CLI, Creative, Media, Productivity, and Network), plus Discover 20. Presets add choices to your current selection; they never start an installation. Unavailable packages cannot be selected or exported. **Select all** includes only supported entries in the visible category or search result.

Manual or unavailable tools remain visible with **Setup details** and a vendor link where an exact link is known. Third-party taps, editor extensions, web applications, Windows-only tools, and self-hosted services are not silently substituted with unrelated Homebrew packages. Deprecated or disabled packages remain visible but are blocked from installation; if already managed by Homebrew, they can still appear for uninstallation.

The app's bundled `Resources/catalog.json` is editable and contains package names, official Homebrew metadata, category placements, source entry numbers, and presets. Availability is checked again online before installation. Optional tools such as Azure CLI are catalog choices, not preselected additions to a personal Brewfile. See [CATALOG-NOTES.md](CATALOG.md) for mapping decisions and manual entries. Unverified popularity rankings and comparisons in the supplied text are not carried into the product.

## Uninstall apps

Open **Installed** in the sidebar to see Homebrew-managed installed packages within the curated and personally registered catalog. Select apps, click **Uninstall**, and review the exact list. Nothing is removed until you confirm the removal screen. Switching between install and uninstall clears the selection to avoid carrying an install selection into removal.

Removal uses `brew uninstall --cask <token>` for casks and `brew uninstall --formula <token>` for formulas. Normal removal does not request extra cleanup (`--zap`), dependency overrides, or forced removal. Optional **Uninstall & Clean** separately reviews app-specific leftovers and moves checked items to Trash after successful removal. Automatic orphan dependency removal is disabled with `HOMEBREW_NO_AUTOREMOVE=1`. Homebrew can refuse to remove a formula required by other packages. Failures appear in Operation details; later selected packages continue. Vendor uninstallers may still remove app data or request administrator permission.

The stop button waits for the current removal to complete. Installed state is refreshed afterward. Manually installed applications require reviewed Homebrew adoption before managed removal. Packages outside the curated or personally registered catalog are not included in the uninstall list.

## Brewfiles

**Export setup** has an independent selection that can include installed formulas and casks. Import recognizes plain `brew "token"` and `cask "token"` entries from this application's curated and personally registered catalog. Comments and duplicate entries are handled. Ruby code is never evaluated. Unsupported entries, taps, VS Code extensions, and packages outside the catalog are reported rather than silently installed. Import populates the export selection and selects only missing apps for installation.

## Build

Requires macOS 14 or later and Apple Command Line Tools with a Swift compiler. No third-party Swift dependencies or full Xcode project are required.

```sh
chmod +x build.sh
./build.sh
open "dist/Orbit.app"
```

The build targets the current Mac architecture. The delivered build targets Apple Silicon. Local builds use ad-hoc signing; public distribution still needs an Apple Developer identity, notarization, and release testing.

## Validation

The executable includes a non-installing self-test:

```sh
"dist/Orbit.app/Contents/MacOS/Orbit" --self-test
```

Tests check all 437 source entries, catalog uniqueness, available-package export/import round trips, manual-entry blocking, cross-category membership, starter preset deduplication, rejection of executable Brewfile input, and installer disclosure. Run `bash test.sh` for additional process-runner and installation-plan tests, including literal argument handling, launch failures, large output, and skip/adoption logic. Additional removal tests check installed inventory gating, installed-only filtering, and exact cask/formula removal arguments. Actual package installation, uninstallation, and the administrator password dialog are not exercised by these tests.

## Scope

The starter catalog is curated. Explore Homebrew additionally searches the official formula and cask catalogs; registered personal packages participate in app management. Catalog availability is verified online before installation. Homebrew handles architecture and macOS compatibility; failures remain visible in the installation log. It does not restore app settings, install App Store products, or create Google web apps. NVM and Java may need shell setup after installation.

## References

- [Homebrew installation](https://brew.sh)
- [Homebrew command documentation](https://docs.brew.sh/Manpage)
- [Homebrew catalog API](https://formulae.brew.sh/docs/api/)

## License

MIT. Application names belong to their respective owners; third-party applications retain their own license terms. This project is independent of Homebrew and the application vendors.

## Official application icons (v0.5)

App rows and detail sheets show the installed application's icon first, then an official-site icon, then the bundled category symbol. The catalog includes 344 raster icons: 335 discovered from icon links published by official homepages and nine from logo links in verified GitHub repository READMEs, with their asset URL and source-page provenance. These include site favicons and touch icons; a site icon can represent a vendor rather than a particular product. Generic GitHub, GitLab, and App Store hosting icons are excluded.

All 344 assets ship in the app for immediate offline display. At launch four background workers refresh them from the recorded HTTPS URLs, without blocking Homebrew checks or interaction. Downloaded icons are cached for 30 days under `~/Library/Caches/io.macsetup.desktop/Logos`. Requests time out, responses are limited to 1 MB, and ImageIO decodes bounded 256-pixel thumbnails. Failed requests keep the bundled icon. The detail sheet links to the original icon asset. No third-party icon lookup service is used.

Run `python3 Scripts/update_app_logos.py` to rediscover icons from official homepage links and verified repository README logo links. The script only accepts PNG, JPEG, and ICO payloads. Application logos and trademarks remain owned by their respective vendors; the project MIT license applies to its code, not these assets.

## Updates and reviewed cleanup (v0.6)

**Updates** refreshes Homebrew metadata, lists installed outdated packages in this curated catalog with current/available versions, and upgrades only the checked list after a separate review. Self-updating casks are opt-in; unversioned `latest` casks and pinned packages are excluded. Where an app bundle exposes its actual version, that version is checked when planning and again before upgrade so newer self-updated apps are skipped. This is a conservative numeric comparison, not a universal vendor-version parser. Homebrew may update or repair dependencies as part of an upgrade. Failures remain in Operation details, and stopping waits for the current operation. Searches filter the update list.

Orbit's own **Check app release** checks GitHub's latest release endpoint and links to the release page for manual download. The private repository is unavailable to anonymous API requests; the app explains this and offers the browser page where the user can sign in. It does not collect GitHub credentials or automatically replace the running app. Orbit v0.16.3 is distributed as a DMG through this private repository’s Releases. Access requires repository permission.

**Uninstall & Clean** scans existing application bundle identifiers before removal. It reviews matching caches, logs, preferences, support folders, saved state, containers, HTTP storage, WebKit data, scripts, and cookies under the current user's Library. A small reviewed mapping adds app-specific paths for Chrome, VS Code, Blender, and Slack from the official Homebrew cask definitions. Shared group containers, vendor-wide folders, wildcard matches, system locations, and unrelated files are excluded; formulas have no guessed data cleanup. Cache/log entries are initially checked; settings and possible user data are unchecked. The user sees every path and its estimated size and can change the selection.

Only checked leftovers belonging to a successfully removed app are moved to Trash. Canonical paths and filesystem identity are rechecked immediately before each move; changed paths and symbolic links are rejected. Permission or Trash errors are shown separately from app removal. Users can restore trashed files. This is targeted cleanup and does not guarantee removal of every trace or service.

`bash test.sh` additionally uses simulated command results and isolated temporary fixtures to verify update parsing, selected upgrade arguments, invalid responses, pinned/latest exclusion, cleanup matching and sizes, data-sensitive defaults, symlink/replacement rejection, and successful-removal gating. Tests do not install, upgrade, uninstall, or trash existing applications or user files. Preview rendering skips Homebrew refresh and icon downloads.

## Simplified navigation (v0.7)

All Apps, Installed, and Updates sit above ten purpose-based categories. The separate Google category is removed: Chrome lives under Browsers & Internet, and Drive under Files & Storage. Each category has a short English description; subcategories are ordered, icon-labeled content filters rather than nested sidebar menus. Installed keeps category filters and provides Uninstall and optional Uninstall & Clean actions.

A package can retain multiple category placements with one shared selection ID. Category changes preserve the selection; changing between installation/removal workflows clears it. All Apps and search render each matching catalog record once, with its primary category breadcrumb. Export and operation plans deduplicate selections. All existing package metadata, source entry mappings, presets, official links, and icon assets are retained. `Scripts/simplify_categories.py` documents the original taxonomy migration.

## Repair recognized uninstall conflicts (v0.7.1)

A failed normal cask removal can offer **Repair & Retry** when Homebrew reports an existing app in its Caskroom, the corresponding app is missing from Applications, and the stored path exactly matches the reported Caskroom, package token, version directory, and app bundle name. Unknown failures, permission errors, formulas, and apps still present in Applications do not trigger forced retries. Other removal failures offer a readable **View error** explanation and retain diagnostics in Operation details.

Repair is never automatic. Its review shows the stored app path and the exact previously selected cleanup paths. After explicit confirmation, the Caskroom location and stored app filesystem identity are rechecked, and only `brew uninstall --cask --force <that-token>` is run. The app then verifies successful exit, installed inventory, and absence of the stored/application bundles before declaring removal complete or performing selected leftover cleanup. Verification failure leaves cleanup untouched and reports an error; formula dependency protection is never overridden. Changed paths and symlinks are rejected.

Repair tests use isolated generated app directories and simulated commands. They cover conflict recognition, unrelated errors, wrong roots, symlink/inode replacement, no force without consent, exact retry arguments, retained cleanup selection, verified success, command failures, and nominal success with a still-installed record. No existing app is forcibly removed by validation.

## Installation, setup export, and manual app management (v0.8)

Installation checkboxes now mean install only. Already Homebrew-managed or locally detected apps show a checkmark and cannot join the installation selection; starter selections, Select all, imported Brewfiles, installation counts, and execution guards follow the same rule. Refresh removes stale installation selections. The optional Not installed filter hides existing apps. Export setup has its own independent selection and can include installed apps for a future Mac without installing anything now; imported entries also populate that export selection.

Installed has Managed by Homebrew and Installed manually tabs. The local scan reads bundle identifiers, versions, paths, and filesystem identity under `/Applications` and the user's Applications folder, including shallow utility folders; it skips symlinks and bundle internals. Matching uses the curated and personally registered catalog. Known identifiers in `app-identifiers.json` were read from existing Homebrew-managed app bundles; an exact bundle filename can also suggest a candidate, but does not by itself authorize replacing that app. Unknown or unsupported apps remain visible and unselectable for management.

Only the user's selected candidates enter a separate review. Live `brew info --json=v2 --cask` verifies the package and app artifact. App-bundle adoption uses `--adopt` with the actual app directory and relies on Homebrew's complete content comparison; different contents are never force-overwritten. Vendor package/installer cases require a reference bundle identifier match, are labeled explicitly in review, may modify the existing app, and are blocked if its version is newer. Unverified installer identities are blocked. The app identity is rechecked before execution, no force flags are used, and refreshed Homebrew inventory verifies the result. Failures stay visible in Operation details. Selecting candidates or opening review never starts installation.

Tests additionally cover local bundle scanning and identifiers, unknown apps, installed selection exclusion, independent setup export, review-only behavior, exact adoption arguments, preserved bundles on simulated adoption failure, and installer identity blocking. All command execution tests use simulated results and temporary fixtures; no existing application was adopted or reinstalled during validation.

## Statistics, native permission prompt, and Cleanup (v0.9)

Package details fetch published Homebrew installation events for 30/90/365 days from the official package API. The source generation date and fetch time are shown. These are anonymous reported events, not total downloads or unique users. Most installed sorts each visible list/section by the official 30-day formula/cask installation reports; unknown entries sort last. Refresh stats reloads reports, and unavailable reports retain old data or fall back to names. Sorting never selects or installs packages.

Administrator password requests now use a bundled native AppKit secure-text dialog, with a fixed Orbit title. No AppleScript or System Events Automation permission is requested. Cancel exits without supplying a password; stdout is passed directly to sudo, without logging or persistence. This is not blanket administrator authorization. Existing Automation permissions can be removed in System Settings. Build with `ORBIT_SIGNING_IDENTITY` to sign both executables with your Developer ID; the default remains ad hoc because no valid signing identity is available on this development machine. Keep one copy named Orbit.app in Applications to avoid numbered Finder copies.

Cleanup opens a dedicated scan/review screen. It lists direct children of the user's Homebrew cache, app cache/log folders, and optionally Xcode DerivedData. Known absent-app reference identifiers label cache/log leftovers; other app data is reviewed by Uninstall & Clean. Downloads/Desktop regular files at least 500 MB are discovery-only and can be revealed in Finder, never selected for deletion. The scan excludes symlink paths, omits unreadable/incomplete candidates, and uses a per-directory enumeration limit. System paths, user documents, project folders, credentials, application support, and preferences are not cleanup targets.

No cleanup item is selected by default. Selected items require confirmation, are checked against the allowed path scope and original inode/device identity, and move to Trash individually. Failures are logged without claiming success. Homebrew cache files are moved to Trash rather than invoking broad Homebrew cleanup or dependency removal. Close affected apps first; cache files may be recreated and subsequent builds may be slower. This feature does not guarantee a byte-for-byte amount of freed space and does not empty Trash. Filesystem checks cannot eliminate every concurrent-change race; do not change the reviewed folders during cleanup.

Validation adds official API fixtures, malformed/missing statistics, popularity ordering, opt-in developer cache scope, exact mocked Trash calls, changed-path/symlink rejection, and personal-file deletion blocking. Tests use temporary fixtures and never clean the user's real folders. The native helper cancellation smoke test verifies exit status 1 and empty stdout, without entering any password. Real privileged installers are not run during validation.

## First-launch setup check (v0.9.1)

The first launch opens Welcome to Orbit after read-only checks for Homebrew (`--version`), the selected Apple developer tools directory (`xcode-select -p`), macOS guidance, application location, and bundled executable password helpers. Missing Homebrew links to the official installation guide. Missing tools offer Copy tools setup command and Open Terminal; no command is executed for the user. Moving the app to Applications is suggested without modifying it. Permissions are explained and requested only when needed by later operations.

Check again reruns detection after setup. Continue (or Browse apps for now when prerequisites are missing) records completion locally. Later launches perform the same checks but show the screen automatically only if setup was never completed or Homebrew/password helper checks fail. Optional developer-tools, location, and OS recommendations do not repeatedly interrupt completed setups. Setup check in the sidebar reopens the screen. Homebrew inventory refresh runs after leaving the screen when Homebrew can start; browsing is available without Homebrew, while Homebrew operations require the required setup checks to pass and installation still requires known Homebrew inventory.

Tests use injected environments, command replies, and isolated defaults to verify read-only scope, first-run/completed behavior, missing/broken prerequisites, optional suggestions, local completion, repeated-window protection, reopening, and preview isolation. No software is installed and no permissions are granted during checks or tests.

## Inline Cleanup and Explore Homebrew (v0.10)

Cleanup is now a sidebar destination in the main window. Its scan results, selection, developer-cache option and operation details remain in shared app state when switching pages. Only the final Trash confirmation uses a small alert. Existing scope, identity/symlink checks, empty default selection and personal-file discovery protections remain in place.

Explore Homebrew downloads metadata from the official Homebrew/core and Homebrew/cask APIs when opened, with name/description search, application/CLI filters, availability filtering, versions and detail links/statistics. Results show up to 150 entries; narrow the search to find more. The catalog is cached for 24 hours, can be refreshed manually, and retains its last successful snapshot when offline. Private or third-party taps are not added by this explorer.

Add to My apps saves a favorite without installing it. Select to install registers the package and adds it to the ordinary reviewed installation workflow. My apps can include starter-catalog entries and newly discovered packages. Personal metadata and favorites persist locally; removing a favorite does not uninstall it or discard package tracking. Registered packages join All Apps, Installed, selected updates, existing-app detection and setup export. Import recognizes both curated and previously registered package entries; unsupported entries remain reported.

Only explicitly selected packages are registered/exported; dependency lists are never converted into direct selections. Dynamic tokens and persisted metadata are validated, disabled/deprecated entries cannot be added, and dynamic lifecycle commands qualify official taps to avoid ambiguous package names. Live metadata is checked again before installation. Existing installed/local-app selection guards and vendor-installer disclosure apply. Export setup remains independent and can include installed personal packages.

Tests cover official-only API parsing, invalid tokens/taps, metadata deduplication, persistent-record sanitization, favorites, navigation selection preservation, dynamic mocked installation/update/removal, independent Brewfile round trips, dependency exclusion, offline refresh/filtering and retained inline Cleanup state. A separate optional check parses downloaded official API snapshots without installing software.

## Orbit naming (v0.11)

The app, executable, helper, interface, and documentation now use Orbit. The existing internal bundle identifier and cache directory (`io.macsetup.desktop`) are retained to preserve local preferences, favorites, and caches when upgrading.

## Orbit icon and DMG (v0.12)

Orbit uses a bundled original orbital logo in the sidebar, Welcome screen, and macOS app icon. The PNG source and multi-resolution ICNS are included in Resources/Branding.

Run `bash build.sh` then `bash package-dmg.sh` to produce a compressed DMG, with Orbit.app, an Applications shortcut, installation instructions, and a separate SHA-256 checksum. DMGs are release assets rather than Git source files. Current builds are ad-hoc signed, not notarized; users must trust the download and may need to approve it in macOS Privacy & Security. Creating a DMG does not bypass Gatekeeper.

## Terminal Setup (v0.13)

Terminal Setup is a main-window destination for developer essentials, language environments, and optional terminal integrations. The read-only scan inspects .zprofile, .zshrc, .zshenv, and .zlogin for existing configuration. Custom ZDOTDIR, non-UTF-8 or oversized profiles, links, wrong ownership, incomplete Orbit markers, and conflicting existing settings are blocked. Detection is conservative text matching; it cannot fully understand arbitrary shell frameworks or indirect includes. Only home-directory Zsh profiles are supported.

Review shows the new Orbit blocks, without exposing the rest of your profile. Apply rechecks the reviewed state, validates Zsh syntax using `zsh -f -n` without sourcing the profiles, saves originals privately under ~/.orbit-terminal-backups, and atomically replaces only .zprofile/.zshrc. Originals and a restore receipt are stored with private permissions. Existing content and permissions are retained. Orbit-managed blocks are replaced rather than duplicated; unchecking an Orbit option removes it. Multiple-file writes attempt rollback on failure and retain backup data. Filesystem rechecks cannot eliminate every concurrent-change race; avoid editing these profiles during apply or restore. Syntax checks do not prove runtime compatibility. Open a new terminal to use the settings.

Restore latest backup shows a confirmation and refuses to overwrite post-apply user edits. Open backup folder also exposes the saved originals for manual comparison. Restoring an originally absent profile removes the generated file. Backups persist across app launches and should be kept private because profiles can contain credentials.

Python uses uv with a chosen Python version, with explicit project helpers ov (create .venv) and oa (activate). It does not alter Apple's Python, install global pip packages, or activate environments automatically. Node loads existing official NVM or Homebrew NVM without adding Homebrew Node/Corepack. Homebrew NVM is unsupported by NVM upstream; this is disclosed. Node/Python/Rust/Ruby downloads are separate reviewed commands; installing Homebrew tools or applying profiles does not start those downloads. Java uses the installed Homebrew JDK 21 without system registration; Go adds its default tool path; Rustup and rbenv initialize only installed tools. ruby-build remains a dependency of rbenv and is not registered as a direct selection.

Missing tools are verified through official Homebrew metadata, registered only after all requested metadata checks succeed, and added to the existing reviewed install workflow. No installer runs from this page's selection action. Already present tools are excluded. Runtime initialization takes effect only in a later shell; selected tools may run their normal initialization then. Starship/fzf/plugin integrations are opt-in. No Oh My Zsh installer or remote script is executed.

Validation covers temporary-profile preservation, repeat apply, option replacement, private backup permissions, restore, absent profiles, changed files, symlink/hardlink rejection, custom directories, malformed markers, syntax failures and nonexecution of user shell code. Mocked metadata checks cover package selection without installer execution, offline all-or-nothing registration, and changing installation state. Tests never alter the user's real profiles.

References: [Homebrew shell completion](https://docs.brew.sh/Shell-Completion), [NVM](https://github.com/nvm-sh/nvm), [uv](https://docs.astral.sh/uv/getting-started/installation/), [Starship](https://starship.rs/guide/), [fzf](https://github.com/junegunn/fzf), [Rustup formula](https://formulae.brew.sh/formula/rustup).

## Workflow clarity (v0.14)

Explore Homebrew has actual installation checkboxes separate from app icons and an expandable Selected apps list with removal controls. It shares the existing install selection and review. My apps exposes Remove from My apps directly in each row; removing a favorite does not uninstall or alter installation selection. A short explanation distinguishes favorites from installation choices.

Cleanup supports explicit group selection, group clearing, and Select all cleanable items. Only removable scanned entries enter bulk selection; large personal files remain discovery-only. No default selection or deletion scope changes were made. Final confirmation and filesystem checks still apply. The scanning/Trash loader is centered within the results area. Updates displays a centered loading state with current guidance, and batch progress describes processed items and remaining items rather than pretending to know each package's byte-level percentage. Update queues mark waiting items and mark untouched items skipped when stopped.

Operation details now opens a common summary with package outcomes and detected errors; the technical log is separately expandable and copyable. Successful inventory/API stdout no longer clutters the log, while stderr diagnostics and installer output are retained. Select all/Clear controls are visibly bordered. Tests cover safe bulk selection, shared dynamic selection and favorite removal, aggregate progress, result/error summaries, and diagnostic-only metadata logging.

## Menu bar panel (v0.15)

A native status item uses a monochrome Orbit symbol, with a small activity dot during setup or package operations. Its compact panel contains Open Orbit, cached available update counts, Check for updates, Cleanup, Operation details and Quit Orbit. Counts do not depend on the current search filter. Setup and operation guards prevent navigation or duplicate update checks while an operation is active. Cleanup never displays stale package counters or a package stop button.

Closing the main window hides it while keeping its store and operation state alive. The panel or Dock reopens it. Quit is blocked during operations and preparation. Check for updates opens the Updates page and runs the existing check; all package and cleanup modifications retain their reviewed flows. No automatic scheduled checks, launch-at-login setting or notification permission is introduced.

MenuBarTests covers status, counts and action guards. The nonoperating --menu-bar-smoke-test checks the real native status item, popover, window hide/reopen, minimize recovery and shared navigation using preview data.

## Screen Recorder (v0.16)

Capture a full display, a selected rectangle or a non-Orbit window using ScreenCaptureKit on macOS 14+. Recording works independently of Homebrew. Source refresh or Start recording requests Screen Recording access; microphone and webcam authorization is requested only if enabled. Shortcut labels optionally request Input Monitoring and show only Command/Control combinations from physical key codes, never typed text or clipboard contents. Key labels currently use a fixed US physical-key map. Audio, camera, shortcuts and cursor-follow zoom default off.

The menu bar panel provides capture mode and Start recording; window mode opens the recorder page to choose a window if one is not already selected. A three-second countdown and floating pause/stop controls are provided. Menu bar status shows a red icon and elapsed time. Orbit's own windows, including the controls, are excluded from display recordings; window recording captures only its selected window. Package operations and recording cannot start over each other. Quitting is blocked during preparation, recording, finalization or trimming. Sleep, source disappearance and device runtime errors stop and finalize the recording where possible.

Frames are composited before encoding: configurable halo color/size, click rings, optional smooth cursor-follow zoom, webcam circle, shortcut badges, and normalized privacy rectangles. Privacy areas remain fixed relative to the capture frame; they do not track text or objects. Blur may leave recognizable details; use opaque covers for secrets and preview before sharing. Window output dimensions remain fixed during a recording; resizing a window can stretch the image and move content relative to masks. On macOS 14.2+ single-window shadows are excluded.

Microphone and system audio are encoded as independent source tracks then mixed into one MP4 audio track. Pause removes the paused interval from media timestamps. A private temporary MOV contains already-composited video; the final MP4 is saved to a user-selected new filename with restrictive file permissions. Saving does not replace an existing file, including one created at the chosen destination while recording. Export failures retain a source/recovery file where possible. The preview supports Show in Finder, Copy file and trim-to-new-copy. Recent recordings are listed for the current session. No cloud service, upload, launch-at-login, automatic capture or notification permission is required.

`RecorderTests` uses generated color frames and tones with the actual encoder, two-source audio mix, decoder and trim exporter. It checks multi-display coordinates, privacy composition, halo/ring/zoom/badge/camera effects, pause timestamps, output collision protection and operation guards. The suite needs normal macOS graphics and codec services (a restricted graphics sandbox can produce empty frames). No real screen, camera, microphone or keyboard monitoring is started in tests or previews. Native menu smoke tests cover recorder status and access. Live permission dialogs, hardware capture and multi-monitor behavior still need on-device acceptance testing.

### Video preview compatibility (v0.16.1)

The completed-recording preview hosts native AVPlayerView directly instead of SwiftUI VideoPlayer. On the tested macOS 27.0.1 system, the SwiftUI AVKit overlay aborted while resolving VideoPlayerView superclass metadata. The regression suite now instantiates the completed-recording SwiftUI page with a generated MP4 and checks native player attachment, controls, replacement and teardown. The playback preview command exercises this branch without requesting capture permissions.

### Compact recording controls (v0.16.2)

Menu recording opens a movable, nonactivating control panel without navigating or activating Orbit's main window. Choose Full screen, Area or Window, then press Start. Window sources can be refreshed/chosen in the compact panel. Area recording asks for a fresh rectangle each time controls are opened. The panel handles preparation/cancellation, countdown, pause/resume/stop, inline errors and a Show last recording action. Compact recordings use unique MP4 filenames in Movies/Orbit Recordings; the main recorder page retains its save dialog. Neither capture nor device access starts just by opening controls. Advanced effects remain configurable on the main recorder page. The menu's segmented source selector hides its label to prevent vertical clipping in narrow popovers.

Main-window reopening requests Dock restoration only for genuinely minimized windows, preventing unnecessary deferred foreground restoration during compact recording setup. Native smoke coverage checks the main window stays hidden while compact controls are opened and keeps minimize/reopen coverage separate.

### Screen permission refresh (v0.16.3)

Source refresh queries ScreenCaptureKit directly; the previous CoreGraphics preflight/request gate could return false before the recorder API was ever reached. ScreenCaptureKit success is accepted immediately. Only its explicit userDeclined error is described as denied access, with guidance for a stale installed-copy permission and the actual error domain/code. Other source failures retain their original details. Failed refresh clears stale sources, selected IDs, area and masks; successful refresh clears previous error text. No permissions are bypassed or reset automatically. Regression tests use injected success/denial/source errors and do not prove the installed app's TCC authorization. Ad-hoc builds may still need their installed copy reauthorized; stable signed distribution remains separate work.

## Mac tools and capture studio (0.17.0)

- Permission Center: passive status inspection, explicit requests, direct ScreenCaptureKit verification and Settings links. Also available during first-launch/setup checks and installation review. Permissions belong to Orbit, not apps it installs.
- App Health Check: Homebrew version, missing dependencies, doctor output, known managed bundle locations, Orbit location and packaged helper. Diagnostic only; custom app locations can require manual review.
- Login Items: SMAppService for Orbit, exact-identity System Events management for standard login apps, confirmation before removal, native Settings for background services.
- Recording annotations: arrow, rectangle, pen, highlight, text, color, Undo and Clear. Drawing mode intercepts region clicks; switch off for normal app interaction. The red capture border is visible locally but excluded from recordings.
- Screenshot Studio: display/area/window capture, annotation editing, blur/solid cover, flattened PNG clipboard and exclusive new-file export. No upload.

Automated verification uses synthetic images, real local video encoding/decoding with annotation location and privacy-cover assertions, injected command responses and nonoperating native UI fixtures. macOS consent prompts, live ScreenCaptureKit capture and actual login registration require device acceptance testing.

## Homebrew Center (0.18.0)

The five former sidebar destinations are grouped into one Homebrew Center with Discover, Installed, Updates and My Apps tabs. Discover switches between Curated and All Homebrew, shares search across sources and remembers its source when switching tabs. Category browsing remains available within Curated/Installed.

The shared To install panel persists across all four tabs. Homebrew removal choices are parked separately, so entering Installed never deletes or overwrites persisted installation choices. Update and manual-adoption selections remain independent. Review installation from Installed/Updates explicitly returns to the normal installation review.

## Terminal Setup workspace (0.21.0)

See [Terminal Setup](TERMINAL-SETUP.md) for the three-tab workflow, automatic read-only discovery, explicit version probes, project requirements, custom aliases, Git identity, portable setup files and private multi-file backups.
