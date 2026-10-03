#!/bin/sh
# Native password prompt; stdout goes directly to sudo.
exec "$(dirname "$0")/OrbitAskpass" "$@"
