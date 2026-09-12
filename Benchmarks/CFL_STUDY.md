# CFL stability, accuracy, and throughput

Measured on 2026-09-12–13 on Apple M1 Max (32 GPU cores, 64 GB), using the Release build.

**Selected default: CFL 0.80**, up from 0.45. The inspector allows 0.10–0.82. CFL 0.82 was the highest tested value without growing error in the actual cutoff-mode stress test; 0.83 developed unphysical enstrophy growth and 0.835 crossed the failure threshold. The default N = 1024 viscous decaying flow tolerated 1.14 through t = 20, but 1.16 failed. That higher value is specific to the tested flow and settings; the default leaves room below the more restrictive inviscid boundary.

Three paired native-app runs at N = 1024 measured median T_turbo/T_wall increasing from **0.514694 to 0.949898 (+84.6%)**. Median presentation rates were 59.35 and 58.50 FPS.

The CFL number uses the padded grid: `dt_adv = CFL × (2π/M) / max(|u|+|v|)`, where M = 3N/2. Increasing CFL reduces the number of RK3 timesteps needed for a given simulated interval, provided the user timestep ceiling or explicit diffusion limit does not take over. It does not make an individual FFT or RK step faster.

## Method

The search contains 97 candidate runs across 17 studies, plus their reference runs. `--cfl-study` compares the same seeded initial condition at identical physical times against a CFL 0.225 Float32 reference. It shortens the final step at a checkpoint to match the target time, rather than comparing different simulated intervals. CFL 0.1125 is used for an additional reference-convergence check. Full-field L2 differences and relative energy/enstrophy differences are reported at each checkpoint.

The final decaying-flow boundary refinement compares candidates with the already-checked CFL 1.1 run; that run was compared with CFL 0.225 in the preceding sweep. The extended stress brackets use the established CFL 0.8 run as their reference. Their unforced invariant-growth checks also compare directly with the initial state, independently of the reference timestep.

Each candidate stops on non-finite values, stalled time, or more than 1% unphysical energy/enstrophy growth in an unforced flow. Forced-flow diagnostics are also compared with the matched-time reference; more than 10% excess growth is rejected. These are explicit detection thresholds. A run marked `ok` is finite and passes those growth checks; it is not automatically accurate or universally stable. The CSV records field error separately. In particular, the forced preset at N = 256, CFL 1.2 remained finite through t = 20 but had a 54% relative vorticity L2 difference.

The stress field is a unit-amplitude sinusoidal shear plus 0.01-amplitude perturbations at x wavenumbers N/2−2 and N/2−3, with viscosity and drag zero. This excites high-mode instabilities that smooth, viscous startup flows can hide. Stress runs use a 0.2 timestep ceiling so the normal 0.02 ceiling cannot conceal the CFL boundary.

The additional `--stress-offset 1` test excites N/2−1 and N/2−2, including the actual highest retained mode. The metadata prints the wavenumbers so the two stress definitions remain distinguishable.

The study synchronizes batches and reads fields for verification. Its wall times are not production throughput measurements. Throughput is measured separately with the native app and normal asynchronous engine.

## Stability evidence

| Case | Largest CFL below the stop threshold | First CFL crossing the stop threshold | Observation |
|---|---:|---:|---|
| Inviscid stress, N = 128, t = 20 | 0.85 | 0.90 | Enstrophy growth at t = 2.41 |
| Inviscid stress, N = 256, t = 80 | 0.83 | 0.84 | Enstrophy growth at t = 43.28 |
| Inviscid stress, N = 512, t = 80 | 0.83 | 0.835 | Enstrophy growth at t = 33.08 |
| Inviscid stress, N = 1024, t = 20, offset 2 | 0.83 | 0.835 | Enstrophy growth at t = 3.58 |
| Actual cutoff stress, N = 1024, t = 20, offset 1 | 0.83, with growing error | 0.835 | 0.82 stayed close to the reference; 0.835 stopped at t = 2.55 |
| Inviscid stress, N = 2048, t = 2 | 0.83 | 0.84 | Enstrophy growth at t = 0.665; short horizon |
| Decaying, N = 1024, seed 42, t = 20 | 1.14 | 1.16 | Enstrophy growth at t = 7.88 |

In the actual cutoff test, CFL 0.83's relative vorticity L2 difference from CFL 0.80 grew from 0.34% at t = 2 to **6.53% at t = 20**, with enstrophy **0.426% above the reference**. It remained below the coarse 1% growth stop threshold, so its CSV status is `ok`; that status does not justify choosing it as the default. CFL 0.82's final L2 difference was just **0.0076%**, with enstrophy within 0.000024% of the reference. The earlier stress cases mostly used offset 2 and did not initially excite the very highest retained mode.

These are finite-horizon brackets, not exact universal maxima. The retained maximum component is K = N/2−1. For constant-velocity inviscid advection, [SSP-RK3's imaginary-axis stability interval](https://ketch.github.io/numipedia/methods/SSPRK33.html) gives `CFL ≤ √3 M/(2πK)`, approaching 0.827 as N increases. This is a linear estimate, not a nonlinear guarantee. Viscosity, resolution, initial spectra, forcing, and mouse stirring all change the observed boundary.

## Accuracy and sensitivity

For the default N = 1024 decaying flow at t = 20, CFL 0.80 differs from CFL 0.225 by **1.104% in vorticity L2**, **0.097% in energy**, and **0.079% in enstrophy**. CFL 0.45 differs by 0.801%, 0.068%, and 0.056%, respectively. The higher setting has a modestly larger discrepancy with this reference.

The N = 256 reference-convergence run compares CFL 0.1125 with 0.225, 0.45 and 0.80. At t = 20 their vorticity L2 differences are 0.361%, 0.550% and 0.791%. A smaller-step Float32 run is a numerical reference, not an exact solution.

All four presets with seed 7 at N = 512 completed through t = 30 at CFL 0.80 and 0.82. Long-time pointwise agreement is much more sensitive in vortex gas: CFL 0.45 already differs from the reference by 92% in vorticity L2 at t = 30; CFL 0.80 differs by 98%, while their enstrophy differences are about 2%. Thus a successful stability run does not establish uniformly accurate chaotic trajectories. The raw tables include every checkpoint and diagnostic rather than hiding those differences.

## Native-app throughput

Three paired 15-second runs per setting, reversing the middle pair to reduce order bias. Settings: N = 1024, M = 1536, decaying preset, seed 42, viscosity 0.0001, drag 0.01, automatic timesteps with a 0.02 ceiling, batch 4, R2C forwards. Each run uses the normal asynchronous engine and visible native window with a 1600×1600 drawable. FPS comes from actual presentation timestamps.

| CFL | Median T_turbo/T_wall | Range | Median presented FPS |
|---:|---:|---:|---:|
| 0.45 | 0.514694 | 0.505828–0.521712 | 59.35 |
| 0.80 | 0.949898 | 0.948112–0.958513 | 58.50 |

The ratio of medians is **1.8456× (+84.6%)**. This measures completed simulated time per wall second in the app. The faster setting advances further into the decaying flow during each fixed wall-time run, so velocity and adaptive dt evolve over different physical intervals. The result includes that effect and normal desktop variability; it is not an isolated kernel speedup or a universal gain. The matched-physical-time studies above assess numerical differences separately.

## Verification and raw records

The Release build and both XCTest cases passed with the new 0.80 default: **86 numerical checks**, covering C2C and R2C paths. All six native-app benchmarks completed with empty stderr. See [numerical output](cfl-numerical-tests.txt) and [source SHA-256 fingerprints](cfl-source-sha256.txt).

| Study | Raw data |
|---|---|
| Inviscid stress, offset 2 | [N = 128](cfl-stress-sweep-128.csv), [N = 256](cfl-stress-refine-256.csv), [N = 512](cfl-stress-refine-512.csv), [N = 1024](cfl-stress-long-1024.csv), [N = 2048](cfl-stress-2048.csv) |
| Actual cutoff stress, offset 1 | [N = 1024](cfl-stress-edge-1024.csv) |
| Presets at N = 256, seed 42 | [Decaying](cfl-preset-0-256.csv), [vortex gas](cfl-preset-1-256.csv), [Kelvin–Helmholtz](cfl-preset-2-256.csv), [forced](cfl-preset-3-256.csv) |
| Presets at N = 512, seed 7 | [Decaying](cfl-preset-0-seed7-512.csv), [vortex gas](cfl-preset-1-seed7-512.csv), [Kelvin–Helmholtz](cfl-preset-2-seed7-512.csv), [forced](cfl-preset-3-seed7-512.csv) |
| Default decaying flow, N = 1024 | [Initial bracket](cfl-decaying-1024.csv), [boundary refinement](cfl-decaying-refine-1024.csv) |
| Reference convergence | [N = 256](cfl-reference-convergence-256.csv) |
| Native app, CFL 0.45 | [Repeat 1](cfl-ui-045-r1.txt), [repeat 2](cfl-ui-045-r2.txt), [repeat 3](cfl-ui-045-r3.txt) |
| Native app, CFL 0.80 | [Repeat 1](cfl-ui-080-r1.txt), [repeat 2](cfl-ui-080-r2.txt), [repeat 3](cfl-ui-080-r3.txt) |

## Reproduction

Build and rerun the recorded stability/accuracy matrix:

```sh
./scripts/cfl-study.sh
```

Run one custom case:

```sh
build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab \
  --cfl-study --size 1024 --preset 0 --seed 42 --dt 0.02 \
  --times 2,5,10,20 --reference-cfl 0.225 --cfl-values 0.45,0.8,1
```

Benchmark a chosen value with the production command-buffer pipeline:

```sh
build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab \
  --benchmark --size 1024 --dt 0.02 --cfl-value 0.8 --steps 2400 --repeats 3
```

For the three paired native-app measurements, quit other simulation instances and run `./scripts/cfl-ui-benchmark.sh`. For one run, launch the app with `--ui-benchmark --size 1024 --duration 15 --cfl-value 0.8 --dt 0.02`. Metadata records the actual CFL, timestep ceiling, padded size, and drawable size.
