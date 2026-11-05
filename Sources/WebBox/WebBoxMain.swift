import AppKit
import SwiftUI
import UserNotifications

@main
enum WebBoxMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = WebBoxAppDelegate.shared
        app.delegate = delegate
        MainActor.assumeIsolated {
            delegate.installMainMenu()
        }
        app.run()
    }
}

@MainActor
final class WebBoxAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    /// Strongly retained singleton so weak `NSApp.delegate` and weak `NSMenuItem.target` never deallocate in `-O` Release builds!
    static let shared = WebBoxAppDelegate()

    private var mainWindow: NSWindow?
    private var keyEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first { $0.processIdentifier != ownPID }
            if let existing {
                existing.activate()
                NSApp.terminate(nil)
                return
            }
        }

        UNUserNotificationCenter.current().delegate = self
        installLocalShortcutMonitor()
        openOrFocusMainWindow()

        // Automatically fetch genuine HD icons for any existing or starter accounts
        AppIconFetcher.shared.backfillMissingIcons(in: WorkspaceStore.shared)
        UpdateCheckerService.shared.checkSilentlyOnLaunchIfNeeded()
        ContextMediaExtractor.cleanupStaleTemporaryFiles()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WorkspaceStore.shared.flushPendingSaveSynchronously()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openOrFocusMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func openOrFocusMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let store = WorkspaceStore.shared
        let rootView = MainWorkspaceView()
        let hostingController = NSHostingController(rootView: rootView)

        let defaultSize = store.isStandaloneMode
            ? NSRect(x: 0, y: 0, width: 1120, height: 760)
            : NSRect(x: 0, y: 0, width: 1280, height: 800)

        let window = NSWindow(
            contentRect: defaultSize,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = store.isStandaloneMode
            ? (store.activeInstance?.displayTitle ?? "WebBox")
            : "WebBox"
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 820, height: 560)
        window.contentViewController = hostingController
        window.center()

        let autosaveKey = store.isStandaloneMode
            ? "WebBoxStandaloneWin_\(store.activeInstance?.id.uuidString ?? "default")"
            : "WebBoxNativeHubWindow_v2"
        window.setFrameAutosaveName(autosaveKey)
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Local Keyboard Monitor (Guarantees Cmd+R, Cmd+\, Cmd+1..9 work even inside WKWebView!)

    private func installLocalShortcutMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let keyWin = NSApp.keyWindow
            if WebSessionManager.shared.isImagePreviewWindow(keyWin) || keyWin is NSPanel {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), !flags.contains(.control) else {
                return event
            }
            guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
                return event
            }

            let store = WorkspaceStore.shared

            // 1. Cmd + R / Cmd + Shift + R -> Reload active WebView (or In-App Browser if full overlay)
            if chars == "r" {
                if flags == [.command] {
                    self.performReload(fromOrigin: false)
                    return nil
                } else if flags == [.command, .shift] {
                    self.performReload(fromOrigin: true)
                    return nil
                }
            }

            // 2. Cmd + \ or Cmd + Shift + S -> Hide/Show Left Sidebar; Cmd + Option + S -> Compact Icon-Only Mode
            if !store.isStandaloneMode {
                if (chars == "\\" && flags == [.command]) || (chars == "s" && flags == [.command, .shift]) {
                    store.toggleLeftSidebar()
                    return nil
                }
                if chars == "s" && flags == [.command, .option] {
                    store.toggleSidebarCompactMode()
                    return nil
                }
            }

            // 3. Cmd + 1 ... Cmd + 9 -> Quick switch account
            if !store.isStandaloneMode && flags == [.command],
               let digit = Int(chars), (1...9).contains(digit) {
                store.selectInstanceByIndex(digit - 1)
                return nil
            }

            // 4. Cmd + F -> Find in Page
            if chars == "f" && flags == [.command] {
                store.isFindBarVisible.toggle()
                return nil
            }

            // 5. Cmd + [ / Cmd + ] -> Back / Forward
            if chars == "[" && flags == [.command] {
                self.goBackAction()
                return nil
            }
            if chars == "]" && flags == [.command] {
                self.goForwardAction()
                return nil
            }

            // 6. Cmd + (+ / = / - / 0) -> Page Zoom
            if (chars == "=" || chars == "+") && (flags == [.command] || flags == [.command, .shift]) {
                self.zoomInAction()
                return nil
            }
            if chars == "-" && flags == [.command] {
                self.zoomOutAction()
                return nil
            }
            if chars == "0" && flags == [.command] {
                self.zoomResetAction()
                return nil
            }

            // 7. Cmd + N / Cmd + Shift + N / Cmd + , / Cmd + U
            if !store.isStandaloneMode {
                if chars == "n" && flags == [.command] {
                    self.openCatalogAction()
                    return nil
                }
                if chars == "n" && flags == [.command, .shift] {
                    self.cloneCurrentAccountAction()
                    return nil
                }
                if chars == "u" && flags == [.command] {
                    self.checkForGitHubUpdatesAction()
                    return nil
                }
            }
            if chars == "," && flags == [.command] {
                self.openPreferencesAction()
                return nil
            }

            return event
        }
    }

    private var activeTargetInstanceID: UUID? {
        WebSessionManager.shared.instanceID(forDetachedWindow: NSApp.keyWindow)
            ?? WorkspaceStore.shared.activeInstanceID
    }

    private var isFullInAppOverlayActiveInKeyWindow: Bool {
        let store = WorkspaceStore.shared
        return WebSessionManager.shared.instanceID(forDetachedWindow: NSApp.keyWindow) == nil
            && store.isInAppBrowserVisible
            && store.preferences.inAppBrowserLayout == .fullOverlay
    }

    private func performReload(fromOrigin: Bool) {
        let store = WorkspaceStore.shared
        if isFullInAppOverlayActiveInKeyWindow, let tab = store.activeInAppTab {
            WebSessionManager.shared.reloadInAppTab(tabID: tab.id)
            store.showToast(L10n.s("Đang tải lại trang trong trình duyệt App...", "Reloading in-app browser tab..."))
            return
        }
        guard let id = activeTargetInstanceID else { return }
        WebSessionManager.shared.reload(instanceID: id, fromOrigin: fromOrigin)
        store.showToast(fromOrigin ? L10n.s("Đang tải lại hoàn toàn (bỏ qua bộ nhớ đệm)...", "Reloading completely (ignoring cache)...") : L10n.s("Đang tải lại trang...", "Reloading page..."))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let revealPath = userInfo["revealFilePath"] as? String
        let idStr = userInfo["instanceID"] as? String
        Task { @MainActor in
            if let revealPath, !revealPath.isEmpty {
                WorkspaceStore.shared.revealFileInFinder(URL(fileURLWithPath: revealPath))
                return
            }
            self.openOrFocusMainWindow()
            if let idStr, let uuid = UUID(uuidString: idStr) {
                WorkspaceStore.shared.selectInstance(uuid)
            }
        }
        completionHandler()
    }

    // MARK: - Native macOS Menu Bar

    func installMainMenu() {
        let store = WorkspaceStore.shared
        let appTitle = store.isStandaloneMode
            ? (store.activeInstance?.displayTitle ?? "WebBox")
            : "WebBox"

        let mainMenu = NSMenu()

        // 1. Application Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: String(format: L10n.menuAbout, appTitle),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )

        if !store.isStandaloneMode {
            let checkUpdateItem = appMenu.addItem(
                withTitle: L10n.menuCheckUpdates,
                action: #selector(checkForGitHubUpdatesAction),
                keyEquivalent: "u"
            )
            checkUpdateItem.target = self

            let openRepoItem = appMenu.addItem(
                withTitle: L10n.menuOpenGitHubRepo,
                action: #selector(openGitHubRepoAction),
                keyEquivalent: ""
            )
            openRepoItem.target = self
        }

        appMenu.addItem(.separator())

        let settingsItem = appMenu.addItem(
            withTitle: L10n.settings,
            action: #selector(openPreferencesAction),
            keyEquivalent: ","
        )
        settingsItem.target = self

        if !store.isStandaloneMode {
            let dedicatedMgrItem = appMenu.addItem(
                withTitle: L10n.menuDedicatedApps,
                action: #selector(openDedicatedAppsManagerAction),
                keyEquivalent: "d"
            )
            dedicatedMgrItem.keyEquivalentModifierMask = [.command, .shift]
            dedicatedMgrItem.target = self
        }

        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(format: L10n.menuHide, appTitle),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = appMenu.addItem(
            withTitle: L10n.menuHideOthers,
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: L10n.menuShowAll,
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(format: L10n.menuQuit, appTitle),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        // 2. Account / App Menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: L10n.menuAppCategory)

        if !store.isStandaloneMode {
            let newAppItem = fileMenu.addItem(
                withTitle: L10n.menuNewApp,
                action: #selector(openCatalogAction),
                keyEquivalent: "n"
            )
            newAppItem.target = self

            let cloneAccountItem = fileMenu.addItem(
                withTitle: L10n.menuCloneAccount,
                action: #selector(cloneCurrentAccountAction),
                keyEquivalent: "n"
            )
            cloneAccountItem.keyEquivalentModifierMask = [.command, .shift]
            cloneAccountItem.target = self

            let exportDedicatedItem = fileMenu.addItem(
                withTitle: L10n.menuExportDedicated,
                action: #selector(exportCurrentAsDedicatedAppAction),
                keyEquivalent: "e"
            )
            exportDedicatedItem.keyEquivalentModifierMask = [.command, .shift]
            exportDedicatedItem.target = self

            fileMenu.addItem(.separator())
        }

        let openMainWinItem = fileMenu.addItem(
            withTitle: L10n.menuOpenMainWindow,
            action: #selector(reopenMainWindowAction),
            keyEquivalent: "0"
        )
        openMainWinItem.keyEquivalentModifierMask = [.command, .shift]
        openMainWinItem.target = self

        fileMenu.addItem(
            withTitle: L10n.menuCloseWindow,
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileMenuItem.submenu = fileMenu

        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L10n.menuEditCategory)
        editMenu.addItem(withTitle: L10n.menuUndo, action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: L10n.menuRedo, action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findItem = editMenu.addItem(
            withTitle: L10n.menuFindInPage,
            action: #selector(toggleFindBarAction),
            keyEquivalent: "f"
        )
        findItem.target = self
        editMenuItem.submenu = editMenu

        // 4. View & Navigation Menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: L10n.menuViewCategory)

        let reloadItem = viewMenu.addItem(
            withTitle: L10n.menuReload,
            action: #selector(reloadActiveAction),
            keyEquivalent: "r"
        )
        reloadItem.target = self

        let hardReloadItem = viewMenu.addItem(
            withTitle: L10n.menuHardReload,
            action: #selector(hardReloadActiveAction),
            keyEquivalent: "R"
        )
        hardReloadItem.keyEquivalentModifierMask = [.command, .shift]
        hardReloadItem.target = self

        let backItem = viewMenu.addItem(
            withTitle: L10n.menuBack,
            action: #selector(goBackAction),
            keyEquivalent: "["
        )
        backItem.target = self

        let forwardItem = viewMenu.addItem(
            withTitle: L10n.menuForward,
            action: #selector(goForwardAction),
            keyEquivalent: "]"
        )
        forwardItem.target = self

        viewMenu.addItem(.separator())

        let zoomIn = viewMenu.addItem(
            withTitle: L10n.menuZoomIn,
            action: #selector(zoomInAction),
            keyEquivalent: "+"
        )
        zoomIn.target = self

        let zoomOut = viewMenu.addItem(
            withTitle: L10n.menuZoomOut,
            action: #selector(zoomOutAction),
            keyEquivalent: "-"
        )
        zoomOut.target = self

        let zoomReset = viewMenu.addItem(
            withTitle: L10n.menuZoomReset,
            action: #selector(zoomResetAction),
            keyEquivalent: "0"
        )
        zoomReset.target = self

        if !store.isStandaloneMode {
            viewMenu.addItem(.separator())

            let compactSidebarItem = viewMenu.addItem(
                withTitle: L10n.menuToggleCompactSidebar,
                action: #selector(toggleCompactSidebarAction),
                keyEquivalent: "s"
            )
            compactSidebarItem.keyEquivalentModifierMask = [.command, .option]
            compactSidebarItem.target = self

            let toggleSidebarItem = viewMenu.addItem(
                withTitle: L10n.menuToggleSidebar,
                action: #selector(toggleLeftSidebarAction),
                keyEquivalent: "\\"
            )
            toggleSidebarItem.keyEquivalentModifierMask = [.command]
            toggleSidebarItem.target = self

            viewMenu.addItem(.separator())
            for num in 1...9 {
                let swItem = viewMenu.addItem(
                    withTitle: L10n.menuSwitchAccount(number: num),
                    action: #selector(switchAccountShortcut(_:)),
                    keyEquivalent: "\(num)"
                )
                swItem.tag = num - 1
                swItem.target = self
            }
        }
        viewMenuItem.submenu = viewMenu

        // 5. Window Menu
        let winMenuItem = NSMenuItem()
        mainMenu.addItem(winMenuItem)
        let winMenu = NSMenu(title: L10n.menuWindowCategory)
        winMenu.addItem(withTitle: L10n.menuMinimize, action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: L10n.menuZoomFullScreen, action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
        winMenuItem.submenu = winMenu
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc private func openPreferencesAction() {
        openOrFocusMainWindow()
        let store = WorkspaceStore.shared
        if store.isStandaloneMode, let first = store.activeInstance {
            store.editingInstance = first
        } else {
            store.isGlobalSettingsPresented = true
        }
    }

    @objc private func openDedicatedAppsManagerAction() {
        openOrFocusMainWindow()
        WorkspaceStore.shared.isDedicatedAppsManagerPresented = true
    }

    @objc private func openCatalogAction() {
        openOrFocusMainWindow()
        WorkspaceStore.shared.isCatalogPresented = true
    }

    @objc private func cloneCurrentAccountAction() {
        guard let active = WorkspaceStore.shared.activeInstance else { return }
        WorkspaceStore.shared.addAnotherAccount(basedOn: active)
    }

    @objc private func exportCurrentAsDedicatedAppAction() {
        guard let active = WorkspaceStore.shared.activeInstance else { return }
        _ = try? WorkspaceStore.shared.exportDedicatedDesktopApp(for: active.id)
    }

    @objc private func reopenMainWindowAction() {
        openOrFocusMainWindow()
    }

    @objc private func toggleFindBarAction() {
        WorkspaceStore.shared.isFindBarVisible.toggle()
    }

    @objc private func reloadActiveAction() {
        performReload(fromOrigin: false)
    }

    @objc private func hardReloadActiveAction() {
        performReload(fromOrigin: true)
    }

    @objc private func goBackAction() {
        if isFullInAppOverlayActiveInKeyWindow, let tab = WorkspaceStore.shared.activeInAppTab {
            WebSessionManager.shared.goBackInAppTab(tabID: tab.id)
            return
        }
        guard let id = activeTargetInstanceID else { return }
        WebSessionManager.shared.goBack(instanceID: id)
    }

    @objc private func goForwardAction() {
        if isFullInAppOverlayActiveInKeyWindow, let tab = WorkspaceStore.shared.activeInAppTab {
            WebSessionManager.shared.goForwardInAppTab(tabID: tab.id)
            return
        }
        guard let id = activeTargetInstanceID else { return }
        WebSessionManager.shared.goForward(instanceID: id)
    }

    @objc private func zoomInAction() {
        guard let id = activeTargetInstanceID else { return }
        WebSessionManager.shared.adjustZoom(instanceID: id, delta: 0.1)
    }

    @objc private func zoomOutAction() {
        guard let id = activeTargetInstanceID else { return }
        WebSessionManager.shared.adjustZoom(instanceID: id, delta: -0.1)
    }

    @objc private func zoomResetAction() {
        guard let id = activeTargetInstanceID else { return }
        WebSessionManager.shared.adjustZoom(instanceID: id, delta: 0, reset: true)
    }

    @objc private func toggleCompactSidebarAction() {
        WorkspaceStore.shared.toggleSidebarCompactMode()
    }

    @objc private func toggleLeftSidebarAction() {
        WorkspaceStore.shared.toggleLeftSidebar()
    }

    @objc private func switchAccountShortcut(_ sender: NSMenuItem) {
        WorkspaceStore.shared.selectInstanceByIndex(sender.tag)
    }

    @objc private func checkForGitHubUpdatesAction() {
        openOrFocusMainWindow()
        UpdateCheckerService.shared.checkForUpdatesManually()
    }

    @objc private func openGitHubRepoAction() {
        UpdateCheckerService.shared.openGitHubRepoPage()
    }
}
