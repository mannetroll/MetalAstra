# Current verified baseline

Measured **2026-09-12** on Apple M1 Max (32 GPU cores, 64 GB), AC power, macOS 15.7.9 (24G830), Xcode 26.3 (17C529), Metal compiler 32023.864. This is the implemented and tested local Release build, not a projection for different hardware.

The baseline uses a SwiftUI interface in an explicitly owned native AppKit window; private Float32 spectral state; SSP-RK3; strict 2/3 projection; six packed C2C inverse FFTs plus three R2C forward FFTs per step; two reusable VkFFT plans; fused spectral/product/RK kernels; fresh GPU CFL control; a compensated GPU clock; and three protected display textures. Simulation is completion-driven with two in-flight batches. The UI requests snapshots at display cadence with a 5 Hz diagnostic heartbeat. No normal field readback or per-step CPU wait occurs.

## End-to-end offscreen measurements

All rows include diagnostics, GPU field conversion, and a **1024×1024 offscreen fragment render after every four simulation steps**, plus CPU encoding, submissions, backpressure, and completion handling. They are uncapped throughput runs, not presentation FPS measurements.

Configuration: decaying preset; seed 42; ν=0.0001; α=0.01; batch 4; threadgroup 256; Float32; inverse normalization enabled; R2C forwards. Each repeat resets, warms up 12 steps, then times the stated step count. The reported row is the median by R_turbo of three repeats. R_turbo is actual completed simulated time divided by measured elapsed wall time; higher is better.

| Grid | Timed steps/repeat | Fixed dt | ms/step | steps/s | R_turbo | Range across repeats |
|---|---:|---:|---:|---:|---:|---:|
| 256² | 12000 | 0.002 | 0.3120 | 3205.5 | **6.4110** | 6.3486–6.8929 |
| 512² | 6000 | 0.002 | 0.5075 | 1970.3 | **3.9405** | 3.9375–3.9649 |
| 1024² | 2400 | 0.002 | 1.7875 | 559.4 | **1.1189** | 1.1133–1.1253 |
| 2048² | 600 | 0.002 | 8.2287 | 121.5 | **0.2431** | 0.2422–0.2448 |

Automatic CFL uses a 0.02 ceiling and CFL=0.45. It changes the simulated interval/trajectory, so its increase over fixed dt is **not** a kernel speedup. At 2048² the conservative CFL bound chooses a smaller dt than the fixed benchmark.

| Grid | ms/step | steps/s | Mean dt over timed steps | Last dt | R_turbo |
|---|---:|---:|---:|---:|---:|
| 256² | 0.2468 | 4052.5 | 0.018148 | 0.020000 | **73.5446** |
| 512² | 0.5010 | 1995.9 | 0.006867 | 0.009514 | **13.7055** |
| 1024² | 1.8183 | 550.0 | 0.002824 | 0.002674 | **1.5531** |
| 2048² | 8.2241 | 121.6 | 0.001509 | 0.001431 | **0.1834** |

Raw current data: [256 fixed](Benchmarks/release-fixed-256.csv), [512 fixed](Benchmarks/release-fixed-512.csv), [1024 fixed](Benchmarks/release-fixed-1024.csv), [2048 fixed](Benchmarks/release-fixed-2048.csv); corresponding `release-cfl-*.csv` files contain all adaptive repeats. Earlier `final-*.csv` measurements are retained as history from before the final native-window revision. They showed some faster timings, especially at 256²; they are not silently substituted for the current run. The host is not isolated, and the small-grid result is sensitive to CPU/driver scheduling and concurrent desktop work.

## Actual visible application

One 15-second run per grid, same decaying/seed/viscosity/drag settings, fixed dt=0.002 and batch 4. Content area is 1280×900 points; the actual MTKView drawable is **1620×1620 pixels**. These runs include the native interface, window server, Retina rendering and presentation. FPS is averaged from actual drawable presentation timestamps. Simulated intervals differ because the app runs uncapped.

These recorded UI measurements predate the fitted window layout. Current launches size the window around a square image that fits the screen, so new visible-app runs can use a different drawable size.

| Grid | ms/step | steps/s | R_turbo | Presented FPS |
|---|---:|---:|---:|---:|
| 256² | 0.2148 | 4656.2 | **9.3125** | 58.65 |
| 512² | 0.4600 | 2173.8 | **4.3476** | 57.92 |
| 1024² | 1.7605 | 568.0 | **1.1361** | 59.44 |
| 2048² | 8.0741 | 123.9 | **0.2477** | 30.84 |

At 1024², generating every-batch snapshots instead of display-demand snapshots measured **R=1.083981**, 1.845050 ms/step and 59.04 FPS, versus **R=1.136062**, 1.760467 ms/step and 59.44 FPS with demand scheduling: **+4.80%** R_turbo. This is a single matched UI comparison, not a statistical guarantee. Raw files: `release-ui-*.txt` and `release-ui-eager-1024.txt`.

The 2048² stress configuration is limited to about **31 presented FPS** at batch 4. Four 8 ms steps per submission increase render latency on the shared queue. It is functional and numerically verified, but stable 60 Hz is not claimed there. 256²–1024² were near 60 Hz in these measurements. The default vortex-gas preset has a different velocity/CFL trajectory from these controlled decaying-preset benchmarks; do not assume it will have the same R_turbo.

## Attribution and validation

The isolated 1024² GPU profile measured the following milliseconds per timestep (10-step average). It splits phases into separate command buffers and waits, so these timings perturb scheduling and **must not be used as an end-to-end total**. Display conversion/rendering is profiled once per step here, versus once per batch in the offscreen benchmark.

| Phase | GPU ms |
|---|---:|
| RK update | 0.4523 |
| clock | 0.0046 |
| forward FFT | 0.2159 |
| inverse FFTs | 0.5833 |
| nonlinear + CFL | 0.1811 |
| rendering | 0.1565 |
| spectral | 0.3040 |
| visualization + diagnostics | 0.3481 |

FFT work is the largest combined phase; RK and spectral memory traffic follow. At 1024², recorded CPU encode wall time varied from roughly 0.015 ms/step in earlier trials to 0.10–0.12 ms/step in the final command-line run, while GPU timeline span remained close to total elapsed time. This host variability is preserved in the raw data. GPU timestamp spans include scheduling effects; they are not an occupancy or busy-percentage counter. No claim of exact GPU utilization is made.

Verified: Release build; **two XCTest cases covering 72 deterministic numerical checks**, both full-complex and R2C paths; Metal API and shader validation; native toolbar pause/resume; first launch/relaunch; resizing; all four fields/palettes; contours; mouse vortex input; presets and grid reconstruction. All passed. R2C/C2C physical-state agreement reaches 2048² (max error 1.43e-6). The independent Double DFT/RK3 reference agrees at sub-1e-6 scale on the small grid. Raw validation is in `Benchmarks/metal-validation.txt`, `Benchmarks/xcode-tests.txt`, and `Benchmarks/ui-smoke.txt`.

## Reproduce

```sh
./scripts/test.sh
./scripts/benchmark.sh
```

Quit the interactive app and avoid other GPU-heavy work during offscreen runs. Keep AC power connected. Do not enable Metal validation or attach a debugger for performance measurements. The scripts use the local unsigned Release build; no downloads are required.

```sh
# Exact 1024² fixed-dt row:
build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab \
  --benchmark --size 1024 --steps 2400 --repeats 3 --batch 4 --dt 0.002

# Automatic-CFL row:
build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab \
  --benchmark --size 1024 --steps 2400 --repeats 3 --batch 4 --cfl --dt 0.02

# Visible-app run (open appends stdout, so start with an empty log):
: > Benchmarks/my-ui-run.txt
open -n -W --stdout "$PWD/Benchmarks/my-ui-run.txt" \
  build/Build/Products/Release/TurbulenceLab.app \
  --args --ui-benchmark --size 1024 --duration 15
```

For other grids use 12,000 steps at 256², 6,000 at 512² and 600 at 2048². Initialization/plan construction and the 12 warm-up steps are excluded from offscreen timing. UI timing starts after solver setup and includes its first completed display. Pauses are excluded only after submitted work drains.

Source fingerprints are in [Benchmarks/source-sha256.txt](Benchmarks/source-sha256.txt); dependency revisions and ownership patches are in [Vendor/README.md](Vendor/README.md). [OPTIMIZATION_LOG.md](OPTIMIZATION_LOG.md) preserves all candidate results and limitations. No unmeasured optimizations, live spectrum or semi-implicit solver are claimed.
