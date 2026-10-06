import SwiftUI
import AppKit

@MainActor
public final class WelcomeWindowController: NSObject, NSWindowDelegate, ObservableObject {
    public static let shared = WelcomeWindowController()
    private static let bookmarkKey = "squeezebar.fileAccessBookmark"
    public static let completedKey = "hasCompletedWelcome_v1"

    @Published private(set) var authorizedFolder: URL?
    @Published private(set) var isRequesting = false
    @Published private(set) var accessError: String?
    private var window: NSWindow?
    private var isSecurityScoped = false

    private override init() {
        super.init()
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
            try activate(url)
            if stale { try saveBookmark(url) }
        } catch {
            revokeAccess()
            accessError = String(localized: "Choose the folder again to restore file access.")
        }
    }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = WelcomeView(controller: self)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Welcome to SqueezeBar")
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = NSHostingView(rootView: view)
        win.delegate = self
        win.center()
        win.isReleasedWhenClosed = false
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setFileAccess(_ enabled: Bool) {
        accessError = nil
        guard enabled else {
            revokeAccess()
            return
        }
        guard let window, !isRequesting else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Allow Folder Access")
        panel.message = "Choose the folder SqueezeBar can read and write."
        isRequesting = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isRequesting = false
            guard response == .OK, let url = panel.url else { return }
            do {
                try self.activate(url)
                try self.saveBookmark(url)
            } catch {
                self.revokeAccess()
                self.accessError = String(localized: "Couldn’t access that folder. Please choose another folder.")
            }
        }
    }

    private func activate(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
        authorizedFolder = url
        isSecurityScoped = scoped
    }

    private func saveBookmark(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }

    private func revokeAccess() {
        if isSecurityScoped { authorizedFolder?.stopAccessingSecurityScopedResource() }
        authorizedFolder = nil
        isSecurityScoped = false
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    func completeWelcome() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window?.close()
        StatusBarController.sharedInstance?.showPopover(sender: nil)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct WelcomeView: View {
    @ObservedObject var controller: WelcomeWindowController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    private let frostGradient = LinearGradient(
        stops: [.init(color: .white.opacity(0.10), location: 0), .init(color: .white.opacity(0.55), location: 0.45), .init(color: .white, location: 1)],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Welcome")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white.opacity(0.10), in: Capsule())

            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to SqueezeBar")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Choose a folder to allow access to your media files.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("File access", systemImage: "folder.badge.plus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Toggle("File access", isOn: Binding(
                        get: { controller.authorizedFolder != nil },
                        set: { controller.setFileAccess($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AppState.shared.accentColor)
                    .disabled(controller.isRequesting)
                    .accessibilityLabel("File access")
                    .accessibilityHint("Choose a folder to enable access. Turn off to forget this folder authorization.")
                }

                (controller.authorizedFolder.map { Text(verbatim: $0.path) } ?? Text("Allow access to a folder you choose."))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let error = controller.accessError {
                    Text(error)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Text("You can also select files later.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue", action: controller.completeWelcome)
                    .buttonStyle(.borderedProminent)
                    .tint(AppState.shared.accentColor)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.isRequesting)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .padding(.bottom, 26)
        .frame(width: 540, height: 380)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .background {
            ZStack {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    shape.fill(.ultraThickMaterial).mask(frostGradient)
                    Color.clear
                        .glassEffect(.regular.tint(.black.opacity(0.22)), in: shape)
                        .mask(frostGradient)
                    shape.fill(LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.48), location: 0.22), .init(color: .black.opacity(0.65), location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(0.35), .white.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            ), lineWidth: 0.8)
        }
    }
}
