#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project TurbulenceLab.xcodeproj -scheme TurbulenceLab -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
