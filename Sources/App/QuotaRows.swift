import SwiftUI
import HerdviewCore

/// Every Window of every Provider: the panel the title bar's strip expands
/// into. One block per row the store lists — a Provider, or each of its
/// Accounts — separated by a hairline that starts where the text does.
struct QuotaRows: View {
    @ObservedObject var store: QuotaStore
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(store.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)
                        .padding(.leading, Metrics.cardInset + QuotaRow.textLeading)
                }
                QuotaRow(provider: row.provider, title: row.title, entry: row.entry, now: now)
                    .padding(.horizontal, Metrics.cardInset)
            }
        }
        .padding(.vertical, Metrics.cardInset)
    }
}

/// One Provider: its icon, its name on a line of its own, then one line per
/// Window.
///
/// Every Window line has the same columns (label, bar, percent, time to Reset)
/// at fixed widths, so the bars of every Provider start and end on the same
/// verticals and two Windows can be compared at a glance, down the panel.
struct QuotaRow: View {
    static let textLeading: CGFloat = rowInset + iconSide + iconGap
    private static let iconSide: CGFloat = 22
    private static let iconGap: CGFloat = 10
    private static let rowInset: CGFloat = 8

    let provider: QuotaProvider
    let title: String
    let entry: QuotaEntry
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: Self.iconGap) {
            ProviderIcon(provider: provider, side: Self.iconSide)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Self.rowInset)
        .padding(.vertical, 7)
    }

    @ViewBuilder private var content: some View {
        switch entry {
        case .loading:
            EmptyView()
        case .notSignedIn:
            note("not signed in")
        case .ok(let report):
            lines(report.windows, dimmed: false)
        case .problem(let problem, let last):
            if let last {
                lines(last.windows, dimmed: true)
                note("\(problem.message) · \(QuotaFormat.updatedAgo(last.fetchedAt, now: now))")
            } else {
                note(problem.message)
            }
        }
    }

    @ViewBuilder private func lines(_ windows: [QuotaWindow], dimmed: Bool) -> some View {
        ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
            WindowLine(window: window, now: now)
                .opacity(dimmed ? 0.45 : 1)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A Provider's agent icon on its rounded tile, at whatever size the place
/// using it needs.
struct ProviderIcon: View {
    let provider: QuotaProvider
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 7 / 26, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let image = AgentIcons.image(for: provider.agentKind) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 16 / 26, height: side * 16 / 26)
            }
        }
        .frame(width: side, height: side)
    }
}

/// One Window as a row of fixed columns: its label, a bar that takes the rest
/// of the width, the percent used and the time to Reset.
///
/// A short tick across the bar marks how much of the Window's time has
/// passed, so a bar that has run past its tick is Quota spent faster than the
/// clock. Only drawn when the Window's length is known.
///
/// Colour goes on the bar only (`QuotaBar`). Text stays on the label colours,
/// as it does everywhere in this app, because orange text does not reach a
/// readable contrast against a light window at this size; a Window near its
/// limit says so with a heavier weight instead.
struct WindowLine: View {
    /// Wide enough for `week · Fable`, the longest label a Provider sends.
    private static let labelWidth: CGFloat = 74
    private static let percentWidth: CGFloat = 30
    private static let resetWidth: CGFloat = 44

    let window: QuotaWindow
    let now: Date

    var body: some View {
        let warning = window.usedPercent >= QuotaFormat.warningPercent
        HStack(spacing: 8) {
            Text(window.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.labelWidth, alignment: .leading)
            QuotaBar(window: window, now: now, height: 5, showsPace: true)
            Text(QuotaFormat.percent(window.usedPercent))
                .fontWeight(warning ? .semibold : .regular)
                .foregroundStyle(.primary)
                .frame(width: Self.percentWidth, alignment: .trailing)
            Text(QuotaFormat.untilReset(window.resetsAt, now: now) ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.resetWidth, alignment: .trailing)
        }
        .font(.system(size: 11).monospacedDigit())
    }
}

/// A Window's bar: the used share filled in its tone, and, when asked for and
/// the Window's length is known, the yellow tick where the clock is.
///
/// It takes whatever width it is given, so the same bar serves the title bar's
/// fixed mini gauges and the panel's full-width lines.
struct QuotaBar: View {
    private static let tickWidth: CGFloat = 2

    let window: QuotaWindow
    let now: Date
    let height: CGFloat
    let showsPace: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(color)
                    .frame(width: width * window.usedPercent / 100)
                if showsPace,
                   let elapsed = QuotaFormat.elapsedFraction(resetsAt: window.resetsAt,
                                                             duration: window.duration, now: now) {
                    Capsule()
                        .fill(Color(nsColor: .systemYellow))
                        .frame(width: Self.tickWidth, height: height + 4)
                        .offset(x: min(width - Self.tickWidth, max(0, width * elapsed - Self.tickWidth / 2)))
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: height)
    }

    private var color: Color {
        switch QuotaFormat.tone(of: window, now: now) {
        case .neutral: return .secondary
        case .onPace: return Color(nsColor: .systemGreen)
        case .warning: return Color(nsColor: .systemOrange)
        }
    }
}
