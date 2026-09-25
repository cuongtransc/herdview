import Combine
import HerdviewCore
import SwiftUI

/// The search box and the status segments: the two halves of the filter, kept
/// together because they are one decision, and kept in this file because the
/// list below them is already the busiest thing in the window.
///
/// The counts on the segments come from the filter result rather than being
/// computed here. They are counted against the query alone, over every scope,
/// so each segment says what switching to it would give even while the current
/// scope is hiding that number's agents — a count a segment could not work out
/// for itself without running the whole filter again.
struct FilterBar: View {
    @ObservedObject var filter: FilterState
    let counts: [AgentScope: Int]

    /// Bound to the field rather than tracked by hand, so AppKit's own focus
    /// ring and the caret follow the same state this code sets.
    @FocusState private var isFocused: Bool
    /// The segments' size, as an index into `sizes`, and the width they have.
    @State private var size: Int?
    @State private var available: CGFloat = 0

    /// Widest first. A segmented control does not shrink: given less room
    /// than its labels need, it runs past the window's edge and the last
    /// segment is cut off. So it steps down until it fits — full size, then
    /// small, then small with the short labels — and the counts, which are the
    /// point, survive every step.
    private static let sizes: [(short: Bool, control: ControlSize)] = [
        (false, .regular), (false, .small), (true, .small),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            // One control, its size decided by `SegmentFit` from measured
            // widths. Not `ViewThatFits` over the three sizes: on a width at the
            // edge between two, AppKit's constraint passes traded them forever
            // and threw, which crashed the app.
            //
            // A GeometryReader around the control, not a preference from a
            // background one: inside the list's LazyVStack the preference never
            // arrived, and the segments stayed at their smallest in any width.
            let chosen = Self.sizes[min(size ?? 0, Self.sizes.count - 1)]
            GeometryReader { proxy in
                scopePicker(short: chosen.short)
                    .controlSize(chosen.control)
                    .onAppear { measure(proxy.size.width) }
                    .onChange(of: proxy.size.width) { measure($0) }
                    .onChange(of: counts) { _ in refit() }
            }
            // One height for every size. The size must not change the list's
            // height: a taller row can bring up the list's scroller, which takes
            // 15–17 pt of width, which picks a smaller size, which sends the
            // scroller away again — the loop that crashed the app at 467 pt.
            .frame(height: 24)
        }
        // ⌘F is the menu's, not this view's: the menu item is the only thing
        // that sees the shortcut and this field is the only thing that can act
        // on it, so they meet at the counter the state bumps.
        //
        // `dropFirst` is not decoration. A `@Published` publisher replays its
        // current value to every new subscriber, so without it the field would
        // seize focus the instant the window opens — before any ⌘F was pressed.
        .onReceive(filter.$focusRequest.dropFirst()) { _ in isFocused = true }
    }

    private func measure(_ width: CGFloat) {
        available = width
        refit()
    }

    private func refit() {
        let needs = Self.sizes.map { SegmentWidths.width(labels: labels(short: $0.short), controlSize: $0.control) }
        let next = SegmentFit.choose(available: Double(available), needs: needs.map(Double.init), current: size)
        if next != size { size = next }
    }

    private func labels(short: Bool) -> [String] {
        AgentScope.allCases.map { "\(short ? $0.shortTitle : $0.title) \(counts[$0, default: 0])" }
    }

    private func scopePicker(short: Bool) -> some View {
        Picker("", selection: $filter.scope) {
            ForEach(Array(zip(AgentScope.allCases, labels(short: short))), id: \.0) { scope, label in
                Text(label).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // At its own width: the room around it is the frame's, not the control's.
        .fixedSize()
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Filter", text: $filter.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                // Esc belongs to the field, and here it means the one thing a
                // person expects of it: empty the box and show the herd again.
                .onExitCommand { filter.query = "" }
            // Only offered when there is something to clear, so the trailing
            // edge stays quiet on an empty box.
            if !filter.query.isEmpty {
                Button {
                    filter.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .cardBackground()
    }
}

/// The one thing the filter must never be allowed to swallow: an agent that is
/// waiting on a person.
///
/// The window's whole job is answering "is anything waiting on me", and a
/// filter is a thing that hides rows by design. Put together, a search or a
/// scope could hide the only agent that needed you while the window still
/// looked calm — the exact failure this app exists to prevent. So whenever the
/// filter hides such an agent the banner says so and offers the way back.
///
/// It is deliberately not a notification and does not touch the menu bar item.
/// Those two answer the same question for someone who is not looking at the
/// window, and the filter is a property of the window — letting a search text
/// suppress an alert, or quiet a menu bar icon, would turn a convenience into a
/// way to miss work.
struct HiddenAttentionBanner: View {
    let count: Int
    let show: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .systemOrange))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Show", action: show)
                .buttonStyle(.link)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Metrics.textInset)
        .cardSurface()
    }

    private var text: String {
        count == 1
            ? "1 agent waiting on you is hidden by the filter"
            : "\(count) agents waiting on you are hidden by the filter"
    }
}

/// What the filter is holding back, and the way out of it. Shown only when
/// something is actually hidden, so the list is not permanently captioned with
/// a number that is always zero.
struct FilterFooter: View {
    let hiddenCount: Int
    let hiddenHosts: Int
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Clear", action: clear)
                .buttonStyle(.link)
        }
        .padding(.horizontal, Metrics.textInset)
    }

    private var text: String {
        var line = "Filter hides \(hiddenCount) agents"
        // Hosts are only worth naming when one is gone entirely; otherwise the
        // count would restate the rows still on screen.
        if hiddenHosts > 0 { line += " · \(hiddenHosts) hosts" }
        return line
    }
}

/// What a segmented control with these labels needs, measured on one AppKit
/// never puts in a window, so measuring cannot disturb the window's layout.
/// Cached by labels: they change only when a count does.
@MainActor
enum SegmentWidths {
    private static var cache: [String: CGFloat] = [:]
    /// SwiftUI's segmented picker draws a little wider than a bare
    /// NSSegmentedControl; a few points spare keep "fits" honest.
    private static let margin: CGFloat = 8

    static func width(labels: [String], controlSize: ControlSize) -> CGFloat {
        let size: NSControl.ControlSize = controlSize == .small ? .small : .regular
        let key = "\(size.rawValue)|" + labels.joined(separator: "|")
        if let width = cache[key] { return width }
        // As SwiftUI draws a segmented Picker: every segment as wide as the
        // widest. Each label is measured in a one-segment control of its own —
        // `fittingSize` of a whole `.fillEqually` control came back sometimes
        // equal and sometimes natural.
        let widest = labels.map { label -> CGFloat in
            let control = NSSegmentedControl(labels: [label], trackingMode: .selectOne, target: nil, action: nil)
            control.controlSize = size
            control.font = .systemFont(ofSize: NSFont.systemFontSize(for: size))
            return control.fittingSize.width
        }.max() ?? 0
        let width = widest * CGFloat(labels.count) + margin
        cache[key] = width
        return width
    }
}
