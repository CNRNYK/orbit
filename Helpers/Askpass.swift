import AppKit
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let alert = NSAlert()
alert.messageText = "Orbit · Administrator permission"
alert.informativeText = "Homebrew needs administrator permission for the selected operation. Your password is sent directly to sudo and is not saved."
alert.addButton(withTitle: "Allow operation")
alert.addButton(withTitle: "Cancel")
let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
alert.accessoryView = field
alert.window.initialFirstResponder = field
application.activate(ignoringOtherApps: true)
if CommandLine.arguments.contains("--self-test-cancel") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { alert.buttons[1].performClick(nil) }
}
guard alert.runModal() == .alertFirstButtonReturn else { exit(1) }
FileHandle.standardOutput.write(Data((field.stringValue + "\n").utf8))
field.stringValue = ""
