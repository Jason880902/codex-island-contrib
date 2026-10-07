#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CODING_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$CODING_TEST_DIR"' EXIT
swiftc -parse-as-library -o "$CODING_TEST_DIR/coding-provider-tests" \
  Sources/Model/IslandProvider.swift Sources/Model/ProviderVisibilityStore.swift \
  Sources/Model/UsageDisplayModeStore.swift Sources/Usage/AppUsage.swift \
  Sources/Usage/ConnectedUsage.swift Sources/Usage/CodingProviderConnection.swift Sources/Usage/GLMKeyStore.swift \
  Sources/Cost/TokenEvent.swift Sources/Cost/LocalCostScan.swift Sources/Cost/LogParseCache.swift \
  Sources/Cost/CodingLogReader.swift Sources/Cost/Pricing.swift Sources/Cost/PricingCatalog.swift \
  Sources/Cost/UsageLedger.swift Sources/Cost/CostUsage.swift Sources/Cost/CostBucketing.swift Sources/Cost/HistoricalUsageDay.swift Tests/CodingProviderTests.swift
"$CODING_TEST_DIR/coding-provider-tests"
