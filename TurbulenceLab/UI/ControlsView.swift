import SwiftUI

struct ControlsView: View {
    @ObservedObject var model: SimulationModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:5) {
                    Text("FLOW").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Preset",selection:$model.config.preset) { ForEach(Preset.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                        .onChange(of:model.config.preset) { _,_ in model.reset() }
                    Text(model.config.preset.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Picker("Grid",selection:$model.config.size) { ForEach([256,512,1024,2048],id:\.self) { Text("\($0) × \($0)").tag($0) } }
                        .onChange(of:model.config.size) { _,_ in model.reset() }
                    HStack { Text("Seed"); Spacer(); TextField("Seed",value:$model.config.seed,format:.number).frame(width:95).multilineTextAlignment(.trailing).onSubmit { model.reset() } }
                }
                VStack(alignment:.leading,spacing:12) {
                    label("DYNAMICS")
                    numeric("Viscosity ν",value:$model.config.viscosity,range:0...0.003,format:"%.5f")
                    numeric("Linear drag α",value:$model.config.drag,range:0...0.15,format:"%.3f")
                    numeric("Maximum dt",value:$model.config.dt,range:0.0002...0.02,format:"%.4f")
                    Toggle("Automatic CFL",isOn:$model.config.automatic)
                    if model.config.automatic { numeric("CFL number",value:$model.config.cfl,range:0.1...0.65,format:"%.2f") }
                    if model.config.preset == .inverseCascade { numeric("Forcing",value:$model.config.forcing,range:0...4,format:"%.2f") }
                    Picker("Steps / batch",selection:$model.config.stepsPerBatch) { ForEach([1,2,4,8,16],id:\.self) { Text("\($0)").tag($0) } }
                    Text("Fixed dt also respects the explicit diffusion limit.").font(.caption2).foregroundStyle(.tertiary)
                }
                VStack(alignment:.leading,spacing:12) {
                    label("APPEARANCE")
                    Picker("Field",selection:$model.display.field) {
                        Text("Vorticity ω").tag(UInt32(0));Text("Speed |u|").tag(UInt32(1));Text("Streamfunction ψ").tag(UInt32(2));Text("Enstrophy ½ω²").tag(UInt32(3))
                    }
                    .onChange(of:model.display.field) { _,field in model.display.scale = [Float(1),0.3,0.05,2][Int(field)] }
                    Picker("Color map",selection:$model.display.palette) {
                        Text("Ice / Fire").tag(UInt32(0));Text("Inferno").tag(UInt32(1));Text("Turbo").tag(UInt32(2));Text("Neon").tag(UInt32(3))
                    }
                    numeric("Exposure",value:$model.display.exposure,range:-4...5,format:"%.1f")
                    numeric("Contrast",value:$model.display.contrast,range:0.2...3,format:"%.1f")
                    Toggle("Contour bands",isOn:Binding(get:{model.display.contours != 0},set:{model.display.contours = $0 ? 1 : 0}))
                    Text(String(format:"Color unit scale: %.3g",model.display.scale)).font(.caption2).foregroundStyle(.secondary)
                    Text("Signed fields use a fixed zero-centered scale. Exposure changes the color mapping, never the physics.").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment:.leading,spacing:5) {
                    label("STIR THE FLOW")
                    Text("Drag to add a positive vortex.\nRight-drag to add a negative vortex.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.frame(width:280).background(Color(nsColor:.controlBackgroundColor).opacity(0.72))
        .onChange(of:model.config.viscosity) { _,_ in model.update() }
        .onChange(of:model.config.drag) { _,_ in model.update() }
        .onChange(of:model.config.dt) { _,_ in model.update() }
        .onChange(of:model.config.automatic) { _,_ in model.update() }
        .onChange(of:model.config.cfl) { _,_ in model.update() }
        .onChange(of:model.config.forcing) { _,_ in model.update() }
        .onChange(of:model.config.stepsPerBatch) { _,_ in model.update() }
    }
    func label(_ text:String) -> some View { Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
    func numeric(_ title:String,value:Binding<Float>,range:ClosedRange<Float>,format:String) -> some View {
        VStack(spacing:4) { HStack { Text(title);Spacer();Text(String(format:format,value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) };Slider(value:value,in:range) }
    }
}
