#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project TurbulenceLab.xcodeproj -scheme TurbulenceLab -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
: > Benchmarks/ui-smoke.txt
: > Benchmarks/ui-smoke-errors.txt
open -n -W --stdout "$PWD/Benchmarks/ui-smoke.txt" --stderr "$PWD/Benchmarks/ui-smoke-errors.txt" build/Build/Products/Release/TurbulenceLab.app --args --ui-smoke "$PWD/Benchmarks/app-preview.png"
cat Benchmarks/ui-smoke.txt
if ! rg -q 'ALL UI SMOKE CHECKS PASSED' Benchmarks/ui-smoke.txt; then exit 1; fi
