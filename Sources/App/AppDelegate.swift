import AppKit
import HerdviewCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AgentStore()
    private let quotaStore = QuotaStore()
    private var monitor: Monitor?
    private var quotaMonitor: QuotaMonitor?
    private var statusBar: StatusBarController?
    private var notifier: TransitionNotifier?
    private var mainWindow: MainWindowController?
    private var menuItems: MainMenu.Items?

    func applicationWillFinishLaunching(_ notification: Notification) {
        menuItems = MainMenu.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var config = HerdviewConfig(hosts: [])
        do {
            let load = try ConfigLoader.loadOrCreate()
            config = load.config
            // A first run is not news to put in the window; it is news for the
            // log, where it explains where this Mac came from.
            switch load.origin {
            case .existing:
                break
            case .created:
                NSLog("herdview: wrote a first-run config at %@", ConfigLoader.defaultPath)
            case .inMemory:
                NSLog("herdview: could not write %@; watching this Mac for this launch only",
                      ConfigLoader.defaultPath)
            }
        } catch {
            store.configError = "\(ConfigLoader.defaultPath): \(error)"
        }

        let window = MainWindowController(store: store, quotaStore: quotaStore, keepOnTopItem: menuItems?.keepOnTop)
        mainWindow = window
        window.show()

        let bar = StatusBarController { [weak self] in
            self?.mainWindow?.toggle()
        }
        statusBar = bar
        bar.start()

        // Before the monitor starts, so the first poll's transitions have
        // somewhere to go. The first poll of a session has no previous
        // snapshot to compare against, so it produces no transitions and no
        // burst of banners at launch.
        let notifier = TransitionNotifier(store: store) { [weak self] in
            self?.mainWindow?.show()
        }
        self.notifier = notifier
        notifier.start()

        let monitor = Monitor(config: config, store: store)
        self.monitor = monitor
        monitor.start()

        // Its first tick fetches at once, since the window was shown above.
        let quotaMonitor = QuotaMonitor(store: quotaStore) { [weak self] in
            self?.mainWindow?.isVisible ?? false
        }
        self.quotaMonitor = quotaMonitor
        window.onShow = { [weak quotaMonitor] in quotaMonitor?.windowShown() }
        window.onHide = { [weak quotaMonitor] in quotaMonitor?.windowHidden() }
        quotaStore.refreshAction = { [weak quotaMonitor] in quotaMonitor?.refreshNow() }
        quotaMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        quotaMonitor?.stop()
    }

    /// Command-H hides the application rather than calling the window
    /// controller's `hide()`, so mirror that AppKit lifecycle explicitly.
    func applicationWillHide(_ notification: Notification) {
        quotaMonitor?.windowHidden()
    }

    func applicationDidUnhide(_ notification: Notification) {
        if mainWindow?.isVisible == true { quotaMonitor?.windowShown() }
    }

    /// Closing the window hides it. The herd keeps being polled and the menu bar
    /// item keeps working, so the last window closing must not end the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon of an app with no visible windows asks for one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow?.show()
        return true
    }
}
