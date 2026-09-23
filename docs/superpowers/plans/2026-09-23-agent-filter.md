# Agent Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user narrow Herdview's agent list with a search field and a status scope, without ever silently hiding an agent that is waiting on them.

**Architecture:** Pure filtering logic in `HerdviewCore` (`AgentScope`, `AgentFilter`, `AgentFilterResult`), unit tested. `WindowPreferences` remembers the scope. The App target adds a `FilterState` observable, a pinned filter strip at the top of the list, an "N waiting on you are hidden — Show" banner, a "Filter hides … — Clear" footer, and an Edit menu (Cut/Copy/Paste/Select All, needed for any text field, plus Find ⌘F).

**Tech Stack:** Swift 5.10 package mode (toolchain 6.4), SwiftPM, AppKit + SwiftUI, macOS 13+. No new dependencies.

**Design (approved in chat, 2026-09-23):**
- Search field: matches host, session, directory, agent kind, agent name, title. Case- and diacritic-insensitive. Whitespace-separated words are ANDed; each word may match any field. ⌘F focuses it, Esc clears it.
- Status scope, segmented, with live counts: `All · Needs me (blocked+done) · Working · Idle`. `unknown` shows only under All.
- Safety: when the filter hides any agent whose status `asksForAPerson`, an orange banner at the top says so; clicking **Show** clears query AND resets scope to All.
- Hosts with no visible agent disappear while a filter is active; a footer line says "Filter hides N agents · M hosts — Clear".
- Notifications and the menu bar item ignore the filter entirely — it only changes what the window lists.
- Query is not persisted (empty on launch). Scope is persisted in `UserDefaults`.
- Out of scope: `session:foo` syntax, saved filters, hide-session context menu.

**Deviation from the chat design:** the chat said "toolbar search". `MainWindowController`'s doc comment records why the window dropped `NSToolbar` (macOS 26 wraps each toolbar item in a glass capsule). So the filter is a strip pinned at the top of the list instead, on the window's own glass.

## Global Constraints

- macOS 13 deployment target; no API newer than 13 without `#available`. `@FocusState`, `.onExitCommand`, `Picker(.segmented)` are all fine on 13.
- No new package dependencies.
- `swift test` works on this Mac (Xcode is installed). Run the suite with `mise run test` (or `swift test --filter <Class>` while iterating). Log long runs to `/tmp/herdview-test-<ts>.log`.
- `swift build` must stay warning-free for new code.
- Code style follows the repo: doc comments that say *why*, `// MARK:` sections, Conventional Commits (`feat(core):`, `feat(app):`, `docs:`).
- Never commit on `main`. Work on the branch/worktree you were told to create.
- First commit on your branch: copy this plan file in (it is untracked on `main`) — `docs: plan the agent filter`.

## File Structure

Created:
- `Sources/HerdviewCore/AgentFilter.swift` — `AgentScope`, `AgentFilter`, `AgentFilterResult`.
- `Tests/HerdviewCoreTests/AgentFilterTests.swift`
- `Sources/App/FilterState.swift` — `@MainActor ObservableObject` holding query, scope, focus requests.
- `Sources/App/FilterBar.swift` — the search field + segmented scope strip, the hidden-attention banner, the footer.

Modified:
- `Sources/HerdviewCore/WindowPreferences.swift` + `Tests/HerdviewCoreTests/WindowPreferencesTests.swift` — `agentScope`.
- `Sources/App/MainMenu.swift` — Edit menu; `Items` gains `find`.
- `Sources/App/MainWindowController.swift` — owns `FilterState`, wires Find.
- `Sources/App/AppDelegate.swift` — passes `menuItems?.find`.
- `Sources/App/AgentListView.swift` — renders the filtered list.
- `README.md`, `CONTEXT.md` — document Filter.

---

## Task 1: Core filter logic

**Files:** Create `Sources/HerdviewCore/AgentFilter.swift`, `Tests/HerdviewCoreTests/AgentFilterTests.swift`.

**Interface (produce exactly this):**

```swift
public enum AgentScope: String, CaseIterable, Sendable {
    case all, needsMe, working, idle
    public func includes(_ status: AgentStatus) -> Bool
    public var title: String   // "All", "Needs me", "Working", "Idle"
}

public struct AgentFilter: Equatable, Sendable {
    public var query: String
    public var scope: AgentScope
    public init(query: String = "", scope: AgentScope = .all)
    /// A non-blank query, or any scope but `.all`.
    public var isActive: Bool { get }
    public func matchesQuery(_ agent: TrackedAgent) -> Bool
    public func matches(_ agent: TrackedAgent) -> Bool   // query AND scope
    public func apply(to agents: [TrackedAgent]) -> AgentFilterResult
}

public struct AgentFilterResult: Equatable, Sendable {
    /// Input order preserved.
    public let visible: [TrackedAgent]
    public let hiddenCount: Int
    /// Hosts that have at least one agent in the input and none visible.
    public let hiddenHosts: Int
    /// Hidden agents whose status `asksForAPerson` — drives the banner.
    public let hiddenAskingForAPerson: Int
    /// Per scope: how many agents match the query AND that scope.
    /// Counts ignore the current scope so the segments show what switching would give.
    public let scopeCounts: [AgentScope: Int]
}
```

Matching rules:
- Tokens: `query` split on whitespace/newlines, empty pieces dropped. No tokens → every agent matches the query.
- Fields searched per agent: `host`, `session`, `info.cwd`, `info.agent`, `info.displayAgent`, `info.name`, `info.terminalTitleStripped`, and `AgentTitles.rowText(for:)`'s `primary`, `secondary`, `session`. `nil`s skipped.
- A token matches when any field contains it using `range(of:options: [.caseInsensitive, .diacriticInsensitive])`. All tokens must match (AND); they may match different fields.
- Scope: `.all` → every status; `.needsMe` → `status.asksForAPerson`; `.working` → `.working`; `.idle` → `.idle`.

- [ ] **Step 1: Write failing tests.** Helper builds `TrackedAgent(host:session:info:since:)` with `AgentInfo(paneId:workspaceId:agent:cwd:terminalTitleStripped:agentStatus:revision:)`. Tests (one `func test…` each, names in the repo's sentence style):
  - empty query + `.all` → all visible, `isActive == false`, `hiddenCount == 0`.
  - whitespace-only query → `isActive == false`.
  - query matches cwd substring case-insensitively (`"HERDVIEW"` hits `/Users/x/herdview`).
  - query matches host, session, agent kind (`"codex"`), terminal title.
  - diacritic-insensitive: `"phien"` matches title `"Phiên lọc"`.
  - two tokens AND across fields: `"devtuf claude"` hits a claude agent on host devtuf, misses a codex agent on devtuf and a claude agent on local.
  - scope `.needsMe` keeps blocked+done, drops working/idle/unknown; `.working`, `.idle` likewise; `unknown` visible only under `.all`.
  - `hiddenAskingForAPerson` counts a blocked agent hidden by the query; is 0 under `.needsMe` with empty query.
  - `hiddenHosts`: host whose every agent is hidden counts 1; host with one visible agent counts 0.
  - `scopeCounts` reflect the query but not the current scope (scope `.idle`, query matches 1 blocked + 2 idle → `[.all:3, .needsMe:1, .working:0, .idle:2]`).
  - `visible` preserves input order.
- [ ] **Step 2:** `swift test --filter AgentFilterTests` → fails to compile (types missing). Confirm the failure is that, not something else.
- [ ] **Step 3:** Implement `AgentFilter.swift` with doc comments explaining *why* (ANDed tokens, counts ignoring scope so segments preview the switch, hidden-attention count as the safety rule).
- [ ] **Step 4:** `swift test --filter AgentFilterTests` → all pass. Then `mise run test` → whole suite passes.
- [ ] **Step 5: Commit** `feat(core): filter agents by search text and status scope`.

## Task 2: Remember the scope

**Files:** Modify `Sources/HerdviewCore/WindowPreferences.swift`, `Tests/HerdviewCoreTests/WindowPreferencesTests.swift`.

- [ ] **Step 1: Failing tests** (reuse the file's suite-per-test setUp):
  - `agentScope` is `.all` on a fresh defaults.
  - setting `.needsMe` survives a new `WindowPreferences(defaults:)`.
  - an unknown stored raw value (`defaults.set("bogus", forKey: "herdview.agentScope")`) reads back as `.all`.
- [ ] **Step 2:** run → fail.
- [ ] **Step 3:** add `private static let agentScopeKey = "herdview.agentScope"` and `public var agentScope: AgentScope { get / nonmutating set }` storing `rawValue`.
- [ ] **Step 4:** tests pass; full suite passes.
- [ ] **Step 5: Commit** `feat(core): remember the agent list's status scope`.

## Task 3: FilterState + Edit menu with Find

**Files:** Create `Sources/App/FilterState.swift`. Modify `MainMenu.swift`, `MainWindowController.swift`, `AppDelegate.swift`.

- [ ] **Step 1:** `FilterState`:
  ```swift
  @MainActor
  final class FilterState: ObservableObject {
      @Published var query = ""
      @Published var scope: AgentScope { didSet { preferences.agentScope = scope } }
      /// Bumped by ⌘F; the view focuses the field whenever it changes.
      @Published private(set) var focusRequest = 0
      var filter: AgentFilter { AgentFilter(query: query, scope: scope) }
      init(preferences: WindowPreferences)   // scope = preferences.agentScope
      func requestFocus()                    // focusRequest += 1
      func clear()                           // query = "", scope = .all
  }
  ```
- [ ] **Step 2:** `MainMenu`: add an **Edit** menu between the app menu and Window menu: Undo (⌘Z, `Selector(("undo:"))`), Redo (⇧⌘Z, `Selector(("redo:"))`), separator, Cut/Copy/Paste/Select All with `NSText` selectors (`cut:`, `copy:`, `paste:`, `selectAll:`), separator, **Find…** ⌘F with `action: nil`. Return it as `Items.find`. Doc comment: a text field has no ⌘V without an Edit menu, since the key equivalents live on menu items.
- [ ] **Step 3:** `MainWindowController.init` gains `findItem: NSMenuItem? = nil`; it creates `FilterState(preferences:)`, passes it to `AgentListView`, targets `findItem` at `@objc func find()` which calls `show()` then `filterState.requestFocus()`. `AppDelegate` passes `menuItems?.find`.
- [ ] **Step 4:** `swift build` passes (AgentListView gets a `filter` parameter in Task 4; add it now as `@ObservedObject var filter: FilterState` unused so this compiles).
- [ ] **Step 5: Commit** `feat(app): add an Edit menu and Find for the agent list`.

## Task 4: Filter strip, banner, footer, filtered list

**Files:** Create `Sources/App/FilterBar.swift`. Modify `Sources/App/AgentListView.swift`.

Layout inside the existing `LazyVStack`, top to bottom:
1. `FilterBar` — a `TextField("Filter", text: $filter.query)` with a leading `magnifyingglass` symbol and a trailing `xmark.circle.fill` clear button shown only when the query is non-empty; `.textFieldStyle(.plain)` inside a `.cardBackground()` capsule-ish rounded rect at `Metrics.cardRadius`. `@FocusState` bound to the field; `.onChange(of: filter.focusRequest)` sets focus; `.onExitCommand { filter.query = "" }`. Below it a `Picker("", selection: $filter.scope)` with `.pickerStyle(.segmented)`, `.labelsHidden()`, one segment per `AgentScope` titled `"\(scope.title) \(count)"` from `result.scopeCounts`.
2. Hidden-attention banner, only when `result.hiddenAskingForAPerson > 0`: `Notice`-style row, `exclamationmark.circle.fill`, tint `.systemOrange`, text "N waiting on you hidden by the filter" (singular "1 agent waiting on you is hidden…"), trailing `Button("Show") { filter.clear() }` `.buttonStyle(.link)`. On `.cardSurface()`.
3. `QuotaCard` (unchanged position, after the filter strip and banner).
4. config error / no-hosts notices (unchanged).
5. Host groups: compute `result = filter.filter.apply(to: store.agents)` once per body. When `filter.filter.isActive`, iterate only hosts in `store.hostOrder` with ≥1 visible agent and give each `HostGroup` its visible agents; otherwise exactly today's behaviour (all hosts, including empty/unreachable). `HostGroup` takes `agents: [TrackedAgent]` instead of reading the store, and its count shows the visible count.
6. Footer, only when `isActive && result.hiddenCount > 0`: quiet 11pt secondary text "Filter hides N agents · M hosts" (omit "· M hosts" when 0) and `Button("Clear") { filter.clear() }` `.buttonStyle(.link)`, at `Metrics.textInset`.
7. If the filter is active and `result.visible` is empty, show a `Notice(symbol: "line.3.horizontal.decrease.circle", text: "No agents match")` card in place of the host groups (footer still shown).

`Notice` is `private` in `AgentListView.swift`; make it file-internal (drop `private`) so `FilterBar.swift` can use it, or keep banner/footer in `AgentListView.swift` — pick whichever keeps each file focused.

- [ ] **Step 1:** Implement as above. Doc comments state *why*: the banner exists because the window's job is answering "is anything waiting on me", and a filter must not silently break that; notifications/menu bar are deliberately unaffected.
- [ ] **Step 2:** `swift build` clean. `mise run test` passes.
- [ ] **Step 3: Manual check** — `mise run run` (builds and opens `build/Herdview.app`). With at least one live Herdr agent:
  - type part of a cwd → only matching rows; hosts without matches disappear; footer shows counts; Clear restores.
  - ⌘F from anywhere in the app focuses the field; Esc empties it; ⌘V pastes into it.
  - pick `Needs me` with no blocked/done agents → "No agents match"; relaunch → scope still `Needs me`, query empty.
  - filter so a `done`/`blocked` agent is hidden → orange banner; Show resets to All + empty query.
  - light and dark mode both legible.
  Report what you observed, including anything you could not exercise (e.g. no blocked agent available).
- [ ] **Step 4: Commit** `feat(app): filter the agent list by text and status`.

## Task 5: Docs

- [ ] **Step 1:** `CONTEXT.md` — add a **Filter** term: "What the window lists right now: agents matching the search text and the status scope. It never changes Status, Notifications or the menu bar item, and it never hides an Agent that asks for a person without saying so. _Avoid_: search, view, query".
- [ ] **Step 2:** `README.md` — a short paragraph after the "Keep on Top" paragraph describing the filter strip, ⌘F/Esc, scopes, the banner, and that the scope is remembered but the text is not.
- [ ] **Step 3: Commit** `docs: describe the agent filter`.

## Finish

- [ ] `mise run test` and `swift build -c release` both pass; paste the final summary lines.
- [ ] Use superpowers:finishing-a-development-branch. Do NOT push to or merge into `main` directly; `main` is MR-only.
