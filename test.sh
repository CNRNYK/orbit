#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Sources Tests -type f -name '*.swift' ! -path 'Sources/App/App.swift' | sort)
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -parse-as-library -module-cache-path .build/module-cache "${sources[@]}" -o .build/RunnerTests
.build/RunnerTests
