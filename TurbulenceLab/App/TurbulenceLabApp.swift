import SwiftUI
import AppKit
import Combine

enum WindowLayout {
    static let controlsWidth: CGFloat = 280
    static let dividerWidth: CGFloat = 1
    static let diagnosticsHeight: CGFloat = 90
    static let minimumImageSide: CGFloat = 560
    static let preferredImageSide: CGFloat = 800

    static func contentSize(imageSide: CGFloat) -> NSSize {
        NSSize(width: imageSide + controlsWidth + dividerWidth,
               height: imageSide + diagnosticsHeight)
    }
}

// Explicit AppKit window ownership avoids dependence on saved SwiftUI scene state.
// The content, inspector, alerts, and live diagnostics remain SwiftUI.
@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate {
    private let model = SimulationModel()
    private var window: NSWindow?
    private let runButton = NSButton(), resetButton = NSButton()
    private var subscriptions = Set<AnyCancellable>()
    private let runID = NSToolbarItem.Identifier("simulation.run")
    private let resetID = NSToolbarItem.Identifier("simulation.reset")
    func applicationDidFinishLaunching(_ notification: Notification) { showWindow() }
    func showWindow() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect:NSRect(origin:.zero,size:WindowLayout.contentSize(imageSide:WindowLayout.preferredImageSide)),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Turbulence Lab"
        let hostingController = NSHostingController(rootView:ContentView(model:model))
        // AppKit owns the outer size; SwiftUI lays out the square image inside it.
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.contentMinSize = WindowLayout.contentSize(imageSide:WindowLayout.minimumImageSide)
        window.delegate = self
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
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let available = screen.visibleFrame.insetBy(dx:24,dy:24)
            let content = window.contentRect(forFrameRect:available)
            let side = min(WindowLayout.preferredImageSide,
                           content.width - WindowLayout.controlsWidth - WindowLayout.dividerWidth,
                           content.height - WindowLayout.diagnosticsHeight)
            window.setContentSize(WindowLayout.contentSize(imageSide:side))
            window.contentView?.layoutSubtreeIfNeeded()
            // NSWindow.center() uses an optical vertical offset. Use the actual
            // visible-screen midpoint, after the toolbar and content are sized.
            window.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX - window.frame.width / 2,
                                          y:screen.visibleFrame.midY - window.frame.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps:true)
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !sender.styleMask.contains(.fullScreen) else { return frameSize }
        let content = sender.contentRect(forFrameRect:NSRect(origin:.zero,size:frameSize))
        // Follow the edge being dragged. The inspector/footer keep their readable
        // sizes while both dimensions of the simulation grow by the same amount.
        let widthChange = abs(frameSize.width - sender.frame.width)
        let heightChange = abs(frameSize.height - sender.frame.height)
        var side = widthChange > heightChange
            ? content.width - WindowLayout.controlsWidth - WindowLayout.dividerWidth
            : content.height - WindowLayout.diagnosticsHeight
        side = max(WindowLayout.minimumImageSide, side)
        if let screen = sender.screen {
            let available = sender.contentRect(forFrameRect:screen.visibleFrame)
            side = min(side, available.width - WindowLayout.controlsWidth - WindowLayout.dividerWidth,
                       available.height - WindowLayout.diagnosticsHeight)
        }
        return sender.frameRect(forContentRect:NSRect(origin:.zero,size:WindowLayout.contentSize(imageSide:side))).size
    }
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let content = window.contentRect(forFrameRect:newFrame)
        let side = min(content.width - WindowLayout.controlsWidth - WindowLayout.dividerWidth,
                       content.height - WindowLayout.diagnosticsHeight)
        let size = window.frameRect(forContentRect:NSRect(origin:.zero,size:WindowLayout.contentSize(imageSide:side))).size
        return NSRect(x:newFrame.midX - size.width / 2,y:newFrame.midY - size.height / 2,
                      width:size.width,height:size.height)
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
            let delegate=ApplicationDelegate();app.delegate=delegate
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
