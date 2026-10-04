# Releasing

1. Start from the tested branch and update the version/build in build.sh plus README download links and the changelog.
2. Run regression tests and an optimized build; inspect changed fixture previews and run native menu smoke checks.
3. Push, create the English PR, attach it to the working task, inspect the exact head and merge through the PR workflow.
4. Pull the merged main commit. Rebuild if source content changed. Confirm the packaged Info.plist version/build and executable self-test.
5. Create the DMG:

```sh
bash package-dmg.sh /tmp/Orbit-VERSION-macOS-arm64.dmg
```

6. Verify the image with hdiutil, mount read-only, check Orbit.app and the Applications shortcut, verify the app signature, run the mounted self-test, then detach.
7. Publish the tag/release targeting the merged commit and upload the DMG plus its .sha256 file. Check the uploaded digest against the local checksum.
8. Report merged PRs, release/download links, verification and remaining hardware acceptance limits.

## Distribution status

Default builds are ad-hoc signed and not notarized. Private repository releases require GitHub access. ORBIT_SIGNING_IDENTITY can select an available signing identity, but Developer ID provisioning, hardened-runtime entitlements, notarization and stapling require a separate verified distribution workflow. Do not describe an ad-hoc build as notarized.

Keep CFBundleIdentifier (io.macsetup.desktop) stable across releases. Do not overwrite the running user app or reset its permissions during release validation. Source and DMG releases must refer to the same merged content.
