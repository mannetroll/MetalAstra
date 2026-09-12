#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project TurbulenceLab.xcodeproj -scheme TurbulenceLab -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
app=build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab
mkdir -p Benchmarks
run_study() {
    local output=$1
    shift
    "$app" --cfl-study --batch 16 "$@" > "Benchmarks/$output"
    echo "Completed $output"
}

# Locate failures, then refine the inviscid high-mode boundary.
run_study cfl-stress-sweep-128.csv --size 128 --stress --viscosity 0 --drag 0 --dt 0.2 --times 1,5,20 --cfl-values 0.45,0.65,0.75,0.8,0.85,0.9,1,1.2,1.5
run_study cfl-stress-refine-256.csv --size 256 --stress --viscosity 0 --drag 0 --dt 0.2 --times 1,5,20,80 --cfl-values 0.8,0.82,0.83,0.84,0.85,0.86,0.88
run_study cfl-stress-refine-512.csv --size 512 --stress --viscosity 0 --drag 0 --dt 0.2 --times 1,5,20,80 --cfl-values 0.8,0.82,0.825,0.83,0.835,0.84

# Compare at identical physical times against CFL 0.225, across presets/seeds.
for preset in 0 1 2 3; do
    run_study "cfl-preset-$preset-256.csv" --size 256 --preset "$preset" --dt 0.02 --times 2,5,10,20 --cfl-values 0.45,0.65,0.75,0.8,0.85,0.9,1,1.2,1.5,2
    run_study "cfl-preset-$preset-seed7-512.csv" --size 512 --preset "$preset" --seed 7 --dt 0.02 --times 2,10,30 --cfl-values 0.45,0.8,0.82
done
run_study cfl-decaying-1024.csv --size 1024 --preset 0 --dt 0.02 --times 2,5,10,20 --cfl-values 0.45,0.8,1,1.1,1.2,1.3
run_study cfl-decaying-refine-1024.csv --size 1024 --preset 0 --dt 0.02 --times 2,5,10,20 --reference-cfl 1.1 --cfl-values 1.12,1.14,1.16,1.18

# Check reference convergence and the stress case at the largest supported grid.
run_study cfl-reference-convergence-256.csv --size 256 --preset 0 --dt 0.02 --times 2,5,10,20 --reference-cfl 0.1125 --cfl-values 0.225,0.45,0.8
run_study cfl-stress-2048.csv --size 2048 --stress --viscosity 0 --drag 0 --dt 0.2 --times 0.5,1,2 --cfl-values 0.8,0.82,0.83,0.84
run_study cfl-stress-long-1024.csv --size 1024 --stress --viscosity 0 --drag 0 --dt 0.2 --times 2,5,10,20 --reference-cfl 0.8 --cfl-values 0.82,0.83,0.835
run_study cfl-stress-edge-1024.csv --size 1024 --stress --stress-offset 1 --viscosity 0 --drag 0 --dt 0.2 --times 2,5,10,20 --reference-cfl 0.8 --cfl-values 0.82,0.83,0.835
