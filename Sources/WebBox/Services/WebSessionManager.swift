import Foundation
import AppKit
import WebKit
import UserNotifications

// MARK: - Weak Script Message Wrapper (Prevents WKUserContentController Retain Cycles)

private final class WeakScriptMessageBridge: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(target: WKScriptMessageHandler) {
        self.target = target
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Custom WKWebView with Smart Link Context Menu

final class WebBoxWKWebView: WKWebView {
    var ownerInstanceID: UUID?
    var lastContextLinkURL: URL?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        guard let linkURL = lastContextLinkURL,
              let scheme = linkURL.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let instanceID = ownerInstanceID else {
            return
        }

        let cleanURL = LinkRouter.unwrapRedirectURL(linkURL)

        // Remove default broken "Open Link in New Window" if present
        menu.items.removeAll { item in
            let idRaw = item.identifier?.rawValue ?? ""
            return idRaw.contains("OpenLinkInNewWindow") || idRaw.contains("DownloadLinkedFile") && false
        }

        var insertIndex = 0

        let openInAppItem = NSMenuItem(
            title: "Mở liên kết trong Trình duyệt WebBox",
            action: #selector(handleOpenLinkInApp(_:)),
            keyEquivalent: ""
        )
        openInAppItem.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
        openInAppItem.target = self
        openInAppItem.representedObject = (cleanURL, instanceID)
        menu.insertItem(openInAppItem, at: insertIndex)
        insertIndex += 1

        let defaultBrowserName = LinkRouter.defaultSystemBrowserName()
        let openExternalItem = NSMenuItem(
            title: "Mở bằng Trình duyệt ngoài (\(defaultBrowserName))",
            action: #selector(handleOpenLinkExternalDefault(_:)),
            keyEquivalent: ""
        )
        openExternalItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
        openExternalItem.target = self
        openExternalItem.representedObject = (cleanURL, instanceID)
        menu.insertItem(openExternalItem, at: insertIndex)
        insertIndex += 1

        let browsers = LinkRouter.installedExternalBrowsers()
        if browsers.count > 1 {
            let pickSubmenuItem = NSMenuItem(title: "Mở liên kết bằng trình duyệt khác", action: nil, keyEquivalent: "")
            pickSubmenuItem.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
            let sub = NSMenu()
            for browser in browsers {
                let bItem = NSMenuItem(
                    title: browser.name,
                    action: #selector(handleOpenLinkSpecificBrowser(_:)),
                    keyEquivalent: ""
                )
                bItem.target = self
                bItem.representedObject = (cleanURL, browser.bundleIdentifier)
                let icon = NSWorkspace.shared.icon(forFile: browser.appURL.path)
                icon.size = NSSize(width: 16, height: 16)
                bItem.image = icon
                sub.addItem(bItem)
            }
            pickSubmenuItem.submenu = sub
            menu.insertItem(pickSubmenuItem, at: insertIndex)
            insertIndex += 1
        }

        let copyCleanItem = NSMenuItem(
            title: "Sao chép liên kết sạch",
            action: #selector(handleCopyCleanLink(_:)),
            keyEquivalent: ""
        )
        copyCleanItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyCleanItem.target = self
        copyCleanItem.representedObject = cleanURL
        menu.insertItem(copyCleanItem, at: insertIndex)
        insertIndex += 1

        menu.insertItem(.separator(), at: insertIndex)
        lastContextLinkURL = nil
    }

    @objc private func handleOpenLinkInApp(_ sender: NSMenuItem) {
        guard let (url, instanceID) = sender.representedObject as? (URL, UUID) else { return }
        Task { @MainActor in
            WorkspaceStore.shared.openLinkInAppBrowser(url, for: instanceID)
        }
    }

    @objc private func handleOpenLinkExternalDefault(_ sender: NSMenuItem) {
        guard let (url, instanceID) = sender.representedObject as? (URL, UUID) else { return }
        Task { @MainActor in
            let preferred = WorkspaceStore.shared.instance(for: instanceID)?.preferredExternalBrowserBundleID
            LinkRouter.openInExternalBrowser(url, preferredBrowserBundleID: preferred)
        }
    }

    @objc private func handleOpenLinkSpecificBrowser(_ sender: NSMenuItem) {
        guard let (url, bundleID) = sender.representedObject as? (URL, String) else { return }
        Task { @MainActor in
            LinkRouter.openInExternalBrowser(url, preferredBrowserBundleID: bundleID)
        }
    }

    @objc private func handleCopyCleanLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        Task { @MainActor in
            WorkspaceStore.shared.showToast("Đã sao chép liên kết vào Clipboard")
        }
    }
}

// MARK: - Runtime State Snapshot Per Instance

struct InstanceRuntimeState {
    var currentURL: URL?
    var pageTitle: String = ""
    var isLoading: Bool = false
    var estimatedProgress: Double = 0
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var unreadCount: Int = 0
    var hasUnreadDot: Bool = false
    var isHibernated: Bool = false
    var isDetachedInWindow: Bool = false
}

// MARK: - Deferred Popup Catcher (Catches JS `const w = window.open(); w.location = url`)

@MainActor
private final class DeferredPopupCatcher: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let sourceInstanceID: UUID
    let webView: WKWebView
    var onResolved: ((UUID) -> Void)?

    init(sourceInstanceID: UUID, configuration: WKWebViewConfiguration) {
        self.sourceInstanceID = sourceInstanceID
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100), configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let abs = url.absoluteString
        if abs == "about:blank" || abs.isEmpty {
            decisionHandler(.allow)
            return
        }

        if LinkRouter.isAuthenticationFlowURL(url) {
            // Promote this exact webView into a visible OAuth window so window.opener stays intact!
            decisionHandler(.allow)
            WebSessionManager.shared.promoteWebViewToAuthWindow(webView, title: url.host ?? "Đăng nhập")
            onResolved?(id)
            return
        }

        decisionHandler(.cancel)
        WorkspaceStore.shared.handleClickedLink(url, from: sourceInstanceID)
        onResolved?(id)
    }

    func webViewDidClose(_ webView: WKWebView) {
        onResolved?(id)
    }
}

// MARK: - Auxiliary OAuth Popup Window Controller

@MainActor
private final class AuthPopupWindow: NSObject, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate {
    let id = UUID()
    let window: NSWindow
    let webView: WKWebView
    var onClosed: ((UUID) -> Void)?

    init(webView: WKWebView, title: String) {
        self.webView = webView
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        super.init()

        webView.frame = win.contentView?.bounds ?? .zero
        webView.autoresizingMask = [.width, .height]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        win.contentView?.addSubview(webView)
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
    }

    func webViewDidClose(_ webView: WKWebView) {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?(id)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let t = webView.title, !t.isEmpty {
            window.title = t
        }
    }
}

// MARK: - WebSessionManager

@MainActor
final class WebSessionManager: NSObject, ObservableObject {
    static let shared = WebSessionManager()

    @Published private(set) var runtimeStates: [UUID: InstanceRuntimeState] = [:]
    @Published var downloads: [DownloadTaskItem] = []

    private var instanceControllers: [UUID: InstanceWebController] = [:]
    private var inAppTabControllers: [UUID: InAppTabWebController] = [:]
    private var detachedWindows: [UUID: DetachedInstanceWindow] = [:]
    private var authWindows: [UUID: AuthPopupWindow] = [:]
    private var deferredCatchers: [UUID: DeferredPopupCatcher] = [:]
    private var activeDownloads: [UUID: DownloadTracker] = [:]

    private override init() {
        super.init()
        requestNotificationAuthorizationIfNeeded()
    }

    // MARK: - Notification Authorization & Delivery

    func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func postNativeNotification(title: String, body: String, instance: WebAppInstance) {
        guard !WorkspaceStore.shared.preferences.globalDoNotDisturb,
              !instance.notificationsMuted else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(instance.displayTitle) — \(title)"
        content.body = body
        content.sound = .default
        content.userInfo = ["instanceID": instance.id.uuidString]

        let req = UNNotificationRequest(
            identifier: "webbox.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    func refreshDockBadge() {
        let totalUnread = runtimeStates.values.reduce(0) { $0 + $1.unreadCount }
        let anyDot = runtimeStates.values.contains { $0.hasUnreadDot }
        if totalUnread > 0 {
            NSApp.dockTile.badgeLabel = totalUnread > 99 ? "99+" : "\(totalUnread)"
        } else if anyDot {
            NSApp.dockTile.badgeLabel = "•"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    // MARK: - Instance WebView Access & Lifecycle

    func state(for instanceID: UUID) -> InstanceRuntimeState {
        runtimeStates[instanceID] ?? InstanceRuntimeState()
    }

    func webView(for instance: WebAppInstance) -> WebBoxWKWebView {
        if let existing = instanceControllers[instance.id] {
            if runtimeStates[instance.id]?.isHibernated == true {
                runtimeStates[instance.id]?.isHibernated = false
            }
            return existing.webView
        }
        let controller = InstanceWebController(instance: instance, manager: self)
        instanceControllers[instance.id] = controller
        var initial = runtimeStates[instance.id] ?? InstanceRuntimeState()
        initial.isHibernated = false
        initial.currentURL = instance.baseURL
        runtimeStates[instance.id] = initial
        controller.loadInitialPage()
        return controller.webView
    }

    func reload(instanceID: UUID) {
        if let ctrl = instanceControllers[instanceID] {
            ctrl.webView.reload()
        } else if let inst = WorkspaceStore.shared.instance(for: instanceID) {
            _ = webView(for: inst)
        }
    }

    func goHome(instanceID: UUID) {
        guard let inst = WorkspaceStore.shared.instance(for: instanceID) else { return }
        let wv = webView(for: inst)
        wv.load(URLRequest(url: inst.baseURL))
    }

    func goBack(instanceID: UUID) {
        instanceControllers[instanceID]?.webView.goBack()
    }

    func goForward(instanceID: UUID) {
        instanceControllers[instanceID]?.webView.goForward()
    }

    func adjustZoom(instanceID: UUID, delta: Double, reset: Bool = false) {
        guard var inst = WorkspaceStore.shared.instance(for: instanceID) else { return }
        if reset {
            inst.pageZoom = 1.0
        } else {
            inst.pageZoom = min(2.5, max(0.5, (inst.pageZoom + delta * 100.0 / 100.0)))
        }
        WorkspaceStore.shared.updateInstance(inst)
        instanceControllers[instanceID]?.webView.pageZoom = inst.pageZoom
        WorkspaceStore.shared.showToast("Thu phóng: \(Int(round(inst.pageZoom * 100)))%")
    }

    func findInActiveWebView(_ query: String, forward: Bool = true) {
        guard let activeID = WorkspaceStore.shared.activeInstanceID,
              let wv = instanceControllers[activeID]?.webView else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = false
        config.wraps = true
        wv.find(trimmed, configuration: config) { _ in }
    }

    /// Unloads the WKWebView from RAM while keeping 100% of cookies/IndexedDB on disk!
    func hibernateInstance(_ instanceID: UUID) {
        guard detachedWindows[instanceID] == nil else {
            WorkspaceStore.shared.showToast("Hãy đóng cửa sổ tách rời trước khi ngủ đông tài khoản.")
            return
        }
        if let ctrl = instanceControllers.removeValue(forKey: instanceID) {
            ctrl.teardown()
        }
        var st = runtimeStates[instanceID] ?? InstanceRuntimeState()
        st.isHibernated = true
        st.isLoading = false
        runtimeStates[instanceID] = st
        refreshDockBadge()
        WorkspaceStore.shared.showToast("Đã chuyển tài khoản sang chế độ Ngủ đông (Giải phóng RAM)")
    }

    func wakeInstance(_ instance: WebAppInstance) {
        runtimeStates[instance.id]?.isHibernated = false
        _ = webView(for: instance)
    }

    func clearSessionData(for instance: WebAppInstance) async {
        let store = WKWebsiteDataStore(forIdentifier: instance.profileID)
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: allTypes)
        await store.removeData(ofTypes: allTypes, for: records)
        if let ctrl = instanceControllers.removeValue(forKey: instance.id) {
            ctrl.teardown()
        }
        _ = webView(for: instance)
        WorkspaceStore.shared.showToast("Đã xoá sạch phiên đăng nhập & bộ nhớ đệm của \(instance.displayTitle)")
    }

    func applyUpdatedSettings(from old: WebAppInstance, to updated: WebAppInstance) {
        guard let ctrl = instanceControllers[updated.id] else { return }
        if old.profileID != updated.profileID || old.userAgentPreset != updated.userAgentPreset || old.customUserAgent != updated.customUserAgent {
            // Recreate WebView with updated profile data store or user-agent
            ctrl.teardown()
            instanceControllers.removeValue(forKey: updated.id)
            _ = webView(for: updated)
            return
        }
        ctrl.instance = updated
        ctrl.webView.pageZoom = updated.pageZoom
        if old.baseURLString != updated.baseURLString {
            ctrl.webView.load(URLRequest(url: updated.baseURL))
        }
    }

    func destroyInstanceSession(instanceID: UUID, profileID: UUID?) {
        detachedWindows[instanceID]?.window.close()
        detachedWindows.removeValue(forKey: instanceID)
        if let ctrl = instanceControllers.removeValue(forKey: instanceID) {
            ctrl.teardown()
        }
        runtimeStates.removeValue(forKey: instanceID)
        refreshDockBadge()

        if let profileID {
            Task { @MainActor in
                try? await WKWebsiteDataStore.remove(forIdentifier: profileID)
            }
        }
    }

    // MARK: - Detached Dedicated Window Per Account

    func openDetachedWindow(for instance: WebAppInstance) {
        if let existing = detachedWindows[instance.id] {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let wv = webView(for: instance)
        wv.removeFromSuperview()

        let detached = DetachedInstanceWindow(instance: instance, webView: wv) { [weak self] closedID in
            guard let self else { return }
            self.detachedWindows.removeValue(forKey: closedID)
            self.runtimeStates[closedID]?.isDetachedInWindow = false
            self.objectWillChange.send()
        }
        detachedWindows[instance.id] = detached
        var st = runtimeStates[instance.id] ?? InstanceRuntimeState()
        st.isDetachedInWindow = true
        runtimeStates[instance.id] = st
        objectWillChange.send()
    }

    func reattachWindowToWorkspace(instanceID: UUID) {
        detachedWindows[instanceID]?.window.close()
    }

    func focusDetachedWindow(instanceID: UUID) {
        detachedWindows[instanceID]?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - In-App Browser Tab WebViews

    func inAppWebView(for tab: InAppBrowserTab) -> WebBoxWKWebView {
        if let existing = inAppTabControllers[tab.id] {
            return existing.webView
        }
        let ctrl = InAppTabWebController(tab: tab, manager: self)
        inAppTabControllers[tab.id] = ctrl
        ctrl.loadInitial()
        return ctrl.webView
    }

    func navigateInAppTab(tabID: UUID, to url: URL) {
        inAppTabControllers[tabID]?.webView.load(URLRequest(url: url))
    }

    func reloadInAppTab(tabID: UUID) {
        inAppTabControllers[tabID]?.webView.reload()
    }

    func goBackInAppTab(tabID: UUID) {
        inAppTabControllers[tabID]?.webView.goBack()
    }

    func goForwardInAppTab(tabID: UUID) {
        inAppTabControllers[tabID]?.webView.goForward()
    }

    func destroyInAppTabWebView(tabID: UUID) {
        if let ctrl = inAppTabControllers.removeValue(forKey: tabID) {
            ctrl.teardown()
        }
    }

    // MARK: - OAuth Popup & Deferred Catcher Helpers

    fileprivate func registerDeferredCatcher(sourceInstanceID: UUID, configuration: WKWebViewConfiguration) -> WKWebView {
        let catcher = DeferredPopupCatcher(sourceInstanceID: sourceInstanceID, configuration: configuration)
        catcher.onResolved = { [weak self] id in
            self?.deferredCatchers.removeValue(forKey: id)
        }
        deferredCatchers[catcher.id] = catcher
        return catcher.webView
    }

    fileprivate func promoteWebViewToAuthWindow(_ webView: WKWebView, title: String) {
        let popup = AuthPopupWindow(webView: webView, title: title)
        popup.onClosed = { [weak self] id in
            self?.authWindows.removeValue(forKey: id)
        }
        authWindows[popup.id] = popup
    }

    fileprivate func createAuthPopupWebView(configuration: WKWebViewConfiguration, title: String) -> WKWebView {
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 540, height: 680), configuration: configuration)
        promoteWebViewToAuthWindow(wv, title: title)
        return wv
    }

    // MARK: - Download Registration

    fileprivate func attachDownload(_ download: WKDownload, sourceTitle: String) {
        let tracker = DownloadTracker(download: download, sourceTitle: sourceTitle, manager: self)
        activeDownloads[tracker.id] = tracker
        download.delegate = tracker
    }

    fileprivate func upsertDownloadItem(_ item: DownloadTaskItem, finished: Bool = false) {
        if let idx = downloads.firstIndex(where: { $0.id == item.id }) {
            downloads[idx] = item
        } else {
            downloads.insert(item, at: 0)
        }
        if finished {
            activeDownloads.removeValue(forKey: item.id)
        }
    }

    fileprivate func updateRuntimeState(for id: UUID, mutate: (inout InstanceRuntimeState) -> Void) {
        var current = runtimeStates[id] ?? InstanceRuntimeState()
        mutate(&current)
        runtimeStates[id] = current
        refreshDockBadge()
    }
}

// MARK: - Per-Instance WKWebView Controller

@MainActor
private final class InstanceWebController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var instance: WebAppInstance
    weak var manager: WebSessionManager?
    let webView: WebBoxWKWebView
    private var observations: [NSKeyValueObservation] = []

    private static let bridgeHandlerName = "webboxBridge"

    init(instance: WebAppInstance, manager: WebSessionManager) {
        self.instance = instance
        self.manager = manager

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: instance.profileID)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if WorkspaceStore.shared.preferences.enableDeveloperExtras {
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

        let userContent = WKUserContentController()
        config.userContentController = userContent

        let wv = WebBoxWKWebView(frame: .zero, configuration: config)
        wv.ownerInstanceID = instance.id
        wv.customUserAgent = instance.resolvedUserAgent
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        wv.pageZoom = instance.pageZoom
        if #available(macOS 13.3, *) {
            wv.isInspectable = WorkspaceStore.shared.preferences.enableDeveloperExtras
        }
        self.webView = wv

        super.init()

        userContent.add(WeakScriptMessageBridge(target: self), name: Self.bridgeHandlerName)
        userContent.addUserScript(Self.makeBridgeScript(customCSS: instance.customCSS))

        wv.navigationDelegate = self
        wv.uiDelegate = self
        installObservers()
    }

    func loadInitialPage() {
        webView.load(URLRequest(url: instance.baseURL))
    }

    func teardown() {
        observations.removeAll()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeHandlerName)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    private func installObservers() {
        observations.append(
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.manager?.updateRuntimeState(for: self.instance.id) {
                        $0.isLoading = wv.isLoading
                    }
                }
            }
        )
        observations.append(
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.manager?.updateRuntimeState(for: self.instance.id) {
                        $0.estimatedProgress = wv.estimatedProgress
                    }
                }
            }
        )
        observations.append(
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.manager?.updateRuntimeState(for: self.instance.id) {
                        $0.currentURL = wv.url
                        $0.canGoBack = wv.canGoBack
                        $0.canGoForward = wv.canGoForward
                    }
                }
            }
        )
        observations.append(
            webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let title = wv.title ?? ""
                    self.applyParsedUnreadBadge(from: title)
                }
            }
        )
    }

    private func applyParsedUnreadBadge(from title: String) {
        // Matches "(3) Zalo", "[12] Messenger", "(99+) Facebook"
        var count = 0
        if let range = title.range(of: #"^\s*[\(\[](\d+)\+?[\)\]]"#, options: .regularExpression) {
            let sub = String(title[range])
            let digits = sub.filter(\.isNumber)
            count = Int(digits) ?? 0
        }
        let hasDot = count == 0 && (title.hasPrefix("•") || title.hasPrefix("●") || title.contains("tin nhắn mới"))
        manager?.updateRuntimeState(for: instance.id) {
            $0.pageTitle = title
            $0.unreadCount = count
            if !hasDot && count == 0 {
                $0.hasUnreadDot = false
            } else if hasDot {
                $0.hasUnreadDot = true
            }
        }
    }

    // MARK: - Injected JS Bridge (Modifier Clicks, Context Link, Notifications & Custom CSS)

    private static func makeBridgeScript(customCSS: String) -> WKUserScript {
        let escapedCSS = customCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let source = """
        (function() {
            if (window.__webboxBridgeInstalled) return;
            window.__webboxBridgeInstalled = true;

            function post(payload) {
                try {
                    window.webkit.messageHandlers.webboxBridge.postMessage(payload);
                } catch (_) {}
            }

            function findAnchor(el) {
                while (el && el !== document.body) {
                    if (el.tagName && el.tagName.toLowerCase() === 'a' && el.href) {
                        return el;
                    }
                    el = el.parentElement;
                }
                return null;
            }

            // Capture right-click link URL for native macOS Context Menu
            document.addEventListener('contextmenu', function(e) {
                const a = findAnchor(e.target);
                if (a && /^https?:\\/\\//i.test(a.href)) {
                    post({ type: 'contextLink', url: a.href });
                }
            }, true);

            // Capture Cmd+Click (In-App Browser), Option+Click (External Browser), and Middle-Click
            document.addEventListener('click', function(e) {
                const a = findAnchor(e.target);
                if (!a || !/^https?:\\/\\//i.test(a.href)) return;
                if (e.altKey) {
                    e.preventDefault();
                    e.stopPropagation();
                    post({ type: 'openLink', url: a.href, override: 'external' });
                } else if (e.metaKey) {
                    e.preventDefault();
                    e.stopPropagation();
                    post({ type: 'openLink', url: a.href, override: 'inApp' });
                }
            }, true);

            document.addEventListener('auxclick', function(e) {
                if (e.button !== 1) return;
                const a = findAnchor(e.target);
                if (a && /^https?:\\/\\//i.test(a.href)) {
                    e.preventDefault();
                    e.stopPropagation();
                    post({ type: 'openLink', url: a.href, override: 'inApp' });
                }
            }, true);

            // Bridge Web Notification API to macOS UNUserNotificationCenter
            const NativeNotification = function(title, options) {
                const opts = options || {};
                post({
                    type: 'webNotification',
                    title: String(title || ''),
                    body: String(opts.body || '')
                });
                this.close = function() {};
            };
            NativeNotification.permission = 'granted';
            NativeNotification.requestPermission = function(cb) {
                if (typeof cb === 'function') cb('granted');
                return Promise.resolve('granted');
            };
            window.Notification = NativeNotification;

            // Inject optional custom CSS
            const cssText = `\(escapedCSS)`;
            if (cssText.trim().length > 0) {
                document.addEventListener('DOMContentLoaded', function() {
                    const style = document.createElement('style');
                    style.textContent = cssText;
                    document.head.appendChild(style);
                });
            }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "contextLink":
            if let urlStr = body["url"] as? String, let url = URL(string: urlStr) {
                webView.lastContextLinkURL = url
            }
        case "openLink":
            guard let urlStr = body["url"] as? String, let url = URL(string: urlStr) else { return }
            let overrideStr = body["override"] as? String
            let mod: ClickModifierOverride = overrideStr == "external" ? .forceExternal : .forceInApp
            WorkspaceStore.shared.handleClickedLink(url, from: instance.id, modifierOverride: mod)
        case "webNotification":
            let title = (body["title"] as? String) ?? instance.name
            let text = (body["body"] as? String) ?? "Bạn có thông báo mới"
            manager?.postNativeNotification(title: title, body: text, instance: instance)
            if WorkspaceStore.shared.activeInstanceID != instance.id {
                manager?.updateRuntimeState(for: instance.id) {
                    if $0.unreadCount == 0 {
                        $0.hasUnreadDot = true
                    }
                }
            }
        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate (Link Interception & Downloads)

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow, preferences)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "http" && scheme != "https" && scheme != "about" && scheme != "blob" && scheme != "data" {
            // mailto:, tel:, zalo:// etc. -> let macOS handle if user clicked
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel, preferences)
            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }

        // Intercept external links clicked in the main frame so the chat app never navigates away!
        if navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.navigationType == .linkActivated,
           (scheme == "http" || scheme == "https") {
            let flags = navigationAction.modifierFlags
            if flags.contains(.option) {
                decisionHandler(.cancel, preferences)
                WorkspaceStore.shared.handleClickedLink(url, from: instance.id, modifierOverride: .forceExternal)
                return
            }
            if flags.contains(.command) {
                decisionHandler(.cancel, preferences)
                WorkspaceStore.shared.handleClickedLink(url, from: instance.id, modifierOverride: .forceInApp)
                return
            }

            if !LinkRouter.isInternalAppURL(url, for: instance) {
                decisionHandler(.cancel, preferences)
                WorkspaceStore.shared.handleClickedLink(url, from: instance.id)
                return
            }
        }

        decisionHandler(.allow, preferences)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        manager?.attachDownload(download, sourceTitle: instance.displayTitle)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        manager?.attachDownload(download, sourceTitle: instance.displayTitle)
    }

    // MARK: - WKUIDelegate (target="_blank", window.open, File Upload, Media, Dialogs)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            let abs = url.absoluteString
            if abs.isEmpty || abs == "about:blank" {
                return manager?.registerDeferredCatcher(
                    sourceInstanceID: instance.id,
                    configuration: configuration
                )
            }

            if LinkRouter.isAuthenticationFlowURL(url) {
                return manager?.createAuthPopupWebView(
                    configuration: configuration,
                    title: url.host ?? "Đăng nhập \(instance.name)"
                )
            }

            // Message link clicked via target="_blank" or window.open(url)!
            let flags = NSEvent.modifierFlags
            let mod: ClickModifierOverride
            if flags.contains(.option) {
                mod = .forceExternal
            } else if flags.contains(.command) {
                mod = .forceInApp
            } else {
                mod = .none
            }
            WorkspaceStore.shared.handleClickedLink(url, from: instance.id, modifierOverride: mod)
            return nil
        }

        // Deferred JS popup (`const win = window.open('', '_blank'); win.location = ...`)
        return manager?.registerDeferredCatcher(
            sourceInstanceID: instance.id,
            configuration: configuration
        )
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.prompt = "Chọn tệp đính kèm"

        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            let response = panel.runModal()
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = instance.displayTitle
        alert.informativeText = message
        alert.addButton(withTitle: "Đóng")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = instance.displayTitle
        alert.informativeText = message
        alert.addButton(withTitle: "Đồng ý")
        alert.addButton(withTitle: "Huỷ")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = instance.displayTitle
        alert.informativeText = prompt
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Huỷ")
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
    }
}

// MARK: - In-App Browser Tab Controller

@MainActor
private final class InAppTabWebController: NSObject, WKNavigationDelegate, WKUIDelegate {
    let tab: InAppBrowserTab
    weak var manager: WebSessionManager?
    let webView: WebBoxWKWebView
    private var observations: [NSKeyValueObservation] = []

    init(tab: InAppBrowserTab, manager: WebSessionManager) {
        self.tab = tab
        self.manager = manager

        let config = WKWebViewConfiguration()
        if let profileID = tab.profileID {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: profileID)
        } else {
            config.websiteDataStore = .nonPersistent()
        }
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let wv = WebBoxWKWebView(frame: .zero, configuration: config)
        wv.ownerInstanceID = tab.ownerInstanceID
        wv.customUserAgent = UserAgentPreset.safariMac.resolvedUserAgent(customValue: "")
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        if #available(macOS 13.3, *) {
            wv.isInspectable = WorkspaceStore.shared.preferences.enableDeveloperExtras
        }
        self.webView = wv

        super.init()
        wv.navigationDelegate = self
        wv.uiDelegate = self
        installObservers()
    }

    func loadInitial() {
        webView.load(URLRequest(url: tab.currentURL))
    }

    func teardown() {
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    private func installObservers() {
        observations.append(
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    WorkspaceStore.shared.updateInAppTabState(
                        tabID: self.tab.id,
                        url: wv.url,
                        title: wv.title,
                        isLoading: wv.isLoading,
                        progress: wv.estimatedProgress,
                        canGoBack: wv.canGoBack,
                        canGoForward: wv.canGoForward
                    )
                }
            }
        )
        observations.append(
            webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    WorkspaceStore.shared.updateInAppTabState(
                        tabID: self.tab.id,
                        url: wv.url,
                        title: wv.title,
                        isLoading: nil,
                        progress: nil,
                        canGoBack: wv.canGoBack,
                        canGoForward: wv.canGoForward
                    )
                }
            }
        )
        observations.append(
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    WorkspaceStore.shared.updateInAppTabState(
                        tabID: self.tab.id,
                        url: wv.url,
                        title: wv.title,
                        isLoading: wv.isLoading,
                        progress: wv.estimatedProgress,
                        canGoBack: wv.canGoBack,
                        canGoForward: wv.canGoForward
                    )
                }
            }
        )
        observations.append(
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    WorkspaceStore.shared.updateInAppTabState(
                        tabID: self.tab.id,
                        url: nil,
                        title: nil,
                        isLoading: wv.isLoading,
                        progress: wv.estimatedProgress,
                        canGoBack: nil,
                        canGoForward: nil
                    )
                }
            }
        )
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if LinkRouter.isAuthenticationFlowURL(url) {
                return manager?.createAuthPopupWebView(configuration: configuration, title: url.host ?? "Đăng nhập")
            }
            // Open new-tab links inside In-App Browser as another In-App Tab!
            WorkspaceStore.shared.openLinkInAppBrowser(LinkRouter.unwrapRedirectURL(url), for: tab.ownerInstanceID)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        manager?.attachDownload(download, sourceTitle: "Trình duyệt WebBox")
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }
}

// MARK: - Detached Instance Window

@MainActor
private final class DetachedInstanceWindow: NSObject, NSWindowDelegate {
    let instanceID: UUID
    let window: NSWindow
    let webView: WebBoxWKWebView
    let onClose: (UUID) -> Void

    init(instance: WebAppInstance, webView: WebBoxWKWebView, onClose: @escaping (UUID) -> Void) {
        self.instanceID = instance.id
        self.webView = webView
        self.onClose = onClose

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = instance.displayTitle
        win.minSize = NSSize(width: 480, height: 420)
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        super.init()

        let container = NSView(frame: win.contentView?.bounds ?? .zero)
        container.autoresizingMask = [.width, .height]
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        win.contentView = container
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        webView.removeFromSuperview()
        onClose(instanceID)
    }
}

// MARK: - WKDownloadDelegate Tracker

@MainActor
private final class DownloadTracker: NSObject, WKDownloadDelegate {
    let id = UUID()
    let sourceTitle: String
    weak var manager: WebSessionManager?
    private var filename: String = "Tep_tai_xuong"
    private var destinationURL: URL?
    private let startedAt = Date()
    private var progressObservation: NSKeyValueObservation?

    init(download: WKDownload, sourceTitle: String, manager: WebSessionManager) {
        self.sourceTitle = sourceTitle
        self.manager = manager
        super.init()

        progressObservation = download.progress.observe(\.completedUnitCount, options: [.new]) { [weak self] prog, _ in
            let completed = prog.completedUnitCount
            let total = prog.totalUnitCount
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.manager?.upsertDownloadItem(
                    DownloadTaskItem(
                        id: self.id,
                        sourceInstanceTitle: self.sourceTitle,
                        filename: self.filename,
                        destinationURL: self.destinationURL,
                        bytesReceived: completed,
                        expectedBytes: total,
                        state: .downloading,
                        startedAt: self.startedAt
                    )
                )
            }
        }
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let safeDestination = Self.uniqueFileURL(in: downloadsDir, suggestedName: suggestedFilename)
        self.filename = safeDestination.lastPathComponent
        self.destinationURL = safeDestination

        manager?.upsertDownloadItem(
            DownloadTaskItem(
                id: id,
                sourceInstanceTitle: sourceTitle,
                filename: filename,
                destinationURL: safeDestination,
                bytesReceived: 0,
                expectedBytes: response.expectedContentLength,
                state: .downloading,
                startedAt: startedAt
            )
        )
        completionHandler(safeDestination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        progressObservation = nil
        manager?.upsertDownloadItem(
            DownloadTaskItem(
                id: id,
                sourceInstanceTitle: sourceTitle,
                filename: filename,
                destinationURL: destinationURL,
                bytesReceived: 1,
                expectedBytes: 1,
                state: .completed,
                startedAt: startedAt
            ),
            finished: true
        )
        WorkspaceStore.shared.showToast("Đã tải xong: \(filename)")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        progressObservation = nil
        manager?.upsertDownloadItem(
            DownloadTaskItem(
                id: id,
                sourceInstanceTitle: sourceTitle,
                filename: filename,
                destinationURL: destinationURL,
                bytesReceived: 0,
                expectedBytes: 0,
                state: .failed(error.localizedDescription),
                startedAt: startedAt
            ),
            finished: true
        )
    }

    private static func uniqueFileURL(in directory: URL, suggestedName: String) -> URL {
        let baseURL = directory.appendingPathComponent(suggestedName)
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            return baseURL
        }
        let ext = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        for idx in 1...999 {
            let candidateName = ext.isEmpty ? "\(stem) (\(idx))" : "\(stem) (\(idx)).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        return directory.appendingPathComponent("\(UUID().uuidString)_\(suggestedName)")
    }
}
