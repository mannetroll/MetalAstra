import SwiftUI
import MetalKit

struct SimulationView: NSViewRepresentable {
    @ObservedObject var model: SimulationModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> FlowView {
        let view = FlowView(); view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm; view.framebufferOnly = true
        view.clearColor = MTLClearColor(red:0.01,green:0.014,blue:0.024,alpha:1)
        view.preferredFramesPerSecond = 60; view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        view.inject = { x,y,strength in model.engine.inject(x:x,y:y,strength:strength) }
        return view
    }
    func updateNSView(_ view: FlowView, context: Context) { context.coordinator.settings = model.display }
    final class Coordinator: NSObject, MTKViewDelegate {
        let engine: SimulationEngine
        var settings = DisplaySettings()
        private let capacity = DispatchSemaphore(value: 2)
        @MainActor init(model: SimulationModel) { engine = model.engine; settings = model.display }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            engine.requestSnapshot()
            guard capacity.wait(timeout:.now()) == .success else { return }
            guard let (r,exchange) = engine.renderResources(), let slot = exchange.acquire() else { capacity.signal(); return }
            guard let drawable = view.currentDrawable, let cb = r.queue.makeCommandBuffer() else { exchange.release(slot); capacity.signal(); return }
            SpectralSolver.encodeRender(r,cb,texture:slot.texture,target:drawable.texture,settings:settings)
            cb.label = "Present completed flow snapshot"; cb.present(drawable)
            drawable.addPresentedHandler { [engine] drawable in engine.framePresented(time:drawable.presentedTime) }
            cb.addCompletedHandler { [capacity] _ in exchange.release(slot); capacity.signal() }
            cb.commit()
        }
    }
}
final class FlowView: MTKView {
    var inject: ((Float,Float,Float)->Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { send(event,sign:1) }
    override func mouseDragged(with event: NSEvent) { send(event,sign:1) }
    override func rightMouseDown(with event: NSEvent) { send(event,sign:-1) }
    override func rightMouseDragged(with event: NSEvent) { send(event,sign:-1) }
    private func send(_ event: NSEvent,sign:Float) {
        let p = convert(event.locationInWindow,from:nil)
        // Metal image row zero is shown at the top; AppKit coordinates start at the bottom.
        inject?(Float(p.x/bounds.width),Float(1-p.y/bounds.height),sign*12)
    }
}
