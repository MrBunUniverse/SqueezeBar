import Foundation
import AppKit

@main
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app operates strictly as an accessory utility without a dock icon
        NSApp.setActivationPolicy(.accessory)
        
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
            FloatingBallController.shared.show()
        }
        
        if !UserDefaults.standard.bool(forKey: WelcomeWindowController.completedKey) {
            welcome.show()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        FolderWatchService.shared.stopMonitoring()
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
