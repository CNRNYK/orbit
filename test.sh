#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache Sources/Catalog.swift Sources/Store.swift Sources/Logos.swift Sources/Lifecycle.swift Sources/Repair.swift Sources/Adoption.swift Sources/Analytics.swift Sources/Maintenance.swift Sources/Startup.swift Sources/Explore.swift Sources/TerminalSetup.swift Sources/WorkflowUI.swift Sources/MenuBar.swift LifecycleTests.swift RepairTests.swift AdoptionTests.swift MaintenanceTests.swift StartupTests.swift ExploreTests.swift Tests.swift TerminalSetupTests.swift WorkflowUITests.swift MenuBarTests.swift -o .build/RunnerTests
.build/RunnerTests
