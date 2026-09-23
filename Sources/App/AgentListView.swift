import AppKit
import SwiftUI
import HerdviewCore

/// What every host is running: one card per host, most attention-worthy agent
/// first. This is the window's whole content, and it is drawn on the window's
/// own glass — nothing here paints a background of its own.
///
/// There is no summary of the herd. Every card carries its host's count, what
/// an agent is doing is on its own row, and a notification reaches whoever is
/// not looking at either; a bar restating all of it only cost the window its
/// top inch.
///
/// Nothing here reserves room for the title bar either. The window hands the
/// list a safe area that already excludes it, and the window buttons sit inside
/// that area — so a spacer of the title bar's height on top of it counts the
/// same strip twice and pushes the first host most of an inch down the window.
///
/// The tick lives here, and moves the elapsed times only: it runs at half a
/// second so a row never shows a stale second. The blink is not on this clock
/// at all — it is handed to Core Animation once and runs on its own.
struct AgentListView: View {
    /// Half a second, so the displayed second is never more than half a second
    /// behind the real one.
    private static let tick: TimeInterval = 0.5

    @ObservedObject var store: AgentStore
    @ObservedObject var quotaStore: QuotaStore
    @ObservedObject var filter: FilterState

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.tick)) { context in
            ScrollView {
                // Host groups are separated by air rather than by a rule:
                // the card edge already says where one host ends.
                LazyVStack(alignment: .leading, spacing: Metrics.groupGap) {
                    QuotaCard(store: quotaStore, now: context.date)
                    if let error = store.configError {
                        Notice(symbol: "exclamationmark.triangle.fill", text: error, tint: .red)
                            .padding(.horizontal, Metrics.textInset)
                            .cardSurface()
                    }
                    if store.hostOrder.isEmpty {
                        Notice(symbol: "server.rack",
                               text: "No hosts yet. Add one in \(ConfigLoader.defaultPath)")
                            .padding(.horizontal, Metrics.textInset)
                            .cardSurface()
                    }
                    ForEach(store.hostOrder, id: \.self) { host in
                        HostGroup(host: host, store: store, now: context.date)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                // Asymmetric on purpose. The window already holds the list clear
                // of the title bar through the safe area, and the window buttons
                // live inside that; anything more on top is a gap this window
                // cannot afford. The bottom has nothing above it and keeps the
                // whole margin.
                .padding(.top, 2)
                .padding(.bottom, Metrics.gutter)
            }
            // No background here on purpose. The window's own backdrop is an
            // `NSVisualEffectView` blurring whatever is behind the window, and
            // painting a colour over it would be painting the blur out again.
            // That view, not this one, is what keeps light text off a light
            // sheet in dark mode.
            //
            // The popover was a fixed 360 wide; a window is whatever the user
            // drags it to, so the list fills the width and the rows spread.
            .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

enum Metrics {
    /// Page margin, outside the cards.
    static let gutter: CGFloat = 14
    /// Air between one host's card and the next host's label.
    static let groupGap: CGFloat = 18
    /// A card's own corner, and the padding that keeps its content off its
    /// edge. `cardRadius - cardInset` is the row wash's radius, so the wash
    /// sits concentric inside the card instead of fighting its corner.
    static let cardRadius: CGFloat = 12
    static let cardInset: CGFloat = 4
    static let washRadius: CGFloat = cardRadius - cardInset
    /// A row's own padding, inside the card's.
    static let rowInset: CGFloat = 8
    /// Where text sits in from a card's outer edge. Everything that has to
    /// line up with the column of agent names uses it — the host's label above
    /// the card, and the notice that stands in for the rows when a host has
    /// none — so the window has one text margin rather than three.
    static let textInset: CGFloat = cardInset + rowInset
    /// How far the blinking wash is held off the top and bottom of its row, so
    /// that two blinking neighbours stay two rows instead of merging into one
    /// block. Half the gap each, so the gap between them is twice this.
    static let washInset: CGFloat = 1.5
}

// MARK: - Card surface

/// The one elevated surface in the window. Everything the list has to say —
/// a host's agents, an empty host, a broken config — is said on one of these,
/// so there is a single shape to recognise rather than a rule here and a box
/// there.
private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, Metrics.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
    }
}

/// The card's own surface, and the one place in the app that asks the system
/// for glass.
///
/// From macOS 26 it is real Liquid Glass, which is what makes a card read as a
/// pane held above the blurred desktop rather than as a grey box drawn on it.
/// Below 26 there is no such thing, so the card stays exactly the flat filled
/// rectangle it has always been — a known surface, not a second design
/// imitating the first.
private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
        } else {
            let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            content
                .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
    func cardBackground() -> some View { modifier(CardBackground()) }
}

// MARK: - Host

private struct HostGroup: View {
    let host: String
    @ObservedObject var store: AgentStore
    let now: Date

    var body: some View {
        let agents = store.agents(forHost: host)
        let unreachable = store.unreachableHosts.contains(host)
        VStack(alignment: .leading, spacing: 6) {
            HostLabel(host: host, count: agents.count, unreachable: unreachable)
            VStack(alignment: .leading, spacing: 0) {
                if agents.isEmpty {
                    Notice(symbol: unreachable ? "antenna.radiowaves.left.and.right.slash" : "moon.zzz",
                           text: unreachable ? "Can't reach this host" : "No agents here",
                           tint: unreachable ? Color(nsColor: .systemOrange) : nil)
                        .padding(.horizontal, Metrics.textInset)
                }
                ForEach(Array(agents.enumerated()), id: \.element.key) { index, agent in
                    if index > 0 {
                        RowSeparator()
                    }
                    AgentRow(agent: agent, now: now)
                        .padding(.horizontal, Metrics.cardInset)
                }
            }
            .cardSurface()
        }
    }
}

/// The hairline between two agents in the same card, indented to start where
/// their names do, so the column of names is what the eye follows down the
/// card rather than a rule crossing it.
///
/// Drawn as a rectangle rather than with `Divider`. A `Divider` inside a
/// leading-aligned stack takes its intrinsic width, which is nothing, and
/// disappears; asking for the width outright is the only way it is reliably
/// there.
private struct RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .padding(.leading, Metrics.textInset + AgentRow.textLeading)
    }
}

/// The host's name sits above its card in the quiet type, with the agent count
/// at the far end. The card edge does the separating that a rule used to do,
/// so the label is left to be nothing but a label.
private struct HostLabel: View {
    let host: String
    let count: Int
    let unreachable: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(host)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if unreachable {
                Circle()
                    .fill(Color(nsColor: .systemOrange))
                    .frame(width: 6, height: 6)
                Text("unreachable")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Metrics.textInset)
    }
}

// MARK: - Agent

private struct AgentRow: View {
    /// Where a row's text starts, measured from the row's own leading edge.
    /// The divider between two rows is indented to meet it, so the column of
    /// names reads as one column.
    static let textLeading: CGFloat = iconSide + iconGap

    private static let iconSide: CGFloat = 26
    private static let iconGap: CGFloat = 10

    let agent: TrackedAgent
    let now: Date

    var body: some View {
        let text = AgentTitles.rowText(for: agent)
        HStack(spacing: Self.iconGap) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                // The session keeps the quiet type it had when it sat on the
                // second line: it says which herd the agent belongs to, not
                // what the agent is, so it rides beside the name rather than
                // competing with it.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(text.primary)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let session = text.session {
                        Text(session)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(-1)
                    }
                }
                Text(text.secondary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            StatusPill(status: agent.status)
            Text(TimerFormatter.string(from: agent.since, to: now))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(agent.status == .blocked ? .primary : .secondary)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.horizontal, Metrics.rowInset)
        .padding(.vertical, 8)
        .background(wash)
        .help(tooltip(for: text))
    }

    /// A blocked or done row blinks for as long as it stays that way — it is
    /// asking for a person, and it keeps asking until someone comes. Every
    /// other row is plain. Rows do not light up under the pointer, because
    /// clicking one does nothing and a hover highlight would promise that it
    /// did.
    ///
    /// The inset is applied out here rather than inside the wash so that the
    /// layer being animated fills its own view exactly, with nothing between
    /// the two to lay out. Horizontally it is the card's own inset, which puts
    /// the wash's corner concentric with the card's; vertically it is only
    /// enough to keep two blinking neighbours apart.
    private var wash: some View {
        BlinkWash(status: agent.status)
            .padding(.vertical, Metrics.washInset)
    }

    @ViewBuilder private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let image = AgentIcons.image(for: AgentKind.from(label: agent.info.agent)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.iconSide, height: Self.iconSide)
    }

    /// Every line is truncated in the row, so the pointer can ask for the
    /// parts that did not fit — the directory spelled out in full, since that
    /// is the one the row shortens to its last component.
    private func tooltip(for text: AgentRowText) -> String {
        let lead = agent.info.cwd.flatMap { $0.isEmpty ? nil : $0 } ?? text.primary
        guard let session = text.session else { return "\(lead)\n\(text.secondary)" }
        return "\(lead) · \(session)\n\(text.secondary)"
    }
}

/// The breathing wash behind a blocked or done row.
///
/// Drawn by Core Animation rather than by SwiftUI. A wash redrawn through the
/// view graph costs a whole `NSHostingView` layout pass per frame — measured
/// at around fourteen points of CPU for two blinking rows, against a floor of
/// four for the rest of the app put together. Handed to Core Animation, the
/// interpolation happens on the render server: the app does nothing at all
/// between the moment the animation is added and the moment the status
/// changes, and the breath runs at the screen's own refresh rate instead of a
/// rate this code had to pick.
private struct BlinkWash: NSViewRepresentable {
    let status: AgentStatus

    func makeNSView(context: Context) -> WashView { WashView() }

    func updateNSView(_ view: WashView, context: Context) {
        view.show(status)
    }
}

/// A single layer that holds the row's colour and breathes.
private final class WashView: NSView {
    private static let breathKey = "breath"
    private var shown: AgentStatus?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Metrics.washRadius
        layer?.cornerCurve = .continuous
        layer?.opacity = 0
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not loaded from a nib") }

    /// Nothing here reacts to the pointer: this is the row's background, and
    /// letting it take part in hit testing would take the row's own tooltip
    /// away from it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The row above is rebuilt about twice a second, for the elapsed time and
    /// for every snapshot the herd pushes, so this is called that often with
    /// the status unchanged. Restarting the animation each time would jerk the
    /// breath back to its beginning twice a second and put the cost straight
    /// back; it must only act when something actually changed.
    func show(_ status: AgentStatus) {
        guard shown != status else { return }
        shown = status
        redraw()
    }

    /// A `CGColor` is resolved against whichever appearance was current when
    /// it was made, and unlike a SwiftUI `Color` it does not follow the system
    /// afterwards. Switching between light and dark has to resolve it again.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redraw()
    }

    /// A layer loses its animations when its view leaves the window, which
    /// this one does every time the window is closed to the menu bar.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { redraw() }
    }

    private func redraw() {
        guard let layer, let status = shown else { return }
        layer.removeAnimation(forKey: WashView.breathKey)

        guard let ends = status.washOpacity else {
            layer.opacity = 0
            layer.backgroundColor = nil
            return
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = status.nsTint.cgColor
        }

        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = ends.dim
        breath.toValue = ends.bright
        breath.duration = BlinkPhase.period / 2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // Wound forward to wherever the clock already is, so a row that
        // appears now falls in step with the rows already breathing instead of
        // starting a beat of its own.
        let clock = CACurrentMediaTime()
        breath.beginTime = layer.convertTime(clock, from: nil)
            - BlinkPhase.secondsSinceDimmest(clock: clock)

        layer.opacity = Float(ends.dim)
        layer.add(breath, forKey: WashView.breathKey)
    }
}

private struct StatusPill: View {
    let status: AgentStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 11, weight: status == .blocked ? .semibold : .regular))
            .foregroundStyle(status == .blocked ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(status.tint.opacity(status == .blocked ? 0.24 : 0.14))
            )
    }
}

// MARK: - Empty and error states

/// Every state where there is nothing to list says what is true and, where
/// there is one, what to do about it.
private struct Notice: View {
    let symbol: String
    let text: String
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint ?? Color.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(tint == nil ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
