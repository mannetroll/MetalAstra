#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project TurbulenceLab.xcodeproj -scheme TurbulenceLab -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
mkdir -p Benchmarks

# Three paired runs, reversing the middle pair to reduce order bias.
# Quit other simulation instances before measuring the visible app.
for spec in 045:1 080:1 080:2 045:2 045:3 080:3; do
    tag=${spec%:*}
    repeat=${spec#*:}
    if [[ "$tag" == 045 ]]; then cfl=0.45; else cfl=0.8; fi
    output="$PWD/Benchmarks/cfl-ui-$tag-r$repeat.txt"
    errors="$PWD/Benchmarks/cfl-ui-$tag-r$repeat-errors.txt"
    : > "$output"
    : > "$errors"
    open -n -W --stdout "$output" --stderr "$errors" build/Build/Products/Release/TurbulenceLab.app \
        --args --ui-benchmark --size 1024 --duration 15 --cfl-value "$cfl" --dt 0.02
    if ! rg -q '^UI,1024,' "$output"; then cat "$errors"; exit 1; fi
    echo "Completed CFL $cfl, repeat $repeat"
done
