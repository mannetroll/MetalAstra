import SwiftUI
struct ContentView: View {
    @ObservedObject var model: SimulationModel
    @State private var smokeStarted = false
    var body: some View {
        GeometryReader { geometry in
            let side = max(1, min(geometry.size.width - WindowLayout.controlsWidth - WindowLayout.dividerWidth,
                                  geometry.size.height - WindowLayout.diagnosticsHeight))
            HStack(spacing:0) {
                VStack(spacing:0) {
                    simulation.frame(width:side,height:side)
                    VStack(spacing:0) {
                        Divider()
                        DiagnosticsView(metrics:model.metrics)
                        HStack {
                            Text(model.deviceName + " · Metal / VkFFT");Spacer()
                            Text(String(format:"Active wall %.1f s · GPU %.2f ms/step · CPU %.2f ms/step",model.metrics.wallTime,model.metrics.gpuMilliseconds,model.metrics.cpuMilliseconds))
                        }.font(.system(size:10)).foregroundStyle(.tertiary).padding(.horizontal,20).padding(.bottom,10)
                    }.frame(maxHeight:.infinity,alignment:.top)
                }.frame(width:side)
                Divider().frame(width:WindowLayout.dividerWidth)
                ControlsView(model:model)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let args = CommandLine.arguments
            if !smokeStarted, let i = args.firstIndex(of:"--ui-smoke"), i+1<args.count {
                smokeStarted = true
                Task { await UIAutomation.run(model,output:args[i+1]) }
            }
        }
        .alert("Simulation stopped",isPresented:Binding(get:{model.error != nil},set:{if !$0 { model.error = nil }})) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }

    private var simulation: some View {
        ZStack {
            SimulationView(model:model)
            VStack {
                HStack {
                    Text("\(model.config.size)²  /  \(model.config.preset.title.uppercased())").font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    if !model.running { Text("PAUSED").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                }
                Spacer()
                HStack {
                    Text(String(format:"t = %.3f     dt = %.5f",model.metrics.physical.time,model.metrics.physical.dt))
                    Spacer()
                    Text(String(format:"max |ω| %.2f   |u| %.3f",model.metrics.physical.maxOmega,model.metrics.physical.maxSpeed))
                }.font(.system(size:10,design:.monospaced)).foregroundStyle(.white.opacity(0.7))
            }.padding(18).allowsHitTesting(false)
            if model.loading { VStack(spacing:12) { ProgressView();Text("Preparing GPU flow…").font(.callout) }.padding(24).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:14)) }
        }
    }
}
