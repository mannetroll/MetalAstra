# Optimization history

Hardware: Apple M1 Max, 32 GPU cores, 64 GB unified memory, AC power. macOS 15.7.9 (24G830), Xcode 26.3 (17C529). Experiments were run on the local interactive machine, not an isolated performance appliance; small differences require caution. All numbers below are measured, not projected.

## Verified baseline and integration repairs

Implemented Float32 spectral state, explicit SSP-RK3, strict 2/3 projection, private persistent buffers, a GPU CFL reduction on every step, and one compute encoder per submitted batch. Kept these as architectural requirements, without inventing an A/B speedup against an intentionally inefficient implementation.

The initial Release build succeeded, but a real GPU launch crashed while draining the VkFFT initialization autorelease pool. LLDB located `objc_release`/`objc_msgSend` under `TLFFTCreate`. Vendored VkFFT released autoreleased strings, command buffers and encoders. Owned string initialization, initialized compile options/error pointers, and correct command-buffer/encoder ownership fixed the crash. See `Vendor/README.md`. No numerical code changed. Repeated plan construction, teardown, resets, and both FFT paths now pass Metal API/shader validation.

Initial window testing passed once, but repeated launches revealed that SwiftUI scene restoration could suppress the initial window. The final app owns one AppKit window and native toolbar/menu bar explicitly, hosting all simulation content and inspector controls in SwiftUI. This removes dependence on saved scene state. Native first launch, repeated launches, pause/resume, resizing and preset/grid reconstruction are exercised by the smoke test. Earlier stalled UI launch attempts produced no valid performance results and are not baseline measurements.

Two instrumentation fixes were made before final measurement: command-buffer GPU intervals are merged/spanned instead of summed (they overlap), and the GPU simulated clock uses compensated summation. Pausing excludes wall time only after queued work drains. Actual presentation timestamps drive FPS, independent of steps/s.

## Controlled numerical/performance experiments

Unless stated otherwise: 1024², decaying preset, seed 42, ν=0.0001, α=0.01, fixed dt=0.002, batch=4, threadgroup=256, display/diagnostics and a 1024² offscreen render every batch. Twelve warm-up steps precede each repeat. Ratios are medians of three repeats. The first set uses 1,200 timed steps per repeat and C2C forwards. Changing batch size also amortizes display/diagnostics; it does not isolate command-commit cost alone.

| Candidate | Before R | After R | Change | Decision |
|---|---:|---:|---:|---|
| Pack velocity and gradient pairs: 5 → 3 transforms/stage | 0.730225 | 1.069230 | +46.42% | KEEP |
| Batch 1 → 4 timesteps | 0.859577 | 1.069230 | +24.39% | KEEP 4 as interactive default |
| Batch 4 → 8 | 1.069230 | 1.088434 | +1.80% | KEEP as user option |
| Batch 4 → 16 | 1.069230 | 1.133828 | +6.04% | KEEP as throughput option; more latency |
| Threadgroup 256 → 128 | 1.069230 | 1.063036 | −0.58% | REVERT default; retain test switch |
| Threadgroup 256 → 512 | 1.069230 | 1.070891 | +0.16% | REVERT default; difference is noise |
| Display/diagnostics every 4 batches instead of every batch | 1.069230 | 1.139916 | +6.61% | KEEP configurable; use display demand in UI |
| Skip forcing cosine/read outside the active forcing band, 2,400-step confirmation | 1.053041 | 1.064455 | +1.08% | KEEP; modest gain, not a large claim |
| R2C nonlinear forward FFT, 2,400 steps | 1.036671 | 1.125366 | +8.56% | KEEP, with variance caveat below |

### Transform packing

Files: `TurbulenceKernels.metal`, `SpectralSolver.swift`, `SimulationConfig.swift`. Hypothesis: two packed complex inverses can replace four separate inverses without changing the real fields. The packed/unpacked physical states agree within 4.8e-7 in the small-grid test. The independent Double CPU reference agrees at the same scale. FFT plan reuse and in-place workspace reuse are unchanged. Raw results: `01-packed.csv`, `02-unpacked.csv`, `experiment-baseline.csv`, `experiment-unpacked.csv`. The initial short run showed +49.45%; the longer result above is the more conservative comparison.

### Batching, diagnostics, threadgroups

Files: orchestration/configuration and benchmark harness. Hypothesis: amortize submissions/display work while preserving identical timesteps. The final energy/enstrophy are identical at reported precision across batch and display-cadence experiments. Threadgroup changes affect reduction rounding at ~1e-8 in energy and show no useful speedup. Raw results: `experiment-batch1.csv`, `experiment-batch8.csv`, `experiment-batch16.csv`, `experiment-display4.csv`, `experiment-threads128.csv`, `experiment-threads512.csv`.

The UI prepares snapshots when MTKView requests one, plus a 5 Hz diagnostic heartbeat. This preserves fresh per-step GPU CFL control; diagnostic throttling never changes timestep selection. `--eager-display` restores every-batch snapshots for an actual visible-app comparison. The final native-window comparison measured R=1.083981 eager versus R=1.136062 on demand (**+4.80%**), with 59.04 versus 59.44 presented FPS. Files: `release-ui-eager-1024.txt`, `release-ui-1024.txt`. This is a single matched 15-second UI pair; final results and host variability are recorded in `CURRENT_BASELINE.md`.

### Forcing branch

File: `TurbulenceKernels.metal`. Hypothesis: avoid a cosine and forcing-buffer read on the overwhelmingly many unforced modes. The numerical trajectory is unchanged. Initial 1,200-step medians improved 2.71%; a longer before/after shader-library swap improved 1.08%. This is a small measured improvement with host variability, not evidence for a universal percentage. Raw results: `experiment-forcing-branch.csv`, `forcing-confirm-before.csv`, `forcing-confirm-after.csv`. The isolated profile reduced RK phase time from about 0.461 to 0.401 ms, but other phases also varied with GPU state, so that isolated change is not used as the throughput claim.

### R2C forward transform

Files: `VkFFTBridge.h/.mm`, `MetalResources.swift`, `SpectralSolver.swift`, `SimulationConfig.swift`, `TurbulenceKernels.metal`, tests/harness. Hypothesis: the nonlinear product is real, so compute/store only its Hermitian half-spectrum. The physical kernel writes `N+2` padded rows; RK reconstructs negative-x modes directly. A second reusable plan replaces each C2C forward with R2C. No unpack kernel or additional copy is introduced.

The first C2C comparison repeat was an outlier (R=0.822350); the other two were 1.036671 and 1.076044. R2C repeats were 1.130847, 1.125055, 1.125366. Even comparing the slowest R2C repeat to the fastest C2C repeat gives +4.55%. Preserve this variance rather than treating the median +8.56% as a precise universal speedup. Raw results: `r2c-before.csv`, `r2c-after.csv`.

Numerical effect: maximum physical-field difference versus C2C after eight steps was 9.54e-7 at 256² and 512², 1.19e-6 at 1024², and 1.43e-6 at 2048². Both complete numerical suites, including forcing from rest, Hermitian forcing-band checks, conservation, RK convergence, and fault detection, pass. No precision reduction was used.

## Candidate audit and next work

The following covers the requested optimization areas without claiming unperformed experiments:

| Area | Status / evidence |
|---|---|
| Fewer transforms, real forwards, Hermitian symmetry | Measured and retained as above |
| Reusable plans/scratch, in-place transforms, immutable spectral coefficients | Baseline requirements; verified by ownership/code inspection and repeated tests |
| Fewer commits, multiple steps per command buffer | Measured batch sweep; 4 balances latency and throughput |
| Reduced CPU waits, asynchronous diagnostics | Normal loop has no synchronous GPU waits; bounded completion-driven submission |
| Fused spectral construction / nonlinear product + CFL partials | Baseline implementation; no separate-fusion percentage claimed |
| Fused RK linear terms/forcing/filter | Baseline plus measured forcing branch |
| Reduced temporary count, low-storage RK3 | Original/current state plus two reused derivative/display workspaces and RHS; lifetime table in architecture |
| Diagnostic frequency, direct texture rendering, triple buffering | Measured cadence experiment; protected snapshots; no normal CPU field readback |
| Threadgroup sizes | 128/256/512 tested; retained 256 |
| Float32 main state | Validated against Double reference; no lower precision physics |
| Half-precision display textures | Not retained or claimed: optional future memory-traffic experiment |
| Swift ARC / Objective-C autorelease overhead | One pool per batch, no field arrays in timestep, locally fixed VkFFT ownership; measured CPU encoding is small |
| Swift/C bridge-call reduction, additional encoder fusion | Not retained: CPU encoding is already a small share; GPU passes dominate |
| Four C2R inverse fields instead of two packed C2C fields | Not implemented; a different layout/transform scheduling experiment, not an assumed gain |
| Semi-implicit linear terms | Deferred: measured default 1024² CFL runs are advection-limited, well below the diffusion ceiling |
| Isotropic spectrum | Optional feature deferred; no hidden per-frame spectrum cost |
| GPU occupancy/counters | No occupancy claim. Command-buffer timestamps and isolated phase timings are available; counters would improve attribution |

The remaining cost is predominantly FFT work and global-memory traffic in spectral/RK kernels. Further worthwhile experiments are full half-spectrum state layouts, reduced RK/workspace traffic, and hardware-counter guided scheduling. They require the same deterministic correctness and end-to-end comparisons before adoption.

## Final self-review

Normal steps remain GPU-resident; only 32-byte completed diagnostics are read by Swift. Plans and large allocations are reused. No CPU waits occur between FFTs or stages. Both FFT normalization and Hermitian reconstruction are tested. The zero mode and strict 2/3 mask are applied at every necessary projection point. The renderer only acquires completed protected textures. CFL uses a fresh GPU reduction, independent of delayed diagnostics. Wall-time and simulated-time windows match; rendering FPS is separately measured. No CPU fallback, unimplemented solver branch, or claimed unmeasured performance remains.
