You are GPT-6 Astra running at xhigh reasoning effort inside Codex CLI.

Work directly on the files in the current directory.

Do not ask clarifying questions.
Do not stop after producing a plan.
Do not merely describe an implementation.
Implement the complete application, build it, test it, profile it where possible, fix problems, and iterate.

If an existing TurbulenceLab Xcode project is present, inspect it first and evolve it rather than blindly replacing useful UI or functionality.

If no project exists, create the complete Xcode project.

PRIMARY OBJECTIVE

Build an exceptionally fast native macOS application for interactive visualization of 2D incompressible turbulence on Apple Silicon, specifically optimized for an M1 Max MacBook Pro.

The primary architecture is:

Swift / SwiftUI
    +
Metal compute
    +
VkFFT using its Metal backend

DO NOT use MLX.

The dominant optimization objective is not source-code simplicity and not individual FFT benchmark speed.

Optimize the complete application for:

maximum simulated physical time per wall-clock time

while maintaining a smooth interactive visualization.

Define and report a metric equivalent to:

R_turbo = T_simulated / T_wall

or, if preserving the existing naming convention:

T_turbo / T_wall

Higher is better.

This metric must include the real end-to-end simulation loop, including the costs that matter in the interactive application.

Secondary objectives:

1. High sustained GPU utilization.
2. Minimal CPU↔GPU synchronization.
3. Minimal GPU memory traffic.
4. Stable 60 Hz visualization where practical.
5. Correct pseudo-spectral numerics.
6. Excellent native macOS user experience.
7. Clean architecture that allows further automated optimization.

NON-NEGOTIABLE DESIGN RULE

Keep simulation data on the GPU.

The normal timestep must NOT copy the full flow field back to the CPU.

The intended execution path is approximately:

SwiftUI
   |
Swift orchestration
   |
MTLCommandQueue
   |
Metal command buffers
   |
   +-- VkFFT forward/inverse FFT
   +-- spectral Metal kernels
   +-- nonlinear Metal kernels
   +-- time integration
   +-- forcing/filtering
   +-- diagnostics reductions
   +-- visualization
   |
MTLTexture / MTKView
   |
screen

The field used for visualization should remain GPU-resident.

Only tiny diagnostic scalars should normally cross back to the CPU.

NUMERICAL MODEL

Implement 2D incompressible Navier-Stokes in periodic Cartesian geometry using the vorticity-streamfunction formulation.

Use:

∂ω/∂t + u·∇ω = ν∇²ω - αω + f

with

∇²ψ = -ω

and

u =  ∂ψ/∂y
v = -∂ψ/∂x

Use a doubly periodic domain.

Default domain:

Lx = 2π
Ly = 2π

Represent the primary state spectrally where this improves performance.

Use a Fourier pseudo-spectral formulation.

Support at least:

256²
512²
1024²
2048²

Prefer power-of-two grids.

The 1024² case should be treated as a serious optimization target on the M1 Max.

2048² may be treated as a stress-test configuration.

SPECTRAL IMPLEMENTATION

Use VkFFT for GPU FFTs through the Metal backend.

Use the minimum number of FFTs compatible with a correct pseudo-spectral timestep.

Investigate opportunities to reduce transform count.

Precompute immutable spectral quantities such as:

kx
ky
k²
1/k²
dealias mask
forcing mask

Handle k=0 explicitly and safely.

For the streamfunction:

ψ_hat = ω_hat / k²

with the mathematically correct sign according to the transform convention used in the implementation.

Derive velocity and vorticity derivatives spectrally.

For example:

u_hat      =  i ky ψ_hat
v_hat      = -i kx ψ_hat
dωdx_hat   =  i kx ω_hat
dωdy_hat   =  i ky ω_hat

Then obtain the required real-space fields using inverse transforms and evaluate:

N = -(u*dωdx + v*dωdy)

in physical space.

Apply 2/3 dealiasing or an equivalently justified pseudo-spectral anti-aliasing scheme.

Document exactly how aliasing is controlled.

VkFFT INTEGRATION

Integrate VkFFT properly rather than wrapping it in a high-overhead API.

Use a thin bridge between Swift and the C/C++/Objective-C++ code required by VkFFT and metal-cpp.

Keep the bridge minimal.

Prefer opaque handles exposed to Swift rather than leaking C++ types into the application layer.

The bridge should own/configure reusable VkFFT plans.

Do NOT create FFT plans every timestep.

Reuse all plans and scratch allocations.

Investigate VkFFT append-to-command-buffer support so FFTs can participate naturally in the same GPU command-buffer pipeline as custom Metal kernels.

Avoid unnecessary waits between VkFFT and Metal kernels.

Account for any Metal/VkFFT autorelease-pool requirements safely.

GPU MEMORY ARCHITECTURE

Allocate simulation buffers once.

Do not allocate arrays or MTLBuffers inside the normal timestep loop unless unavoidable.

Use persistent buffers for quantities such as:

omega
omega_hat
psi_hat
u
v
dwdx
dwdy
nonlinear/RHS
RK temporary state
VkFFT scratch
diagnostic reduction buffers
visualization field/texture

Reuse buffers aggressively where lifetimes do not overlap.

Construct a buffer-lifetime analysis and eliminate unnecessary temporaries.

Prefer private GPU storage where CPU access is not required.

Use shared storage only where it gives a measured benefit or is necessary for tiny diagnostics.

Avoid managed-storage synchronization patterns inappropriate for Apple Silicon.

METAL COMPUTE

Implement performance-critical numerical operations as Metal compute kernels.

Candidate kernels include:

1. spectral coefficient generation
2. streamfunction/velocity/gradient construction
3. dealias filtering
4. physical nonlinear product
5. viscosity/drag/forcing
6. RK stage update
7. field normalization for rendering
8. reductions for diagnostics
9. vortex injection / user interaction

Look for opportunities to fuse operations.

For example, one spectral kernel may derive several Fourier-space fields from omega_hat rather than launching separate kernels.

Likewise, combine nonlinear evaluation and RHS construction where beneficial.

Do not fuse blindly.

Measure whether fusion actually improves the end-to-end metric.

Minimize:

global-memory reads
global-memory writes
command encoder transitions
command-buffer commits
CPU synchronization

Pay attention to threadgroup size and memory-coalescing behavior on Apple GPUs.

Do not optimize only for FLOPs.

For this workload memory bandwidth and synchronization may dominate.

TIME INTEGRATION

Start with a stable explicit scheme suitable for pseudo-spectral turbulence.

Preferred baseline:

SSP-RK3

or an equivalent three-stage low-storage RK3 formulation.

Use a low-storage implementation where possible.

Avoid needless copies of the full state between stages.

If a semi-implicit treatment of the linear viscous term can materially improve the end-to-end result, investigate it after establishing a correct baseline.

Do not make the algorithm numerically worse merely to reduce wall time.

Implement a CFL-aware timestep option.

Provide:

fixed dt
automatic CFL dt

Avoid GPU→CPU synchronization every timestep merely to obtain max velocity.

If CFL estimation requires a reduction, design it asynchronously or perform it less frequently if numerically acceptable.

FORCING / PRESETS

Implement useful turbulence presets.

At minimum:

1. Decaying turbulence

Random spectrally filtered initial vorticity.

2. Vortex gas

Many signed vortices with reproducible seeded initialization.

3. Kelvin-Helmholtz

A shear-layer instability that develops recognizable coherent vortices.

4. Forced inverse cascade

Low-wavenumber or band-limited statistically appropriate forcing suitable for sustained 2D turbulence.

Allow deterministic random seeds.

VISUALIZATION

Use SwiftUI for the application shell and controls.

Use MTKView for the high-performance simulation visualization.

Do not copy the simulation field to CPU merely to draw it.

Render directly from GPU-resident Metal data.

Support at least:

vorticity
velocity magnitude
streamfunction
enstrophy density

Provide attractive scientific color maps, for example:

Ice/Fire
Inferno
Turbo
Neon or equivalent

Do not make the visualization scientifically misleading.

Include:

exposure
contrast
optional contour bands

Rendering and simulation should be decoupled.

The simulation may execute multiple timesteps per visual frame.

The renderer should display the most recently completed simulation state without unnecessarily blocking the simulation.

Investigate double buffering or triple buffering if appropriate.

INTERACTION

Make the application feel like a high-quality native macOS scientific visualization program.

Include:

Start/Pause
Reset
preset selection
grid size
viscosity
linear drag
dt
CFL mode
simulation speed / steps per display frame
field selection
colormap
exposure
contrast

Allow interactive vortex injection.

For example:

left drag  -> positive vorticity
right drag -> negative vorticity

Implement the injection on the GPU if practical.

The application must remain responsive while the simulation is running.

LIVE DIAGNOSTICS

Display at least:

grid resolution
simulated time
wall time
T_simulated / T_wall
steps/s
ms/timestep
FPS
kinetic energy
enstrophy
max |omega|
estimated max velocity
current dt

Do not make diagnostics so expensive that they materially reduce the simulation rate.

Run expensive reductions less frequently if necessary.

PERFORMANCE INSTRUMENTATION

Instrumentation is a first-class part of this project.

Measure separately where possible:

FFT time
spectral kernels
inverse FFTs
nonlinear kernel
RK update
diagnostics
rendering
command-buffer overhead
CPU orchestration
total timestep

Use GPU timestamps/counters where supported and appropriate.

Add a benchmark mode that runs without UI-induced noise.

Benchmark at least:

256²
512²
1024²

if the hardware and runtime environment permit it.

Report:

ms/step
steps/s
simulated seconds / wall second

Do not claim performance numbers that were not actually measured.

PERFORMANCE OPTIMIZATION LOOP

After establishing a correct working baseline, perform iterative optimization.

For each meaningful candidate:

inspect/profile
    ->
identify dominant cost
    ->
formulate one hypothesis
    ->
make an isolated change
    ->
build
    ->
correctness tests
    ->
benchmark
    ->
compare T_simulated/T_wall
    ->
KEEP or REVERT

Do not accumulate speculative optimizations without measuring them.

Maintain:

OPTIMIZATION_LOG.md

For each experiment record:

candidate
rationale
files changed
numerical effect
benchmark before
benchmark after
percentage change
KEEP / REVERT
observations

Maintain a concise current-performance document:

CURRENT_BASELINE.md

Include exact benchmark configuration so results are repeatable.

IMPORTANT OPTIMIZATION CANDIDATES

Investigate these systematically, but retain them only if measurement supports them:

1. fewer FFTs per RK stage
2. reusable VkFFT plans
3. one command buffer containing multiple simulation operations
4. fewer command-buffer commits
5. reduced CPU waits
6. fused spectral kernels
7. fused physical-space kernels
8. reduced temporary-buffer count
9. in-place transforms where safe
10. real-to-complex transforms where they reduce work
11. exploiting Hermitian symmetry where beneficial
12. low-storage RK3
13. asynchronous diagnostics
14. reduced diagnostic frequency
15. direct GPU texture rendering
16. double/triple buffering
17. optimized Metal threadgroup sizes
18. half precision ONLY for visualization if useful
19. Float32 for the main simulation unless evidence shows otherwise
20. precomputed constants/masks
21. avoiding Swift ARC activity in inner loops
22. avoiding Objective-C allocation/autorelease activity in the timestep
23. batching encoder work
24. minimizing Swift↔C bridge calls
25. eliminating unnecessary Metal encoder boundaries

Do not assume every item is beneficial.

Measure.

CORRECTNESS TESTS

Create deterministic numerical tests.

At minimum test:

1. FFT forward/inverse consistency.
2. Spectral derivative accuracy using analytic periodic functions.
3. Laplacian accuracy.
4. Poisson/streamfunction inversion.
5. Velocity reconstructed from streamfunction.
6. Divergence is approximately zero.
7. Correct treatment of k=0.
8. Correct 2/3 dealias mask.
9. Inviscid/unforced short-run sanity.
10. Viscous kinetic-energy decay.
11. Finite values after many timesteps.
12. Deterministic seeded initialization.
13. RK convergence/sanity.
14. No exploding energy caused by transform normalization mistakes.
15. CPU reference comparison on a small grid where useful.

For small-grid verification, it is acceptable to write a straightforward CPU reference implementation solely for tests.

The production solver must remain Metal/VkFFT.

PHYSICAL DIAGNOSTICS

Compute meaningful quantities correctly.

For periodic 2D turbulence include:

kinetic energy
enstrophy

If practical, add an optional isotropic energy spectrum:

E(k)

Do not make spectrum computation part of every visual frame.

Compute it on demand or infrequently.

A small live spectrum panel would be valuable if it does not compromise simulation speed.

APP ARCHITECTURE

Prefer a structure conceptually similar to:

TurbulenceLab/
    App/
        TurbulenceLabApp.swift
        ContentView.swift
    Simulation/
        SimulationEngine.swift
        SimulationConfig.swift
        SimulationState.swift
        Diagnostics.swift
    Metal/
        TurbulenceKernels.metal
        Visualization.metal
        MetalRenderer.swift
        MetalResources.swift
    VkFFTBridge/
        VkFFTBridge.h
        VkFFTBridge.mm
        ...
    UI/
        SimulationView.swift
        ControlsView.swift
        DiagnosticsView.swift
        SpectrumView.swift
    Tests/
        ...
    README.md
    ARCHITECTURE.md
    OPTIMIZATION_LOG.md
    CURRENT_BASELINE.md

Use the actual structure that best suits Xcode and the implementation.

Do not force this exact tree if another clean structure works better.

XCODE

Produce a real Xcode project that opens and builds normally.

Target:

macOS
Apple Silicon
M1 Max

Use a reasonably current macOS deployment target compatible with required Metal features.

Avoid unnecessary third-party dependencies other than VkFFT and what is required to integrate it.

Do not introduce a package manager merely for convenience if vendoring/integrating VkFFT directly produces a simpler reliable Xcode build.

The final project should not depend on Python.

USER EXPERIENCE

The visual result should be striking.

On launch the user should quickly see evolving vortical structures rather than a static or boring field.

Use sensible defaults.

The app should look like a real macOS application, not a debug control panel.

Prefer:

large visualization area
compact side inspector
dark appearance suitable for scientific visualization
readable live metrics
excellent resizing behavior
Retina rendering

Avoid excessive UI ornamentation.

The turbulence itself should be the focus.

NUMERICAL/PERFORMANCE PRIORITY

When there is a conflict, use this order:

1. numerical correctness
2. stability
3. T_simulated/T_wall
4. smooth interaction
5. visualization quality
6. architectural elegance
7. code brevity

Do not sacrifice correctness for a benchmark.

But once correctness is established, aggressively optimize the actual execution path.

AVOID THESE FAILURE MODES

Do NOT:

* use MLX
* use Python
* use NumPy
* use SciPy
* make the CPU perform the spectral solver
* repeatedly copy full simulation fields GPU→CPU
* allocate major buffers every timestep
* recreate VkFFT plans repeatedly
* call waitUntilCompleted after every kernel
* synchronize the CPU after every FFT
* run one Metal command buffer per trivial operation without measurement
* optimize only a standalone FFT benchmark
* confuse rendering FPS with simulation performance
* claim unmeasured performance
* leave placeholder functions
* leave TODO implementations for core functionality
* silently fall back to a CPU solver
* stop because integration is difficult

Solve integration problems properly.

BUILD / DEBUG LOOP

Perform the complete implementation loop:

inspect existing project
implement
build
inspect compiler/linker/runtime failures
fix
rebuild
run tests
fix
repeat

Use xcodebuild from the command line where appropriate.

Run every test that can run in the current environment.

If GPU execution is available, run actual simulation/benchmark tests.

If a specific hardware-dependent test cannot execute in the current Codex environment, clearly distinguish:

verified by build/test

from:

requires execution on the M1 Max

Do not invent success.

DOCUMENTATION

README.md should explain:

* what the application does
* numerical equations
* pseudo-spectral method
* VkFFT/Metal architecture
* how to open/build/run it
* controls
* performance metric
* benchmark procedure

ARCHITECTURE.md should explain the execution pipeline, GPU buffers, VkFFT bridge, command-buffer organization and synchronization strategy.

OPTIMIZATION_LOG.md should preserve the experimental performance history.

CURRENT_BASELINE.md should state the best verified implementation and reproducible benchmark configuration.

FINAL SELF-REVIEW

Before finishing, inspect the implementation critically.

Ask:

1. Does the entire normal timestep remain GPU-resident?
2. Are there any hidden synchronous GPU→CPU waits?
3. Are FFT plans reused?
4. Are large buffers reused?
5. Can transforms be eliminated?
6. Can memory traffic be reduced?
7. Are command buffers unnecessarily fragmented?
8. Does visualization block simulation?
9. Are diagnostics too frequent?
10. Is T_simulated/T_wall actually being measured correctly?
11. Is the pseudo-spectral method mathematically correct?
12. Does dealiasing operate at the correct point?
13. Are FFT normalization conventions correct?
14. Does the zero Fourier mode behave correctly?
15. Are there any unnecessary abstractions in the inner simulation path?

Fix significant findings before declaring completion.

FINAL RESPONSE

At completion, give a concise engineering report containing:

1. architecture implemented
2. numerical method
3. VkFFT integration
4. Metal kernels
5. GPU memory strategy
6. synchronization strategy
7. tests performed and results
8. benchmark results actually measured
9. optimization candidates tried
10. what was kept/reverted
11. current limiting bottleneck
12. exact instructions to open and run the Xcode project on the M1 Max

Most importantly, state the achieved:

T_simulated / T_wall

for every configuration actually measured.

The goal is not merely to make the application work.

The goal is to make this a highly optimized native Apple-Silicon 2D turbulence engine and visualization application, and to use measurement-driven iteration to push the complete interactive simulation as fast as the M1 Max can reasonably run it.
