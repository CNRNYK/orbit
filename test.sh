#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -parse-as-library -module-cache-path .build/module-cache Sources/Catalog.swift Sources/Store.swift Sources/Logos.swift Sources/Lifecycle.swift Sources/Repair.swift Sources/Adoption.swift Sources/Analytics.swift Sources/Maintenance.swift Sources/Startup.swift Sources/Explore.swift Sources/TerminalSetup.swift Sources/WorkflowUI.swift Sources/MenuBar.swift Sources/RecorderCore.swift Sources/RecorderEngine.swift Sources/RecorderSelection.swift Sources/Recorder.swift Sources/SystemTools.swift Sources/Annotations.swift Sources/ScreenshotStudio.swift MacToolsTests.swift LifecycleTests.swift RepairTests.swift AdoptionTests.swift MaintenanceTests.swift StartupTests.swift ExploreTests.swift Tests.swift TerminalSetupTests.swift WorkflowUITests.swift MenuBarTests.swift RecorderTests.swift -o .build/RunnerTests
.build/RunnerTests
