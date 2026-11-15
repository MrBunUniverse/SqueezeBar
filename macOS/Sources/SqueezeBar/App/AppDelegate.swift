import Foundation
import AppKit

@main
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app operates strictly as an accessory utility without a dock icon
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        
        // Register for macOS Services provider
        NSApp.servicesProvider = self
        
        // Initialize menu bar status item and drop controller
        statusBarController = StatusBarController()
        
        // Start watch folder monitoring if enabled
        let state = AppState.shared
        let welcome = WelcomeWindowController.shared
        if state.isWatchFolderEnabled, let path = state.watchFolderPath {
            FolderWatchService.shared.startMonitoring(path: path)
        }
        
        // Show floating desktop drop basket if enabled
        if state.floatingBallEnabled {
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                LiquidBallModel.shared.inflateIn()
            }
            FloatingBallController.shared.show()
        }
        
        if !UserDefaults.standard.bool(forKey: WelcomeWindowController.completedKey) {
            welcome.show()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        FolderWatchService.shared.stopMonitoring()
        AppState.shared.flushHistory()
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Quit SqueezeBar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    // MARK: - Quit
    // Every quit path (DropBall menu, status menu, popover, Cmd+Q) ends in NSApp.terminate, so they all pass through here.
    private var isAwaitingTerminateReply = false
    
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isAwaitingTerminateReply { return .terminateLater }
        
        // Logout, restart and shutdown get no prompt and no animation, so the system is never held up by them.
        let systemQuit = isSystemQuit()
        let unfinishedJobs = AppState.shared.activeJobs.filter { !$0.isFinished }.count
        
        if unfinishedJobs > 0 {
            if !systemQuit && !confirmQuit(cancelling: unfinishedJobs) {
                return .terminateCancel
            }
            AppState.shared.cancelAllJobs()
        }
        
        let popsBall = !systemQuit
            && FloatingBallController.shared.isBallVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard popsBall || unfinishedJobs > 0 else { return .terminateNow }
        
        isAwaitingTerminateReply = true
        Task { @MainActor in
            if popsBall {
                await LiquidBallModel.shared.playPop()
            }
            await MediaCompressionEngine.shared.waitUntilIdle()
            self.replyToTerminate()
        }
        // The reply must always arrive or the app can never quit, so it does not depend on the work above finishing.
        let fallback = Timer(timeInterval: unfinishedJobs > 0 ? 3 : 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.replyToTerminate() }
        }
        RunLoop.main.add(fallback, forMode: .common)
        return .terminateLater
    }
    
    private func replyToTerminate() {
        guard isAwaitingTerminateReply else { return }
        isAwaitingTerminateReply = false
        NSApp.reply(toApplicationShouldTerminate: true)
    }
    
    /// True when macOS is ending the session rather than the user quitting the app.
    /// loginwindow tags its quit Apple event with a reason; a quit from a menu, Cmd+Q or the Dock carries none.
    private func isSystemQuit() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        let reason = AEKeyword(kAEQuitReason)
        return event.attributeDescriptor(forKeyword: reason) != nil || event.paramDescriptor(forKeyword: reason) != nil
    }
    
    private func confirmQuit(cancelling jobCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Quit SqueezeBar?")
        alert.informativeText = String(localized: "\(jobCount) compressions are still running. Quitting cancels them.")
        alert.addButton(withTitle: String(localized: "Quit"))
        // NSAlert only binds Escape by itself when the title is the English "Cancel".
        alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
    
    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - macOS Finder Service Right-Click Handler (Beta Feature)
    @objc public func handleFinderService(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        guard let types = pboard.types,
              types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")),
              let items = pboard.pasteboardItems else {
            return
        }
        
        var urls: [URL] = []
        for item in items {
            if let str = item.string(forType: .fileURL), let url = URL(string: str) {
                urls.append(url)
            } else if let propertyList = item.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
                urls.append(contentsOf: propertyList.map { URL(fileURLWithPath: $0) })
            }
        }
        
        guard !urls.isEmpty else { return }
        
        Task { @MainActor in
            guard AppState.shared.finderServiceEnabled else { return }
            
            // Play haptic feedback
            if AppState.shared.hapticEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
            
            await MediaCompressionEngine.shared.processDroppedURLs(urls)
        }
    }
    
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
