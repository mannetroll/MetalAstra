import Foundation
import Metal

struct NumericalTests {
    static func run(_ r: MetalResources, realFFT: Bool = true) throws {
        print("NUMERICAL SUITE: forward \(realFFT ? "R2C" : "C2C")")
        var passed = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") throws {
            if !condition { throw LabError.message("FAIL \(name): \(detail)") }
            passed += 1; print("PASS \(name) \(detail)")
        }
        func maxError(_ a:[Float],_ b:[Float])->Float { zip(a,b).map { abs($0-$1) }.max() ?? 0 }
        var config = SimulationConfig();config.size = 32;config.automatic = false;config.dt = 0.002;config.viscosity = 0;config.drag = 0;config.preset = .decaying
        config.realFFT = realFFT
        let s = try SpectralSolver(resources:r,config:config)
        let n = s.size
        func field(_ f:(Float,Float)->Float)->[Float] { (0..<n*n).map { f(2 * .pi * Float($0%n)/Float(n),2 * .pi * Float($0/n)/Float(n)) } }
        let analytic = field { x,y in sin(3*x)*cos(2*y) }
        // General complex input, including zero and Nyquist frequencies.
        var input = [Float](repeating:0,count:s.count*2)
        for i in input.indices { input[i] = sin(Float(i)*0.713)+cos(Float(i)*0.237) }
        let staging = r.device.makeBuffer(bytes:input,length:input.count*4,options:.storageModeShared)!
        let roundtrip = try s.command("FFT roundtrip test"), blit = roundtrip.makeBlitCommandEncoder()!
        blit.copy(from:staging,sourceOffset:0,to:s.rhs,destinationOffset:0,size:input.count*4);blit.endEncoding()
        let re = roundtrip.makeComputeCommandEncoder()!
        try s.plan.append(roundtrip,re,s.rhs,inverse:false);try s.plan.append(roundtrip,re,s.rhs,inverse:true);re.endEncoding();try SpectralSolver.finish(roundtrip)
        let fftError = maxError(input,try s.read(s.rhs))
        try check("complex FFT forward/inverse",fftError < 2e-5,"max error \(fftError)")
        try s.loadPhysical(analytic)
        let expected: [[Float]] = [field { x,y in 3*cos(3*x)*cos(2*y) },analytic.map { -13*$0 },analytic.map { $0/13 },field { x,y in -2*sin(3*x)*sin(2*y)/13 },field { x,y in -3*cos(3*x)*cos(2*y)/13 },[Float](repeating:0,count:n*n)]
        for op in 0..<6 {
            let cb = try s.command("Spectral operator"), e = cb.makeComputeCommandEncoder()!;var p = GPUParams(config);p.stage = UInt32(op)
            s.dispatch("testOperator",e,&p,s.omega,s.coefficients,s.rhs);try s.plan.append(cb,e,s.rhs,inverse:true);e.endEncoding();try SpectralSolver.finish(cb)
            let complex = try s.read(s.rhs), real = stride(from:0,to:complex.count,by:2).map { complex[$0] }
            let err = maxError(real,expected[op])
            try check(["spectral derivative","Laplacian","Poisson inversion","velocity u sign","velocity v sign","zero divergence"][op],err < 0.0002,"max error \(err)")
        }
        let co = try s.read(s.coefficients)
        var maskOK = true
        for i in 0..<s.count {
            let x=i%n,y=i/n,kx=x<=n/2 ? x:x-n,ky=y<=n/2 ? y:y-n
            let keep = abs(kx)*3<n && abs(ky)*3<n && i != 0
            maskOK = maskOK && co[4*i+3] == (keep ? 1:0)
        }
        try check("strict rectangular 2/3 mask",maskOK)
        try check("safe zero mode inverse",co[2] == 0 && co[3] == 0)
        try s.loadPhysical([Float](repeating:3,count:s.count))
        try check("zero mean projection",try s.physicalState().allSatisfy { abs($0)<1e-6 })
        try s.loadPhysical(field { x,_ in cos(12*x) })
        try check("out-of-band modes removed",try s.physicalState().allSatisfy { abs($0)<1e-5 })
        try s.reset();let seed1 = try s.read(s.omega);try s.reset();let seed2 = try s.read(s.omega)
        try check("deterministic seed",seed1 == seed2)
        s.config.seed += 1;try s.reset()
        try check("distinct seeds",seed1 != (try s.read(s.omega)));s.config = config
        let slot = s.snapshots.slots[0]
        try s.reset();_ = try s.run(steps:0,display:slot);let before = slot.values
        _ = try s.run(steps:100,display:slot);let after = slot.values
        try check("inviscid energy conservation",abs(after.energy/before.energy-1)<0.001,"relative drift \(after.energy/before.energy-1)")
        try check("inviscid enstrophy conservation",abs(after.enstrophy/before.enstrophy-1)<0.001)
        s.config.viscosity = 0.01
        _ = try s.run(steps:100,display:slot)
        try check("viscous kinetic energy decay",slot.values.energy < after.energy && slot.values.energy>0)
        for _ in 0..<5 { _ = try s.run(steps:100,display:slot) }
        try check("700 steps remain finite",slot.values.fault == 0 && (try s.read(s.omega)).allSatisfy(\.isFinite))
        try check("compensated simulated clock",abs(slot.values.time-Float(slot.values.steps)*config.dt)<2e-7)
        // Exact shear mode: nonlinear advection vanishes, so RK order can be isolated.
        func decayError(dt:Float) throws -> Float {
            var c = config;c.size = 16;c.viscosity = 0.2;c.dt = dt
            let solver = try SpectralSolver(resources:r,config:c)
            let wave = (0..<256).map { cos(3*2*Float.pi*Float($0%16)/16) }
            try solver.loadPhysical(wave);_ = try solver.run(steps:Int(round(1/dt)))
            return maxError(try solver.physicalState(),wave.map { $0*exp(-1.8) })
        }
        let coarse = try decayError(dt:0.1),fine = try decayError(dt:0.05)
        try check("SSP-RK3 convergence",coarse/fine>6 && coarse/fine<11,"error ratio \(coarse/fine), fine \(fine)")
        try s.loadPhysical(analytic);s.config = config;_ = try s.run(steps:0,display:slot)
        try check("Parseval physical energy",abs(slot.values.energy-1/104.0)<1e-6)
        try check("physical enstrophy",abs(slot.values.enstrophy-0.125)<1e-6)
        // Packed and ordinary transforms must produce the same nonlinear evolution.
        var separateConfig = config;separateConfig.packed = false
        let separate = try SpectralSolver(resources:r,config:separateConfig)
        try s.reset();try separate.reset();_ = try s.run(steps:15);_ = try separate.run(steps:15)
        let packingError = maxError(try s.physicalState(),try separate.physicalState())
        try check("3 vs 5 transforms per stage",packingError<3e-5,"max error \(packingError)")
        // Independent Double DFT + RK3 reference on a small grid.
        var small = config;small.size = 16;small.dt = 0.003;small.viscosity = 0.005
        let gs = try SpectralSolver(resources:r,config:small)
        let initial = (0..<256).map { i -> Float in let x=2*Float.pi*Float(i%16)/16,y=2*Float.pi*Float(i/16)/16;return cos(x)+0.4*sin(2*y)+0.3*cos(2*x+y) }
        try gs.loadPhysical(initial)
        var cpu = CPUReference(size:16,physical:initial.map(Double.init))
        for _ in 0..<8 { cpu.step(dt:Double(small.dt),viscosity:Double(small.viscosity)) }
        _ = try gs.run(steps:8)
        let referenceError = maxError(try gs.physicalState(),cpu.physical().map(Float.init))
        try check("GPU vs independent Double DFT/RK3",referenceError<2e-5,"max error \(referenceError)")
        small.realFFT = true
        let realSolver = try SpectralSolver(resources:r,config:small)
        try realSolver.loadPhysical(initial);_ = try realSolver.run(steps:8)
        let realError = maxError(try realSolver.physicalState(),cpu.physical().map(Float.init))
        try check("R2C RHS vs Double DFT/RK3",realError<2e-5,"max error \(realError)")
        for preset in Preset.allCases {
            s.config = config;s.config.preset = preset;s.config.automatic = true;s.config.viscosity = 0.0001
            try s.reset();_ = try s.run(steps:40,display:slot)
            try check("preset \(preset.title)",slot.values.fault==0 && slot.values.energy>0)
        }
        s.config = config;s.config.automatic = true;s.config.dt = 0.1
        try s.loadPhysical(analytic.map { $0*100 });_ = try s.run(steps:1,display:slot)
        try check("GPU CFL lowers dt",slot.values.dt>0 && slot.values.dt<0.01,"dt \(slot.values.dt)")
        s.config = config;try s.loadPhysical([Float](repeating:0,count:s.count))
        let icb = try s.command("Injection test"),ie = icb.makeComputeCommandEncoder()!
        s.inject(icb,ie,x:0.5,y:0.5,strength:12);ie.endEncoding();try SpectralSolver.finish(icb)
        let injected = try s.physicalState()
        try check("GPU vortex injection sign",injected[(n/2)*n+n/2]>0)
        try check("GPU vortex injection zero mean",abs(injected.reduce(0,+)/Float(s.count))<1e-6)
        // GPU-produced CFL fault propagates to the tiny diagnostics record.
        var bad = analytic;bad[0] = .nan;try s.loadPhysical(bad);_ = try s.run(steps:1,display:slot)
        try check("non-finite fault detection",slot.values.fault != 0)
        s.config = config;s.config.preset = .inverseCascade;try s.reset()
        let force = try s.read(s.forcing)
        var forcingOK = true
        for i in 0..<s.count {
            let x=i%n,y=i/n,kx=x<=n/2 ? x:x-n,ky=y<=n/2 ? y:y-n,k2=kx*kx+ky*ky
            let mirror=((n-y)%n)*n+(n-x)%n
            forcingOK = forcingOK && force[2*i] == force[2*mirror] && force[2*i+1] == -force[2*mirror+1]
            if k2<64 || k2>144 { forcingOK = forcingOK && force[2*i]==0 && force[2*i+1]==0 }
        }
        try check("forcing Hermitian symmetry and band",forcingOK)
        try s.loadPhysical([Float](repeating:0,count:s.count));_ = try s.run(steps:10,display:slot)
        try check("forcing drives a resting flow",slot.values.energy>0 && slot.values.fault==0)
        if realFFT {
            for n in [256,512,1024,2048] {
                var large = config;large.size=n;large.realFFT=false
                let complexSolver=try SpectralSolver(resources:r,config:large)
                large.realFFT=true
                let realSolver=try SpectralSolver(resources:r,config:large)
                _ = try complexSolver.run(steps:8);_ = try realSolver.run(steps:8)
                let error=maxError(try complexSolver.physicalState(),try realSolver.physicalState())
                try check("R2C vs C2C at \(n)²",error<0.0001,"max error \(error)")
            }
        }
        print("ALL \(passed) NUMERICAL CHECKS PASSED on \(r.device.name)")
    }
}

// Test-only O(N^3) separable DFT; production never calls this implementation.
struct CPUReference {
    let n:Int
    var w:[SIMD2<Double>]
    init(size:Int,physical:[Double]) { n=size;w=physical.map { SIMD2($0,0) };w=transform(w,inverse:false);filter(&w) }
    func mul(_ a:SIMD2<Double>,_ b:SIMD2<Double>)->SIMD2<Double> { SIMD2(a.x*b.x-a.y*b.y,a.x*b.y+a.y*b.x) }
    func transform(_ a:[SIMD2<Double>],inverse:Bool)->[SIMD2<Double>] {
        var temp=a,out=a;let sign=inverse ? 1.0 : -1.0
        for y in 0..<n { for k in 0..<n { var v=SIMD2<Double>.zero
            for x in 0..<n { let phase=sign*2*Double.pi*Double(k*x)/Double(n);v += mul(a[y*n+x],SIMD2(cos(phase),sin(phase))) };temp[y*n+k]=v
        } }
        for x in 0..<n { for k in 0..<n { var v=SIMD2<Double>.zero
            for y in 0..<n { let phase=sign*2*Double.pi*Double(k*y)/Double(n);v += mul(temp[y*n+x],SIMD2(cos(phase),sin(phase))) };out[k*n+x]=inverse ? v/Double(n*n):v
        } };return out
    }
    func mode(_ i:Int)->(Double,Double) { let x=i%n,y=i/n;return (Double(x<=n/2 ? x:x-n),Double(y<=n/2 ? y:y-n)) }
    func filter(_ a:inout [SIMD2<Double>]) { for i in a.indices { let (x,y)=mode(i);if abs(x)*3>=Double(n) || abs(y)*3>=Double(n) || i==0 { a[i] = .zero } } }
    func rhs(_ a:[SIMD2<Double>],viscosity:Double)->[SIMD2<Double>] {
        var u=a,v=a,dx=a,dy=a
        for i in a.indices { let (x,y)=mode(i),k2=x*x+y*y;let iz=SIMD2(-a[i].y,a[i].x)
            u[i]=k2>0 ? iz*y/k2:.zero;v[i]=k2>0 ? -iz*x/k2:.zero;dx[i]=iz*x;dy[i]=iz*y
        }
        u=transform(u,inverse:true);v=transform(v,inverse:true);dx=transform(dx,inverse:true);dy=transform(dy,inverse:true)
        var nonlinear=a
        for i in a.indices { nonlinear[i]=SIMD2(-(u[i].x*dx[i].x+v[i].x*dy[i].x),0) }
        nonlinear=transform(nonlinear,inverse:false)
        for i in a.indices { let (x,y)=mode(i);nonlinear[i] -= viscosity*(x*x+y*y)*a[i] };filter(&nonlinear);return nonlinear
    }
    mutating func step(dt:Double,viscosity:Double) {
        let original=w
        for stage in 0..<3 {
            let r=rhs(w,viscosity:viscosity),a=stage==0 ? 0.0:(stage==1 ? 0.75:1.0/3)
            for i in w.indices { w[i]=a*original[i]+(1-a)*(w[i]+dt*r[i]) };filter(&w)
        }
    }
    func physical()->[Double] { transform(w,inverse:true).map(\.x) }
}
