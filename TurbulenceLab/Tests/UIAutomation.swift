import AppKit
import Metal

@MainActor enum UIAutomation {
    static func run(_ model: SimulationModel, output: String) async {
        do {
            try await wait { !model.loading }
            guard let window = NSApplication.shared.windows.first(where: { $0.contentView != nil }) else { throw LabError.message("No application window") }
            window.makeKeyAndOrderFront(nil)
            try await wait { model.metrics.physical.steps > 0 }
            print("PASS native window and live simulation")
            guard let runButton = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "simulation.run" })?.view as? NSButton else { throw LabError.message("Native run toolbar button missing") }
            runButton.performClick(nil)
            guard !model.running else { throw LabError.message("Native pause action failed") }
            try await Task.sleep(nanoseconds:600_000_000)
            let paused = model.metrics.physical.steps
            try await Task.sleep(nanoseconds:300_000_000)
            guard model.metrics.physical.steps == paused else { throw LabError.message("Pause did not drain outstanding work") }
            print("PASS pause drains outstanding simulation")
            for size in [NSSize(width:1050,height:720),NSSize(width:1500,height:950),NSSize(width:1280,height:900)] {
                window.setContentSize(size);try await Task.sleep(nanoseconds:100_000_000)
            }
            print("PASS native window resizing")
            for field in UInt32(0)...3 {
                model.display.field = field;model.display.palette = field;model.display.contours = field%2
                try await Task.sleep(nanoseconds:100_000_000)
            }
            model.display = DisplaySettings()
            guard let content = window.contentView, let flow = findFlow(content) else { throw LabError.message("MTKView missing from window") }
            let point = flow.convert(NSPoint(x:flow.bounds.midX,y:flow.bounds.midY),to:nil)
            guard let event = NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1) else { throw LabError.message("Cannot create input event") }
            flow.mouseDown(with:event)
            try await Task.sleep(nanoseconds:300_000_000)
            print("PASS four fields, four palettes, contours and vortex input")
            for preset in Preset.allCases {
                model.config.size = 256;model.config.preset = preset;model.reset()
                try await wait { !model.loading }
                guard model.error == nil else { throw LabError.message(model.error!) }
            }
            print("PASS preset changes and grid reconstruction")
            model.config.size = 1024;model.config.preset = .vortexGas;model.reset()
            try await wait { !model.loading }
            runButton.performClick(nil)
            guard model.running else { throw LabError.message("Native resume action failed") }
            try await wait { model.metrics.physical.steps > 1600 }
            model.running = false;model.update()
            try await Task.sleep(nanoseconds:400_000_000)
            guard model.error == nil else { throw LabError.message(model.error!) }
            try capture(window:window,engine:model.engine,path:output)
            print("PASS resume and native view/GPU image capture: \(output)")
            print("ALL UI SMOKE CHECKS PASSED")
            fflush(stdout);NSApplication.shared.terminate(nil)
        } catch { fputs("UI SMOKE FAILURE: \(error.localizedDescription)\n",stderr);exit(1) }
    }
    static func wait(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition() {
            if Date()>deadline { throw LabError.message("UI condition timed out") }
            try await Task.sleep(nanoseconds:20_000_000)
        }
    }
    static func findFlow(_ view:NSView)->FlowView? {
        if let view = view as? FlowView { return view }
        for child in view.subviews { if let found = findFlow(child) { return found } }
        return nil
    }
    static func capture(window:NSWindow,engine:SimulationEngine,path:String) throws {
        guard let root = window.contentView?.superview, let flow = findFlow(root), let bitmap = root.bitmapImageRepForCachingDisplay(in:root.bounds), let (r,exchange) = engine.renderResources(), let slot = exchange.acquire() else { throw LabError.message("UI capture resources unavailable") }
        defer { exchange.release(slot) }
        root.cacheDisplay(in:root.bounds,to:bitmap)
        // CAMetalLayer is not drawn by cacheDisplay: compose its exact current GPU snapshot
        // into the cached native view hierarchy, using the view's actual coordinates.
        let n = slot.texture.width, target = try r.texture(size:n,display:true)
        let staging = try r.buffer(n*n*4,"UI verification pixels",shared:true)
        let cb=r.queue.makeCommandBuffer()!
        SpectralSolver.encodeRender(r,cb,texture:slot.texture,target:target)
        let b=cb.makeBlitCommandEncoder()!
        b.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:n,height:n,depth:1),to:staging,destinationOffset:0,destinationBytesPerRow:n*4,destinationBytesPerImage:n*n*4);b.endEncoding()
        try SpectralSolver.finish(cb)
        let data=Data(bytes:staging.contents(),count:n*n*4)
        guard let provider=CGDataProvider(data:data as CFData), let cg=CGImage(width:n,height:n,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:n*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent),let context=NSGraphicsContext(bitmapImageRep:bitmap) else { throw LabError.message("UI bitmap conversion failed") }
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        NSImage(cgImage:cg,size:NSSize(width:n,height:n)).draw(in:flow.convert(flow.bounds,to:root))
        NSGraphicsContext.restoreGraphicsState()
        guard let png=bitmap.representation(using:.png,properties:[:]) else { throw LabError.message("UI PNG conversion failed") }
        try png.write(to:URL(fileURLWithPath:path))
    }
}
