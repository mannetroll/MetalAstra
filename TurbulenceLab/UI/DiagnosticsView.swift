import SwiftUI
struct DiagnosticsView: View {
    let metrics: LiveMetrics
    var body: some View {
        HStack(spacing:16) {
            metric("PHYSICAL / WALL",String(format:"%.2f×",metrics.turbo),accent:true)
            metric("STEPS / S",String(format:"%.1f",metrics.stepsPerSecond))
            metric("MS / STEP",String(format:"%.2f",metrics.milliseconds))
            metric("FPS",String(format:"%.0f",metrics.fps))
            Divider().frame(height:28)
            metric("ENERGY",String(format:"%.4f",metrics.physical.energy))
            metric("ENSTROPHY",String(format:"%.4f",metrics.physical.enstrophy))
            Spacer(minLength:0)
        }.padding(.horizontal,20).padding(.vertical,14)
    }
    func metric(_ title:String,_ value:String,accent:Bool = false) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.system(size:9,weight:.semibold,design:.rounded)).foregroundStyle(.secondary)
            Text(value).font(.system(size:19,weight:.medium,design:.monospaced)).foregroundStyle(accent ? Color.cyan : Color.primary)
        }
    }
}
