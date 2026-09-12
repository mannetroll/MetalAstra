import SwiftUI
import AppKit
import Combine

// Explicit AppKit window ownership avoids dependence on saved SwiftUI scene state.
// The content, inspector, alerts, and live diagnostics remain SwiftUI.
@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {
    private let model = SimulationModel()
    private var window: NSWindow?
    private let runButton = NSButton(), resetButton = NSButton()
    private var subscriptions = Set<AnyCancellable>()
    private let runID = NSToolbarItem.Identifier("simulation.run")
    private let resetID = NSToolbarItem.Identifier("simulation.reset")
    func showWindow() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Turbulence Lab"
        window.contentViewController = NSHostingController(rootView:ContentView(model:model))
        window.contentMinSize = NSSize(width:1050,height:720)
        window.appearance = NSAppearance(named:.darkAqua)
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier:"TurbulenceLab.controls")
        toolbar.delegate = self;toolbar.displayMode = .iconOnly
        window.toolbar = toolbar;window.toolbarStyle = .unified
        self.window = window
        model.$running.combineLatest(model.$loading).sink { [weak self] running,loading in
            self?.runButton.title = running ? "Pause" : "Start"
            self?.runButton.image = NSImage(systemSymbolName:running ? "pause.fill":"play.fill",accessibilityDescription:running ? "Pause":"Start")
            self?.runButton.isEnabled = !loading;self?.resetButton.isEnabled = !loading
        }.store(in:&subscriptions)
        installMenus()
        window.center();window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool { showWindow();return true }
    @objc private func toggleRun() { guard !model.loading else { return };model.running.toggle();model.update() }
    @objc private func resetFlow() { guard !model.loading else { return };model.reset() }
    func toolbarAllowedItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { [.flexibleSpace,runID,resetID] }
    func toolbarDefaultItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { [.flexibleSpace,runID,resetID] }
    func toolbar(_ toolbar:NSToolbar,itemForItemIdentifier id:NSToolbarItem.Identifier,willBeInsertedIntoToolbar:Bool)->NSToolbarItem? {
        guard id==runID || id==resetID else { return nil }
        let item=NSToolbarItem(itemIdentifier:id),button=id==runID ? runButton:resetButton
        button.title = id==runID ? "Pause":"Reset"
        button.image = NSImage(systemSymbolName:id==runID ? "pause.fill":"arrow.counterclockwise",accessibilityDescription:button.title)
        button.bezelStyle = .texturedRounded;button.imagePosition = .imageLeading;button.target=self
        button.action = id==runID ? #selector(toggleRun):#selector(resetFlow)
        item.label=button.title;item.view=button;return item
    }
    private func installMenus() {
        let bar=NSMenu()
        let app=NSMenuItem();bar.addItem(app)
        let appMenu=NSMenu();app.submenu=appMenu
        appMenu.addItem(withTitle:"About Turbulence Lab",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"Hide Turbulence Lab",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        appMenu.addItem(withTitle:"Quit Turbulence Lab",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let edit=NSMenuItem();edit.title="Edit";bar.addItem(edit)
        let editMenu=NSMenu(title:"Edit");edit.submenu=editMenu
        editMenu.addItem(withTitle:"Undo",action:Selector(("undo:")),keyEquivalent:"z")
        let redo=editMenu.addItem(withTitle:"Redo",action:Selector(("redo:")),keyEquivalent:"z");redo.keyEquivalentModifierMask=[.command,.shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle:"Cut",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
        editMenu.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        editMenu.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        editMenu.addItem(withTitle:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        let simulation=NSMenuItem();simulation.title="Simulation";bar.addItem(simulation)
        let simulationMenu=NSMenu(title:"Simulation");simulation.submenu=simulationMenu
        let toggle=simulationMenu.addItem(withTitle:"Start / Pause",action:#selector(toggleRun),keyEquivalent:" ");toggle.keyEquivalentModifierMask=[];toggle.target=self
        simulationMenu.addItem(withTitle:"Reset",action:#selector(resetFlow),keyEquivalent:"r").target=self
        let windows=NSMenuItem();windows.title="Window";bar.addItem(windows)
        let windowMenu=NSMenu(title:"Window");windows.submenu=windowMenu
        windowMenu.addItem(withTitle:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        windowMenu.addItem(withTitle:"Close",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        let fullscreen=windowMenu.addItem(withTitle:"Toggle Full Screen",action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f");fullscreen.keyEquivalentModifierMask=[.command,.control]
        NSApplication.shared.mainMenu=bar;NSApplication.shared.windowsMenu=windowMenu
    }
}
@main enum EntryPoint {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--benchmark") || CommandLine.arguments.contains("--profile") || CommandLine.arguments.contains("--snapshot") {
            do { try autoreleasepool { try CommandLineRunner.run() } }
            catch { fputs("ERROR: \(error.localizedDescription)\n",stderr);exit(1) }
        } else {
            let app=NSApplication.shared
            app.setActivationPolicy(.regular)
            let delegate=ApplicationDelegate();app.delegate=delegate;delegate.showWindow()
            if CommandLine.arguments.contains("--ui-benchmark") {
                let args=CommandLine.arguments
                let index=args.firstIndex(of:"--duration")
                let duration=index.flatMap { $0+1<args.count ? Double(args[$0+1]):nil } ?? 20
                DispatchQueue.main.asyncAfter(deadline:.now()+max(duration,3)+30) {
                    fputs("UI benchmark timed out without completing.\n",stderr);exit(1)
                }
            }
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}
