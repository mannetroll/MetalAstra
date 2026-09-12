import QuartzCore
import Foundation
import Metal
import Combine
import AppKit

@MainActor final class SimulationModel: ObservableObject {
    @Published var config = SimulationConfig()
    @Published var display = DisplaySettings()
    @Published var running = true
    @Published var loading = true
    @Published var error: String?
    @Published var metrics = LiveMetrics()
    @Published var deviceName = "Apple Silicon"
    let engine = SimulationEngine()
    init() {
        let args = CommandLine.arguments
        let uiBenchmark = args.contains("--ui-benchmark")
        var benchmarkDuration = 20.0
        if uiBenchmark {
            config.preset = .decaying; config.automatic = false; config.dt = 0.002
            if let i = args.firstIndex(of:"--size"), i+1<args.count, let n = Int(args[i+1]), [256,512,1024,2048].contains(n) { config.size = n }
            if let i = args.firstIndex(of:"--duration"), i+1<args.count, let t = Double(args[i+1]) { benchmarkDuration = max(3,t) }
            if args.contains("--cfl") || args.contains("--cfl-value") { config.automatic=true;config.dt=0.02 }
            if let i=args.firstIndex(of:"--cfl-value"),i+1<args.count,let value=Float(args[i+1]),value.isFinite,value>0 { config.cfl=value }
            if let i=args.firstIndex(of:"--dt"),i+1<args.count,let value=Float(args[i+1]),value.isFinite,value>0 { config.dt=value }
            print("# spectral N=\(config.size), nonlinear M=\(config.paddedSize); 3/2 zero padding; zero Nyquist lines")
            print("# CFL=\(config.cfl), automatic=\(config.automatic), dt_max=\(config.dt)")
            print("UI BENCHMARK: size,wall_s,simulated_s,R_turbo,steps_s,ms_step,FPS,energy,enstrophy")
        }
        engine.report = { [weak self] metrics in Task { @MainActor in
            self?.metrics = metrics
            if uiBenchmark, metrics.wallTime >= benchmarkDuration, let self {
                if let content = NSApplication.shared.windows.first?.contentView, let flow = UIAutomation.findFlow(content) {
                    print("# drawable \(Int(flow.drawableSize.width))x\(Int(flow.drawableSize.height)); FPS uses actual drawable presentation timestamps")
                }
                print(String(format:"UI,%d,%.6f,%.6f,%.6f,%.3f,%.6f,%.2f,%.8f,%.8f", self.config.size,metrics.wallTime,metrics.physical.time,metrics.turbo,metrics.stepsPerSecond,metrics.milliseconds,metrics.averageFPS,metrics.physical.energy,metrics.physical.enstrophy))
                fflush(stdout); NSApplication.shared.terminate(nil)
            }
        } }
        engine.ready = { [weak self] name in Task { @MainActor in self?.loading = false; self?.deviceName = name } }
        engine.failure = { [weak self] text in Task { @MainActor in self?.error = text; self?.loading = false; self?.running = false } }
        engine.rebuild(config)
    }
    func reset() { loading = true; error = nil; engine.rebuild(config); engine.setRunning(running) }
    func update() { engine.update(config); engine.setRunning(running) }
}

final class SimulationEngine: @unchecked Sendable {
    private let worker = DispatchQueue(label:"TurbulenceLab.simulation",qos:.userInitiated)
    private let access = NSLock()
    private var sharedResources: MetalResources?
    private var sharedExchange: SnapshotExchange?
    private var solver: SpectralSolver?
    private var running = true, inflight = 0
    private var pendingConfig: SimulationConfig?
    private var injection: (Float,Float,Float)?
    private var needsSnapshot = true
    private let eagerDisplay = CommandLine.arguments.contains("--eager-display")
    private var lastSnapshot = 0.0
    private var wallStart = 0.0, activeWall = 0.0
    private var lastPublish = 0.0, completedSteps = 0
    private var gpuSpan = 0.0, gpuLast = 0.0, cpuTotal = 0.0
    private var frameCount = 0, fps = 0.0, fpsStart = CACurrentMediaTime()
    private var allFrames = 0, firstFrame = 0.0, averageFPS = 0.0
    var report: ((LiveMetrics)->Void)?
    var ready: ((String)->Void)?
    var failure: ((String)->Void)?
    func renderResources() -> (MetalResources,SnapshotExchange)? {
        access.lock(); defer { access.unlock() }
        guard let r = sharedResources, let s = sharedExchange else { return nil }; return (r,s)
    }
    func framePresented(time: Double) {
        access.lock(); defer { access.unlock() }
        frameCount += 1
        let now = time > 0 ? time : CACurrentMediaTime()
        allFrames += 1
        if firstFrame == 0 { firstFrame = now }
        averageFPS = Double(allFrames-1)/max(now-firstFrame,1e-9)
        if now-fpsStart >= 0.5 { fps = Double(frameCount)/(now-fpsStart); frameCount = 0; fpsStart = now }
    }
    func requestSnapshot() { worker.async { self.needsSnapshot = true } }
    func rebuild(_ config: SimulationConfig) {
        worker.async { self.pendingConfig = config; self.pump() }
    }
    func update(_ config: SimulationConfig) { worker.async {
        guard let solver = self.solver else { return }
        var c = config; c.size = solver.size; c.packed = solver.config.packed; c.threadgroup = solver.groupWidth; c.realFFT = solver.config.realFFT
        c.seed = solver.config.seed; c.preset = solver.config.preset
        solver.config = c
    } }
    func setRunning(_ value: Bool) { worker.async {
        let now = CACurrentMediaTime()
        if !value && self.inflight == 0 && self.wallStart > 0 { self.activeWall += now-self.wallStart; self.wallStart = 0 }
        if value && self.wallStart == 0 { self.wallStart = now }
        self.running = value; self.pump()
    } }
    func inject(x: Float, y: Float, strength: Float) { worker.async { self.injection = (x,y,strength); self.pump() } }
    private func pump() {
        if pendingConfig != nil && inflight > 0 { return }
        if let config = pendingConfig {
            pendingConfig = nil
            do {
                let r = try sharedResources ?? MetalResources()
                let s = try autoreleasepool { try SpectralSolver(resources:r,config:config) }
                solver = s; needsSnapshot = true; completedSteps = 0; activeWall = 0; gpuSpan = 0; gpuLast = 0; cpuTotal = 0; wallStart = running ? CACurrentMediaTime() : 0
                access.lock(); sharedResources = r; sharedExchange = s.snapshots; access.unlock()
                ready?(r.device.name)
                // Always show the initial field, including when paused.
                try submit(s, steps:0)
            } catch { running = false; failure?(error.localizedDescription) }
        }
        guard let solver, pendingConfig == nil, inflight < 2 else { return }
        if running || injection != nil {
            do { try autoreleasepool { try submit(solver,steps:running ? solver.config.stepsPerBatch : 0) } }
            catch { running = false; failure?(error.localizedDescription) }
        }
    }
    private func submit(_ solver: SpectralSolver, steps: Int) throws {
        let start = CACurrentMediaTime(), cb = try solver.command("Simulation · \(steps) RK3 steps")
        let e = cb.makeComputeCommandEncoder()!
        if let i = injection { solver.inject(cb,e,x:i.0,y:i.1,strength:i.2); injection = nil }
        for _ in 0..<steps { try solver.encodeStep(cb,e) }
        let slot = eagerDisplay || needsSnapshot || steps == 0 || start-lastSnapshot > 0.2 ? solver.snapshots.reserve() : nil
        if let slot { try solver.encodeDisplay(cb,e,slot:slot); needsSnapshot = false; lastSnapshot = start }
        e.endEncoding(); inflight += 1
        cpuTotal += CACurrentMediaTime()-start
        cb.addCompletedHandler { [weak self, solver] buffer in
            // Copy only 32 bytes while this slot is reserved; publish after the copy.
            let d = slot?.values
            if let slot { if buffer.error == nil { solver.snapshots.publish(slot) } else { solver.snapshots.cancel(slot) } }
            self?.worker.async {
                guard let self else { return }
                self.inflight -= 1; self.completedSteps += steps
                self.gpuSpan += max(0,buffer.gpuEndTime-max(buffer.gpuStartTime,self.gpuLast)); self.gpuLast = max(self.gpuLast,buffer.gpuEndTime)
                if let error = buffer.error { self.running = false; self.failure?(error.localizedDescription) }
                if let d, d.fault != 0 { self.running = false; self.failure?("A non-finite field was detected. Reduce dt or reset the flow.") }
                let now = CACurrentMediaTime()
                if !self.running && self.inflight == 0 && self.wallStart > 0 { self.activeWall += now-self.wallStart; self.wallStart = 0 }
                if let d, now-self.lastPublish > 0.2 || !self.running {
                    self.lastPublish = now
                    let wall = self.activeWall + (self.wallStart > 0 ? now-self.wallStart : 0)
                    var m = LiveMetrics();m.physical = d;m.wallTime = wall
                    m.turbo = Double(d.time)/max(wall,1e-9)
                    m.stepsPerSecond = Double(self.completedSteps)/max(wall,1e-9)
                    m.milliseconds = wall*1000/Double(max(self.completedSteps,1))
                    m.gpuMilliseconds = self.gpuSpan*1000/Double(max(self.completedSteps,1))
                    m.cpuMilliseconds = self.cpuTotal*1000/Double(max(self.completedSteps,1))
                    self.access.lock();m.fps = self.fps;m.averageFPS = self.averageFPS;self.access.unlock()
                    self.report?(m)
                }
                self.pump()
            }
        }
        cb.commit()
    }
}
