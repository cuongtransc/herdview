import AppKit
import SwiftUI
import HerdviewCore

/// What every host is running: one card per host, most attention-worthy agent
/// first. This is everything below the Quota's row, and it is drawn on the
/// window's own glass — nothing here paints a background of its own.
///
/// There is no summary of the herd. Every card carries its host's count, what
/// an agent is doing is on its own row, and a notification reaches whoever is
/// not looking at either; a bar restating all of it only cost the window its
/// top inch.
///
/// The window's top row is the Quota's, not this list's: `QuotaTitleBar` draws
/// the title-bar strip there and, when expanded, the panel below it. The strip
/// has to sit in the title bar's own row beside the window buttons, so this view
/// reads the title bar's height from the top safe-area inset and then ignores
/// that inset — the row it draws is exactly the height of the area it gave up,
/// so the first host still starts where it always did.
///
/// The tick lives here, and moves the elapsed times only: it runs at half a
/// second so a row never shows a stale second. The blink is not on this clock
/// at all — it is handed to Core Animation once and runs on its own.
struct AgentListView: View {
    /// Half a second, so the displayed second is never more than half a second
    /// behind the real one.
    private static let tick: TimeInterval = 0.5

    /// A window in full screen reports no top inset, and the strip still needs a
    /// row to sit in: a title bar's height is a better guess than nothing.
    private static let titleBarFallback: CGFloat = 28

    @ObservedObject var store: AgentStore
    @ObservedObject var quotaStore: QuotaStore
    @ObservedObject var filter: FilterState

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.tick)) { context in
            // The title bar's height is the top safe-area inset, read here before
            // the inset is ignored below: the row of exactly that height is what
            // the strip sits in. Taking it from the window's metrics once at
            // construction would freeze a number that changes with the window's
            // shape; measuring it here keeps the row and the strip in step.
            GeometryReader { proxy in
                let titleBarHeight = max(proxy.safeAreaInsets.top, Self.titleBarFallback)
                // Run the filter once for the whole body and read every answer off
                // the one result — the segments, the banner, the hosts, the empty
                // state and the footer all have to agree, and a second pass could
                // only ever disagree with the first.
                let result = filter.filter.apply(to: store.agents)
                let isFiltering = filter.filter.isActive
                // Grouping once here rather than filtering per host keeps the work
                // proportional to the herd, not to the herd times the hosts.
                let visibleByHost = isFiltering
                    ? Dictionary(grouping: result.visible, by: \.host)
                    : [:]
                // A host with nothing left to show is not shown at all — a card
                // that says "No agents here" while a filter is on would read as a
                // fact about the host rather than about the filter. Hosts keep the
                // store's order, and the agents within them keep theirs.
                let hosts = isFiltering
                    ? store.hostOrder.filter { !(visibleByHost[$0] ?? []).isEmpty }
                    : store.hostOrder
                // The Quota's row and the list are one column. The panel the
                // Quota expands into sits between them, outside the `ScrollView`,
                // so expanding pushes the filter and the herd down rather than
                // covering them.
                VStack(spacing: 0) {
                    // The row itself is left empty here: `QuotaTitleBar` is laid
                    // over it in a hosting view of its own, which is the only way
                    // its clicks get past this list's scroll view (see there).
                    Color.clear.frame(height: titleBarHeight)
                    if quotaStore.isExpanded {
                        QuotaPanel(store: quotaStore, now: context.date)
                    }
                    ScrollView {
                        // Host groups are separated by air rather than by a rule:
                        // the card edge already says where one host ends.
                        LazyVStack(alignment: .leading, spacing: Metrics.groupGap) {
                            FilterBar(filter: filter, counts: result.scopeCounts)
                            if result.hiddenAskingForAPerson > 0 {
                                HiddenAttentionBanner(count: result.hiddenAskingForAPerson) {
                                    filter.clear()
                                }
                            }
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
                            // Only when there were hosts to filter: with none, the
                            // notice above already says why the list is empty, and
                            // "No agents match" would blame the filter for it.
                            if isFiltering && result.visible.isEmpty && !store.hostOrder.isEmpty {
                                Notice(symbol: "line.3.horizontal.decrease.circle",
                                       text: "No agents match")
                                    .padding(.horizontal, Metrics.textInset)
                                    .cardSurface()
                            } else {
                                ForEach(hosts, id: \.self) { host in
                                    HostGroup(host: host,
                                              agents: isFiltering ? (visibleByHost[host] ?? [])
                                                                  : store.agents(forHost: host),
                                              unreachable: store.unreachableHosts.contains(host),
                                              now: context.date)
                                }
                            }
                            if isFiltering && result.hiddenCount > 0 {
                                FilterFooter(hiddenCount: result.hiddenCount,
                                             hiddenHosts: result.hiddenHosts) {
                                    filter.clear()
                                }
                            }
                        }
                        .padding(.horizontal, Metrics.gutter)
                        // Asymmetric on purpose. The title bar row above already
                        // holds the list clear of the window buttons, so anything
                        // more on top is a gap this window cannot afford. The
                        // bottom has nothing above it and keeps the whole margin.
                        .padding(.top, 2)
                        .padding(.bottom, Metrics.gutter)
                    }
                    // No background here on purpose. The window's own backdrop is
                    // an `NSVisualEffectView` blurring whatever is behind the
                    // window, and painting a colour over it would be painting the
                    // blur out again. That view, not this one, is what keeps light
                    // text off a light sheet in dark mode.
                    //
                    // The popover was a fixed 360 wide; a window is whatever the
                    // user drags it to, so the list fills the width and the rows
                    // spread.
                }
                .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
                // The strip has to sit in the title bar's own row, so the column
                // is drawn into the safe area rather than below it. The list keeps
                // the space it always had, because the row it gained is exactly
                // the height of the inset that was given up.
                .ignoresSafeArea(.container, edges: .top)
            }
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
    /// The agents this host is actually showing. Handed in rather than read
    /// from the store, because with a filter on it is the visible subset and
    /// not everything the host is running; the count beside the name has to be
    /// the count on screen.
    let agents: [TrackedAgent]
    let unreachable: Bool
    let now: Date

    var body: some View {
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
/// Internal rather than private so the filter bar's banner can say the same
/// kind of thing in the same shape, instead of growing a second notice style.
struct Notice: View {
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
