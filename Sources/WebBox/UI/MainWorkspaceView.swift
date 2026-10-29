import SwiftUI
import AppKit

struct MainWorkspaceView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var sessionManager = WebSessionManager.shared
    @ObservedObject var updater = UpdateCheckerService.shared

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if !store.isStandaloneMode {
                    sidebarRail
                    Divider()
                }

                VStack(spacing: 0) {
                    if let active = store.activeInstance {
                        if !store.isStandaloneMode || store.showStandaloneToolbar {
                            topToolbar(for: active)
                            Divider()
                        }

                        if store.isFindBarVisible {
                            findInPageBar
                            Divider()
                        }

                        mainContentArea(activeInstance: active)
                    } else {
                        emptyWorkspaceWelcomeView
                    }
                }
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

            // Floating Toast Notification
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
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(.ultraThickMaterial)
                            .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
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

    // MARK: - Left Multi-Account Sidebar Rail

    private var sidebarRail: some View {
        VStack(spacing: 0) {
            // Space Filter Menu / Header
            Menu {
                Button {
                    store.selectedSpaceID = nil
                    if let first = store.filteredInstances.first {
                        store.selectInstance(first.id)
                    }
                } label: {
                    Label("Tất cả không gian (\(store.instances.count))", systemImage: "square.grid.2x2.fill")
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
                        Label("\(sp.name) (\(count))", systemImage: sp.symbolName)
                    }
                }

                Divider()

                Button {
                    store.isGlobalSettingsPresented = true
                } label: {
                    Label("Quản lý Không gian (Spaces)...", systemImage: "folder.badge.gearshape")
                }
            } label: {
                HStack(spacing: 6) {
                    let currentSpace = store.spaces.first { $0.id == store.selectedSpaceID }
                    Image(systemName: currentSpace?.symbolName ?? "square.grid.2x2.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(currentSpace.map { Color(hex: $0.colorHex) } ?? .accentColor)
                    Text(currentSpace?.name ?? "Tất cả (\(store.instances.count))")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            // Scrollable Multi-Account App List
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(store.filteredInstances.enumerated()), id: \.element.id) { index, instance in
                        sidebarAccountRow(instance: instance, index: index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }

            Divider()

            // Sidebar Bottom Actions
            VStack(spacing: 6) {
                Button {
                    store.isCatalogPresented = true
                } label: {
                    Label("Thêm App / Tài khoản", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                HStack(spacing: 6) {
                    Button {
                        store.isDedicatedAppsManagerPresented = true
                    } label: {
                        Label(".app Độc lập", systemImage: "app.badge.checkmark")
                            .font(.caption2.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Quản lý và xuất các ứng dụng thành tệp .app riêng trên macOS")

                    Button {
                        store.isGlobalSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Cài đặt chung WebBox (⌘,)")
                }

                sidebarGitHubUpdateButton
            }
            .padding(10)
        }
        .frame(width: 215)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarAccountRow(instance: WebAppInstance, index: Int) -> some View {
        let isActive = store.activeInstanceID == instance.id
        let isSplitSecondary = store.secondarySplitInstanceID == instance.id
        let rtState = sessionManager.state(for: instance.id)

        return HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                AppInstanceAvatarView(instance: instance, size: 36)
                    .opacity(rtState.isHibernated ? 0.55 : 1.0)

                // Unread count / dot badge
                if rtState.unreadCount > 0 {
                    Text(rtState.unreadCount > 99 ? "99+" : "\(rtState.unreadCount)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 5, y: -4)
                } else if rtState.hasUnreadDot {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                        .offset(x: 3, y: -3)
                }
            }

            if store.preferences.showAccountLabelsInSidebar {
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 4) {
                        Text(instance.name)
                            .font(.callout.weight(isActive ? .bold : .medium))
                            .lineLimit(1)
                        if instance.notificationsMuted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(rtState.isHibernated ? Color.secondary.opacity(0.4) : Color.green)
                            .frame(width: 6, height: 6)

                        Text(instance.accountLabel.isEmpty ? (instance.baseURL.host ?? "") : instance.accountLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            if isSplitSecondary {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            } else if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectInstance(instance.id)
        }
        .contextMenu {
            instanceContextMenu(for: instance, rtState: rtState)
        }
    }

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
            Label("Xuất thành file .app độc lập ra macOS", systemImage: "app.badge.checkmark")
        }

        Divider()

        Button {
            sessionManager.reload(instanceID: instance.id)
        } label: {
            Label("Tải lại trang", systemImage: "arrow.clockwise")
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

    // MARK: - Top Instance & Link Routing Toolbar

    private func topToolbar(for active: WebAppInstance) -> some View {
        let rtState = sessionManager.state(for: active.id)
        let effectiveLinkMode = store.effectiveLinkRoutingMode(for: active)
        let openTabsCount = store.visibleInAppTabs.count

        return HStack(spacing: 8) {
            // Navigation controls
            HStack(spacing: 4) {
                Button {
                    sessionManager.goBack(instanceID: active.id)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!rtState.canGoBack)

                Button {
                    sessionManager.goForward(instanceID: active.id)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!rtState.canGoForward)

                Button {
                    sessionManager.reload(instanceID: active.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Tải lại trang (⌘R)")

                Button {
                    sessionManager.goHome(instanceID: active.id)
                } label: {
                    Image(systemName: "house")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Về trang chủ của ứng dụng")
            }

            // Active Account Badge + Current Host Pill
            HStack(spacing: 7) {
                AppInstanceAvatarView(instance: active, size: 22, showBadgePill: false)
                Text(active.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                if let currentURL = rtState.currentURL {
                    Text("• \(currentURL.host ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            Spacer(minLength: 4)

            // Prominent GitHub Update Pill when a newer release is found
            if let updateInfo = updater.availableUpdateInfo {
                Button {
                    updater.showUpdatePromptDialog = true
                } label: {
                    Label("Cập nhật v\(updateInfo.version)", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
                .help("Đã có phiên bản mới trên GitHub Releases — Bấm để tự động tải và nâng cấp")
            }

            // 1-Click Quick Multi-Account Add Button (in Hub Mode)
            if !store.isStandaloneMode {
                Button {
                    store.addAnotherAccount(basedOn: active)
                } label: {
                    Label("Thêm nick \(active.name)", systemImage: "person.badge.plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Tạo ngay một phiên đăng nhập \(active.name) độc lập mới")
            }

            // Quick Smart Link Mode Switcher right in Toolbar!
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
                    "Bố cục trình duyệt App: Chia đôi cạnh bên",
                    isOn: Binding(
                        get: { store.preferences.inAppBrowserLayout == .splitRight },
                        set: { isSplit in
                            store.preferences.inAppBrowserLayout = isSplit ? .splitRight : .fullOverlay
                            store.save()
                        }
                    )
                )
            } label: {
                Label("Link: \(effectiveLinkMode.shortTitle)", systemImage: effectiveLinkMode.symbolName)
                    .font(.caption.weight(.medium))
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .help("Chọn cách mở khi bấm đường link trong tin nhắn: Hỏi nhanh, Mở trong App, hoặc Mở trình duyệt ngoài")

            // Toggle In-App Browser Tabs if any are open (or open empty In-App Browser!)
            Button {
                if openTabsCount == 0 {
                    if let url = URL(string: "https://www.google.com") {
                        store.openLinkInAppBrowser(url, for: active.id)
                    }
                } else {
                    store.isInAppBrowserVisible.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    if openTabsCount > 0 {
                        Text("\(openTabsCount)")
                            .font(.caption2.weight(.bold))
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(store.isInAppBrowserVisible ? .accentColor : nil)
            .controlSize(.small)
            .help("Mở / Ẩn khung Trình duyệt tích hợp của WebBox")

            // Split View 2 Accounts Simultaneously (Hub mode)
            if !store.isStandaloneMode && store.instances.count > 1 {
                Menu {
                    if store.secondarySplitInstanceID != nil {
                        Button("Đóng chế độ xem song song 2 tài khoản") {
                            store.secondarySplitInstanceID = nil
                        }
                        Divider()
                    }
                    Section("Chọn tài khoản mở song song bên cạnh:") {
                        ForEach(store.instances.filter { $0.id != active.id }) { candidate in
                            Button {
                                store.secondarySplitInstanceID = candidate.id
                            } label: {
                                Text(candidate.displayTitle)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .help("Chia đôi màn hình để dùng 2 tài khoản Zalo / Facebook cùng lúc")
            }

            // Downloads Popover Button
            if !sessionManager.downloads.isEmpty {
                Button {
                    store.isDownloadsPopoverShown.toggle()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $store.isDownloadsPopoverShown) {
                    downloadsPopoverView
                }
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
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Mở trang hiện tại ra trình duyệt ngoài")
            }

            // Instance Settings Button
            Button {
                store.editingInstance = active
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Cài đặt tài khoản, User-Agent, Cookie & Xuất .app")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
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
                            .buttonStyle(.plain)
                            Button {
                                store.secondarySplitInstanceID = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))

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

            Button {
                store.isFindBarVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
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
                .buttonStyle(.plain)
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
        VStack(spacing: 18) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Chào mừng đến với WebBox")
                    .font(.title2.weight(.bold))
                Text("Biến mọi trang web thành ứng dụng Desktop độc lập và đăng nhập không giới hạn tài khoản Zalo, Facebook, Messenger, Gmail...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            Button {
                store.isCatalogPresented = true
            } label: {
                Label("Mở Kho Ứng Dụng & Tạo Website Mới", systemImage: "plus.circle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sidebar GitHub Update Button

    @ViewBuilder
    private var sidebarGitHubUpdateButton: some View {
        switch updater.state {
        case .available(let info):
            Button {
                updater.showUpdatePromptDialog = true
            } label: {
                Label("Cập nhật v\(info.version) mới!", systemImage: "arrow.down.circle.fill")
                    .font(.caption2.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
            .help("Tải và cài đặt tự động bản mới v\(info.version) từ GitHub")

        case .checking:
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Đang kiểm tra GitHub...")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)

        case .downloading(let ver, let pct):
            Button {
                updater.showUpdatePromptDialog = true
            } label: {
                Label("Đang tải v\(ver) (\(Int(pct * 100))%)", systemImage: "arrow.down.circle")
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .installing(let ver):
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Đang cài v\(ver)...")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)

        default:
            Button {
                updater.checkForUpdatesManually()
            } label: {
                Label("Kiểm tra Update (GitHub)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Kiểm tra và tự động cập nhật phiên bản mới từ github.com/hungmtuci/WebBox (⌘U)")
        }
    }
}

// MARK: - GitHub Self-Update Modal Card

struct GitHubUpdateOverlayCard: View {
    @ObservedObject var updater = UpdateCheckerService.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
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

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cập nhật WebBox từ GitHub")
                            .font(.title3.weight(.bold))
                        Text("Kho phát hành chính thức: github.com/\(UpdateCheckerService.githubOwner)/\(UpdateCheckerService.githubRepo)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !updater.isBusy {
                        Button {
                            updater.showUpdatePromptDialog = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                switch updater.state {
                case .available(let info):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Đang dùng: v\(updater.currentVersion)")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))

                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            Text("Bản mới: v\(info.version)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.green.opacity(0.16)))
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
                            Label("Tải & Cập nhật tự động v\(info.version)", systemImage: "bolt.fill")
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .keyboardShortcut(.defaultAction)
                    }

                case .downloading(let ver, let pct):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Đang tải gói cập nhật WebBox v\(ver)...")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text("\(Int(pct * 100))%")
                                .font(.system(.callout, design: .monospaced).weight(.bold))
                        }
                        ProgressView(value: pct)
                            .progressViewStyle(.linear)
                        Text("Đang tải trực tiếp từ GitHub Releases...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .installing(let ver):
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Đang giải nén & cài đặt WebBox v\(ver)...")
                                .font(.callout.weight(.semibold))
                            Text("Ứng dụng sẽ tự động khởi động lại ngay sau khi hoàn tất.")
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
            .padding(22)
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}
