import AppKit
import HerdviewCore

/// `mise run ui:shots`: the window drawn from fixtures, driven through its key
/// states, each state written to a PNG, and the clicks that matter checked.
///
/// It exists because the window's failures so far were ones no unit test could
/// see: a strip that drew correctly and could not be clicked, a focus ring the
/// design did not have. Both show up here as a failed check or a picture.
///
/// Everything it needs is inside the app, so it runs without Screen Recording or
/// Accessibility permission: the window renders itself with `cacheDisplay`, and
/// clicks are real `NSEvent`s sent to the window. The blur behind the window is
/// not in the pictures — it is the desktop, drawn by the window server — so the
/// shots are layout and colour, not glass.
///
/// Nothing touches the real app's state. The herd and Quota come from
/// `UIShotFixtures`, preferences from a throwaway defaults suite, and the window
/// never saves its frame. No monitor, notifier or menu bar item is started.
@MainActor
enum UIShots {
    static let environmentKey = "HERDVIEW_UI_SHOTS"

    /// Where to write the shots, when this launch is a shots run.
    static var outputDirectory: String? {
        ProcessInfo.processInfo.environment[environmentKey].flatMap { $0.isEmpty ? nil : $0 }
    }

    private static let wide = NSSize(width: 940, height: 700)
    private static let narrow = NSSize(width: 360, height: 700)
    /// Long enough for SwiftUI to lay out and for the expand animation to end.
    private static let settle: UInt64 = 700_000_000

    /// Builds the window, runs every step, and exits: 0 when every check
    /// passed, 1 otherwise. Kept alive by the returned task until then.
    static func run(into directory: String, menuItems: MainMenu.Items?) {
        let suite = "herdview.uishots.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            FileHandle.standardError.write(Data("ui-shots: no defaults suite\n".utf8))
            exit(2)
        }
        let preferences = WindowPreferences(defaults: defaults)
        let now = Date()

        let store = AgentStore()
        store.setHostOrder(UIShotFixtures.hosts)
        let bySession = Dictionary(grouping: UIShotFixtures.agents()) { "\($0.host)\t\($0.session)" }
        for (key, agents) in bySession {
            let parts = key.split(separator: "\t").map(String.init)
            store.apply(host: parts[0], session: parts[1], snapshot: agents.map(\.info), now: now)
        }
        let quotaStore = QuotaStore(providers: QuotaProvider.allCases, preferences: preferences)
        for (provider, entry) in UIShotFixtures.quota(now: now) {
            quotaStore.set(entry, for: provider)
        }

        let controller = MainWindowController(store: store, quotaStore: quotaStore, preferences: preferences,
                                               keepOnTopItem: menuItems?.keepOnTop,
                                               findItem: menuItems?.find, autosavesFrame: false)
        let runner = Runner(controller: controller, quotaStore: quotaStore,
                            directory: URL(fileURLWithPath: directory, isDirectory: true))
        Task { @MainActor in
            let failures = await runner.runAll()
            defaults.removePersistentDomain(forName: suite)
            exit(failures == 0 ? 0 : 1)
        }
    }

    @MainActor
    private final class Runner {
        let controller: MainWindowController
        let quotaStore: QuotaStore
        let directory: URL
        private var lines: [String] = []
        private var failures = 0

        init(controller: MainWindowController, quotaStore: QuotaStore, directory: URL) {
            self.controller = controller
            self.quotaStore = quotaStore
            self.directory = directory
        }

        var window: NSWindow { controller.window }

        func runAll() async -> Int {
            // Shown without activating the app, so a shots run does not pull
            // focus away from whatever the person is doing.
            window.orderFrontRegardless()
            window.makeKey()

            await state(size: UIShots.wide, dark: false, expanded: false)
            checkTitleBarHit(named: "strip", at: stripPoint)
            await shoot("01-collapsed")

            await click(stripPoint)
            check("click on the strip expands the Quota", quotaStore.isExpanded)
            await shoot("02-expanded-by-click")

            // Expanded outright, so the collapse check below cannot pass just
            // because the expand above failed.
            quotaStore.isExpanded = true
            await pause()
            checkTitleBarHit(named: "header chevron", at: chevronPoint)
            await click(chevronPoint)
            check("click on the header chevron collapses the Quota", !quotaStore.isExpanded)
            await shoot("03-collapsed-by-chevron")

            await state(size: UIShots.narrow, dark: false, expanded: false)
            checkTitleBarHit(named: "strip at 360 pt", at: stripPoint)
            await shoot("04-narrow-collapsed")

            await state(size: UIShots.wide, dark: true, expanded: true)
            await shoot("05-dark-expanded")

            await state(size: UIShots.wide, dark: false, expanded: false)
            controller.filterState.query = UIShotFixtures.filterWord
            await pause()
            await shoot("06-filter-hides-attention")
            controller.filterState.clear()

            let report = lines.joined(separator: "\n") + "\n"
            try? report.write(to: directory.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
            FileHandle.standardOutput.write(Data(report.utf8))
            return failures
        }

        // MARK: - Steps

        private func state(size: NSSize, dark: Bool, expanded: Bool) async {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.setContentSize(size)
            quotaStore.isExpanded = expanded
            await pause()
        }

        private func pause() async {
            try? await Task.sleep(nanoseconds: UIShots.settle)
        }

        /// The whole window, title bar included, as the window itself draws it.
        private func shoot(_ name: String) async {
            await pause()
            guard let frame = window.contentView?.superview,
                  let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else {
                fail("\(name): nothing to draw")
                return
            }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            let url = directory.appendingPathComponent("\(name).png")
            do {
                guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: url)
                lines.append("SHOT \(url.lastPathComponent)")
            } catch {
                fail("\(name): could not write \(url.path): \(error)")
            }
        }

        private func click(_ point: NSPoint) async {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window.windowNumber, context: nil,
                                                     eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
                window.sendEvent(event)
            }
            await pause()
        }

        // MARK: - Checks

        /// A point in the title bar row must reach the row's own hosting view.
        /// The failure this guards against is the list's scroll view, which
        /// covers the whole window, taking the click instead.
        private func checkTitleBarHit(named name: String, at point: NSPoint) {
            guard let frame = window.contentView?.superview, let titleBar = controller.titleBarView else {
                fail("\(name): no title bar view")
                return
            }
            let hit = frame.hitTest(frame.convert(point, from: nil))
            check("\(name) at \(NSStringFromPoint(point)) is hit-tested to the title bar (got \(hit.map { String(describing: type(of: $0)) } ?? "nothing"))",
                  hit?.isDescendant(of: titleBar) == true)
        }

        private func check(_ what: String, _ passed: Bool) {
            if passed { lines.append("PASS \(what)") } else { fail(what) }
        }

        private func fail(_ what: String) {
            failures += 1
            lines.append("FAIL \(what)")
        }

        // MARK: - Where to click

        /// Inside the collapsed strip: a Provider's gauges, clear of the chevron.
        private var stripPoint: NSPoint {
            let bar = titleBarFrame
            return NSPoint(x: bar.maxX - Metrics.gutter - 60, y: bar.midY)
        }

        /// The chevron at the row's trailing end, collapsed or expanded.
        private var chevronPoint: NSPoint {
            let bar = titleBarFrame
            return NSPoint(x: bar.maxX - Metrics.gutter - 6, y: bar.midY)
        }

        private var titleBarFrame: NSRect {
            guard let view = controller.titleBarView else { return .zero }
            return view.convert(view.bounds, to: nil)
        }
    }
}
