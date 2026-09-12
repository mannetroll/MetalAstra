import Foundation
import Metal

// This object is confined to the simulation worker. Readbacks are explicit test utilities.
final class SpectralSolver {
    let resources: MetalResources
    let size: Int, count: Int, groupWidth: Int, groupCount: Int
    let omega: MTLBuffer, base: MTLBuffer, velocity: MTLBuffer, gradient: MTLBuffer, rhs: MTLBuffer
    let coefficients: MTLBuffer, forcing: MTLBuffer, maxima: MTLBuffer, partial: MTLBuffer, clock: MTLBuffer
    let extraDX: MTLBuffer, extraDY: MTLBuffer
    let plan: FFTPlan
    let realPlan: FFTPlan?
    let snapshots: SnapshotExchange
    var config: SimulationConfig
    var profile: [String: Double] = [:]

    init(resources r: MetalResources, config: SimulationConfig) throws {
        guard config.size >= 16, config.size <= 2048, config.size.nonzeroBitCount == 1, [128,256,512].contains(config.threadgroup) else { throw LabError.message("Use a power-of-two grid from 16 to 2048 and a 128, 256 or 512 thread group.") }
        self.resources = r; self.config = config; size = config.size; count = size*size
        groupWidth = config.threadgroup; groupCount = (count+groupWidth-1)/groupWidth
        omega = try r.buffer(count*8, "Spectral vorticity")
        base = try r.buffer(count*8, "RK initial state")
        velocity = try r.buffer(count*8, "Packed velocity / display omega-psi")
        gradient = try r.buffer(count*8, "Packed gradients / display velocity")
        rhs = try r.buffer(count*8, "Nonlinear physical / spectral RHS")
        coefficients = try r.buffer(count*16, "Immutable spectral coefficients")
        forcing = try r.buffer(count*8, "Hermitian forcing band")
        maxima = try r.buffer(groupCount*4, "CFL partials")
        partial = try r.buffer(groupCount*16, "Diagnostic partials")
        clock = try r.buffer(32, "GPU compensated clock")
        // The five-transform reference path is allocated only when requested.
        extraDX = try r.buffer(config.packed ? 8 : count*8, "Reference derivative x")
        extraDY = try r.buffer(config.packed ? 8 : count*8, "Reference derivative y")
        plan = try FFTPlan(resources: r, buffer: omega, size: size)
        realPlan = config.realFFT ? try FFTPlan(resources:r,buffer:rhs,size:size,real:true) : nil
        snapshots = try SnapshotExchange(r, size: size)
        try reset()
    }
    func dispatch(_ name: String, _ e: MTLComputeCommandEncoder, _ p: inout GPUParams,
                  _ b0: MTLBuffer? = nil, _ b1: MTLBuffer? = nil, _ b2: MTLBuffer? = nil,
                  _ b3: MTLBuffer? = nil, _ b4: MTLBuffer? = nil, _ b5: MTLBuffer? = nil,
                  threads: Int? = nil) {
        e.setComputePipelineState(resources.kernels[name]!)
        e.setBuffer(b0, offset: 0, index: 0); e.setBuffer(b1, offset: 0, index: 1)
        e.setBuffer(b2, offset: 0, index: 2); e.setBuffer(b3, offset: 0, index: 3)
        e.setBuffer(b4, offset: 0, index: 4); e.setBuffer(b5, offset: 0, index: 5)
        e.setBytes(&p, length: MemoryLayout<GPUParams>.stride, index: 8)
        var groups = UInt32(groupCount); e.setBytes(&groups, length: 4, index: 9)
        let total = threads ?? count
        e.dispatchThreadgroups(MTLSize(width: (total+groupWidth-1)/groupWidth, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: groupWidth, height: 1, depth: 1))
        e.memoryBarrier(scope: .buffers)
    }
    func command(_ label: String) throws -> MTLCommandBuffer {
        guard let cb = resources.queue.makeCommandBuffer() else { throw LabError.message("Metal command buffer unavailable.") }
        cb.label = label; return cb
    }
    static func finish(_ cb: MTLCommandBuffer) throws {
        cb.commit(); cb.waitUntilCompleted()
        if let error = cb.error { throw error }
    }
    func reset() throws {
        let cb = try command("Initialize seeded flow")
        let blit = cb.makeBlitCommandEncoder()!; blit.fill(buffer: clock, range: 0..<clock.length, value: 0); blit.endEncoding()
        let e = cb.makeComputeCommandEncoder()!; var p = GPUParams(config)
        dispatch("coefficients", e, &p, coefficients, forcing)
        dispatch("initializeField", e, &p, omega)
        try plan.append(cb, e, omega, inverse: false)
        dispatch("filterState", e, &p, omega, coefficients)
        e.endEncoding(); try Self.finish(cb)
    }
    // All operations share one encoder and command buffer in the production path.
    func encodeStep(_ cb: MTLCommandBuffer, _ e: MTLComputeCommandEncoder) throws {
        var p = GPUParams(config)
        for stage in 0..<3 {
            p.stage = UInt32(stage)
            encodeDerivatives(e, &p)
            try inverseDerivatives(cb, e)
            dispatch("nonlinear", e, &p, velocity, gradient, rhs, maxima, extraDX, extraDY)
            if stage == 0 { dispatch("chooseDT", e, &p, maxima, clock, threads: groupWidth) }
            try (realPlan ?? plan).append(cb, e, rhs, inverse: false)
            dispatch("rkUpdate", e, &p, omega, base, rhs, coefficients, forcing, clock)
        }
        dispatch("advanceClock", e, &p, clock, threads: 1)
    }
    private func encodeDerivatives(_ e: MTLComputeCommandEncoder, _ p: inout GPUParams) {
        dispatch(config.packed ? "derivePacked" : "deriveSeparate", e, &p, omega, coefficients, velocity, gradient, extraDX, extraDY)
    }
    private func inverseDerivatives(_ cb: MTLCommandBuffer, _ e: MTLComputeCommandEncoder) throws {
        try plan.append(cb, e, velocity, inverse: true); try plan.append(cb, e, gradient, inverse: true)
        if !config.packed { try plan.append(cb, e, extraDX, inverse: true); try plan.append(cb, e, extraDY, inverse: true) }
    }
    func encodeDisplay(_ cb: MTLCommandBuffer, _ e: MTLComputeCommandEncoder, slot: DisplaySlot) throws {
        var p = GPUParams(config)
        dispatch("prepareDisplay", e, &p, omega, coefficients, velocity, gradient)
        try plan.append(cb, e, velocity, inverse: true); try plan.append(cb, e, gradient, inverse: true)
        e.setTexture(slot.texture, index: 0)
        dispatch("diagnosticField", e, &p, velocity, gradient, partial)
        dispatch("finishDiagnostic", e, &p, partial, slot.diagnostic, clock, threads: groupWidth)
    }
    func inject(_ cb: MTLCommandBuffer, _ e: MTLComputeCommandEncoder, x: Float, y: Float, strength: Float) {
        var p = GPUParams(config); p.injectionX = x; p.injectionY = y; p.injectionStrength = strength
        dispatch("injectVortex", e, &p, omega, coefficients)
    }
    func run(steps: Int, display: DisplaySlot? = nil) throws -> Double {
        let cb = try command("Synchronous verification batch")
        let encoder = cb.makeComputeCommandEncoder()!
        for _ in 0..<steps { try encodeStep(cb, encoder) }
        if let display { try encodeDisplay(cb, encoder, slot: display) }
        encoder.endEncoding(); try Self.finish(cb)
        return (cb.gpuEndTime-cb.gpuStartTime)*1000
    }
    // Profiling deliberately isolates phases. This perturbs scheduling and is never a throughput result.
    func profileStep(slot: DisplaySlot, target: MTLTexture) throws {
        func phase(_ label: String, _ body: (MTLCommandBuffer, MTLComputeCommandEncoder) throws -> Void) throws {
            let cb = try command(label), e = cb.makeComputeCommandEncoder()!
            try body(cb,e); e.endEncoding(); try Self.finish(cb)
            profile[label, default: 0] += (cb.gpuEndTime-cb.gpuStartTime)*1000
        }
        var p = GPUParams(config)
        for stage in 0..<3 {
            p.stage = UInt32(stage)
            try phase("spectral") { _,e in self.encodeDerivatives(e,&p) }
            try phase("inverse FFTs") { cb,e in try self.inverseDerivatives(cb,e) }
            try phase("nonlinear + CFL") { _,e in
                self.dispatch("nonlinear", e, &p, self.velocity, self.gradient, self.rhs, self.maxima, self.extraDX, self.extraDY)
                if stage == 0 { self.dispatch("chooseDT", e, &p, self.maxima, self.clock, threads: self.groupWidth) }
            }
            try phase("forward FFT") { cb,e in try (self.realPlan ?? self.plan).append(cb,e,self.rhs,inverse:false) }
            try phase("RK update") { _,e in self.dispatch("rkUpdate", e, &p, self.omega, self.base, self.rhs, self.coefficients, self.forcing, self.clock) }
        }
        try phase("clock") { _,e in self.dispatch("advanceClock", e, &p, self.clock, threads:1) }
        try phase("visualization + diagnostics") { cb,e in try self.encodeDisplay(cb,e,slot:slot) }
        let cb = try command("Render profile"); Self.encodeRender(resources, cb, texture:slot.texture, target:target)
        try Self.finish(cb); profile["rendering", default:0] += (cb.gpuEndTime-cb.gpuStartTime)*1000
    }
    static func encodeRender(_ r: MetalResources, _ cb: MTLCommandBuffer, texture: MTLTexture, target: MTLTexture, settings: DisplaySettings = DisplaySettings()) {
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
        let e = cb.makeRenderCommandEncoder(descriptor: pass)!
        e.setRenderPipelineState(r.renderPipeline); e.setFragmentTexture(texture, index:0)
        var s = settings; e.setFragmentBytes(&s, length: MemoryLayout<DisplaySettings>.stride, index:0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount:3); e.endEncoding()
    }
    // Full-field transfers below are used ONLY by correctness tests and explicit export.
    func read(_ buffer: MTLBuffer, floats: Int? = nil) throws -> [Float] {
        let bytes = (floats ?? buffer.length/4)*4
        let staging = try resources.buffer(bytes, "Test readback", shared:true)
        let cb = try command("Test readback"), b = cb.makeBlitCommandEncoder()!
        b.copy(from:buffer, sourceOffset:0, to:staging, destinationOffset:0, size:bytes); b.endEncoding(); try Self.finish(cb)
        return Array(UnsafeBufferPointer(start:staging.contents().assumingMemoryBound(to:Float.self), count:bytes/4))
    }
    func loadPhysical(_ values: [Float]) throws {
        precondition(values.count == count)
        var complex = [Float](repeating:0,count:count*2)
        for i in 0..<count { complex[i*2] = values[i] }
        let staging = resources.device.makeBuffer(bytes:complex, length:count*8, options:.storageModeShared)!
        let cb = try command("Test upload"), b = cb.makeBlitCommandEncoder()!
        b.copy(from:staging,sourceOffset:0,to:omega,destinationOffset:0,size:count*8); b.fill(buffer:clock,range:0..<clock.length,value:0); b.endEncoding()
        let e = cb.makeComputeCommandEncoder()!; var p = GPUParams(config)
        try plan.append(cb,e,omega,inverse:false); dispatch("filterState",e,&p,omega,coefficients); e.endEncoding(); try Self.finish(cb)
    }
    func physicalState() throws -> [Float] {
        let cb = try command("Test inverse"), b = cb.makeBlitCommandEncoder()!
        b.copy(from:omega,sourceOffset:0,to:rhs,destinationOffset:0,size:count*8); b.endEncoding()
        let e = cb.makeComputeCommandEncoder()!; try plan.append(cb,e,rhs,inverse:true);e.endEncoding();try Self.finish(cb)
        let data = try read(rhs); return stride(from:0,to:data.count,by:2).map { data[$0] }
    }
}
