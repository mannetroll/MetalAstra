#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project TurbulenceLab.xcodeproj -scheme TurbulenceLab -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
mkdir -p Benchmarks
for spec in 256:12000 512:6000 1024:2400 2048:600; do
    n=${spec%:*}
    steps=${spec#*:}
    build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab --benchmark --size "$n" --steps "$steps" --repeats 3 | tee "Benchmarks/local-$n.csv"
done
