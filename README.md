# Turbulence Lab

A native macOS laboratory for interactive 2D incompressible turbulence. SwiftUI controls a GPU-resident Float32 pseudo-spectral solver, Metal compute kernels, reusable VkFFT plans, and a Retina MTKView. Built and tested on a **32-core GPU M1 Max with 64 GB unified memory**.

The complete solver, four presets, four visualization fields, seeded initialization, vortex painting, automatic CFL control, live physical diagnostics, numerical tests, and command-line benchmarks are implemented. There is no MLX or Python dependency and no CPU solver fallback. The original project specification is preserved in [REQUIREMENTS.md](REQUIREMENTS.md).

## Open and run

1. Open **`TurbulenceLab.xcodeproj`** in Xcode.
2. Select **TurbulenceLab → My Mac** and run (`⌘R`). The shared scheme uses Release for interactive performance.
3. The window opens centered, fitted around the square simulation image, with Decaying turbulence, the Inferno palette, and exposure −1.3. Resize it to scale the image without surrounding padding. Drag in the field to stir the flow.

Requires Apple Silicon, macOS 15 or later, Xcode with its Metal compiler component installed. Verified with Xcode 26.3 on macOS 15.7.9. All third-party headers and licenses are vendored; opening/building requires no dependency downloads or package manager. If Xcode reports a missing Metal toolchain, install it from Xcode Settings → Components, or run `xcodebuild -downloadComponent MetalToolchain`.

Terminal build and launch:

```sh
xcodebuild -project TurbulenceLab.xcodeproj -scheme TurbulenceLab \
  -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Release/TurbulenceLab.app
```

A signing team is unnecessary for the command-line build above. Xcode can use local signing for development; distributing a notarized app is outside this repository's current scope.

## Controls

- **Space / Start / Pause** controls advancement. Pausing drains the already submitted work.
- **⌘R / Reset** rebuilds the selected seeded flow.
- **Preset:** decaying turbulence, vortex gas, Kelvin–Helmholtz double shear, or forced inverse cascade.
- **Spectral grid:** N = 256, 512, 1024, or 2048 per axis. Nonlinear evaluation uses M = 3N/2: 384, 768, 1536, or 3072 per axis. The inspector shows both sizes; N = 2048 is a stress configuration.
- **Seed:** edit and press Return to regenerate a reproducible field.
- **Viscosity, drag, forcing:** update the GPU dynamics live.
- **Maximum dt / Automatic CFL:** automatic mode computes a fresh velocity bound on the GPU every step. CFL defaults to **0.80**, with an inspector range of 0.10–0.82 and a maximum-dt default of 0.02. Fixed mode still enforces the explicit diffusion limit, but the user must choose an advectively stable dt. [The CFL study](Benchmarks/CFL_STUDY.md) records stability and accuracy limits.
- **Steps / batch:** 1, 2, 4, 8, or 16. More work per submission can improve throughput and increase interaction latency. Four is the interactive default.
- **Field:** vorticity, velocity magnitude, streamfunction, enstrophy density. Field-specific fixed unit scales keep small streamfunction values visible.
- **Palette:** Ice/Fire, Inferno, Turbo, Neon; exposure, contrast, and optional contour bands affect rendering only.
- **Left drag:** positive vortex. **Right drag:** negative vortex. Injection is a periodic Gaussian added directly in Fourier space, with zero mean and dealias projection.

Rendering targets 60 Hz, independently of the simulation's timestep count. GPU snapshots are prepared on display demand, with a 5 Hz diagnostic heartbeat when the view is not requesting images. Three protected textures prevent simultaneous reads/writes of a snapshot.

Live diagnostics show resolution, simulated/active wall time, physical/wall ratio, steps/s, ms/step, presentation FPS, mean kinetic energy, mean enstrophy, maximum vorticity, maximum speed, and actual dt. The FPS counter uses drawable presentation timestamps. Magenta pixels and a pause/error message identify non-finite data.

The display maps `z = field * 2^exposure / unitScale`. Signed fields use `t = (1+tanh(z*contrast))/2`; positive fields use `t = 1-exp(-max(z,0)*contrast)`. Ice/Fire's midpoint is zero for signed fields. There is no per-frame min/max normalization that could hide decay or amplify weak noise. The scale is printed in the inspector. Inferno is useful for positive fields; Turbo and Neon are aesthetic alternatives rather than perceptually uniform scientific maps.

## Numerical method

On the periodic domain `[0,2π)²`:

```
∂tω + u∂xω + v∂yω = ν∇²ω − αω + f
∇²ψ = −ω,     u = ∂yψ,     v = −∂xψ
```

The primary state is complex spectral vorticity on an **N×N spectral grid**. With the forward convention `exp(-i k·x)`, `ψ̂ = ω̂/k²`, `û = i ky ψ̂`, and `v̂ = -i kx ψ̂`. VkFFT normalizes inverse transforms by the transform's grid size squared. The zero mode and even-grid Nyquist rows/columns are explicitly removed; all modes with `|kx|, |ky| < N/2` otherwise remain available.

**3/2 zero padding** removes quadratic aliasing. At every RK stage, signed spectral modes are embedded in an **M×M grid, M = 3N/2**, and multiplied by `(M/N)²` before the inverse FFTs. Nonlinear products are computed there, transformed forward, cropped back to N×N, and multiplied by `(N/M)²`. For N = 1024, the nonlinear FFTs are 1536×1536. The former 2/3 spectral cutoff is no longer used. SSP-RK3 advances advection, viscosity, drag, and stage-time forcing, using only original/current state buffers.

The optimized nonlinear evaluation packs two real fields into each complex inverse FFT: `(u,v)` and `(∂xω,∂yω)`. Its real nonlinear product uses an in-place **R2C forward transform**, and the RK kernel reconstructs the negative-x half through Hermitian symmetry. That is **six C2C inverse transforms and three R2C forward transforms per timestep**. The full C2C and five-transform reference paths remain available for tests and benchmark comparisons.

The GPU chooses dt from the user ceiling, a conservative SSP-RK3 diffusion bound using `K = N/2−1`, and optionally `CFL*(2π/M)/max(|u|+|v|)`, with the velocity bound reduced over the padded grid. No per-step CPU readback is needed. Display and physical diagnostics use the N×N grid. A compensated GPU clock avoids accumulating Float32 time-summation drift. Kinetic energy and enstrophy are spatial means, not domain integrals.

Forced inverse cascade uses seeded, Hermitian, spatially random forcing in `8 ≤ |k| ≤ 12` with smooth time correlations. It is not a white-noise stochastic integrator. See [ARCHITECTURE.md](ARCHITECTURE.md) for equations, layout, memory lifetimes, forcing, and synchronization details.

## Verification

```sh
./scripts/test.sh
```

Or run the built app's numerical suite directly:

```sh
build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab --self-test
```

The Xcode test target runs **86 deterministic numerical checks** across both FFT paths: N-grid and mixed-radix padded FFT roundtrips, signed-mode placement and scaling, high-mode retention, Nyquist handling, derivatives, Laplacian, Poisson inversion, velocity signs, divergence, zero mode, seeded initialization, inviscid conservation, viscous decay, 700-step finite evolution, compensated clock, RK convergence, Parseval diagnostics, packed/unpacked agreement, an independent Double DFT plus exact spectral convolution/RK3 reference, alias-prone high-mode interactions, all presets, full-band diffusion bounds, CFL, vortex injection, fault detection, and C2C/R2C comparisons through N = 2048 (M = 3072).

Metal API and shader validation were also run successfully:

```sh
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 \
  build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab --self-test
```

`./scripts/ui-smoke.sh` exercises centered startup, square image layout, resizing/zoom, pause/resume, fields/palettes, contours, vortex input, preset resets and grid reconstruction. Its previews (`app-preview.png` and `app-preview.minimum.png`) combine a cached native view hierarchy with the exact completed GPU field; they are layout verification artifacts, not desktop screenshots.

## Performance

The primary metric is **`R_turbo = T_simulated / T_wall`**. It includes the real solver, GPU CFL reduction, diagnostics, field conversion, rendering, CPU encoding, submission/backpressure and completion costs. FFT plan creation and warm-up are excluded. The interactive metric excludes explicit pauses after outstanding work drains.

[CURRENT_BASELINE.md](CURRENT_BASELINE.md) distinguishes the current solver from the recorded M1 Max measurements. Earlier 2/3-truncated timings describe a different resolution and workload from the 3/2-padded solver. [OPTIMIZATION_LOG.md](OPTIMIZATION_LOG.md) records experiments and numerical changes. [The complete measurement index](Benchmarks/SUMMARY.md) links recorded configurations and raw results.

`./scripts/cfl-study.sh` reproduces the matched-time CFL stability/accuracy search. `./scripts/cfl-ui-benchmark.sh` compares CFL 0.45 and 0.80 with three paired native-app runs. The study's synchronized verification timings are separate from production throughput. Use `--cfl-value C` for a chosen automatic CFL in CLI or UI benchmarks; larger experimental values are allowed in the CLI.

```sh
./scripts/benchmark.sh

# Explicit repeatable run, including a 1024² offscreen render after each batch:
build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab \
  --benchmark --size 1024 --steps 2400 --repeats 3 --batch 4 --dt 0.002

# Adaptive CFL throughput; compares different simulated intervals, not identical trajectories:
build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab \
  --benchmark --size 1024 --steps 2400 --repeats 3 --cfl --dt 0.02

# Actual visible app, including Retina presentation, with the window fitted to the screen:
: > Benchmarks/my-ui-run.txt
open -n -W --stdout "$PWD/Benchmarks/my-ui-run.txt" \
  build/Build/Products/Release/TurbulenceLab.app \
  --args --ui-benchmark --size 1024 --duration 20

# Isolated phase profiling (extra command buffers/waits perturb scheduling):
build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab --profile --size 1024
```

Benchmark switches: `--c2c` restores a full-complex forward transform; `--unpacked` uses four separate inverse transforms per stage; `--threads 128|256|512`, `--batch N`, `--display-every N`, and `--no-render` support controlled comparisons. `--eager-display` in a UI benchmark generates a snapshot every batch, allowing comparison with demand scheduling. `--r2c` is accepted for older experiment commands; it is now the default.

GPU timing spans are not occupancy measurements. Command-buffer intervals can overlap, so summing their durations overstates GPU time. The recorded end-to-end ratio always uses an actual wall-clock interval. Offscreen benchmark results are distinguished from visible-app presentation measurements; none are extrapolated from isolated FFT timing.

Explicit GPU image export (CPU pixel readback occurs only for this requested export):

```sh
build/Build/Products/Release/TurbulenceLab.app/Contents/MacOS/TurbulenceLab \
  --snapshot flow.png --size 1024 --steps 1600 --preset 1 --field 0 --palette 0
```

Optional isotropic spectra and semi-implicit time integration are not implemented. The current baseline is the measured and tested explicit GPU solver. Vendored dependency revisions, licenses, and the required VkFFT Metal ownership fixes are documented in [Vendor/README.md](Vendor/README.md).
