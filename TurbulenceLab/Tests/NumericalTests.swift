import Foundation
import Metal

struct NumericalTests {
    static func run(_ r: MetalResources, realFFT: Bool = true) throws {
        print("NUMERICAL SUITE: 3/2 padding, forward \(realFFT ? "R2C" : "C2C")")
        var passed = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") throws {
            if !condition { throw LabError.message("FAIL \(name): \(detail)") }
            passed += 1; print("PASS \(name) \(detail)")
        }
        func maxError(_ a:[Float],_ b:[Float])->Float {
            precondition(a.count==b.count)
            return zip(a,b).map { abs($0-$1) }.max() ?? 0
        }
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
        let fftError = maxError(input,try s.read(s.rhs,floats:s.count*2))
        try check("complex FFT forward/inverse",fftError < 2e-5,"max error \(fftError)")
        try check("N spectral nodes and 3N/2 transform nodes",s.size==32 && s.paddedSize==48 && s.paddedCount==2304)
        let paddedInput = (0..<s.paddedCount*2).map { sin(Float($0)*0.173)+cos(Float($0)*0.417) }
        let paddedUpload = r.device.makeBuffer(bytes:paddedInput,length:paddedInput.count*4,options:.storageModeShared)!
        let pcb = try s.command("Mixed radix padded FFT test"),pb = pcb.makeBlitCommandEncoder()!
        pb.copy(from:paddedUpload,sourceOffset:0,to:s.rhs,destinationOffset:0,size:paddedInput.count*4);pb.endEncoding()
        let pe = pcb.makeComputeCommandEncoder()!
        try s.paddedPlan.append(pcb,pe,s.rhs,inverse:false);try s.paddedPlan.append(pcb,pe,s.rhs,inverse:true)
        pe.endEncoding();try SpectralSolver.finish(pcb)
        let paddedError = maxError(paddedInput,try s.read(s.rhs))
        try check("3N/2 mixed-radix FFT forward/inverse",paddedError<2e-5,"max error \(paddedError)")
        try s.loadPhysical(analytic)
        let expected: [[Float]] = [field { x,y in 3*cos(3*x)*cos(2*y) },analytic.map { -13*$0 },analytic.map { $0/13 },field { x,y in -2*sin(3*x)*sin(2*y)/13 },field { x,y in -3*cos(3*x)*cos(2*y)/13 },[Float](repeating:0,count:n*n)]
        for op in 0..<6 {
            let cb = try s.command("Spectral operator"), e = cb.makeComputeCommandEncoder()!;var p = GPUParams(config);p.stage = UInt32(op)
            s.dispatch("testOperator",e,&p,s.omega,s.coefficients,s.rhs);try s.plan.append(cb,e,s.rhs,inverse:true);e.endEncoding();try SpectralSolver.finish(cb)
            let complex = try s.read(s.rhs,floats:s.count*2), real = stride(from:0,to:complex.count,by:2).map { complex[$0] }
            let err = maxError(real,expected[op])
            try check(["spectral derivative","Laplacian","Poisson inversion","velocity u sign","velocity v sign","zero divergence"][op],err < 0.0002,"max error \(err)")
        }
        let co = try s.read(s.coefficients)
        var maskOK = true
        for i in 0..<s.count {
            let x=i%n,y=i/n,kx=x<=n/2 ? x:x-n,ky=y<=n/2 ? y:y-n
            let keep = abs(kx)<n/2 && abs(ky)<n/2 && i != 0
            maskOK = maskOK && co[4*i+3] == (keep ? 1:0)
        }
        try check("full spectral band with zero Nyquist lines",maskOK)
        try check("safe zero mode inverse",co[2] == 0 && co[3] == 0)
        try s.loadPhysical([Float](repeating:3,count:s.count))
        try check("zero mean projection",try s.physicalState().allSatisfy { abs($0)<1e-6 })
        let high = field { x,y in sin(13*x)*cos(11*y) }
        try s.loadPhysical(high)
        try check("modes above the old 2/3 cutoff retained",maxError(try s.physicalState(),high)<1e-5)
        // Poison workspaces so this also detects padding that was not cleared.
        let dcb = try s.command("Padded derivative interpolation"),db = dcb.makeBlitCommandEncoder()!
        db.fill(buffer:s.velocity,range:0..<s.velocity.length,value:255)
        db.fill(buffer:s.gradient,range:0..<s.gradient.length,value:255);db.endEncoding()
        let de = dcb.makeComputeCommandEncoder()!;var dp = GPUParams(config)
        s.dispatch("derivePacked",de,&dp,s.omega,s.coefficients,s.velocity,s.gradient,threads:s.paddedCount)
        try s.paddedPlan.append(dcb,de,s.velocity,inverse:true);try s.paddedPlan.append(dcb,de,s.gradient,inverse:true)
        de.endEncoding();try SpectralSolver.finish(dcb)
        let paddedVelocity = try s.read(s.velocity),paddedGradient = try s.read(s.gradient)
        var interpolationError:Float = 0
        for i in 0..<s.paddedCount {
            let x=2*Float.pi*Float(i%s.paddedSize)/Float(s.paddedSize),y=2*Float.pi*Float(i/s.paddedSize)/Float(s.paddedSize)
            let dx=13*cos(13*x)*cos(11*y),dy = -11*sin(13*x)*sin(11*y)
            interpolationError=max(interpolationError,abs(paddedVelocity[2*i]-dy/290),abs(paddedVelocity[2*i+1]+dx/290),abs(paddedGradient[2*i]-dx),abs(paddedGradient[2*i+1]-dy))
        }
        try check("padded signed-mode placement and inverse normalization",paddedVelocity.allSatisfy(\.isFinite) && paddedGradient.allSatisfy(\.isFinite) && interpolationError<0.0003,"max error \(interpolationError)")
        try s.loadPhysical(field { x,y in cos(16*x)+cos(16*y) })
        try check("Nyquist rows and columns removed",try s.physicalState().allSatisfy { abs($0)<1e-5 })
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
            var c = config;c.size = 16;c.viscosity = 0.025;c.dt = dt
            let solver = try SpectralSolver(resources:r,config:c)
            let wave = (0..<256).map { cos(6*2*Float.pi*Float($0%16)/16) }
            try solver.loadPhysical(wave);_ = try solver.run(steps:Int(round(1/dt)))
            return maxError(try solver.physicalState(),wave.map { $0*exp(-0.9) })
        }
        let coarse = try decayError(dt:0.2),fine = try decayError(dt:0.1)
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
        // Independent Double DFT + exact (non-wrapping) spectral convolution.
        var small = config;small.size = 16;small.dt = 0.003;small.viscosity = 0.005
        let gs = try SpectralSolver(resources:r,config:small)
        let initial = (0..<256).map { i -> Float in let x=2*Float.pi*Float(i%16)/16,y=2*Float.pi*Float(i/16)/16;return cos(x)+0.4*sin(2*y)+0.3*cos(2*x+y) }
        try gs.loadPhysical(initial)
        var cpu = CPUReference(size:16,physical:initial.map(Double.init))
        for _ in 0..<8 { cpu.step(dt:Double(small.dt),viscosity:Double(small.viscosity)) }
        _ = try gs.run(steps:8)
        let referenceError = maxError(try gs.physicalState(),cpu.physical().map(Float.init))
        try check("GPU vs independent Double convolution/RK3",referenceError<2e-5,"max error \(referenceError)")
        small.realFFT = true
        let realSolver = try SpectralSolver(resources:r,config:small)
        try realSolver.loadPhysical(initial);_ = try realSolver.run(steps:8)
        let realError = maxError(try realSolver.physicalState(),cpu.physical().map(Float.init))
        try check("R2C RHS vs Double convolution/RK3",realError<2e-5,"max error \(realError)")
        // These modes survive the new cutoff. Their sum (13,-1) would alias to
        // (-3,-1) on an unpadded 16² grid, while their difference (1,3) is physical.
        let aliasField = (0..<256).map { i -> Float in
            let x=2*Float.pi*Float(i%16)/16,y=2*Float.pi*Float(i/16)/16
            return cos(7*x+y)+0.7*cos(6*x-2*y)+0.3*sin(x-7*y)
        }
        try gs.loadPhysical(aliasField)
        var exact = CPUReference(size:16,physical:aliasField.map(Double.init))
        for _ in 0..<8 { exact.step(dt:Double(small.dt),viscosity:Double(small.viscosity)) }
        _ = try gs.run(steps:8)
        let aliasError = maxError(try gs.physicalState(),exact.physical().map(Float.init))
        try check("high-mode quadratic products agree with alias-free convolution",aliasError<2e-5,"max error \(aliasError)")
        let evolved = try gs.read(gs.omega)
        var hermitianError:Float = 0,nyquistError:Float = 0
        for i in 0..<256 {
            let x=i%16,y=i/16,mirror=((16-y)%16)*16+(16-x)%16
            hermitianError=max(hermitianError,abs(evolved[2*i]-evolved[2*mirror]),abs(evolved[2*i+1]+evolved[2*mirror+1]))
            if x==8 || y==8 || i==0 { nyquistError=max(nyquistError,abs(evolved[2*i]),abs(evolved[2*i+1])) }
        }
        try check("cropped RHS preserves Hermitian symmetry and Nyquist convention",hermitianError<0.0001 && nyquistError==0,"Hermitian error \(hermitianError)")
        for preset in Preset.allCases {
            s.config = config;s.config.preset = preset;s.config.automatic = true;s.config.viscosity = 0.0001
            try s.reset();_ = try s.run(steps:40,display:slot)
            try check("preset \(preset.title)",slot.values.fault==0 && slot.values.energy>0)
        }
        s.config = config;s.config.automatic = true;s.config.dt = 0.1
        // Both speed maxima lie beyond the first N² entries of the M² grid.
        // This catches a CFL reduction accidentally retaining the N-grid count.
        try s.loadPhysical(field { _,y in 100*(-sin(y)-0.6*cos(2*y)) })
        _ = try s.run(steps:1,display:slot)
        let speedBound = (0..<s.paddedSize).map { j -> Float in
            let y=2*Float.pi*Float(j)/Float(s.paddedSize)
            return abs(100*(-cos(y)+0.3*sin(2*y)))
        }.max()!
        let expectedDT = config.cfl*(2*Float.pi/Float(s.paddedSize))/speedBound
        try check("GPU CFL uses the entire padded grid and spacing",abs(slot.values.dt-expectedDT)<1e-7,"dt \(slot.values.dt), expected \(expectedDT)")
        s.config = config;s.config.dt = 1;s.config.viscosity = 0.2
        try s.loadPhysical(analytic);_ = try s.run(steps:1,display:slot)
        let diffusionLimit:Float = 1.5/(2*0.2*15*15)
        try check("diffusion limit uses the full spectral band",abs(slot.values.dt-diffusionLimit)<1e-7)
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

// Test-only separable DFT and exact Galerkin convolution; never used in production.
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
    func filter(_ a:inout [SIMD2<Double>]) { for i in a.indices { let (x,y)=mode(i);if abs(x)>=Double(n/2) || abs(y)>=Double(n/2) || i==0 { a[i] = .zero } } }
    func rhs(_ a:[SIMD2<Double>],viscosity:Double)->[SIMD2<Double>] {
        // Exact Galerkin sum: no padded FFT, index wrapping or physical product.
        // With unnormalized DFT coefficients the convolution carries 1/N².
        var nonlinear=[SIMD2<Double>](repeating:.zero,count:n*n)
        for i in a.indices {
            let (px,py)=mode(i),p2=px*px+py*py
            if p2==0 || abs(px)>=Double(n/2) || abs(py)>=Double(n/2) { continue }
            for j in a.indices {
                let (qx,qy)=mode(j),kx=Int(px+qx),ky=Int(py+qy)
                if abs(qx)>=Double(n/2) || abs(qy)>=Double(n/2) || abs(kx)>=n/2 || abs(ky)>=n/2 { continue }
                let k=(ky<0 ? ky+n:ky)*n+(kx<0 ? kx+n:kx)
                nonlinear[k] += ((py*qx-px*qy)/(p2*Double(n*n)))*mul(a[i],a[j])
            }
        }
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
