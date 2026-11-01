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

// MARK: - Custom WKWebView with Native Image, Media & Smart Link Context Menu

final class WebBoxWKWebView: WKWebView {
    var ownerInstanceID: UUID?
    var sourceTitleOverride: String?
    var lastContextHit: ContextMenuHitSnapshot?
    private var activeSharingPicker: NSSharingServicePicker?

    private var resolvedSourceTitle: String {
        if let sourceTitleOverride, !sourceTitleOverride.isEmpty {
            return sourceTitleOverride
        }
        if let id = ownerInstanceID,
           let inst = WorkspaceStore.shared.instance(for: id) {
            return inst.displayTitle
        }
        return "WebBox"
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        let viewPoint = convert(event.locationInWindow, from: nil)
        let zoom = max(0.25, pageZoom)
        let topDownY = isFlipped ? viewPoint.y : (bounds.height - viewPoint.y)
        let domPoint = CGPoint(x: viewPoint.x / zoom, y: topDownY / zoom)

        let hit = (lastContextHit?.isRecent == true) ? lastContextHit : nil
        lastContextHit = nil

        let makePayload: (String?) -> ContextMenuActionPayload = { [weak self] browserID in
            ContextMenuActionPayload(
                viewPoint: viewPoint,
                domPoint: domPoint,
                linkURL: hit?.linkURL,
                linkDownloadFilename: hit?.linkDownloadFilename ?? "",
                fallbackImageURLString: hit?.imageURLString ?? "",
                fallbackMediaURLString: hit?.mediaURLString ?? "",
                frameInfo: hit?.frameInfo,
                instanceID: self?.ownerInstanceID,
                sourceTitle: self?.resolvedSourceTitle ?? "WebBox",
                browserBundleID: browserID
            )
        }

        // 1. Image Context Menu (Native WebKit items + Overlay-piercing JS detection)
        let hasNativeImageItems = menu.items.contains { item in
            let id = item.identifier?.rawValue ?? ""
            return id.contains("OpenImageInNewWindow")
                || id.contains("DownloadImage")
                || id.contains("CopyImage")
                || id.contains("CopySubject")
        }
        let hasJSImageHit = (hit?.hasImage == true)

        if hasNativeImageItems {
            rewireNativeImageMenuItems(in: menu, payloadFactory: makePayload)
        } else if hasJSImageHit {
            insertCustomImageMenuGroup(into: menu, at: 0, payloadFactory: makePayload)
        }

        // 2. Rewire WebKit's broken DownloadLinkedFile & Media context menu items
        for item in menu.items {
            let id = item.identifier?.rawValue ?? ""
            if id.contains("DownloadLinkedFile") {
                item.title = "Tải về tệp được liên kết"
                item.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)
                item.target = self
                item.action = #selector(handleDownloadLinkedFile(_:))
                item.representedObject = makePayload(nil)
                item.isEnabled = true
            } else if id.contains("DownloadMedia") || id.contains("DownloadVideo") || id.contains("DownloadAudio") {
                item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
                item.target = self
                item.action = #selector(handleDownloadMedia(_:))
                item.representedObject = makePayload(nil)
                item.isEnabled = true
            } else if id.contains("OpenMediaInNewWindow") || id.contains("OpenVideoInNewWindow") {
                item.image = NSImage(systemSymbolName: "play.rectangle.on.rectangle", accessibilityDescription: nil)
                item.target = self
                item.action = #selector(handleOpenMediaInNewWindow(_:))
                item.representedObject = makePayload(nil)
                item.isEnabled = true
            }
        }

        // 3. Smart Link Routing Context Menu (<a href="http(s)://...">)
        if let rawLink = hit?.linkURL,
           let scheme = rawLink.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           let instanceID = ownerInstanceID {
            let cleanURL = LinkRouter.unwrapRedirectURL(rawLink)

            menu.items.removeAll { item in
                let idRaw = item.identifier?.rawValue ?? ""
                return idRaw.contains("OpenLinkInNewWindow")
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
                    bItem.image = LinkRouter.cachedIcon(for: browser, size: 16)
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

            let alreadyHasDownloadLink = menu.items.contains { ($0.identifier?.rawValue ?? "").contains("DownloadLinkedFile") }
            if !alreadyHasDownloadLink {
                let dlLinkItem = NSMenuItem(
                    title: "Tải về tệp được liên kết",
                    action: #selector(handleDownloadLinkedFile(_:)),
                    keyEquivalent: ""
                )
                dlLinkItem.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)
                dlLinkItem.target = self
                dlLinkItem.representedObject = makePayload(nil)
                menu.insertItem(dlLinkItem, at: insertIndex)
                insertIndex += 1
            }

            menu.insertItem(.separator(), at: insertIndex)
        }
    }

    private func rewireNativeImageMenuItems(
        in menu: NSMenu,
        payloadFactory: (String?) -> ContextMenuActionPayload
    ) {
        var foundCopySubject = false
        var foundShare = false
        var downloadIndex: Int? = nil
        var copyImageIndex: Int? = nil

        for (idx, item) in menu.items.enumerated() {
            let id = item.identifier?.rawValue ?? ""
            if id.contains("OpenImageInNewWindow") {
                item.title = "Mở hình ảnh trong cửa sổ mới"
                item.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
                item.target = self
                item.action = #selector(handleOpenImageInNewWindow(_:))
                item.representedObject = payloadFactory(nil)
                item.isEnabled = true
            } else if id.contains("DownloadImage") {
                item.title = "Tải về hình ảnh"
                item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
                item.target = self
                item.action = #selector(handleDownloadImage(_:))
                item.representedObject = payloadFactory(nil)
                item.isEnabled = true
                downloadIndex = idx
            } else if id.contains("CopyImage") {
                item.title = "Sao chép hình ảnh"
                item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
                item.target = self
                item.action = #selector(handleCopyImage(_:))
                item.representedObject = payloadFactory(nil)
                item.isEnabled = true
                copyImageIndex = idx
            } else if id.contains("CopySubject") {
                item.title = "Sao chép chủ thể"
                item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
                item.target = self
                item.action = #selector(handleCopySubject(_:))
                item.representedObject = payloadFactory(nil)
                item.isEnabled = true
                foundCopySubject = true
            } else if id.contains("ShareMenu") {
                item.submenu = nil
                item.title = "Chia sẻ..."
                item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
                item.target = self
                item.action = #selector(handleShareImage(_:))
                item.representedObject = payloadFactory(nil)
                item.isEnabled = true
                foundShare = true
            }
        }

        // Insert "Sao chép chủ thể" right below "Sao chép hình ảnh" if WebKit omitted it (e.g. on blob:/WebP)
        if !foundCopySubject, let cIdx = copyImageIndex {
            let subjectItem = NSMenuItem(
                title: "Sao chép chủ thể",
                action: #selector(handleCopySubject(_:)),
                keyEquivalent: ""
            )
            subjectItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            subjectItem.target = self
            subjectItem.representedObject = payloadFactory(nil)
            menu.insertItem(subjectItem, at: min(menu.items.count, cIdx + 1))
        }

        // Insert "Lưu hình ảnh thành..." right below "Tải về hình ảnh"
        if let dIdx = downloadIndex {
            let saveAsItem = NSMenuItem(
                title: "Lưu hình ảnh thành...",
                action: #selector(handleSaveImageAs(_:)),
                keyEquivalent: ""
            )
            saveAsItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
            saveAsItem.target = self
            saveAsItem.representedObject = payloadFactory(nil)
            menu.insertItem(saveAsItem, at: min(menu.items.count, dIdx + 1))
        }

        // Insert "Chia sẻ..." if WebKit omitted it
        if !foundShare {
            let shareItem = NSMenuItem(
                title: "Chia sẻ...",
                action: #selector(handleShareImage(_:)),
                keyEquivalent: ""
            )
            shareItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
            shareItem.target = self
            shareItem.representedObject = payloadFactory(nil)
            if let inspectIdx = menu.items.firstIndex(where: { ($0.identifier?.rawValue ?? "").contains("InspectElement") }) {
                let targetIdx = max(0, inspectIdx - (inspectIdx > 0 && menu.items[inspectIdx - 1].isSeparatorItem ? 1 : 0))
                menu.insertItem(.separator(), at: targetIdx)
                menu.insertItem(shareItem, at: targetIdx + 1)
            } else {
                menu.addItem(.separator())
                menu.addItem(shareItem)
            }
        }
    }

    private func insertCustomImageMenuGroup(
        into menu: NSMenu,
        at startIndex: Int,
        payloadFactory: (String?) -> ContextMenuActionPayload
    ) {
        var idx = min(startIndex, menu.items.count)

        let entries: [(String, String, Selector)] = [
            ("Mở hình ảnh trong cửa sổ mới", "macwindow.badge.plus", #selector(handleOpenImageInNewWindow(_:))),
            ("Tải về hình ảnh", "arrow.down.circle", #selector(handleDownloadImage(_:))),
            ("Lưu hình ảnh thành...", "folder.badge.plus", #selector(handleSaveImageAs(_:))),
            ("Sao chép hình ảnh", "doc.on.doc", #selector(handleCopyImage(_:))),
            ("Sao chép chủ thể", "sparkles", #selector(handleCopySubject(_:))),
            ("Chia sẻ...", "square.and.arrow.up", #selector(handleShareImage(_:)))
        ]

        for (title, symbol, action) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.target = self
            item.representedObject = payloadFactory(nil)
            menu.insertItem(item, at: idx)
            idx += 1
        }
        menu.insertItem(.separator(), at: idx)
    }

    // MARK: - Image & Media Context Menu Actions

    @objc private func handleOpenImageInNewWindow(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let extracted = await ContextMediaExtractor.extractImage(from: self, payload: payload) else {
                WorkspaceStore.shared.showToast("Không thể đọc dữ liệu hình ảnh từ trang này")
                return
            }
            WebSessionManager.shared.presentImagePreviewWindow(
                extracted: extracted,
                sourceTitle: payload.sourceTitle
            )
        }
    }

    @objc private func handleDownloadImage(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let extracted = await ContextMediaExtractor.extractImage(from: self, payload: payload) else {
                WorkspaceStore.shared.showToast("Không thể tải về hình ảnh này")
                return
            }
            _ = ContextMediaExtractor.saveDataToDownloads(
                extracted.rawData,
                suggestedFilename: extracted.suggestedFilename,
                sourceTitle: payload.sourceTitle,
                forceSavePanel: false,
                parentWindow: self.window
            )
        }
    }

    @objc private func handleSaveImageAs(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let extracted = await ContextMediaExtractor.extractImage(from: self, payload: payload) else {
                WorkspaceStore.shared.showToast("Không thể lưu hình ảnh này")
                return
            }
            _ = ContextMediaExtractor.saveDataToDownloads(
                extracted.rawData,
                suggestedFilename: extracted.suggestedFilename,
                sourceTitle: payload.sourceTitle,
                forceSavePanel: true,
                parentWindow: self.window
            )
        }
    }

    @objc private func handleCopyImage(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let extracted = await ContextMediaExtractor.extractImage(from: self, payload: payload) else {
                WorkspaceStore.shared.showToast("Không thể sao chép hình ảnh này")
                return
            }
            ContextMediaExtractor.copyImageToPasteboard(extracted.image, preferredPNGData: extracted.pngData)
            WorkspaceStore.shared.showToast("Đã sao chép hình ảnh vào Clipboard")
        }
    }

    @objc private func handleCopySubject(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let extracted = await ContextMediaExtractor.extractImage(from: self, payload: payload) else {
                WorkspaceStore.shared.showToast("Không thể đọc hình ảnh để tách chủ thể")
                return
            }
            WorkspaceStore.shared.showToast("Đang tách chủ thể bằng AI...")
            if let lifted = await ContextMediaExtractor.liftForegroundSubject(from: extracted.image) {
                ContextMediaExtractor.copyImageToPasteboard(lifted.image, preferredPNGData: lifted.pngData)
                WorkspaceStore.shared.showToast("Đã tách nền & sao chép chủ thể vào Clipboard")
            } else {
                ContextMediaExtractor.copyImageToPasteboard(extracted.image, preferredPNGData: extracted.pngData)
                WorkspaceStore.shared.showToast("Không tìm thấy chủ thể riêng biệt — đã sao chép toàn bộ ảnh")
            }
        }
    }

    @objc private func handleShareImage(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let extracted = await ContextMediaExtractor.extractImage(from: self, payload: payload),
                  let tempFileURL = ContextMediaExtractor.makeTemporaryShareFile(for: extracted) else {
                WorkspaceStore.shared.showToast("Không thể chuẩn bị hình ảnh để chia sẻ")
                return
            }
            guard self.window != nil else { return }
            let anchor = NSRect(x: payload.viewPoint.x, y: payload.viewPoint.y, width: 2, height: 2)
            let picker = NSSharingServicePicker(items: [tempFileURL])
            self.activeSharingPicker = picker
            picker.show(relativeTo: anchor, of: self, preferredEdge: .minY)
        }
    }

    @objc private func handleDownloadLinkedFile(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolved = await ContextMediaExtractor.extractBlobOrMedia(from: self, payload: payload, preferMedia: false)
            if let blobBytes = resolved.blobData {
                _ = ContextMediaExtractor.saveDataToDownloads(
                    blobBytes,
                    suggestedFilename: resolved.suggestedFilename,
                    sourceTitle: payload.sourceTitle,
                    forceSavePanel: false,
                    parentWindow: self.window
                )
            } else if let remoteURL = resolved.remoteURL {
                let cleanURL = LinkRouter.unwrapRedirectURL(remoteURL)
                WebSessionManager.shared.startManagedDownload(
                    request: URLRequest(url: cleanURL),
                    in: self,
                    sourceTitle: payload.sourceTitle
                )
            } else {
                WorkspaceStore.shared.showToast("Không tìm thấy tệp liên kết hợp lệ để tải về")
            }
        }
    }

    @objc private func handleDownloadMedia(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolved = await ContextMediaExtractor.extractBlobOrMedia(from: self, payload: payload, preferMedia: true)
            if let blobBytes = resolved.blobData {
                _ = ContextMediaExtractor.saveDataToDownloads(
                    blobBytes,
                    suggestedFilename: resolved.suggestedFilename,
                    sourceTitle: payload.sourceTitle,
                    forceSavePanel: false,
                    parentWindow: self.window
                )
            } else if let remoteURL = resolved.remoteURL {
                WebSessionManager.shared.startManagedDownload(
                    request: URLRequest(url: remoteURL),
                    in: self,
                    sourceTitle: payload.sourceTitle
                )
            } else {
                WorkspaceStore.shared.showToast("Không thể tải trực tiếp luồng phát này")
            }
        }
    }

    @objc private func handleOpenMediaInNewWindow(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolved = await ContextMediaExtractor.extractBlobOrMedia(from: self, payload: payload, preferMedia: true)
            if let remoteURL = resolved.remoteURL, let instID = payload.instanceID {
                WorkspaceStore.shared.openLinkInAppBrowser(remoteURL, for: instID)
            } else if let blobBytes = resolved.blobData,
                      let savedURL = ContextMediaExtractor.saveDataToDownloads(
                          blobBytes,
                          suggestedFilename: resolved.suggestedFilename,
                          sourceTitle: payload.sourceTitle,
                          forceSavePanel: false,
                          parentWindow: self.window
                      ) {
                NSWorkspace.shared.open(savedURL)
            }
        }
    }

    // MARK: - Link Context Menu Actions

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

struct InstanceRuntimeState: Equatable {
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
    private var timeoutTask: Task<Void, Never>?
    private var isResolved = false

    init(sourceInstanceID: UUID, configuration: WKWebViewConfiguration) {
        self.sourceInstanceID = sourceInstanceID
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100), configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self

        // Auto-expire abandoned `window.open('', '_blank')` popups after 15s so WKWebViews never leak in RAM
        let catcherID = self.id
        self.timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self, !self.isResolved else { return }
            self.finish(promotedToAuthWindow: false, catcherID: catcherID)
        }
    }

    private func finish(promotedToAuthWindow: Bool, catcherID: UUID) {
        guard !isResolved else { return }
        isResolved = true
        timeoutTask?.cancel()
        timeoutTask = nil
        if !promotedToAuthWindow {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        onResolved?(catcherID)
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

        if url.scheme?.lowercased() == "blob" {
            decisionHandler(.cancel)
            let title = WorkspaceStore.shared.instance(for: sourceInstanceID)?.displayTitle ?? "WebBox"
            WebSessionManager.shared.handleBlobPopupNavigation(url, from: webView, sourceTitle: title)
            finish(promotedToAuthWindow: false, catcherID: id)
            return
        }

        if LinkRouter.isAuthenticationFlowURL(url) {
            // Promote this exact webView into a visible OAuth window so window.opener stays intact!
            decisionHandler(.allow)
            WebSessionManager.shared.promoteWebViewToAuthWindow(webView, title: url.host ?? "Đăng nhập")
            finish(promotedToAuthWindow: true, catcherID: id)
            return
        }

        decisionHandler(.cancel)
        WorkspaceStore.shared.handleClickedLink(url, from: sourceInstanceID)
        finish(promotedToAuthWindow: false, catcherID: id)
    }

    func webViewDidClose(_ webView: WKWebView) {
        finish(promotedToAuthWindow: false, catcherID: id)
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
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
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
    private var imagePreviewWindows: [UUID: ImagePreviewWindow] = [:]
    private var deferredCatchers: [UUID: DeferredPopupCatcher] = [:]
    private var activeDownloads: [UUID: DownloadTracker] = [:]
    private var lastActiveTimestamps: [UUID: CFAbsoluteTime] = [:]
    private var autoHibernateTimer: Timer?
    private var lastAppliedDockBadge: String? = "__uninitialized__"

    private override init() {
        super.init()
        requestNotificationAuthorizationIfNeeded()
        startAutoHibernateMonitor()
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

    func postDownloadCompletedNotification(filename: String, fileURL: URL) {
        guard !WorkspaceStore.shared.preferences.globalDoNotDisturb else { return }

        let content = UNMutableNotificationContent()
        content.title = "Đã tải xong tệp"
        content.body = "\(filename) — Bấm vào thông báo để hiện trên Finder"
        content.sound = .default
        content.userInfo = ["revealFilePath": fileURL.path]

        let req = UNNotificationRequest(
            identifier: "webbox.download.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    func refreshDockBadge() {
        let totalUnread = runtimeStates.values.reduce(0) { $0 + $1.unreadCount }
        let anyDot = runtimeStates.values.contains { $0.hasUnreadDot }
        let nextBadge: String?
        if totalUnread > 0 {
            nextBadge = totalUnread > 99 ? "99+" : "\(totalUnread)"
        } else if anyDot {
            nextBadge = "•"
        } else {
            nextBadge = nil
        }
        guard nextBadge != lastAppliedDockBadge else { return }
        lastAppliedDockBadge = nextBadge
        NSApp.dockTile.badgeLabel = nextBadge
    }

    // MARK: - Instance WebView Access & Lifecycle

    func state(for instanceID: UUID) -> InstanceRuntimeState {
        runtimeStates[instanceID] ?? InstanceRuntimeState()
    }

    func markInstanceActive(_ instanceID: UUID) {
        lastActiveTimestamps[instanceID] = CFAbsoluteTimeGetCurrent()
    }

    func isImagePreviewWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return imagePreviewWindows.values.contains { $0.window === window }
    }

    func instanceID(forDetachedWindow window: NSWindow?) -> UUID? {
        guard let window else { return nil }
        return detachedWindows.values.first { $0.window === window }?.instanceID
    }

    func syncDeveloperExtrasPreference(_ enabled: Bool) {
        for ctrl in instanceControllers.values {
            ctrl.webView.configuration.preferences.setValue(enabled, forKey: "developerExtrasEnabled")
            if #available(macOS 13.3, *) {
                ctrl.webView.isInspectable = enabled
            }
        }
        for ctrl in inAppTabControllers.values {
            ctrl.webView.configuration.preferences.setValue(enabled, forKey: "developerExtrasEnabled")
            if #available(macOS 13.3, *) {
                ctrl.webView.isInspectable = enabled
            }
        }
    }

    private func startAutoHibernateMonitor() {
        autoHibernateTimer?.invalidate()
        autoHibernateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkIdleInstancesForAutoHibernation()
            }
        }
        autoHibernateTimer?.tolerance = 10.0
    }

    private func checkIdleInstancesForAutoHibernation() {
        let store = WorkspaceStore.shared
        let minutes = store.preferences.autoHibernateMinutes
        guard minutes > 0, !store.isStandaloneMode else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let thresholdSeconds = Double(minutes) * 60.0

        for id in Array(instanceControllers.keys) {
            if id == store.activeInstanceID || id == store.secondarySplitInstanceID {
                lastActiveTimestamps[id] = now
                continue
            }
            if detachedWindows[id] != nil {
                lastActiveTimestamps[id] = now
                continue
            }
            if store.inAppTabs.contains(where: { $0.ownerInstanceID == id }) {
                continue
            }
            guard let inst = store.instance(for: id), !inst.keepAwakeInBackground else {
                continue
            }
            guard let lastActive = lastActiveTimestamps[id] else {
                lastActiveTimestamps[id] = now
                continue
            }
            if (now - lastActive) >= thresholdSeconds {
                hibernateInstance(id, silent: true)
            }
        }
    }

    func webView(for instance: WebAppInstance) -> WebBoxWKWebView {
        lastActiveTimestamps[instance.id] = CFAbsoluteTimeGetCurrent()
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

    func reload(instanceID: UUID, fromOrigin: Bool = false) {
        if let ctrl = instanceControllers[instanceID] {
            if fromOrigin {
                ctrl.webView.reloadFromOrigin()
            } else {
                ctrl.webView.reload()
            }
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
    func hibernateInstance(_ instanceID: UUID, silent: Bool = false) {
        guard detachedWindows[instanceID] == nil else {
            if !silent {
                WorkspaceStore.shared.showToast("Hãy đóng cửa sổ tách rời trước khi ngủ đông tài khoản.")
            }
            return
        }
        if let ctrl = instanceControllers.removeValue(forKey: instanceID) {
            ctrl.teardown()
        }
        lastActiveTimestamps.removeValue(forKey: instanceID)
        var st = runtimeStates[instanceID] ?? InstanceRuntimeState()
        st.isHibernated = true
        st.isLoading = false
        runtimeStates[instanceID] = st
        refreshDockBadge()
        if !silent {
            WorkspaceStore.shared.showToast("Đã chuyển tài khoản sang chế độ Ngủ đông (Giải phóng RAM)")
        }
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
        lastActiveTimestamps.removeValue(forKey: instanceID)
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

    // MARK: - Download Registration & Image Preview Windows

    func presentImagePreviewWindow(extracted: ExtractedContextImage, sourceTitle: String) {
        let preview = ImagePreviewWindow(extracted: extracted, sourceTitle: sourceTitle) { [weak self] closedID in
            self?.imagePreviewWindows.removeValue(forKey: closedID)
        }
        imagePreviewWindows[preview.id] = preview
    }

    func startManagedDownload(request: URLRequest, in webView: WKWebView, sourceTitle: String) {
        webView.startDownload(using: request) { [weak self] download in
            self?.attachDownload(download, sourceTitle: sourceTitle)
        }
    }

    func recordCompletedDirectDownload(
        filename: String,
        destinationURL: URL,
        byteCount: Int64,
        sourceTitle: String
    ) {
        let item = DownloadTaskItem(
            id: UUID(),
            sourceInstanceTitle: sourceTitle,
            filename: filename,
            destinationURL: destinationURL,
            bytesReceived: max(1, byteCount),
            expectedBytes: max(1, byteCount),
            state: .completed,
            startedAt: Date()
        )
        downloads.insert(item, at: 0)
        if downloads.count > 100 {
            downloads.removeLast(downloads.count - 100)
        }
        WorkspaceStore.shared.showToast("Đã tải xong: \(filename)", revealFileURL: destinationURL)
        postDownloadCompletedNotification(filename: filename, fileURL: destinationURL)
    }

    func handleBlobPopupNavigation(_ blobURL: URL, from webView: WKWebView, sourceTitle: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let extractedBlob = await ContextMediaExtractor.extractDirectBlobURL(blobURL, from: webView) else {
                WorkspaceStore.shared.showToast("Không thể mở dữ liệu tạm thời từ trang này")
                return
            }
            if extractedBlob.mimeType.hasPrefix("image/"),
               let nsImg = NSImage(data: extractedBlob.data) {
                let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
                let imgPayload = ExtractedContextImage(
                    image: nsImg,
                    rawData: extractedBlob.data,
                    pngData: ContextMediaExtractor.encodePNG(from: nsImg),
                    fileExtension: (extractedBlob.filename as NSString).pathExtension,
                    suggestedFilename: extractedBlob.filename,
                    pixelWidth: cg?.width ?? max(1, Int(nsImg.size.width)),
                    pixelHeight: cg?.height ?? max(1, Int(nsImg.size.height))
                )
                self.presentImagePreviewWindow(extracted: imgPayload, sourceTitle: sourceTitle)
            } else {
                _ = ContextMediaExtractor.saveDataToDownloads(
                    extractedBlob.data,
                    suggestedFilename: extractedBlob.filename,
                    sourceTitle: sourceTitle,
                    forceSavePanel: false,
                    parentWindow: webView.window
                )
            }
        }
    }

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
            if downloads.count > 100 {
                downloads.removeLast(downloads.count - 100)
            }
        }
        if finished {
            activeDownloads.removeValue(forKey: item.id)
        }
    }

    fileprivate func cancelAndCleanupDownload(id: UUID) {
        activeDownloads.removeValue(forKey: id)
        downloads.removeAll { $0.id == id }
    }

    fileprivate func updateRuntimeState(for id: UUID, mutate: (inout InstanceRuntimeState) -> Void) {
        let previous = runtimeStates[id]
        var current = previous ?? InstanceRuntimeState()
        mutate(&current)
        guard previous != current else { return }
        runtimeStates[id] = current
        if previous?.unreadCount != current.unreadCount || previous?.hasUnreadDot != current.hasUnreadDot {
            refreshDockBadge()
        }
    }
}

// MARK: - Per-Instance WKWebView Controller

@MainActor
private final class InstanceWebController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var instance: WebAppInstance
    weak var manager: WebSessionManager?
    let webView: WebBoxWKWebView
    private var observations: [NSKeyValueObservation] = []
    private var lastReportedProgress: Double = -1

    private static let bridgeHandlerName = "webboxBridge"
    private static let unreadTitleRegex = try? NSRegularExpression(pattern: #"^\s*[\(\[](\d+)\+?[\)\]]"#)

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
                    let p = wv.estimatedProgress
                    guard abs(p - self.lastReportedProgress) >= 0.03 || p <= 0.01 || p >= 0.99 else { return }
                    self.lastReportedProgress = p
                    self.manager?.updateRuntimeState(for: self.instance.id) {
                        $0.estimatedProgress = p
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
        if let regex = Self.unreadTitleRegex,
           let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..<title.endIndex, in: title)),
           match.numberOfRanges > 1,
           let digitRange = Range(match.range(at: 1), in: title) {
            count = Int(title[digitRange]) ?? 0
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

    // MARK: - Injected JS Bridge (Modifier Clicks, Context Menu Hit-Test, Notifications & Custom CSS)

    private static func makeBridgeScript(customCSS: String) -> WKUserScript {
        let source = ContextMediaExtractor.makeBridgeScriptSource(
            includeLinkClickInterception: true,
            includeNotificationsBridge: true,
            customCSS: customCSS
        )
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "contextMenuHit":
            let linkStr = (body["linkURL"] as? String) ?? ""
            let linkURL = linkStr.isEmpty ? nil : URL(string: linkStr)
            webView.lastContextHit = ContextMenuHitSnapshot(
                timestamp: CFAbsoluteTimeGetCurrent(),
                linkURL: linkURL,
                linkDownloadFilename: (body["linkDownload"] as? String) ?? "",
                hasImage: (body["hasImage"] as? Bool) ?? false,
                imageURLString: (body["imageURL"] as? String) ?? "",
                imageAlt: (body["imageAlt"] as? String) ?? "",
                mediaURLString: (body["mediaURL"] as? String) ?? "",
                frameInfo: message.frameInfo
            )
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Fallback: If an internal/private site still has no icon, extract the live <link rel="icon"> URL from DOM
        guard WorkspaceStore.shared.instance(for: instance.id)?.customIconPNGData == nil else { return }
        let js = """
        (function() {
            const links = Array.from(document.querySelectorAll('link[rel*="icon"]'));
            const touch = links.find(l => (l.rel || '').toLowerCase().includes('apple-touch-icon') && l.href);
            if (touch) return touch.href;
            const first = links.find(l => l.href);
            return first ? first.href : '';
        })();
        """
        let instID = instance.id
        webView.evaluateJavaScript(js) { result, _ in
            guard let href = result as? String, !href.isEmpty, let iconURL = URL(string: href) else { return }
            Task { @MainActor in
                guard WorkspaceStore.shared.instance(for: instID)?.customIconPNGData == nil else { return }
                if let png = await AppIconFetcher.shared.downloadAndNormalizeIcon(from: iconURL, minPixelDimension: 24) {
                    WorkspaceStore.shared.updateIconSilently(instanceID: instID, pngData: png)
                }
            }
        }
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

            if url.scheme?.lowercased() == "blob" {
                manager?.handleBlobPopupNavigation(url, from: webView, sourceTitle: instance.displayTitle)
                return nil
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
private final class InAppTabWebController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let tab: InAppBrowserTab
    weak var manager: WebSessionManager?
    let webView: WebBoxWKWebView
    private var observations: [NSKeyValueObservation] = []
    private var lastReportedProgress: Double = -1

    private static let bridgeHandlerName = "webboxBridge"

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
        if WorkspaceStore.shared.preferences.enableDeveloperExtras {
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

        let userContent = WKUserContentController()
        config.userContentController = userContent

        let wv = WebBoxWKWebView(frame: .zero, configuration: config)
        wv.ownerInstanceID = tab.ownerInstanceID
        wv.sourceTitleOverride = "Trình duyệt WebBox"
        wv.customUserAgent = UserAgentPreset.safariMac.resolvedUserAgent(customValue: "")
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        if #available(macOS 13.3, *) {
            wv.isInspectable = WorkspaceStore.shared.preferences.enableDeveloperExtras
        }
        self.webView = wv

        super.init()

        userContent.add(WeakScriptMessageBridge(target: self), name: Self.bridgeHandlerName)
        let bridgeSource = ContextMediaExtractor.makeBridgeScriptSource(
            includeLinkClickInterception: false,
            includeNotificationsBridge: false,
            customCSS: ""
        )
        userContent.addUserScript(WKUserScript(source: bridgeSource, injectionTime: .atDocumentStart, forMainFrameOnly: false))

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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeHandlerName)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              (body["type"] as? String) == "contextMenuHit" else { return }
        let linkStr = (body["linkURL"] as? String) ?? ""
        webView.lastContextHit = ContextMenuHitSnapshot(
            timestamp: CFAbsoluteTimeGetCurrent(),
            linkURL: linkStr.isEmpty ? nil : URL(string: linkStr),
            linkDownloadFilename: (body["linkDownload"] as? String) ?? "",
            hasImage: (body["hasImage"] as? Bool) ?? false,
            imageURLString: (body["imageURL"] as? String) ?? "",
            imageAlt: (body["imageAlt"] as? String) ?? "",
            mediaURLString: (body["mediaURL"] as? String) ?? "",
            frameInfo: message.frameInfo
        )
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
                    let p = wv.estimatedProgress
                    guard abs(p - self.lastReportedProgress) >= 0.03 || p <= 0.01 || p >= 0.99 else { return }
                    self.lastReportedProgress = p
                    WorkspaceStore.shared.updateInAppTabState(
                        tabID: self.tab.id,
                        url: nil,
                        title: nil,
                        isLoading: wv.isLoading,
                        progress: p,
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
            if url.scheme?.lowercased() == "blob" {
                manager?.handleBlobPopupNavigation(url, from: webView, sourceTitle: "Trình duyệt WebBox")
                return nil
            }

            if LinkRouter.isAuthenticationFlowURL(url) {
                return manager?.createAuthPopupWebView(configuration: configuration, title: url.host ?? "Đăng nhập")
            }
            if let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
                WorkspaceStore.shared.openLinkInAppBrowser(LinkRouter.unwrapRedirectURL(url), for: tab.ownerInstanceID)
            }
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        manager?.attachDownload(download, sourceTitle: "Trình duyệt WebBox")
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

private final class ProgressThrottleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmitTime: CFAbsoluteTime = 0

    func shouldEmit(completed: Int64, total: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        if (now - lastEmitTime) >= 0.08 || (total > 0 && completed >= total) {
            lastEmitTime = now
            return true
        }
        return false
    }
}

@MainActor
private final class DownloadTracker: NSObject, WKDownloadDelegate {
    let id = UUID()
    let sourceTitle: String
    weak var manager: WebSessionManager?
    private var filename: String = "Tep_tai_xuong"
    private var destinationURL: URL?
    private var lastKnownExpectedBytes: Int64 = 0
    private var lastKnownReceivedBytes: Int64 = 0
    private let startedAt = Date()
    private var progressObservation: NSKeyValueObservation?

    init(download: WKDownload, sourceTitle: String, manager: WebSessionManager) {
        self.sourceTitle = sourceTitle
        self.manager = manager
        super.init()

        let gate = ProgressThrottleGate()
        progressObservation = download.progress.observe(\.completedUnitCount, options: [.new]) { [weak self] prog, _ in
            let completed = prog.completedUnitCount
            let total = prog.totalUnitCount
            guard gate.shouldEmit(completed: completed, total: total) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastKnownReceivedBytes = completed
                if total > 0 {
                    self.lastKnownExpectedBytes = total
                }
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
        let store = WorkspaceStore.shared
        let downloadsDir = store.resolvedDownloadsDirectoryURL()
        self.lastKnownExpectedBytes = response.expectedContentLength

        if store.preferences.askWhereToSaveEachDownload {
            let panel = NSSavePanel()
            panel.title = "Lưu tệp tải xuống"
            panel.prompt = "Lưu"
            panel.canCreateDirectories = true
            panel.directoryURL = downloadsDir
            panel.nameFieldStringValue = suggestedFilename
            if panel.runModal() == .OK, let chosenURL = panel.url {
                self.filename = chosenURL.lastPathComponent
                self.destinationURL = chosenURL
                manager?.upsertDownloadItem(
                    DownloadTaskItem(
                        id: id,
                        sourceInstanceTitle: sourceTitle,
                        filename: filename,
                        destinationURL: chosenURL,
                        bytesReceived: 0,
                        expectedBytes: response.expectedContentLength,
                        state: .downloading,
                        startedAt: startedAt
                    )
                )
                completionHandler(chosenURL)
            } else {
                progressObservation = nil
                manager?.cancelAndCleanupDownload(id: id)
                completionHandler(nil)
            }
            return
        }

        let safeDestination = ContextMediaExtractor.uniqueFileURL(in: downloadsDir, suggestedName: suggestedFilename)
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
        let diskBytes: Int64 = {
            if let path = destinationURL?.path,
               let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64,
               size > 0 {
                return size
            }
            return max(1, max(lastKnownReceivedBytes, lastKnownExpectedBytes))
        }()
        manager?.upsertDownloadItem(
            DownloadTaskItem(
                id: id,
                sourceInstanceTitle: sourceTitle,
                filename: filename,
                destinationURL: destinationURL,
                bytesReceived: diskBytes,
                expectedBytes: diskBytes,
                state: .completed,
                startedAt: startedAt
            ),
            finished: true
        )
        WorkspaceStore.shared.showToast("Đã tải xong: \(filename)", revealFileURL: destinationURL)
        if let destinationURL {
            manager?.postDownloadCompletedNotification(filename: filename, fileURL: destinationURL)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        progressObservation = nil
        manager?.upsertDownloadItem(
            DownloadTaskItem(
                id: id,
                sourceInstanceTitle: sourceTitle,
                filename: filename,
                destinationURL: destinationURL,
                bytesReceived: lastKnownReceivedBytes,
                expectedBytes: lastKnownExpectedBytes,
                state: .failed(error.localizedDescription),
                startedAt: startedAt
            ),
            finished: true
        )
    }
}
