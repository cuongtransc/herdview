import SwiftUI
import HerdviewCore

/// The Quota, in the window's title bar.
///
/// Collapsed — the default — it is a compact strip beside the window buttons:
/// one item per Provider, its icon and a mini bar per Window the strip shows
/// (`QuotaFormat.titleBarWindows`), and a chevron that says there is more. It
/// answers "can I keep going" in the one row of the window that was empty.
///
/// Clicking the strip swaps it for a header in the same row and puts the full
/// per-Window list in a panel below it. The panel is a sibling of the list's
/// `ScrollView`, not part of it, so expanding pushes the filter and the herd
/// down instead of covering them.
struct QuotaTitleBar: View {
    /// Where the strip's content starts so that it clears the window buttons.
    /// AppKit lays those out in the title bar's leading corner and SwiftUI
    /// cannot see them, so this is a measured constant: on a standard window the
    /// zoom button's trailing edge is at 69 pt, and 78 leaves it a gap.
    private static let trafficLightInset: CGFloat = 78

    @ObservedObject var store: QuotaStore
    let now: Date
    /// The title bar's own height, measured by the list from the window's top
    /// safe-area inset before it ignores that inset.
    let titleBarHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            titleBarRow
            if store.isExpanded {
                panel
            }
        }
    }

    /// The title bar's row: the collapsed strip or the expanded header, never
    /// both. Either is trailing-aligned, so the control stays where the eye left
    /// it when it swaps, and the empty part of the row is still the window's to
    /// drag.
    private var titleBarRow: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            if store.isExpanded {
                expandedHeader
            } else {
                collapsedStrip
            }
        }
        .frame(height: titleBarHeight)
        .padding(.leading, Self.trafficLightInset)
        .padding(.trailing, Metrics.gutter)
    }

    // MARK: - Collapsed

    /// The whole strip is one button: the gauges are a summary, not controls, so
    /// a click anywhere on them means the same thing.
    private var collapsedStrip: some View {
        Button {
            setExpanded(true)
        } label: {
            // Two strips rather than one that shrinks: at 360 pt the percents no
            // longer fit beside the traffic lights, and dropping them whole keeps
            // every bar's length readable where truncating the text would not.
            ViewThatFits(in: .horizontal) {
                strip(showPercent: true)
                strip(showPercent: false)
            }
        }
        .buttonStyle(.plain)
        .help("Show every Window")
    }

    private func strip(showPercent: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(store.providers, id: \.self) { provider in
                QuotaMiniGauge(provider: provider,
                               entry: store.entry(for: provider),
                               now: now,
                               showPercent: showPercent)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        // The gauges do not fill every pixel between them, and a click in one of
        // those gaps is still a click on the strip.
        .contentShape(Rectangle())
    }

    // MARK: - Expanded

    /// The header in the title bar's row: `Quota · updated 2m ago`, the refresh
    /// button, the chevron. Everything in it collapses except the refresh
    /// button, which sits between two collapse buttons rather than inside one: a
    /// button inside a button would leave the refresh's own clicks to whichever
    /// one SwiftUI happened to hit first.
    private var expandedHeader: some View {
        HStack(spacing: 8) {
            Button {
                setExpanded(false)
            } label: {
                HStack(spacing: 4) {
                    Text("Quota")
                    if let updated = QuotaFormat.lastUpdated(store.providers.map(store.entry(for:))) {
                        Text("· \(QuotaFormat.updatedAgo(updated, now: now))")
                            .fontWeight(.regular)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show only the short and weekly Windows")

            refreshButton

            Button {
                setExpanded(false)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show only the short and weekly Windows")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    /// A spinner stands in for the button while any Provider is being fetched:
    /// pressing again then would do nothing, and the spinner says so.
    @ViewBuilder private var refreshButton: some View {
        if store.fetching.isEmpty {
            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh Quota now")
        } else {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
                // The spinner is not a control: a click in this slot belongs
                // to neither refresh nor collapse.
                .allowsHitTesting(false)
        }
    }

    /// The full list, pinned below the title bar row and above the filter: it is
    /// a sibling of the list's `ScrollView`, so it never scrolls away and never
    /// covers what is under it.
    private var panel: some View {
        QuotaRows(store: store, now: now)
            .cardSurface()
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, Metrics.groupGap / 2)
    }

    /// One animation for the swap, so the panel and the header it came with move
    /// together rather than snapping in two steps.
    private func setExpanded(_ expanded: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) { store.isExpanded = expanded }
    }
}

/// One Provider in the collapsed strip: its icon and one mini bar per Window the
/// strip shows, each with its percent when there is room.
///
/// A Provider with nothing to show keeps a faded icon, so it is still there to
/// be missed rather than silently gone; a Provider whose last numbers are stale
/// keeps its bars, faded, the same way the expanded row does.
private struct QuotaMiniGauge: View {
    private static let barWidth: CGFloat = 30
    private static let barHeight: CGFloat = 4
    private static let iconSide: CGFloat = 18
    private static let percentWidth: CGFloat = 24

    let provider: QuotaProvider
    let entry: QuotaEntry
    let now: Date
    let showPercent: Bool

    var body: some View {
        let windows: [QuotaWindow]
        let fresh: Bool
        switch entry {
        case .ok(let report):
            windows = QuotaFormat.titleBarWindows(of: report.windows)
            fresh = true
        case .problem(_, let last?):
            windows = QuotaFormat.titleBarWindows(of: last.windows)
            fresh = false
        default:
            windows = []
            fresh = false
        }
        return HStack(spacing: 5) {
            ProviderIcon(provider: provider, side: Self.iconSide)
                .opacity(windows.isEmpty ? 0.45 : 1)
            VStack(spacing: 2) {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    line(window)
                        .opacity(fresh ? 1 : 0.45)
                }
            }
        }
        .help(help)
        // The strip has to be measured at its true width for `ViewThatFits` to
        // know when the percents no longer fit, so nothing here may compress.
        .fixedSize()
    }

    private func line(_ window: QuotaWindow) -> some View {
        let warning = window.usedPercent >= QuotaFormat.warningPercent
        return HStack(spacing: 4) {
            QuotaBar(window: window, now: now, height: Self.barHeight, showsPace: false)
                .frame(width: Self.barWidth)
            if showPercent {
                // A fixed column, so a Provider's two bars line up and the
                // strip does not shift as a percent gains a digit.
                Text(QuotaFormat.percent(window.usedPercent))
                    .font(.system(size: 9.5).monospacedDigit())
                    .fontWeight(warning ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .frame(width: Self.percentWidth, alignment: .leading)
            }
        }
    }

    /// The same words the expanded row would say, in one line: the Windows the
    /// strip shows with their percents and times to Reset, or why it has none.
    private var help: String {
        switch entry {
        case .loading:
            return provider.displayName
        case .notSignedIn:
            return "\(provider.displayName): not signed in"
        case .problem(let problem, _):
            return "\(provider.displayName): \(problem.message(for: provider))"
        case .ok(let report):
            let parts = QuotaFormat.titleBarWindows(of: report.windows).map { window -> String in
                var text = "\(window.label) \(QuotaFormat.percent(window.usedPercent))"
                if let until = QuotaFormat.untilReset(window.resetsAt, now: now) {
                    text += " · \(until)"
                }
                return text
            }
            return "\(provider.displayName): \(parts.joined(separator: ", "))"
        }
    }
}
