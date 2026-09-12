import Foundation

enum Preset: UInt32, CaseIterable, Identifiable {
    case decaying, vortexGas, kelvinHelmholtz, inverseCascade
    var id: UInt32 { rawValue }
    var title: String { ["Decaying turbulence", "Vortex gas", "Kelvin–Helmholtz", "Forced inverse cascade"][Int(rawValue)] }
    var detail: String { ["Random phase eddies merge and decay", "Forty seeded vortices interact", "A periodic double shear rolls into billows", "Sustained stirring in the 8–12 wavenumber band"][Int(rawValue)] }
}
struct SimulationConfig {
    // N spectral nodes per axis; nonlinear products use M = 3N/2 nodes.
    var size = 1024
    var paddedSize: Int { size * 3 / 2 }
    var preset: Preset = .decaying
    var seed: UInt32 = 42
    var viscosity: Float = 0.0001
    var drag: Float = 0.01
    var dt: Float = 0.02
    var automatic = true
    var cfl: Float = 0.8
    var stepsPerBatch = 4
    var forcing: Float = 1
    var packed = true
    var realFFT = true
    var threadgroup = 256
}
struct GPUParams {
    var n: UInt32, count: UInt32, stage: UInt32 = 0, preset: UInt32
    var dt: Float, viscosity: Float, drag: Float, cfl: Float
    var automatic: UInt32, seed: UInt32, packed: UInt32, realFFT: UInt32
    var force: Float, injectionX: Float = 0, injectionY: Float = 0, injectionStrength: Float = 0
    init(_ c: SimulationConfig) {
        n = UInt32(c.size); count = n*n; preset = c.preset.rawValue
        dt = c.dt; viscosity = c.viscosity; drag = c.drag; cfl = c.cfl
        automatic = c.automatic ? 1 : 0; seed = c.seed; packed = c.packed ? 1 : 0; realFFT = c.realFFT ? 1 : 0; force = c.forcing
    }
}
struct GPUDiagnostic {
    var energy: Float = 0, enstrophy: Float = 0, maxOmega: Float = 0, maxSpeed: Float = 0
    var time: Float = 0, dt: Float = 0
    var steps: UInt32 = 0, fault: UInt32 = 0
}
struct LiveMetrics {
    var physical = GPUDiagnostic()
    var wallTime: Double = 0, turbo: Double = 0, stepsPerSecond: Double = 0, milliseconds: Double = 0
    var fps: Double = 0, averageFPS: Double = 0, gpuMilliseconds: Double = 0, cpuMilliseconds: Double = 0
}
struct DisplaySettings {
    var field: UInt32 = 0, palette: UInt32 = 1
    var exposure: Float = -1.3, contrast: Float = 1
    var contours: UInt32 = 0
    var scale: Float = 1
    var padding0: UInt32 = 0, padding1: UInt32 = 0
}
enum LabError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
