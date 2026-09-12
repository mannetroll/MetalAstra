import QuartzCore
import Foundation
import Metal

struct CommandLineRunner {
    static func run() throws {
        let args = CommandLine.arguments
        func value(_ flag:String,_ fallback:String)->String { guard let i=args.firstIndex(of:flag),i+1<args.count else { return fallback };return args[i+1] }
        let r = try MetalResources()
        if args.contains("--self-test") { try NumericalTests.run(r,realFFT:false);try NumericalTests.run(r,realFFT:true);return }
        var config = SimulationConfig()
        config.size = Int(value("--size","1024")) ?? 1024
        config.preset = .decaying;config.seed = 42;config.automatic = args.contains("--cfl")
        config.dt = Float(value("--dt",args.contains("--cfl-study") ? "0.02":"0.002")) ?? 0.002
        config.viscosity = 0.0001;config.drag = 0.01
        config.cfl = Float(value("--cfl-value",String(config.cfl))) ?? config.cfl
        if args.contains("--cfl-value") { config.automatic = true }
        config.seed = UInt32(value("--seed","42")) ?? 42
        config.viscosity = Float(value("--viscosity","0.0001")) ?? 0.0001
        config.drag = Float(value("--drag","0.01")) ?? 0.01
        config.stepsPerBatch = Int(value("--batch","4")) ?? 4
        config.threadgroup = Int(value("--threads","256")) ?? 256
        config.packed = !args.contains("--unpacked")
        config.realFFT = !args.contains("--c2c")
        config.preset = Preset(rawValue:UInt32(value("--preset",args.contains("--snapshot") ? "1":"0")) ?? 0) ?? .decaying
        guard config.cfl.isFinite,config.cfl>0,config.dt.isFinite,config.dt>0,
              config.viscosity.isFinite,config.viscosity>=0,config.drag.isFinite,config.drag>=0 else {
            throw LabError.message("CFL and dt must be finite and positive; viscosity and drag must be finite and nonnegative.")
        }
        if args.contains("--cfl-study") {
            let times = value("--times","2,5,10,20").split(separator:",").compactMap { Float($0) }
            let candidates = value("--cfl-values","0.45,0.65,0.75,0.85,1,1.2").split(separator:",").compactMap { Float($0) }
            let reference = Float(value("--reference-cfl","0.225")) ?? 0.225
            let maxWall = Double(value("--max-wall","300")) ?? 300
            let stressOffset = Int(value("--stress-offset","2")) ?? 2
            guard !times.isEmpty,times.allSatisfy({ $0.isFinite && $0>0 }),times==times.sorted(),Set(times).count==times.count,
                  !candidates.isEmpty,candidates.allSatisfy({ $0.isFinite && $0>0 }),reference.isFinite,reference>0,
                  maxWall.isFinite,maxWall>0,config.stepsPerBatch>0,stressOffset>=1,stressOffset<config.size/2-1 else { throw LabError.message("Invalid CFL study parameters.") }
            try CFLStudy.run(r,config:config,times:times,candidates:candidates,referenceCFL:reference,stress:args.contains("--stress"),stressOffset:stressOffset,maxWall:maxWall)
            return
        }
        let steps = Int(value("--steps","240")) ?? 240
        let repeats = Int(value("--repeats","3")) ?? 3
        let displayEvery = Int(value("--display-every","1")) ?? 1
        guard steps>0,config.stepsPerBatch>0,repeats>0,displayEvery>0 else { throw LabError.message("Benchmark counts must be positive.") }
        let s = try SpectralSolver(resources:r,config:config)
        print("# spectral N=\(s.size), nonlinear M=\(s.paddedSize); 3/2 zero padding; zero Nyquist lines")
        print("# CFL=\(config.cfl), automatic=\(config.automatic), dt_max=\(config.dt), preset=\(config.preset.rawValue), seed=\(config.seed), viscosity=\(config.viscosity), drag=\(config.drag)")
        if args.contains("--snapshot") {
            var remaining = steps
            while remaining>0 { let batch=min(remaining,16); _ = try s.run(steps:batch); remaining -= batch }
            var settings=DisplaySettings();settings.field=UInt32(value("--field","0")) ?? 0;settings.palette=UInt32(value("--palette","0")) ?? 0
            guard settings.field<4,settings.palette<4 else { throw LabError.message("Field and palette must be 0…3.") }
            try RenderExport.write(s,path:value("--snapshot","flow.png"),settings:settings);return
        }
        let target = try r.texture(size:1024,display:true),slot = s.snapshots.slots[0]
        _ = try s.run(steps:12,display:slot)
        if args.contains("--profile") {
            for _ in 0..<10 { try s.profileStep(slot:slot,target:target) }
            print("ISOLATED GPU PHASE PROFILE — extra commits/waits perturb scheduling; ms per step")
            for key in s.profile.keys.sorted() { print("\(key): \(s.profile[key]!/10)") };return
        }
        print("# forward transform: \(config.realFFT ? "R2C" : "C2C")")
        print("device,size,steps,batch,packed,threads,displayEvery,rendered,repeat,wall_s,ms_step,steps_s,R_turbo,gpu_span_ms_step,cpu_encode_ms_step,energy,enstrophy,dt")
        for repeatIndex in 1...repeats {
            try s.reset();_ = try s.run(steps:12,display:slot)
            let initial = slot.values
            let accumulator = BenchmarkAccumulator(), capacity = DispatchSemaphore(value:2), finished = DispatchGroup()
            let start = CACurrentMediaTime();var cpuTime=0.0,submitted=0,batch=0
            while submitted<steps {
                capacity.wait()
                let count=min(config.stepsPerBatch,steps-submitted),index=batch
                let shouldDisplay = index%displayEvery==0 || submitted+count==steps
                let targetSlot = s.snapshots.slots[index%3]
                let encodeStart = CACurrentMediaTime()
                try autoreleasepool {
                    let cb = try s.command("Benchmark batch"),e = cb.makeComputeCommandEncoder()!
                    for _ in 0..<count { try s.encodeStep(cb,e) }
                    if shouldDisplay { try s.encodeDisplay(cb,e,slot:targetSlot) }
                    e.endEncoding()
                    if shouldDisplay && !args.contains("--no-render") { SpectralSolver.encodeRender(r,cb,texture:targetSlot.texture,target:target) }
                    finished.enter()
                    cb.addCompletedHandler { buffer in
                        accumulator.record(buffer,diagnostic:shouldDisplay ? targetSlot.values:nil,index:index)
                        capacity.signal();finished.leave()
                    }
                    cb.commit()
                }
                cpuTime += CACurrentMediaTime()-encodeStart;submitted += count;batch += 1
            }
            finished.wait()
            let wall = CACurrentMediaTime()-start
            if let error = accumulator.error { throw LabError.message(error) }
            let d=accumulator.diagnostic
            guard d.fault==0,d.energy.isFinite else { throw LabError.message("Benchmark produced non-finite data.") }
            let sim=Double(d.time-initial.time)
            print(String(format:"%@,%d,%d,%d,%@,%d,%d,%@,%d,%.6f,%.6f,%.3f,%.6f,%.6f,%.6f,%.8f,%.8f,%.7f",r.device.name,config.size,steps,config.stepsPerBatch,config.packed ? "yes":"no",config.threadgroup,displayEvery,args.contains("--no-render") ? "no":"yes",repeatIndex,wall,wall*1000/Double(steps),Double(steps)/wall,sim/wall,(accumulator.gpuLast-accumulator.gpuFirst)*1000/Double(steps),cpuTime*1000/Double(steps),d.energy,d.enstrophy,d.dt))
        }
    }
}
final class BenchmarkAccumulator: @unchecked Sendable {
    let lock=NSLock()
    var gpuFirst=Double.infinity,gpuLast=0.0,diagnostic=GPUDiagnostic(),error:String?,latest = -1
    func record(_ cb:MTLCommandBuffer,diagnostic:GPUDiagnostic?,index:Int) {
        lock.lock();defer { lock.unlock() };gpuFirst=min(gpuFirst,cb.gpuStartTime);gpuLast=max(gpuLast,cb.gpuEndTime)
        if let e=cb.error { error=e.localizedDescription }
        if let diagnostic,index>latest { self.diagnostic=diagnostic;latest=index }
    }
}

// Explicit offline experiment. Synchronization/readbacks here are for stability
// and accuracy comparisons; use --benchmark for production throughput numbers.
enum CFLStudy {
    struct Reference {
        let field: [Float]
        let diagnostic: GPUDiagnostic
    }
    static func run(_ r:MetalResources,config:SimulationConfig,times:[Float],candidates:[Float],referenceCFL:Float,stress:Bool,stressOffset:Int,maxWall:Double) throws {
        var c=config;c.automatic=true
        let solver=try SpectralSolver(resources:r,config:c),slot=solver.snapshots.slots[0]
        let ceiling=c.dt
        var reference:[Reference]=[]
        let stressField:[Float]? = stress ? (0..<solver.count).map { i in
            let x=2*Float.pi*Float(i%solver.size)/Float(solver.size),y=2*Float.pi*Float(i/solver.size)/Float(solver.size)
            let k=Float(solver.size/2-stressOffset),phase=Float(config.seed%31)*0.13
            // Strong smooth shear transports a small, nearly Nyquist perturbation.
            return sin(y)+0.01*cos(k*x+phase)*cos(2*y)+0.01*sin((k-1)*x-phase)*sin(3*y)
        } : nil
        print("# CFL stability/accuracy study; synchronized batches, NOT production throughput")
        print("# N=\(solver.size), M=\(solver.paddedSize), preset=\(c.preset.rawValue), seed=\(c.seed), viscosity=\(c.viscosity), drag=\(c.drag), dt_max=\(ceiling), stress=\(stress), reference_CFL=\(referenceCFL)")
        if stress { print("# stress wavenumbers: \(solver.size/2-stressOffset), \(solver.size/2-stressOffset-1)") }
        print("# checkpoints are matched physical times; unforced energy/enstrophy growth >1% stops a run; reference L2/diagnostics are reported separately")
        print("kind,size,preset,seed,stress,cfl,target,time,steps,wall_s,mean_dt,last_dt,energy,enstrophy,energy_rel_ref,enstrophy_rel_ref,field_rel_L2,max_omega,status")
        for (index,cfl) in ([referenceCFL]+candidates).enumerated() {
            solver.config=c;solver.config.cfl=cfl
            if let stressField { try solver.loadPhysical(stressField) } else { try solver.reset() }
            // Warm all pipelines, then restore exactly the same initial state.
            _ = try solver.run(steps:4,display:slot)
            if let stressField { try solver.loadPhysical(stressField) } else { try solver.reset() }
            _ = try solver.run(steps:0,display:slot)
            let initial=slot.values,start=Date()
            var previous=initial,status="ok"
            for (checkpoint,target) in times.enumerated() {
                var lastTime=slot.values.time
                while slot.values.time < target {
                    let remaining=target-slot.values.time
                    // Cap the batch so every case ends at the same physical time.
                    // Near a checkpoint use one final step; no interpolation of states.
                    let count=remaining <= Float(c.stepsPerBatch)*max(slot.values.dt,1e-6) ? 1:c.stepsPerBatch
                    solver.config.dt=min(ceiling,remaining/Float(count))
                    try autoreleasepool { _ = try solver.run(steps:count,display:slot) }
                    let d=slot.values
                    if d.fault != 0 || !d.energy.isFinite || !d.enstrophy.isFinite || !d.maxOmega.isFinite { status="nonfinite";break }
                    if c.preset != .inverseCascade && (d.energy>initial.energy*1.01 || d.enstrophy>initial.enstrophy*1.01) { status="invariant_growth";break }
                    if d.time<=lastTime || d.steps>500_000 || Date().timeIntervalSince(start)>maxWall { status="stalled_or_timeout";break }
                    lastTime=d.time
                }
                let d=slot.values
                var energyError=Double.nan,enstrophyError=Double.nan,fieldError=Double.nan
                if status=="ok" {
                    let field=try solver.physicalState()
                    guard field.allSatisfy(\.isFinite) else { throw LabError.message("CFL study found a non-finite field without a GPU fault") }
                    if index==0 {
                        reference.append(Reference(field:field,diagnostic:d))
                        energyError=0;enstrophyError=0;fieldError=0
                    } else {
                        let ref=reference[checkpoint]
                        energyError=Double(d.energy/ref.diagnostic.energy-1)
                        enstrophyError=Double(d.enstrophy/ref.diagnostic.enstrophy-1)
                        var error=0.0,norm=0.0
                        for i in field.indices {
                            let delta=Double(field[i])-Double(ref.field[i])
                            error += delta*delta;norm += Double(ref.field[i])*Double(ref.field[i])
                        }
                        fieldError=sqrt(error/max(norm,1e-30))
                        if c.preset != .inverseCascade && (d.energy>previous.energy*1.01 || d.enstrophy>previous.enstrophy*1.01) { status="invariant_growth" }
                        if energyError>0.1 || enstrophyError>0.1 { status="excess_growth_vs_reference" }
                    }
                }
                print(String(format:"%@,%d,%d,%u,%@,%.5f,%.6f,%.6f,%u,%.6f,%.9f,%.9f,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%@",index==0 ? "reference":"candidate",solver.size,c.preset.rawValue,c.seed,stress ? "yes":"no",cfl,target,d.time,d.steps,Date().timeIntervalSince(start),Double(d.time)/Double(max(d.steps,1)),d.dt,d.energy,d.enstrophy,energyError,enstrophyError,fieldError,d.maxOmega,status))
                fflush(stdout);previous=d
                if status != "ok" { break }
            }
            if index==0 && status != "ok" { throw LabError.message("Reference CFL did not complete: \(status)") }
        }
    }
}
