# Mac Setup

A native SwiftUI application for selecting, installing, and uninstalling Homebrew packages on macOS. English interface; MIT licensed source code.

## Use

Open **Mac Setup.app**. Browse categories, search, select apps, then choose **Install**. Review the plan before running it. Each package is checked against Homebrew's official JSON catalog before installation. Disabled, deprecated, and unverified packages are skipped.

Version 0.3 integrates the supplied Mac Power User / Developer / Designer / Creator toolkit. It contains 432 unique catalog entries across 27 categories, with expandable subcategories: 373 active Homebrew packages (246 casks and 127 formulas) and 59 manual or unavailable entries. All 437 numbered source entries are represented, including duplicates through shared category placements. The original application catalog is retained. It uses local application icons when available and native category icons otherwise. Selection is saved locally.

Homebrew must already be installed at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`. If it is missing, the application links to the official Homebrew setup instructions. After setting it up, use Refresh. The app does not install Homebrew automatically.

Already managed packages are skipped. Existing manually installed `.app` bundles are skipped unless you enable adoption. Adoption requires identical contents. Vendor `.pkg` and custom installers can run even when an app already exists; this is disclosed in the review screen. Licenses, subscriptions, and sign-in are handled separately by each vendor.

Homebrew runs as your user, not as root. For individual installers requiring administrator access, Homebrew uses the bundled `SUDO_ASKPASS` helper. This is an AppleScript password dialog labeled **Mac Setup · Administrator permission**, not a system authorization sheet. Its password output goes directly to sudo, is not saved or included in the application's logs. Canceling the dialog causes that installation to fail. macOS may request automation permission for System Events.

Installation is sequential. Logs are visible in **Operation details**. A failed package does not stop subsequent packages. **Stop after current app** waits for the running installer to finish instead of terminating it. Quitting during an installation is blocked. No extra cleanup, forced reinstall, automatic adoption, or automatic upgrade commands are used. Dependencies and vendor installers may still make changes as part of normal installation.

## App details and links

Click an app's icon, name, description, or info button to open its detail sheet. It shows a description, every category placement, installation availability, catalog version, package license when provided by Homebrew, and official links. Viewing details never starts installation or removal. The checkbox remains a separate selection control.

All 432 entries include an official website or project page. 314 have evidence-backed GitHub links. Source mirrors, extension collections, and issue trackers are labeled separately from source repositories. Unverified GitHub links are not guessed. GitHub links do not imply that the installed application itself is open source. Homebrew package pages are also linked when available.

Link provenance is stored in the catalog. `Scripts/update_package_links.py --metadata-dir /path/to/cache` can refresh links from official Homebrew API snapshots and package homepages; reviewed repository links are stored in `Scripts/verified_github_links.json`. External links open in the default browser; only HTTP(S) URLs without embedded credentials are accepted.

## Categories and starter selections

Expand a sidebar category to browse its subcategories, or use the section picker. Search includes package names, descriptions, categories, and subcategories. In All Apps, each package appears once; inside a category, repeated tools appear in their relevant category placement but share one selection and installation ID.

**Starter selections** includes the supplied Core Mac Stack groups (Mac, AI, Development, CLI, Creative, Media, Productivity, and Network), plus Discover 20. Presets add choices to your current selection; they never start an installation. Unavailable packages cannot be selected or exported. **Select all** includes only supported entries in the visible category or search result.

Manual or unavailable tools remain visible with **Setup details** and a vendor link where an exact link is known. Third-party taps, editor extensions, web applications, Windows-only tools, and self-hosted services are not silently substituted with unrelated Homebrew packages. Deprecated or disabled packages remain visible but are blocked from installation; if already managed by Homebrew, they can still appear for uninstallation.

The app's bundled `Resources/catalog.json` is editable and contains package names, official Homebrew metadata, category placements, source entry numbers, and presets. Availability is checked again online before installation. Optional tools such as Azure CLI are catalog choices, not preselected additions to a personal Brewfile. See [CATALOG-NOTES.md](CATALOG-NOTES.md) for mapping decisions and manual entries. Unverified popularity rankings and comparisons in the supplied text are not carried into the product.

## Uninstall apps

Switch to **Uninstall apps** to see Homebrew-managed installed packages within the curated catalog. Select apps, click **Uninstall**, and review the exact list. Nothing is removed until you confirm the removal screen. Switching between install and uninstall clears the selection to avoid carrying an install selection into removal.

Removal uses `brew uninstall --cask <token>` for casks and `brew uninstall --formula <token>` for formulas. Normal removal does not request extra cleanup (`--zap`), dependency overrides, or forced removal. Optional **Uninstall & Clean** separately reviews app-specific leftovers and moves checked items to Trash after successful removal. Automatic orphan dependency removal is disabled with `HOMEBREW_NO_AUTOREMOVE=1`. Homebrew can refuse to remove a formula required by other packages. Failures appear in Operation details; later selected packages continue. Vendor uninstallers may still remove app data or request administrator permission.

The stop button waits for the current removal to complete. Installed state is refreshed afterward. Manually installed applications and installed packages outside this catalog are not included in the uninstall list.

## Brewfiles

Export writes selected formulas and casks. Import recognizes plain `brew "token"` and `cask "token"` entries from this application's curated catalog. Comments and duplicate entries are handled. Ruby code is never evaluated. Unsupported entries, taps, VS Code extensions, and packages outside the catalog are reported rather than silently installed. Import replaces the current selection.

## Build

Requires macOS 14 or later and Apple Command Line Tools with a Swift compiler. No third-party Swift dependencies or full Xcode project are required.

```sh
chmod +x build.sh
./build.sh
open "dist/Mac Setup.app"
```

The build targets the current Mac architecture. The delivered build targets Apple Silicon. Local builds use ad-hoc signing; public distribution still needs an Apple Developer identity, notarization, and release testing.

## Validation

The executable includes a non-installing self-test:

```sh
"dist/Mac Setup.app/Contents/MacOS/MacSetup" --self-test
```

Tests check all 437 source entries, catalog uniqueness, available-package export/import round trips, manual-entry blocking, cross-category membership, starter preset deduplication, rejection of executable Brewfile input, and installer disclosure. Run `bash test.sh` for additional process-runner and installation-plan tests, including literal argument handling, launch failures, large output, and skip/adoption logic. Additional removal tests check installed inventory gating, installed-only filtering, and exact cask/formula removal arguments. Actual package installation, uninstallation, and the administrator password dialog are not exercised by these tests.

## Scope

This is an initial working version with a curated catalog, not the entire Homebrew catalog. Catalog availability is verified online before installation. Homebrew handles architecture and macOS compatibility; failures remain visible in the installation log. It does not restore app settings, install App Store products, or create Google web apps. NVM and Java may need shell setup after installation.

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

Mac Setup's own **Check app release** checks GitHub's latest release endpoint and links to the release page for manual download. The current private repository is unavailable to anonymous API requests; the app explains this and offers the browser page where the user can sign in. It does not collect GitHub credentials or automatically replace the running app. No published GitHub release is assumed.

**Uninstall & Clean** scans existing application bundle identifiers before removal. It reviews matching caches, logs, preferences, support folders, saved state, containers, HTTP storage, WebKit data, scripts, and cookies under the current user's Library. A small reviewed mapping adds app-specific paths for Chrome, VS Code, Blender, and Slack from the official Homebrew cask definitions. Shared group containers, vendor-wide folders, wildcard matches, system locations, and unrelated files are excluded; formulas have no guessed data cleanup. Cache/log entries are initially checked; settings and possible user data are unchecked. The user sees every path and its estimated size and can change the selection.

Only checked leftovers belonging to a successfully removed app are moved to Trash. Canonical paths and filesystem identity are rechecked immediately before each move; changed paths and symbolic links are rejected. Permission or Trash errors are shown separately from app removal. Users can restore trashed files. This is targeted cleanup and does not guarantee removal of every trace or service.

`bash test.sh` additionally uses simulated command results and isolated temporary fixtures to verify update parsing, selected upgrade arguments, invalid responses, pinned/latest exclusion, cleanup matching and sizes, data-sensitive defaults, symlink/replacement rejection, and successful-removal gating. Tests do not install, upgrade, uninstall, or trash existing applications or user files. Preview rendering skips Homebrew refresh and icon downloads.
