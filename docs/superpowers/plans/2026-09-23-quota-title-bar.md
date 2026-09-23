# Quota in the Title Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Quota card out of the agent list and into the window's title bar row as a compact strip (short Window + `week` per Provider), which expands in place, pushing the list down, to show every Window.

**Architecture:** One pure selector in `HerdviewCore` (`QuotaFormat.titleBarWindows(of:)`) and a renamed preference (`isQuotaExpanded`), both unit tested. The App target gets a `QuotaTitleBar` view (collapsed strip + expanded panel) pinned above the list's `ScrollView`, sitting in the transparent title bar beside the traffic lights. `QuotaCard`'s rows (`QuotaRow`, `WindowGauge`, `ProviderIcon`, `FlowLayout`) are reused for the expanded panel. `QuotaSummary` and the in-list card go away.

**Tech Stack:** Swift 5.10 package mode (toolchain 6.4), SwiftPM, AppKit + SwiftUI, macOS 13+. No new dependencies.

**Design (approved in chat 2026-09-23; mockups: https://claude.ai/artifact/EmQ6cU3eDxgLHg4pTxaP9t, frames `C-collapsed`, `C-expanded`, `C-live`):**
- **Collapsed (default):** in the title bar row, to the right of the traffic lights, one item per Provider: icon, then up to two stacked mini bars, each with its percent: the short Window (`QuotaFormat.summaryWindow`) and the `week` Window. Then a small chevron-down. The whole strip is one button that expands.
- **Which week:** the Window labelled exactly `week`; else the first Window whose `duration` is 7 days (604 800 s); omitted when that is the same Window as the short one. Per-model weeks (`week · Fable`) only appear when expanded.
- **Colours:** bars use `QuotaFormat.tone` exactly like `WindowGauge` (green on pace, orange past the pace tick or ≥90 %, grey with no length). Percent text stays label-coloured; ≥90 % gets `.semibold` (same rule as `WindowGauge` — no orange text).
- **Provider with no numbers** (loading, not signed in, problem without last report): the icon at 0.45 opacity, no bars. Problem **with** a last report: bars at 0.45 opacity (same as today's `QuotaSummary`).
- **Tooltip** per item: `"<Provider>: 5h 62% · 1h20m, week 41% · 4d2h"`, or the problem message / "not signed in".
- **Narrow window:** `ViewThatFits(in: .horizontal)` — first try bars + percents, then bars only. Minimum window width stays 360.
- **Expanded:** clicking the strip swaps it for a header row in the same title bar position: `Quota` label, the ↻ refresh button (spinner while fetching — existing `refreshButton` behaviour), chevron-up. Everything in that row collapses it except ↻. Below the title bar row, above the filter strip, the existing per-Provider rows (every Window, reset countdown, yellow pace tick, stale note) on one `.cardSurface()`. This panel is **pinned** (outside the `ScrollView`) and pushes the filter + list down. It does not overlay them.
- Expanded/collapsed is remembered across launches under a **new** key `herdview.quotaExpanded`, default `false` (collapsed). The old `herdview.quotaCollapsed` key is no longer read.
- The Quota card no longer appears inside the list.

## Global Constraints

- macOS 13 deployment target; `ViewThatFits` and `Layout` are macOS 13. Nothing newer without `#available`.
- No new package dependencies.
- Tests: `mise run test` (`swift test` works on this Mac). While iterating, `swift test --filter <Class>`. Log long runs to `/tmp/herdview-test-<ts>.log`.
- `swift build` warning-free for new code.
- Keep the repo's style: doc comments that say *why*, `// MARK:` sections, Conventional Commits (`feat(core):`, `feat(app):`, `refactor(app):`, `docs:`).
- Never commit on `main`; `main` is MR-only. First commit on your branch: copy this plan in (untracked on `main`) — `docs: plan Quota in the title bar`.
- Quota numbers are read only (ADR 0005). Nothing about fetching, scheduling or credentials changes.

## File Structure

Created:
- `Sources/App/QuotaTitleBar.swift` — collapsed strip, expanded header, expanded panel wrapper.

Modified:
- `Sources/HerdviewCore/QuotaFormat.swift` + `Tests/HerdviewCoreTests/QuotaFormatTests.swift` — `titleBarWindows(of:)`.
- `Sources/HerdviewCore/WindowPreferences.swift` + `Tests/HerdviewCoreTests/WindowPreferencesTests.swift` — `isQuotaCollapsed` → `isQuotaExpanded`.
- `Sources/App/QuotaStore.swift` — `isCollapsed` → `isExpanded`.
- `Sources/App/QuotaCard.swift` — drop the card chrome, header and `QuotaSummary`; keep and expose (drop `private`) `QuotaRow`, `WindowGauge`, `ProviderIcon`, `FlowLayout`; add a `QuotaRows` view that lists every Provider's row with separators (today's `rows`).
- `Sources/App/AgentListView.swift` — remove `QuotaCard` from the list; root becomes `VStack(spacing: 0) { QuotaTitleBar(...); ScrollView {...} }` with the title bar row drawn into the top safe area.
- `Sources/App/MainWindowController.swift` — only if needed for title-bar hit-testing (see Task 3); update its doc comment that describes the title bar.
- `README.md` — the Quota paragraph.

---

## Task 1: Which Windows the title bar shows

**Files:** `Sources/HerdviewCore/QuotaFormat.swift`, `Tests/HerdviewCoreTests/QuotaFormatTests.swift`.

**Interface:**
```swift
/// The Windows the title bar strip shows for a Provider, short one first:
/// `summaryWindow`, then its `week` if that is a different Window. At most two.
public static func titleBarWindows(of windows: [QuotaWindow]) -> [QuotaWindow]
```

- [ ] **Step 1: Failing tests** (use the file's existing window-building helpers/style):
  - Claude-shaped `[5h, week, week · Fable]` → labels `["5h", "week"]`.
  - `[week · Fable, 5h, week]` (order shuffled) → `["5h", "week"]` (plain `week` beats the per-model one).
  - `[5h, week · Fable]` only (no plain `week`, per-model has 7-day duration) → `["5h", "week · Fable"]` (fallback: first 7-day Window).
  - `[week]` only → `["week"]` (week is also the summary; not repeated).
  - `[month]` (no duration) → `["month"]`.
  - `[]` → `[]`.
- [ ] **Step 2:** `swift test --filter QuotaFormatTests` → compile failure for the missing function.
- [ ] **Step 3:** Implement. Compare Windows by value (`QuotaWindow` is `Equatable`) to decide "same Window".
- [ ] **Step 4:** Filter passes; `mise run test` passes.
- [ ] **Step 5: Commit** `feat(core): pick the short and weekly Window for the title bar`.

## Task 2: Remember expanded, not collapsed

**Files:** `Sources/HerdviewCore/WindowPreferences.swift`, its tests, `Sources/App/QuotaStore.swift`, `Sources/App/QuotaCard.swift` (compile fix only).

- [ ] **Step 1: Tests first.** Replace the `isQuotaCollapsed` tests with:
  - `isQuotaExpanded` is `false` on fresh defaults.
  - setting `true` survives a new `WindowPreferences(defaults:)`.
  - a stored legacy `herdview.quotaCollapsed = false` does **not** make it expanded (the old key is not read).
- [ ] **Step 2:** run → fail.
- [ ] **Step 3:** Replace `quotaCollapsedKey`/`isQuotaCollapsed` with `quotaExpandedKey = "herdview.quotaExpanded"`/`isQuotaExpanded`. Doc comment: collapsed by default because the title bar strip already answers "can I keep going", and the list below is the window's main job. `QuotaStore.isCollapsed` → `isExpanded` (same didSet pattern). Fix `QuotaCard.swift` usages minimally so it compiles (it is rewritten in Task 3).
- [ ] **Step 4:** `mise run test` passes; `swift build` passes.
- [ ] **Step 5: Commit** `refactor(core): remember whether Quota is expanded`.

## Task 3: Quota in the title bar

**Files:** create `Sources/App/QuotaTitleBar.swift`; modify `QuotaCard.swift`, `AgentListView.swift`, maybe `MainWindowController.swift`.

Layout facts to respect (read the doc comments in these files first):
- The window uses `.fullSizeContentView`, `titlebarAppearsTransparent`, `titleVisibility = .hidden`, and an `NSVisualEffectView` backdrop. The SwiftUI list currently respects the top safe area (the title bar's height), so its first item sits just under the traffic lights.
- The title bar row must hold the strip **beside** the traffic lights. Do this in SwiftUI: the root `VStack` ignores the top safe area (`.ignoresSafeArea(.container, edges: .top)`), and its first child is a row of the title bar's height (read it from the window: `window.frame.height - window.contentLayoutRect.height`, passed in from `MainWindowController`, with a fallback of 28 pt; or measure the top safe-area inset with a `GeometryReader` **before** ignoring it). Pick one and say why in a comment. The row's content is trailing-aligned with leading padding that clears the traffic lights (≈ 78 pt; derive from `window.standardWindowButton(.zoomButton)?.frame.maxX` if you pass the window metrics in).
- Nothing in this app paints a background over the backdrop. The expanded panel uses `.cardSurface()` like every other card.

Steps:
- [ ] **Step 1:** In `QuotaCard.swift`: delete `QuotaCard`'s header/collapse logic and `QuotaSummary`; keep `QuotaRow`, `WindowGauge`, `ProviderIcon`, `FlowLayout` (make them internal) and a `QuotaRows(store:now:)` view equal to today's `rows`. Move `refreshButton` into `QuotaTitleBar.swift`. Rename the file to `QuotaRows.swift` if it no longer holds a card (`git mv`).
- [ ] **Step 2:** `QuotaTitleBar(store:now:)`:
  - Collapsed: `Button { store.isExpanded = true } label: { strip }` `.buttonStyle(.plain)`, `.help("Show every Window")`. `strip` = `ViewThatFits(in: .horizontal) { strip(showPercent: true); strip(showPercent: false) }`, each an `HStack(spacing: 10)` of `QuotaMiniGauge` per Provider plus `chevron.down` (9 pt, semibold, secondary).
  - `QuotaMiniGauge(provider:entry:now:showPercent:)`: `ProviderIcon(side: 18)` + `VStack(spacing: 2)` of one line per `QuotaFormat.titleBarWindows(of:)` Window: a 30×4 capsule bar coloured by `QuotaFormat.tone`, then (when `showPercent`) `QuotaFormat.percent` in 9.5 pt monospaced digits, semibold at ≥ `warningPercent`. Dimming and tooltip per the Design section. `.fixedSize()`.
  - Expanded header row (same title-bar row): `Text("Quota")` 11 pt semibold secondary, `Spacer`, `refreshButton`, `chevron.up`; the row except ↻ is a plain button that sets `isExpanded = false`, `.help("Show only the short and weekly Windows")`.
  - Expanded panel (below the title-bar row, outside the `ScrollView`): `QuotaRows(store:now:)` on `.cardSurface()`, horizontal padding `Metrics.gutter`, bottom padding `Metrics.groupGap / 2`.
  - Animate expand/collapse with `withAnimation(.easeInOut(duration: 0.18))`.
- [ ] **Step 3:** `AgentListView`: remove `QuotaCard` from the `LazyVStack`. The `TimelineView` wraps a `VStack(spacing: 0) { QuotaTitleBar(...); ScrollView { … } }` so the gauges share the half-second `now`. Update the struct's doc comment (the list no longer owns the top of the window; the title bar row is the Quota's).
- [ ] **Step 4:** Title-bar clicks. With a transparent full-size title bar, SwiftUI buttons in that strip should receive clicks while empty title-bar space still drags the window. Verify both manually (Step 6). If the button does not get clicks, fix it in `MainWindowController` (e.g. an `NSTitlebarAccessoryViewController` fallback is **not** wanted; first try making sure the hosting view is the one hit-tested, and describe what you did). Update `MainWindowController`'s doc comment where it describes the title bar as empty.
- [ ] **Step 5:** `swift build` clean; `mise run test` passes.
- [ ] **Step 6: Manual check** via `mise run run`, and report what you saw, including anything you could not exercise:
  - collapsed on first launch; each Provider shows 5h + week bars (Claude/Codex), a single bar for OpenCode Go (`month`) / Grok (`week`); tooltips read correctly.
  - click the strip → panel expands in place, pushes filter + list down, every Window incl. `week · <model>` with pace tick and reset; ↻ refreshes without collapsing; click the header → collapses. State survives relaunch.
  - drag the window by empty title-bar space still works; traffic lights still work.
  - narrow the window to 360 → percents drop, bars stay, nothing overlaps the traffic lights.
  - `hidden_providers` still removes a Provider from the strip.
  - light and dark mode legible; macOS 26 glass looks right (no opaque band behind the title bar).
- [ ] **Step 7: Commit** `feat(app): show Quota in the title bar and expand it in place`.

## Task 4: Docs

- [ ] **Step 1:** `README.md`: rewrite the Quota paragraph's placement sentences — the strip in the title bar (short Window + week), clicking it expands every Window in place, the state is remembered; the "Clicking Quota folds the card…" sentence goes. Keep the Provider/credential table and ADR 0005 text as is.
- [ ] **Step 2: Commit** `docs: describe Quota in the title bar`.

## Finish

- [ ] `mise run test` and `swift build -c release` pass; paste the summary lines.
- [ ] Use superpowers:finishing-a-development-branch. Never push to or merge into `main` directly.
