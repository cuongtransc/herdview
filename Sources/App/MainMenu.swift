import AppKit

/// The menu a normal app has to have. Herdview had none while it was a menu bar
/// agent: it had no window to close and nothing to quit from, so the pet's
/// popover carried a Quit button instead. With a real window the app menu is
/// where ⌘Q lives, and nothing appears at all without one.
@MainActor
enum MainMenu {
    /// The items the menu cannot wire up itself. The menu is built before the
    /// window exists, so `Keep on Top` and `Find…` go back to the caller to
    /// point at the window controller once there is one.
    struct Items {
        let keepOnTop: NSMenuItem
        let find: NSMenuItem
    }

    @discardableResult
    static func install(appName: String = "Herdview") -> Items {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // A text field has no ⌘V without an Edit menu, because the key
        // equivalents live on menu items: the field editor knows how to paste,
        // but nothing in the app would ever tell it to. Undo, Redo and the
        // clipboard entries are all left to the responder chain, so whichever
        // field is first responder decides what they mean. Find is the one
        // exception — it is this app's own action, so it is built with no
        // action at all and `MainWindowController` targets it once there is a
        // window to point at.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        // Double parens: undo and redo are resolved by AppKit at send time
        // through the responder chain, so there is no compile-time `#selector`
        // for them.
        editMenu.addItem(withTitle: "Undo",
                         action: Selector(("undo:")),
                         keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo",
                                    action: Selector(("redo:")),
                                    keyEquivalent: "z")
        // ⇧⌘Z, the standard Redo shortcut; without the mask it would collide
        // with Undo's plain ⌘Z.
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editMenu.addItem(.separator())
        let find = editMenu.addItem(withTitle: "Find…",
                                    action: nil,
                                    keyEquivalent: "f")

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(.separator())
        let keepOnTop = windowMenu.addItem(withTitle: "Keep on Top",
                                           action: nil,
                                           keyEquivalent: "t")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
        return Items(keepOnTop: keepOnTop, find: find)
    }
}
