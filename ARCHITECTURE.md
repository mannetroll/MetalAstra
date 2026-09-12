# Turbulence Lab architecture

## Execution and ownership

`ApplicationDelegate` explicitly owns the native AppKit window, toolbar and menu bar, with an `NSHostingController` hosting the SwiftUI interface. This ensures a fresh visible window on every launch without depending on scene restoration. `SimulationModel` owns the SwiftUI state. `SimulationEngine` confines solver configuration, VkFFT plan use, and command encoding to a serial worker queue. A completion-driven pump keeps at most two simulation command buffers outstanding. There is no busy polling or simulation work on the main thread.

A normal batch uses **one serial compute encoder** for all RK stages, GPU CFL reduction, optional injection, and requested completed-state display conversion. The opaque C bridge appends VkFFT dispatches into that same encoder. Explicit buffer barriers separate custom operations and transforms. The Metal command queue preserves dependencies between batches. Two C2C plans and an R2C plan, pipelines, buffers, and textures persist until the grid or preset is reset.

`SnapshotExchange` protects three private RGBA32Float textures with a small CPU lock and reader/writer reservations. The GPU fills a reserved texture, then its completion handler publishes it. `MTKView` requests a fresh snapshot and acquires the latest completed one; a render completion handler releases it. Writers never touch the latest texture or a texture with readers. Rendering and simulation share one command queue, with at most two rendering submissions outstanding. MTKView targets 60 Hz; an idle-view 5 Hz heartbeat keeps diagnostics and fault detection alive. Large user-selected batches can increase display latency; they never block the main thread waiting for the solver.

An encoder or command buffer may still allocate small driver objects. There are no field arrays, FFT plans, or large Metal allocations inside the normal timestep. One autorelease pool surrounds each encoded simulation batch. VkFFT startup LUT uploads may wait; the interactive timestep does not call `waitUntilCompleted`. The explicit synchronous helpers are restricted to initialization, numerical tests, profiling, and image export. Benchmarks use two in-flight submissions with bounded backpressure and one final drain.

## Equations and transforms

The domain is `[0, 2π)²` and the grid is periodic. `N` is the spectral resolution per axis; `M = 3N/2` is the nonlinear evaluation resolution. Wavenumbers are signed integers in FFT order. With forward transform `Σ f(x) exp(-i k·x)` and inverse transform `Σ f̂(k) exp(+i k·x) / N²` on the state grid (or `/ M²` on the padded grid):

```
∂t ω = -u ∂xω - v ∂yω + ν∇²ω - αω + f
ψ̂ = ω̂ / |k|²
û = i ky ψ̂           v̂ = -i kx ψ̂
(∂xω)^ = i kx ω̂     (∂yω)^ = i ky ω̂
```

VkFFT's `normalize = 1` normalizes inverse transforms only. The GPU state is Float32 complex `ω̂`. All zero-mode inverse coefficients are zero. Initial conditions, stage results, and injected vortices are projected onto zero-mean vorticity; a periodic streamfunction cannot represent nonzero mean vorticity.

The state occupies N×N complex entries, retaining `|kx| < N/2 && |ky| < N/2`, with `(0,0)` removed. The even-grid Nyquist row and column stay zero to preserve an unambiguous real-field representation and avoid endpoint aliases. Initial fields, RK states and injected vortices follow this convention. There is no 2/3 cutoff on the N-grid state.

For each nonlinear evaluation, a gather kernel embeds the signed N-grid modes into M×M workspaces and clears all other entries. It scales the input coefficients by `M²/N² = 9/4`, compensating for the padded inverse FFT normalization. After multiplication and the forward FFT, the RK kernel crops the signed modes back to N×N and scales by `N²/M² = 4/9`. With maximum retained component `K = N/2−1`, `3K < M` prevents quadratic products from aliasing into retained modes. This is the [3/2 padding rule](https://kth-nek5000.github.io/kthNekBook/_md/spectral/pseudo.html); the CPU tests verify it against direct, non-wrapping Galerkin convolution rather than another padded implementation.

## Three transforms per nonlinear evaluation

Two real fields fit in one complex inverse transform. Hermitian symmetry of the physical state gives:

```
Â = û + i v̂ = (kx + i ky) ω̂ / |k|²
B̂ = (∂xω)^ + i(∂yω)^ = (-ky + i kx) ω̂
IFFT(Â) = u + i v
IFFT(B̂) = ∂xω + i ∂yω
```

The physical kernel computes the real product `-(u*∂xω + v*∂yω)` over M×M points into rows of `M+2` Floats. The final two values are in-place FFT storage padding, separate from spectral zero padding. A reusable **R2C** forward plan produces `M × (M/2+1)` complex coefficients. The RK kernel maps each retained signed N-grid mode to that half-spectrum, reconstructing negative-x modes by Hermitian symmetry, and applies the crop normalization. No separate crop/unpack pass or extra N-grid nonlinear buffer is needed.

Each stage therefore needs **two C2C inverse transforms and one R2C forward transform**, all M×M: six complex inverses and three real forwards per RK3 timestep. Three plans are reused: N-grid C2C for initialization/display, M-grid C2C for derivatives, and M-grid R2C for products. A full-complex forward comparison is available via `--c2c`, and `--unpacked` restores four separate M-grid inverse transforms. Main-state precision is never reduced. Both forward paths and packed/unpacked evaluation are checked against the independent CPU reference. Earlier R2C performance comparisons used the former 2/3-truncated solver; converting the packed inverse fields to four C2R transforms remains an unmeasured alternative.

SSP-RK3 stores only the original state and the current stage:

```
w1 = w0 + dt R(w0, t)
w2 = 3/4 w0 + 1/4 [w1 + dt R(w1, t+dt)]
w3 = 1/3 w0 + 2/3 [w2 + dt R(w2, t+dt/2)]
```

The first RK write also stores `w0`, avoiding a separate full-field copy. Linear diffusion and drag are explicit. Every timestep reduces `max(|u|+|v|)` on the GPU while forming the first nonlinear product. A second, single-group reduction chooses:

```
dt <= user ceiling
dt <= 1.5 / (2 ν K² + α), K = N/2−1
auto CFL only: dt <= CFL * (2π/M) / max(|u|+|v|)
```

The diffusion bound uses the full retained spectral band and is conservative for SSP-RK3's negative-real stability interval. Fixed dt still obeys this bound. The automatic CFL reduction covers all M² nonlinear points and uses the padded spacing; it is fresh every step and never relies on delayed CPU diagnostics. The GPU clock uses compensated summation to avoid drift from repeatedly adding small Float32 timesteps. Non-finite reduction values set a GPU fault flag and halt advancement; the UI pauses on the next diagnostic completion. Fixed dt can still violate the advective limit, so automatic CFL is the default, with a 0.02 ceiling and CFL 0.80. The inspector spans 0.10–0.82. [The CFL study](Benchmarks/CFL_STUDY.md) records the tested stability brackets, timestep-reference comparisons, and throughput; larger experimental values can be supplied to the CLI. Finite output alone does not establish accuracy or nonlinear stability.

## Presets and forcing

- Decaying: 48 seeded random-phase Fourier waves concentrated around `|k|≈8`, initialized in real space then projected.
- Vortex gas: 40 alternating signed, periodic Gaussian vortices, seeded positions.
- Kelvin–Helmholtz: a smooth periodic double shear `u=tanh(sin(y)/0.16)` with a six-wave perturbation, initialized through its negative y derivative.
- Inverse cascade: random-phase initialization plus Hermitian additive forcing in `8 ≤ |k| ≤ 12`. Each pair of conjugate modes shares a smooth time modulation `cos((0.7+0.01|k|²)t)`. This is deterministic spatially random, temporally correlated band forcing, **not white-noise forcing**. Drag arrests large-scale accumulation; viscosity removes small-scale enstrophy.

The forcing template is computed once from the seed. It is evaluated at the RK stage times. Mouse injection directly adds the analytic Fourier coefficients of a periodic Gaussian, then projects out the mean and unresolved modes. Coordinates match the displayed field, including its vertical orientation.

## Buffer lifetime and memory

Approximate application allocations per N-grid cell, excluding driver/VkFFT private scratch (M² = 2.25 N²):

| Allocation | Bytes/cell | Lifetime / reuse |
|---|---:|---|
| `omega` | 8 | Current spectral state, all stages |
| `base` | 8 | Original state, one RK timestep |
| `velocity` | 18 | M-grid packed velocity; N-grid prefix reused for display omega + i psi |
| `gradient` | 18 | M-grid packed gradients; N-grid prefix reused for display u + i v |
| `rhs` | 18 | M-grid nonlinear product / half spectrum; full C2C capacity retained |
| coefficients | 16 | kx, ky, inverse k², mask; immutable |
| forcing | 8 | Immutable seeded Hermitian band |
| three display textures | 48 | Completed snapshots for rendering |
| reduction partials | ~0.10 | M-grid CFL and N-grid physical diagnostics |

Total: approximately **142 MiB at N = 1024**, 35.5 MiB at N = 512, and 568 MiB at N = 2048, plus VkFFT plan/LUT/scratch allocations. All these allocations use private GPU storage. Only three 32-byte diagnostic records use shared storage. The GPU clock also uses private storage. The conventional FFT comparison adds two M-grid complex derivative buffers (36 bytes per N-grid cell); the packed path allocates only trivial dummy bindings for those slots.

Display generation performs two N×N inverse transforms: `(ω,ψ)` and `(u,v)`, reusing the prefixes of the larger derivative workspaces after the last RK stage. A fused conversion/reduction writes `(ω,|u|,ψ,ω²/2)` into the N×N snapshot. A final small reduction emits mean kinetic energy, mean enstrophy, max vorticity, max velocity, time, dt, step count, and fault status. These diagnostics are sampled on the N-grid; the CFL bound uses M-grid velocities. Energy/enstrophy are spatial means; multiply by domain area `4π²` to obtain integrals. Swift receives only the 32-byte record. Full-state downloads exist only in test helpers. PNG readback is an explicit command-line export.

## Instrumentation and limits

`R_turbo = completed simulated time / active elapsed wall time`. Interactive wall time starts after setup, includes the initial display and the simulation/render submission costs, and excludes pauses after outstanding work drains. Benchmark wall time starts after 12 warm-up steps and ends after all timed GPU work and completion handlers finish; the corresponding warm-up simulated time is subtracted.

The benchmark includes all nine transforms, custom kernels, GPU CFL computation, diagnostics, field textures, offscreen 1024² fragment rendering, CPU encoding, commit/backpressure, and completion overhead. `--display-every` changes display conversion/render cadence. It is uncapped, so it measures throughput without display pacing or the window server. `--ui-benchmark` separately measures the real SwiftUI/MTKView app with presentation.

GPU command-buffer intervals can overlap even on the same queue. Their durations must **not be summed as utilization**. The benchmark reports the span from first GPU start to last GPU end; the UI merges overlapping intervals. Both include scheduler effects and are not hardware occupancy measurements. CPU encoding time is measured independently. `--profile` uses separate command buffers and waits to isolate GPU phase durations; it deliberately perturbs scheduling and its totals are not an end-to-end throughput result. The implementation makes no unsupported GPU occupancy claim.

A live isotropic spectrum and semi-implicit integrator are not implemented. Both are optional extensions; the tested baseline prioritizes the complete GPU-resident RK3 solver and its measured interactive throughput.
