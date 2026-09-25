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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            // A segmented control does not shrink: given less room than its
            // labels need, it runs past the window's edge and the last segment
            // is cut off. So it steps down until it fits — full size, then
            // small, then small with the short labels — and the counts, which
            // are the point, survive every step.
            ViewThatFits(in: .horizontal) {
                scopePicker(short: false).controlSize(.regular)
                scopePicker(short: false).controlSize(.small)
                scopePicker(short: true).controlSize(.small)
            }
            // One height whichever size fits. A taller size could bring up the
            // list's scroller, whose width then picks a shorter size, which
            // sends the scroller away: AppKit crashed on that loop (2026-09-25).
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

    private func scopePicker(short: Bool) -> some View {
        Picker("", selection: $filter.scope) {
            ForEach(AgentScope.allCases, id: \.self) { scope in
                Text("\(short ? scope.shortTitle : scope.title) \(counts[scope, default: 0])").tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // Measured at its own width, so `ViewThatFits` sees what it needs
        // rather than whatever it was offered.
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
