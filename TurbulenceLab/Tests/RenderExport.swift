import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct RenderExport {
    // An explicit image export is the only rendering path that reads pixels to CPU.
    static func write(_ solver: SpectralSolver, path: String, settings: DisplaySettings) throws {
        let r = solver.resources, n = solver.size
        let slot = solver.snapshots.slots[0], target = try r.texture(size:n,display:true)
        let staging = try r.buffer(n*n*4,"Explicit PNG export",shared:true)
        let cb = try solver.command("Export image"), e = cb.makeComputeCommandEncoder()!
        try solver.encodeDisplay(cb,e,slot:slot);e.endEncoding()
        SpectralSolver.encodeRender(r,cb,texture:slot.texture,target:target,settings:settings)
        let b=cb.makeBlitCommandEncoder()!
        b.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:n,height:n,depth:1),to:staging,destinationOffset:0,destinationBytesPerRow:n*4,destinationBytesPerImage:n*n*4)
        b.endEncoding();try SpectralSolver.finish(cb)
        let data = Data(bytes:staging.contents(),count:n*n*4)
        guard let provider = CGDataProvider(data:data as CFData),let image = CGImage(width:n,height:n,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:n*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent),let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath:path) as CFURL,UTType.png.identifier as CFString,1,nil) else { throw LabError.message("Could not create PNG export.") }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { throw LabError.message("Could not write PNG export.") }
        print("Exported \(n) × \(n) image to \(path)")
    }
}
