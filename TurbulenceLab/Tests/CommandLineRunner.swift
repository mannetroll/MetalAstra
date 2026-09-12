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
        config.preset = .decaying;config.seed = 42;config.automatic = args.contains("--cfl");config.dt = Float(value("--dt","0.002")) ?? 0.002
        config.viscosity = 0.0001;config.drag = 0.01
        config.stepsPerBatch = Int(value("--batch","4")) ?? 4
        config.threadgroup = Int(value("--threads","256")) ?? 256
        config.packed = !args.contains("--unpacked")
        config.realFFT = !args.contains("--c2c")
        if args.contains("--snapshot") { config.preset = Preset(rawValue:UInt32(value("--preset","1")) ?? 1) ?? .vortexGas }
        let steps = Int(value("--steps","240")) ?? 240
        let repeats = Int(value("--repeats","3")) ?? 3
        let displayEvery = Int(value("--display-every","1")) ?? 1
        guard steps>0,config.stepsPerBatch>0,repeats>0,displayEvery>0 else { throw LabError.message("Benchmark counts must be positive.") }
        let s = try SpectralSolver(resources:r,config:config)
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
