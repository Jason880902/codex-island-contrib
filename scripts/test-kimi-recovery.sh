#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
KIMI_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$KIMI_TEST_DIR"' EXIT
swiftc -parse-as-library -o "$KIMI_TEST_DIR/kimi-recovery-tests" \
 Sources/Model/IslandProvider.swift Sources/Model/UsageDisplayModeStore.swift Sources/Usage/AppUsage.swift \
 Sources/Usage/ConnectedUsage.swift Sources/Usage/ProviderSessionRecovery.swift Sources/Usage/KimiSessionRecovery.swift \
 Tests/KimiSessionRecoveryTests.swift
"$KIMI_TEST_DIR/kimi-recovery-tests"
