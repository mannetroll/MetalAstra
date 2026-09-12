import Metal
import Foundation

final class MetalResources {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let kernels: [String: MTLComputePipelineState]
    let renderPipeline: MTLRenderPipelineState
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw LabError.message("A Metal GPU is required.") }
        self.device = device; self.queue = queue
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: MetalResources.self))
        self.library = library
        var kernels: [String: MTLComputePipelineState] = [:]
        for name in ["coefficients", "initializeField", "filterState", "derivePacked", "deriveSeparate", "nonlinear", "chooseDT", "rkUpdate", "advanceClock", "prepareDisplay", "diagnosticField", "finishDiagnostic", "injectVortex", "testOperator"] {
            guard let fn = library.makeFunction(name: name) else { throw LabError.message("Missing Metal kernel: \(name)") }
            kernels[name] = try device.makeComputePipelineState(function: fn)
        }
        self.kernels = kernels
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        desc.fragmentFunction = library.makeFunction(name: "fieldFragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderPipeline = try device.makeRenderPipelineState(descriptor: desc)
    }
    func buffer(_ length: Int, _ label: String, shared: Bool = false) throws -> MTLBuffer {
        guard let b = device.makeBuffer(length: length, options: shared ? .storageModeShared : .storageModePrivate) else { throw LabError.message("GPU allocation failed: \(label), \(length) bytes") }
        b.label = label; return b
    }
    func texture(size: Int, display: Bool = false) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: display ? .bgra8Unorm : .rgba32Float, width: size, height: size, mipmapped: false)
        d.storageMode = .private; d.usage = display ? [.renderTarget, .shaderRead] : [.shaderRead, .shaderWrite]
        guard let t = device.makeTexture(descriptor: d) else { throw LabError.message("GPU texture allocation failed.") }; return t
    }
}

final class FFTPlan {
    let handle: OpaquePointer
    init(resources: MetalResources, buffer: MTLBuffer, size: Int, real: Bool = false) throws {
        var error: Int32 = 0
        guard let h = TLFFTCreate(Unmanaged.passUnretained(resources.device as AnyObject).toOpaque(), Unmanaged.passUnretained(resources.queue as AnyObject).toOpaque(), Unmanaged.passUnretained(buffer as AnyObject).toOpaque(), UInt32(size), 1, real ? 1 : 0, &error) else { throw LabError.message("VkFFT plan creation failed (\(error)).") }
        handle = h
    }
    deinit { TLFFTDestroy(handle) }
    func append(_ cb: MTLCommandBuffer, _ e: MTLComputeCommandEncoder, _ buffer: MTLBuffer, inverse: Bool) throws {
        let result = TLFFTAppend(handle, Unmanaged.passUnretained(cb as AnyObject).toOpaque(), Unmanaged.passUnretained(e as AnyObject).toOpaque(), Unmanaged.passUnretained(buffer as AnyObject).toOpaque(), inverse ? 1 : 0)
        guard result == 0 else { throw LabError.message("VkFFT append failed (\(result)).") }
        e.memoryBarrier(scope: .buffers)
    }
}

final class DisplaySlot {
    let texture: MTLTexture
    let diagnostic: MTLBuffer
    var writing = false
    var readers = 0
    init(_ resources: MetalResources, size: Int) throws {
        texture = try resources.texture(size: size)
        diagnostic = try resources.buffer(MemoryLayout<GPUDiagnostic>.stride, "Diagnostic readback", shared: true)
    }
    var values: GPUDiagnostic { diagnostic.contents().load(as: GPUDiagnostic.self) }
}

// All methods are synchronized. A snapshot remains reserved until rendering completes.
final class SnapshotExchange {
    private let lock = NSLock()
    private var latest: DisplaySlot?
    let slots: [DisplaySlot]
    init(_ r: MetalResources, size: Int) throws { slots = try (0..<3).map { _ in try DisplaySlot(r, size: size) } }
    func reserve() -> DisplaySlot? {
        lock.lock(); defer { lock.unlock() }
        guard let slot = slots.first(where: { $0 !== latest && !$0.writing && $0.readers == 0 }) else { return nil }
        slot.writing = true; return slot
    }
    func publish(_ slot: DisplaySlot) { lock.lock(); slot.writing = false; latest = slot; lock.unlock() }
    func cancel(_ slot: DisplaySlot) { lock.lock(); slot.writing = false; lock.unlock() }
    func acquire() -> DisplaySlot? { lock.lock(); defer { lock.unlock() }; latest?.readers += 1; return latest }
    func release(_ slot: DisplaySlot) { lock.lock(); slot.readers -= 1; lock.unlock() }
}
