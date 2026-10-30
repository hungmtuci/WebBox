import SwiftUI
import AppKit

struct MainWorkspaceView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var sessionManager = WebSessionManager.shared
    @ObservedObject var updater = UpdateCheckerService.shared

    private var sidebarVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                store.preferences.isSidebarVisible ? .all : .detailOnly
            },
            set: { newValue in
                let isVisible = (newValue != .detailOnly)
                if store.preferences.isSidebarVisible != isVisible {
                    store.preferences.isSidebarVisible = isVisible
                    store.save()
                }
            }
        )
    }

    private var activeSelectionBinding: Binding<UUID?> {
        Binding(
            get: {
                store.activeInstance?.id
            },
            set: { newID in
                if let id = newID, id != store.activeInstanceID {
                    store.selectInstance(id)
                }
            }
        )
    }

    var body: some View {
        ZStack {
            if store.isStandaloneMode {
                NavigationStack {
                    detailPaneView
                }
            } else {
                NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
                    sidebarColumnView
                        .navigationSplitViewColumnWidth(min: 205, ideal: 236, max: 300)
                } detail: {
                    detailPaneView
                }
                .navigationSplitViewStyle(.balanced)
            }

            // Smart Link Choice Popup ("Ask Every Time" mode)
            if let prompt = store.pendingLinkPrompt {
                LinkChoiceOverlayCard(prompt: prompt)
                    .zIndex(20)
            }

            // GitHub Self-Update Dialog Overlay
            if updater.showUpdatePromptDialog {
                GitHubUpdateOverlayCard()
                    .zIndex(25)
            }

            // Native macOS Floating Toast Pill
            if let toast = store.toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(toast)
                            .font(.callout.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                    )
                    .padding(.bottom, 18)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(30)
            }
        }
        .sheet(isPresented: $store.isCatalogPresented) {
            CatalogSheetView()
        }
        .sheet(item: $store.editingInstance) { target in
            InstanceSettingsSheetView(draft: target)
        }
        .sheet(isPresented: $store.isGlobalSettingsPresented) {
            GlobalSettingsSheetView()
        }
        .sheet(isPresented: $store.isDedicatedAppsManagerPresented) {
            DedicatedAppsManagerSheetView()
        }
    }

    // MARK: - Native macOS Vibrancy Sidebar

    private var sidebarColumnView: some View {
        List(selection: activeSelectionBinding) {
            Section {
                ForEach(store.filteredInstances) { instance in
                    sidebarAccountRow(instance: instance)
                }
                .onMove { source, destination in
                    store.moveInstances(from: source, to: destination)
                }
            } header: {
                sidebarSectionHeader
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarBottomBar
        }
    }

    private var sidebarSectionHeader: some View {
        HStack(spacing: 6) {
            let currentSpace = store.spaces.first { $0.id == store.selectedSpaceID }
            Text(currentSpace?.name ?? "Tài khoản")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            if !store.spaces.isEmpty {
                Menu {
                    Button {
                        store.selectedSpaceID = nil
                        if let first = store.filteredInstances.first {
                            store.selectInstance(first.id)
                        }
                    } label: {
                        HStack {
                            Label("Tất cả (\(store.instances.count))", systemImage: "tray.full")
                            if store.selectedSpaceID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(store.spaces) { sp in
                        let count = store.instances.filter { $0.spaceID == sp.id }.count
                        Button {
                            store.selectedSpaceID = sp.id
                            if let first = store.filteredInstances.first {
                                store.selectInstance(first.id)
                            }
                        } label: {
                            HStack {
                                Label("\(sp.name) (\(count))", systemImage: sp.symbolName)
                                if store.selectedSpaceID == sp.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        store.isGlobalSettingsPresented = true
                    } label: {
                        Label("Quản lý Không gian...", systemImage: "folder.badge.gearshape")
                    }
                } label: {
                    Image(systemName: store.selectedSpaceID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.caption)
                        .foregroundStyle(store.selectedSpaceID == nil ? Color.secondary : Color.accentColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Lọc theo Không gian làm việc (Spaces)")
            }
        }
        .textCase(nil)
    }

    private func sidebarAccountRow(instance: WebAppInstance) -> some View {
        let rtState = sessionManager.state(for: instance.id)
        let isSplitSecondary = store.secondarySplitInstanceID == instance.id
        let shortcutIndex = store.filteredInstances.firstIndex(where: { $0.id == instance.id })

        return HStack(spacing: 10) {
            AppInstanceAvatarView(instance: instance, size: 28, showBadgePill: true)
                .opacity(rtState.isHibernated ? 0.55 : 1.0)

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 4) {
                    Text(instance.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if instance.notificationsMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                if store.preferences.showAccountLabelsInSidebar {
                    let subtitle = instance.accountLabel.isEmpty
                        ? (instance.baseURL.host ?? "")
                        : instance.accountLabel
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            if rtState.unreadCount > 0 {
                Text(rtState.unreadCount > 99 ? "99+" : "\(rtState.unreadCount)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.red))
            } else if rtState.hasUnreadDot {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            } else if isSplitSecondary {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if rtState.isHibernated {
                Image(systemName: "moon.zzz")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let idx = shortcutIndex, idx < 9 {
                Text("⌘\(idx + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(instance.displayTitle)
        .contextMenu {
            instanceContextMenu(for: instance, rtState: rtState)
        }
    }

    // Native macOS Bottom Action Bar inside Sidebar (Apple Mail / Notes / Reminders pattern)
    private var sidebarBottomBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 10) {
                Button {
                    store.isCatalogPresented = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                        Text("Thêm ứng dụng")
                            .font(.callout.weight(.medium))
                    }
                }
                .buttonStyle(.borderless)
                .help("Mở kho ứng dụng hoặc thêm Website bất kỳ (⌘N)")

                Spacer(minLength: 4)

                // GitHub Self-Update Control
                sidebarUpdateStatusControl

                Button {
                    store.isDedicatedAppsManagerPresented = true
                } label: {
                    Image(systemName: "app.badge.checkmark")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Quản lý và xuất thành ứng dụng macOS độc lập (.app)")

                Button {
                    store.isGlobalSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Cài đặt chung WebBox (⌘,)")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var sidebarUpdateStatusControl: some View {
        switch updater.state {
        case .available(let info):
            Button {
                updater.showUpdatePromptDialog = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("v\(info.version)")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .help("Đã có bản mới v\(info.version) trên GitHub — Bấm để cập nhật tự động")

        case .checking, .downloading, .installing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.75)
                .help("Đang xử lý cập nhật từ GitHub...")

        default:
            Button {
                updater.checkForUpdatesManually()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("Kiểm tra bản cập nhật mới từ GitHub (⌘U)")
        }
    }

    // MARK: - Detail Column & Unified macOS Toolbar

    @ViewBuilder
    private var detailPaneView: some View {
        if let active = store.activeInstance {
            let rtState = sessionManager.state(for: active.id)
            VStack(spacing: 0) {
                if store.isFindBarVisible {
                    findInPageBar
                    Divider()
                }

                mainContentArea(activeInstance: active)
            }
            .navigationTitle(active.displayTitle)
            .navigationSubtitle(rtState.currentURL?.host ?? active.baseURL.host ?? "")
            .toolbar {
                if !store.isStandaloneMode || store.showStandaloneToolbar {
                    unifiedToolbarContent(for: active, rtState: rtState)
                }
            }
        } else {
            emptyWorkspaceWelcomeView
                .navigationTitle("WebBox")
        }
    }

    @ToolbarContentBuilder
    private func unifiedToolbarContent(for active: WebAppInstance, rtState: InstanceRuntimeState) -> some ToolbarContent {
        let effectiveLinkMode = store.effectiveLinkRoutingMode(for: active)
        let openTabsCount = store.visibleInAppTabs.count
        let backgroundHasUnread = store.instances.contains { item in
            guard item.id != active.id else { return false }
            let st = sessionManager.state(for: item.id)
            return st.unreadCount > 0 || st.hasUnreadDot
        }

        // Left / Navigation Cluster
        ToolbarItemGroup(placement: .navigation) {
            Button {
                sessionManager.goBack(instanceID: active.id)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!rtState.canGoBack)
            .help("Quay lại (⌘[)")

            Button {
                sessionManager.goForward(instanceID: active.id)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!rtState.canGoForward)
            .help("Tiến tới (⌘])")

            Button {
                sessionManager.reload(instanceID: active.id)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Tải lại trang (⌘R • ⌘⇧R tải lại bỏ qua cache)")

            Button {
                sessionManager.goHome(instanceID: active.id)
            } label: {
                Image(systemName: "house")
            }
            .help("Về trang chủ của ứng dụng")

            // Quick Account Switcher right in the toolbar when Left Sidebar is hidden!
            if !store.isStandaloneMode && !store.preferences.isSidebarVisible {
                Menu {
                    Section("Chuyển nhanh tài khoản:") {
                        ForEach(Array(store.filteredInstances.enumerated()), id: \.element.id) { idx, item in
                            let itemState = sessionManager.state(for: item.id)
                            let unreadSuffix = itemState.unreadCount > 0
                                ? " (\(itemState.unreadCount))"
                                : (itemState.hasUnreadDot ? " •" : "")
                            Button {
                                store.selectInstance(item.id)
                            } label: {
                                HStack {
                                    Text("\(idx < 9 ? "⌘\(idx + 1)  " : "")\(item.displayTitle)\(unreadSuffix)")
                                    if item.id == active.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        store.isCatalogPresented = true
                    } label: {
                        Label("Thêm ứng dụng / Tài khoản mới...", systemImage: "plus.circle")
                    }

                    Button {
                        store.toggleLeftSidebar()
                    } label: {
                        Label("Hiện thanh bên trái (⌘\\)", systemImage: "sidebar.leading")
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        AppInstanceAvatarView(instance: active, size: 20, showBadgePill: false)
                        if backgroundHasUnread {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                                .offset(x: 3, y: -2)
                        }
                    }
                }
                .help("Chuyển nhanh tài khoản khi đang ẩn thanh bên")
            }
        }

        // Right / Primary Action Cluster
        ToolbarItemGroup(placement: .primaryAction) {
            if let updateInfo = updater.availableUpdateInfo {
                Button {
                    updater.showUpdatePromptDialog = true
                } label: {
                    Label("Cập nhật v\(updateInfo.version)", systemImage: "arrow.down.circle.fill")
                }
                .tint(.green)
                .help("Đã có phiên bản mới trên GitHub Releases — Bấm để tự động cập nhật")
            }

            if !store.isStandaloneMode {
                Button {
                    store.addAnotherAccount(basedOn: active)
                } label: {
                    Label("Thêm nick", systemImage: "person.badge.plus")
                }
                .help("Tạo ngay một tài khoản \(active.name) độc lập mới (⌘⇧N)")
            }

            // Smart Link Routing Mode Menu
            Menu {
                Section("Khi bấm đường link trong tin nhắn (\(active.displayTitle)):") {
                    ForEach(LinkRoutingMode.allCases) { mode in
                        Button {
                            var updated = active
                            updated.linkRoutingMode = mode
                            store.updateInstance(updated)
                            store.showToast("Chế độ mở link: \(mode.title)")
                        } label: {
                            HStack {
                                Label(mode.title, systemImage: mode.symbolName)
                                if active.linkRoutingMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Toggle(
                    "Trình duyệt trong App dạng Chia đôi cạnh bên",
                    isOn: Binding(
                        get: { store.preferences.inAppBrowserLayout == .splitRight },
                        set: { isSplit in
                            store.preferences.inAppBrowserLayout = isSplit ? .splitRight : .fullOverlay
                            store.save()
                        }
                    )
                )
            } label: {
                Label(effectiveLinkMode.shortTitle, systemImage: effectiveLinkMode.symbolName)
                    .labelStyle(.titleAndIcon)
            }
            .help("Chọn cách mở khi bấm đường link trong tin nhắn: Hỏi mỗi lần, Mở trong App, hoặc Trình duyệt ngoài")

            // Built-in Browser Toggle
            Button {
                if openTabsCount == 0 {
                    if let url = URL(string: "https://www.google.com") {
                        store.openLinkInAppBrowser(url, for: active.id)
                    }
                } else {
                    store.isInAppBrowserVisible.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: store.isInAppBrowserVisible ? "globe.badge.chevron.backward" : "globe")
                    if openTabsCount > 0 {
                        Text("\(openTabsCount)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                    }
                }
            }
            .help("Mở / Ẩn khung Trình duyệt tích hợp ngay trong WebBox")

            // Side-by-Side 2 Accounts Split Menu
            if !store.isStandaloneMode && store.instances.count > 1 {
                Menu {
                    if store.secondarySplitInstanceID != nil {
                        Button("Đóng chế độ xem song song 2 tài khoản") {
                            store.secondarySplitInstanceID = nil
                        }
                        Divider()
                    }
                    Section("Mở song song tài khoản thứ 2 bên cạnh:") {
                        ForEach(store.instances.filter { $0.id != active.id }) { candidate in
                            Button {
                                store.secondarySplitInstanceID = candidate.id
                            } label: {
                                HStack {
                                    Text(candidate.displayTitle)
                                    if store.secondarySplitInstanceID == candidate.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: store.secondarySplitInstanceID != nil ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                }
                .help("Chia đôi màn hình để dùng 2 tài khoản cùng lúc")
            }

            // Downloads Popover
            if !sessionManager.downloads.isEmpty {
                Button {
                    store.isDownloadsPopoverShown.toggle()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                }
                .popover(isPresented: $store.isDownloadsPopoverShown) {
                    downloadsPopoverView
                }
                .help("Danh sách tệp tải xuống")
            }

            // Open Current URL in External Browser
            if let currentURL = rtState.currentURL {
                Button {
                    LinkRouter.openInExternalBrowser(
                        currentURL,
                        preferredBrowserBundleID: active.preferredExternalBrowserBundleID
                    )
                } label: {
                    Image(systemName: "safari")
                }
                .help("Mở trang hiện tại ra trình duyệt ngoài")
            }

            // Account Settings
            Button {
                store.editingInstance = active
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Tuỳ chỉnh tài khoản, Icon, Chế độ mở Link & Xuất .app")
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func instanceContextMenu(for instance: WebAppInstance, rtState: InstanceRuntimeState) -> some View {
        Button {
            store.addAnotherAccount(basedOn: instance)
        } label: {
            Label("Thêm tài khoản \(instance.name) mới (Độc lập)", systemImage: "person.crop.circle.badge.plus")
        }

        Divider()

        Button {
            sessionManager.openDetachedWindow(for: instance)
        } label: {
            Label("Tách ra cửa sổ riêng (Dedicated Window)", systemImage: "macwindow.on.rectangle")
        }

        if store.activeInstanceID != instance.id {
            Button {
                if store.secondarySplitInstanceID == instance.id {
                    store.secondarySplitInstanceID = nil
                } else {
                    store.secondarySplitInstanceID = instance.id
                }
            } label: {
                Label(
                    store.secondarySplitInstanceID == instance.id
                        ? "Tắt xem song song tài khoản này"
                        : "Xem song song cạnh tài khoản hiện tại",
                    systemImage: "rectangle.split.2x1"
                )
            }
        }

        Button {
            _ = try? store.exportDedicatedDesktopApp(for: instance.id, launchAfterExport: false, pinToDock: false)
        } label: {
            Label("Xuất thành ứng dụng .app độc lập", systemImage: "app.badge.checkmark")
        }

        Divider()

        Button {
            sessionManager.reload(instanceID: instance.id)
        } label: {
            Label("Tải lại trang (⌘R)", systemImage: "arrow.clockwise")
        }

        Button {
            Task { @MainActor in
                if let png = await AppIconFetcher.shared.fetchBestIcon(
                    catalogID: instance.catalogID,
                    appName: instance.name,
                    siteURL: instance.baseURL
                ) {
                    store.updateIconSilently(instanceID: instance.id, pngData: png)
                    store.showToast("Đã cập nhật Icon cho \(instance.name)")
                }
            }
        } label: {
            Label("Tải lại Icon gốc độ phân giải cao", systemImage: "sparkles")
        }

        if rtState.isHibernated {
            Button {
                sessionManager.wakeInstance(instance)
            } label: {
                Label("Đánh thức tài khoản", systemImage: "bolt.fill")
            }
        } else {
            Button {
                sessionManager.hibernateInstance(instance.id)
            } label: {
                Label("Ngủ đông để giải phóng RAM", systemImage: "moon.zzz.fill")
            }
        }

        Button {
            store.editingInstance = instance
        } label: {
            Label("Tuỳ chỉnh tài khoản & Chế độ mở Link...", systemImage: "slider.horizontal.3")
        }

        Divider()

        Button(role: .destructive) {
            store.removeInstance(instance.id, clearWebsiteData: true)
        } label: {
            Label("Xoá tài khoản này", systemImage: "trash")
        }
    }

    // MARK: - Main Content Area (Handles Single / Split-Account / In-App Browser Split or Full)

    @ViewBuilder
    private func mainContentArea(activeInstance: WebAppInstance) -> some View {
        if store.isInAppBrowserVisible && store.preferences.inAppBrowserLayout == .fullOverlay {
            InAppBrowserPaneView()
        } else {
            HSplitView {
                // Primary Active Account WebView
                InstanceWebPaneView(instance: activeInstance)
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                // Optional Second Account Split-Screen (e.g., Zalo #1 + Zalo #2 side-by-side!)
                if let secondAccount = store.secondarySplitInstance {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            AppInstanceAvatarView(instance: secondAccount, size: 20, showBadgePill: false)
                            Text(secondAccount.displayTitle)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button {
                                sessionManager.reload(instanceID: secondAccount.id)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Tải lại khung này")

                            Button {
                                store.secondarySplitInstanceID = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Đóng khung xem song song")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.bar)

                        Divider()

                        InstanceWebPaneView(instance: secondAccount)
                    }
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }

                // Optional Built-in Browser Split Pane (Read message links right next to chat!)
                if store.isInAppBrowserVisible && store.preferences.inAppBrowserLayout == .splitRight {
                    InAppBrowserPaneView()
                        .frame(minWidth: 380, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Find in Page Bar

    private var findInPageBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Tìm nội dung trong trang hiện tại...", text: $store.findQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit {
                    sessionManager.findInActiveWebView(store.findQuery, forward: true)
                }

            Button {
                sessionManager.findInActiveWebView(store.findQuery, forward: false)
            } label: {
                Image(systemName: "chevron.up")
            }
            .controlSize(.small)

            Button {
                sessionManager.findInActiveWebView(store.findQuery, forward: true)
            } label: {
                Image(systemName: "chevron.down")
            }
            .controlSize(.small)

            Spacer()

            Button("Xong") {
                store.isFindBarVisible = false
            }
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - Downloads Popover

    private var downloadsPopoverView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tệp tải xuống")
                    .font(.headline)
                Spacer()
                Button("Xoá danh sách") {
                    sessionManager.downloads.removeAll()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sessionManager.downloads) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.state == .completed ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundStyle(item.state == .completed ? .green : .blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.filename)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                if let frac = item.progressFraction, item.state == .downloading {
                                    ProgressView(value: frac)
                                        .controlSize(.mini)
                                } else {
                                    Text(item.sourceInstanceTitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let url = item.destinationURL, item.state == .completed {
                                Button("Mở") {
                                    NSWorkspace.shared.open(url)
                                }
                                .controlSize(.mini)
                                Button("Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .controlSize(.mini)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Empty Workspace Welcome View

    private var emptyWorkspaceWelcomeView: some View {
        ContentUnavailableView {
            Label("Chào mừng đến với WebBox", systemImage: "macwindow.on.rectangle")
        } description: {
            Text("Biến mọi trang web thành ứng dụng macOS độc lập và đăng nhập nhiều tài khoản Zalo, Facebook, Messenger, Gmail hoàn toàn tách biệt.")
        } actions: {
            Button {
                store.isCatalogPresented = true
            } label: {
                Label("Thêm Ứng Dụng hoặc Website Mới", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - GitHub Self-Update Modal Card

struct GitHubUpdateOverlayCard: View {
    @ObservedObject var updater = UpdateCheckerService.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    if !updater.isBusy {
                        updater.showUpdatePromptDialog = false
                    }
                }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cập nhật WebBox từ GitHub")
                            .font(.headline)
                        Text("github.com/\(UpdateCheckerService.githubOwner)/\(UpdateCheckerService.githubRepo)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !updater.isBusy {
                        Button {
                            updater.showUpdatePromptDialog = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                switch updater.state {
                case .available(let info):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text("Hiện tại: v\(updater.currentVersion)")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))

                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            Text("Bản mới: v\(info.version)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                        }

                        if let notes = info.releaseNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ScrollView {
                                Text(notes)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 160)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        } else {
                            Text("Bản phát hành mới đã sẵn sàng trên GitHub Releases. WebBox sẽ tự động tải về, thay thế ứng dụng và khởi động lại ngay.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button("Xem trên GitHub") {
                            NSWorkspace.shared.open(info.releasePageURL)
                        }
                        Spacer()
                        Button("Để sau") {
                            updater.showUpdatePromptDialog = false
                        }
                        Button {
                            updater.installAvailableUpdate()
                        } label: {
                            Label("Cập nhật tự động v\(info.version)", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .keyboardShortcut(.defaultAction)
                    }

                case .downloading(let ver, let pct):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Đang tải WebBox v\(ver)...")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text("\(Int(pct * 100))%")
                                .font(.callout.monospacedDigit().weight(.bold))
                        }
                        ProgressView(value: pct)
                            .progressViewStyle(.linear)
                        Text("Đang tải trực tiếp gói cài đặt từ GitHub Releases...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .installing(let ver):
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Đang cài đặt WebBox v\(ver)...")
                                .font(.callout.weight(.semibold))
                            Text("Ứng dụng sẽ tự động mở lại ngay sau khi hoàn tất.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                default:
                    Text("Phiên bản hiện tại: v\(updater.currentVersion)")
                        .font(.callout)
                    HStack {
                        Spacer()
                        Button("Đóng") {
                            updater.showUpdatePromptDialog = false
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 500)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
            )
        }
    }
}
