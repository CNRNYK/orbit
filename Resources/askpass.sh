#!/bin/sh
# The password is sent directly to sudo on stdout and is never written to a file.
exec /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
    activate
    set response to display dialog "Homebrew needs administrator permission to change the selected application. Mac Setup passes this password directly to sudo and does not save it." default answer "" with hidden answer buttons {"Cancel", "Allow operation"} default button "Allow operation" with title "Mac Setup · Administrator permission"
    return text returned of response
end tell
APPLESCRIPT
