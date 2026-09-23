import AppKit
import HerdviewCore
import SwiftUI

/// The app's one window: the agent list in a normal title bar window that can be
/// resized, minimized and closed. Closing it must not quit the app — polling and
/// the menu bar item carry on — so `isReleasedWhenClosed` is off and
/// `AppDelegate` refuses to terminate with it.
///
/// The title bar is transparent, and the list runs the whole height of the
/// window underneath it. The title bar's own row is the Quota's: the list reads
/// the top safe-area inset, ignores it, and puts `QuotaTitleBar` in that row
/// beside the window buttons — so the strip is clickable there while the empty
/// part of the row still drags the window.
///
/// It was an `NSToolbar` first, for the Liquid Glass a toolbar is given for
/// free. That was the wrong trade once the window itself became glass: from
/// macOS 26 every toolbar item is wrapped in a glass capsule of its own, and
/// the strip read as a row of separate buttons rather than as one thing. A
/// plain strip on the window's own glass says the same thing and stays quiet.
///
/// It can also be kept on top: at `.floating` the window stays above other
/// apps' windows, so the herd is readable while you work in an editor. That is
/// off by default and remembered between launches.
@MainActor
final class MainWindowController: NSObject {
    private static let frameAutosaveName = "herdview.mainWindow"

    private let window: NSWindow
    private let store: AgentStore
    private let preferences: WindowPreferences
    private let keepOnTopItem: NSMenuItem?
    private let filterState: FilterState
    private var reportedVisible = false

    /// Visibility hooks keep Quota work aligned with AppKit, including actions
    /// that do not go through this controller's `show()` / `hide()` methods.
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

    init(store: AgentStore,
         quotaStore: QuotaStore,
         preferences: WindowPreferences = WindowPreferences(),
         keepOnTopItem: NSMenuItem? = nil,
         findItem: NSMenuItem? = nil) {
        self.store = store
        self.preferences = preferences
        self.keepOnTopItem = keepOnTopItem
        // Built as a local before it is stored, because a stored property of
        // `self` cannot be read until every one of them is initialized — and
        // the list below is handed the very state this controller keeps.
        let filterState = FilterState(preferences: preferences)
        self.filterState = filterState
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            // `.fullSizeContentView` hands the title bar's own strip of the
            // window to the content view, which is what lets the Quota strip sit
            // in the same row as the window buttons instead of below them.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Herdview"
        // The Quota strip occupies the titlebar row, so the name would collide
        // with it. The menu bar item and the Dock already say whose window this
        // is.
        window.titleVisibility = .hidden
        window.contentMinSize = NSSize(width: 360, height: 240)
        window.isReleasedWhenClosed = false
        window.contentViewController = Self.backdrop(
            around: AgentListView(store: store, quotaStore: quotaStore, filter: filterState))
        // The window has to stop painting its own opaque grey before anything
        // behind it can show through the backdrop.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        // Remember where the user put it. Without a saved frame the window lands
        // in the bottom-left corner, so the first launch centres it instead.
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        _ = window.setFrameAutosaveName(Self.frameAutosaveName)

        super.init()

        window.delegate = self

        keepOnTopItem?.target = self
        keepOnTopItem?.action = #selector(toggleAlwaysOnTop)
        applyAlwaysOnTop(preferences.isAlwaysOnTop)

        findItem?.target = self
        findItem?.action = #selector(find)
    }

    var isVisible: Bool { window.isVisible && !window.isMiniaturized }

    func show() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        // `activate(ignoringOtherApps:)` is deprecated from macOS 14, and this
        // package still deploys to 13.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        reportShown()
    }

    func hide() {
        // Cancel synchronously rather than waiting for AppKit's order-off
        // notification; the notification remains the safety net for external
        // order-out and close paths.
        reportHidden()
        window.orderOut(nil)
    }

    private func reportShown() {
        reportedVisible = true
        onShow?()
    }

    private func reportHidden() {
        guard reportedVisible else { return }
        reportedVisible = false
        onHide?()
    }

    /// The Edit menu's `Find…`: bring the window forward and put the caret in
    /// the search field. The menu item is the only thing that knows ⌘F was
    /// pressed and the field is the only thing that can act on it, so the two
    /// are joined through the state's focus counter rather than directly.
    @objc func find() {
        show()
        filterState.requestFocus()
    }

    /// The Window menu's `Keep on Top`: float above other apps, or stop.
    @objc func toggleAlwaysOnTop() {
        let onTop = !preferences.isAlwaysOnTop
        preferences.isAlwaysOnTop = onTop
        applyAlwaysOnTop(onTop)
    }

    private func applyAlwaysOnTop(_ onTop: Bool) {
        window.level = onTop ? .floating : .normal
        keepOnTopItem?.state = onTop ? .on : .off
    }

    /// The menu bar item's action: show the window unless the user is already
    /// looking at it, in which case get out of the way.
    func toggle() {
        if isVisible && NSApp.isActive {
            hide()
        } else {
            show()
        }
    }

    /// The window's backdrop: the list hosted on top of a visual effect view
    /// that blurs whatever is behind the window.
    ///
    /// This is what makes the window read as glass rather than as a grey panel.
    /// It also means the list itself must draw no background of its own — the
    /// blur is the background, and a colour laid over it would erase the very
    /// thing it is here for.
    ///
    /// The blur is kept `.active` rather than following the window's key state.
    /// This is a window you glance at while working in an editor, so it is
    /// almost always the inactive one; letting it fall back to flat grey the
    /// moment it loses focus would mean it is grey exactly whenever it is being
    /// used.
    private static func backdrop<Content: View>(around content: Content) -> NSViewController {
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        // Pinned rather than given a frame and an autoresizing mask. Both views
        // are built at zero size, and a mask only passes on the *changes* a
        // superview makes after the fact — which is a roundabout way of getting
        // the right answer and an easy one to lose. Constraints say the thing
        // that is actually meant: the list is the whole backdrop.
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        let controller = NSViewController()
        controller.view = effect
        return controller
    }
}

extension MainWindowController: NSWindowDelegate {
    /// AppKit sends this for ordering paths outside `hide()`, including an
    /// external `orderOut`. A merely covered window stays active; becoming
    /// uncovered is not a new show and must not bypass the refresh schedule.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        if isVisible {
            if !reportedVisible { reportShown() }
        } else {
            reportHidden()
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        reportHidden()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        reportShown()
    }

    func windowWillClose(_ notification: Notification) {
        reportHidden()
    }
}
