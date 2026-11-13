# Orbit 0.24.0 preview

Writing Assistant lets users review and revise selected or pasted text from the menu bar. Suggestions stay on the Mac and are applied only after the user chooses Copy or Replace. Live spelling marks are available as an opt-in pilot.

## Manual acceptance before publication

- With Accessibility denied, paste an English and a Turkish sample. Check Proofread and Copy without granting access. If a dictionary is missing, verify the panel explains why the request cannot run.
- In Notes and a frequently used editor, select text and open the assistant through the shortcut and menu bar. Confirm Replace affects only the original selection. Change the selection, focused field or source app before pressing Replace and verify the original text remains untouched. In unsupported fields, Copy should remain available after generating a suggestion.
- In a secure text field, confirm no selected text appears in Orbit. Close the panel during a review and verify its contents are cleared.
- On a Mac with an available Apple Intelligence model, test Proofread, Rewrite and each tone in the supported languages. Check that names, numbers and meaning survive. With the model unavailable, verify spelling-only fallback and a clear message for Rewrite or tone changes.
- With existing shortcut preferences, assign Writing Assistant without changing existing bindings. Confirm the shortcut works when Orbit's main window is closed.

Collect findings first. Apply fixes together after acceptance testing, rerun the affected checks, and package the final release separately from this local preview.

## Expanded Writing Assistant preview

- Proofread shows colored before/after cards. Deselect individual changes or use Accept all / Reject all, then check the combined result before Copy or Replace. Punctuation and spacing cards explain that change; other cards are intentionally labeled as text changes rather than claiming a specific grammar rule. Rewrite and translation are reviewed as whole results so sentence changes are not mixed across languages.
- Auto language requires a confident English or Turkish match. Use the manual English, US English, UK English or Turkish option when it is unsure. The local model and spelling dictionaries determine what runs.
- Translate (faithful) and Translate (natural) offer two approaches to English ↔ Turkish. Detect tone and Draft from notes are copy-only. Check the generated result for unchanged facts, identifiers, links and numbers.
- General, Work email, Slack message, QA bug report and Release notes provide different writing instructions. The local dictionary skips listed words in offline proofreading and guides model requests. Snippets append locally saved lines to the editor; editing the original detaches it from the source selection.
- Live spelling is off by default. Enable a supported app under Dictionary & snippets and grant Accessibility. Orbit shows small red marks beneath recognized misspellings in compatible focused fields. Click a mark to review, apply or ignore the suggestion. The full Writing Assistant panel pauses the marks. Chrome and ChatGPT coverage depends on the editor exposing text ranges and allowing replacement; this is not a browser extension.

### Additional acceptance checks

- To distinguish Orbit marks from the editor’s own dotted underlines, hover Orbit’s tinted underline for **Orbit · Review spelling**. Click that mark to open the card. The native smoke command `dist/Orbit.app/Contents/MacOS/Orbit --writing-spelling-smoke-test` uses synthetic text to exercise the button and card without inspecting another application.

- Accept one proofreading card and reject another; Copy and Replace should use only accepted changes.
- Try short and mixed-language text in Auto, then choose a language manually. Check US/UK conventions with installed dictionaries.
- Add a dictionary term and a snippet, reopen Orbit and confirm both persist. Verify a snippet does not write into the original app.
- With Apple Intelligence available, test both translation modes and all profiles. Confirm Tone and Draft cannot Replace a selection.
- Enable one live pilot app and verify other apps are ignored. Click a mark, apply one correction, then test Ignore and change the text before clicking an old suggestion. Verify marks clear on changing apps or disabling the toggle. Test Chrome and ChatGPT separately with synthetic text.
- Open Writing Assistant from a selection near the top, bottom and right edge of an editor. The panel should open below the selection when it fits, above it when there is more room, and stay within the display’s usable area. Repeat on a secondary display with the pointer on the other display. In an editor that does not report selection bounds, check the pointer-screen fallback.
- In **Dictionary & snippets**, enable **Show Orbit button beside selected text**. With Accessibility granted, select text in a compatible editor and verify the small button stays beside the selection, including near a secondary display edge. Click it and check that the assistant opens with that selection. Clear the selection, switch apps or disable the setting and confirm the button disappears. The setting is off by default; Orbit reads selection geometry while enabled and reads the text for this feature only when the button is clicked.
- After enabling the button, leave Writing Assistant open and select a new range in another app. The panel should no longer suppress the button. If the editor reports a nonempty selection but no bounds, the button stays near the pointer position recorded for that selection. Editors that expose neither a usable range nor selected text still need the manual paste workflow.

## Login launch acceptance

With Start at Login enabled, sign out and back in with the normal monitor setup. Use **Open Orbit** from the menu bar and check that the main window appears without restarting Orbit. Repeat after the display arrangement changes or after an external display is reconnected. A window already in a usable position should retain its location. The native smoke test covers opening with no main window and synthetic off-screen geometry; it does not perform a real logout or change Login Items.

## Update authorization acceptance

The update queue keeps the same controlling terminal for its sequential Homebrew commands. Homebrew still runs as the signed-in user, and sudo decides whether to reuse authorization. Orbit does not retain passwords or edit PAM or sudoers settings. The bundled askpass dialog remains available when sudo needs a password.

Run `python3 Tests/Homebrew/UpdateSessionFixture.py` to verify that simulated cask and formula upgrades share a terminal and preserve exit codes and literal arguments. This fixture never calls sudo. On a Mac with Touch ID for sudo already enabled, manually update two reviewed casks that actually require administrator access. Check whether macOS offers Touch ID at the first request, the second package reuses the approval, cancellation is reported and vendor dialogs are handled separately. Repeat without Touch ID to check the password fallback. Reuse depends on sudo policy and timeout.


Build 40: the native fixture opened the Orbit suggestion card with synthetic text. A manual TextEdit screenshot confirmed that the card appeared there. The screenshot of the other editor did not confirm Orbit marks or replacement; test that editor separately.

For changes developed after this release, see the separate [Capture Tools 0.25.0 guide](CAPTURE-PREVIEW.md).
