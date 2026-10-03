#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache Sources/Catalog.swift Sources/Store.swift Sources/Logos.swift Sources/Lifecycle.swift LifecycleTests.swift Tests.swift -o .build/RunnerTests
.build/RunnerTests
