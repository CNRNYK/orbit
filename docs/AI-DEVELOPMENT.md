# Developing Orbit with AI

AI assists with implementation, documentation and fixture tests. Humans define scope and acceptance, review changes and validate the installed app. AI-generated code is subject to the same review and test requirements as any other contribution.

## Recommended workflow

1. Describe the user-visible problem, expected behavior and examples before asking for code.
2. Request a plan for broad changes; define what needs confirmation and what can proceed automatically.
3. Inspect current code and repository state. Existing screenshots or old conversations are context, not proof of current behavior.
4. Implement a focused branch. Preserve shared operation guards and distinguish install, remove, save and export selections.
5. Run meaningful fixture tests and build. Render changed UI and inspect it. Hardware permissions and capture need real device acceptance.
6. Open a PR with the resulting behavior, validation and remaining limits. Merge through the reviewed PR workflow.
7. Package from the merged commit; verify version, signature, DMG contents and checksum before publishing.

## Things the assistant must preserve

- Never run real uninstall, adoption, cleanup, login changes or profile edits as a test without explicit authorization.
- Validate exact paths and identities before moving files; prefer reviewed Trash operations and leave sensitive data unselected.
- Do not request all permissions at launch or try to bypass macOS consent.
- Do not record real screens, camera, microphone or keyboard activity to create documentation screenshots. Use app fixtures.
- Do not add dependencies to Brewfiles merely because Homebrew installed them transitively.
- Do not log passwords, embed credentials or publish private user data in code, screenshots, PRs or examples.
- Do not claim mocked commands prove hardware behavior. State what was actually verified.

## Useful task format

Specify the feature, current issue, desired flow, constraints, acceptance examples, required tests, and whether push/merge/release are authorized. For multi-PR work, describe dependencies and whether the next PR should start automatically.

## Maintaining context

Update architecture and behavior docs when flows change. Record implemented milestones in the changelog and keep ideas separate in the roadmap. Preserve the existing bundle identifier to retain preferences and avoid unnecessary permission identity changes. Stable Developer ID signing and notarization are separate release work, not something AI can substitute with a permission reset.
