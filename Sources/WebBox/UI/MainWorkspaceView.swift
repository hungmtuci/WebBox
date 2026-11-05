import SwiftUI
import AppKit

/// Authentic macOS Sidebar Vibrancy background for the Compact Icon-Only Rail.
private struct SidebarVibrancyBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
    }
}

struct MainWorkspaceView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var sessionManager = WebSessionManager.shared
    @ObservedObject var updater = UpdateCheckerService.shared

    private var sidebarVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                (store.preferences.isSidebarVisible && !store.preferences.isSidebarCompact) ? .all : .detailOnly
            },
            set: { newValue in
                let wantsFullColumn = (newValue != .detailOnly)
                if wantsFullColumn {
                    if !store.preferences.isSidebarVisible || store.preferences.isSidebarCompact {
                        store.preferences.isSidebarVisible = true
                        store.preferences.isSidebarCompact = false
                        store.save()
                    }
                } else {
                    if !store.preferences.isSidebarCompact && store.preferences.isSidebarVisible {
                        store.preferences.isSidebarVisible = false
                        store.save()
                    }
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
                        .navigationSplitViewColumnWidth(min: 208, ideal: 236, max: 300)
                } detail: {
                    HStack(spacing: 0) {
                        if store.preferences.isSidebarVisible && store.preferences.isSidebarCompact {
                            compactIconRailView
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            Divider()
                        }

                        detailPaneView
                    }
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

            // Native macOS Floating Toast Banner (Interactive click-to-reveal-in-Finder for completed downloads!)
            if let toast = store.activeToast {
                VStack {
                    Spacer()
                    toastBannerView(for: toast)
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

    // MARK: - Interactive Toast Banner (Click Download Notification -> Reveal in Finder)

    @ViewBuilder
    private func toastBannerView(for toast: WorkspaceToast) -> some View {
        if let revealURL = toast.revealFileURL {
            HStack(spacing: 10) {
                Button {
                    store.revealFileInFinder(revealURL)
                    store.dismissToast()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(toast.message)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(L10n.revealInFinderBannerHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 420, alignment: .leading)

                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                            Text(L10n.revealInFinder)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.14))
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.toastRevealTooltip)

                Button {
                    store.dismissToast()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.toastDismiss)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 1)
            )
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(toast.message)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
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
        }
    }

    // MARK: - Full Expanded Vibrancy Sidebar

    private var sidebarColumnView: some View {
        let visibleInstances = store.filteredInstances
        let indexByID = Dictionary(
            uniqueKeysWithValues: visibleInstances.enumerated().map { ($0.element.id, $0.offset) }
        )
        return List(selection: activeSelectionBinding) {
            Section {
                ForEach(visibleInstances) { instance in
                    sidebarAccountRow(instance: instance, shortcutIndex: indexByID[instance.id])
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
            Text(currentSpace?.name ?? L10n.accounts)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if !store.spaces.isEmpty {
                spaceFilterMenu(iconOnly: true)
            }

            Button {
                store.setSidebarDisplayMode(.compactIcons)
            } label: {
                Image(systemName: "arrow.left.to.line")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.sidebarCollapseTooltip)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func spaceFilterMenu(iconOnly: Bool) -> some View {
        Menu {
            Button {
                store.selectedSpaceID = nil
                if let first = store.filteredInstances.first {
                    store.selectInstance(first.id)
                }
            } label: {
                HStack {
                    Label(L10n.allCount(store.instances.count), systemImage: "tray.full")
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
                Label(L10n.manageSpaces, systemImage: "folder.badge.gearshape")
            }
        } label: {
            Image(systemName: store.selectedSpaceID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(iconOnly ? .caption : .callout)
                .foregroundStyle(store.selectedSpaceID == nil ? Color.secondary : Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.filterBySpace)
    }

    private func sidebarAccountRow(instance: WebAppInstance, shortcutIndex: Int?) -> some View {
        let rtState = sessionManager.state(for: instance.id)
        let isSplitSecondary = store.secondarySplitInstanceID == instance.id

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

    // Native macOS Bottom Action Bar inside Full Sidebar
    private var sidebarBottomBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                Button {
                    store.isCatalogPresented = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                        Text(L10n.addApp)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderless)
                .help(L10n.addAppTooltip)

                Spacer(minLength: 2)

                sidebarUpdateStatusControl

                Button {
                    store.isDedicatedAppsManagerPresented = true
                } label: {
                    Image(systemName: "app.badge.checkmark")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help(L10n.dedicatedAppTooltip)

                Button {
                    store.isGlobalSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help(L10n.globalSettingsTooltip)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.bar)
        }
    }

    // MARK: - Compact Icon-Only Sidebar Rail (64pt Vibrancy Rail)

    private var compactIconRailView: some View {
        VStack(spacing: 0) {
            // Top Expand / Space Filter Header
            VStack(spacing: 6) {
                Button {
                    store.setSidebarDisplayMode(.expanded)
                } label: {
                    Image(systemName: "arrow.right.to.line")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.sidebarExpandTooltip)

                if !store.spaces.isEmpty {
                    spaceFilterMenu(iconOnly: false)
                        .padding(.bottom, 2)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 10)

            // Scrollable App Icons Column
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(store.filteredInstances.enumerated()), id: \.element.id) { index, instance in
                        compactAccountIconCell(instance: instance, index: index)
                    }
                }
                .padding(.vertical, 10)
            }

            Divider()
                .padding(.horizontal, 10)

            // Compact Bottom Controls
            VStack(spacing: 8) {
                Button {
                    store.isCatalogPresented = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 30)
                }
                .buttonStyle(.plain)
                .help(L10n.newAppAccountTooltip)

                sidebarUpdateStatusControl

                Button {
                    store.isDedicatedAppsManagerPresented = true
                } label: {
                    Image(systemName: "app.badge.checkmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 26)
                }
                .buttonStyle(.plain)
                .help(L10n.newAppDedicatedTooltip)

                Button {
                    store.isGlobalSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 26)
                }
                .buttonStyle(.plain)
                .help(L10n.globalSettingsTooltip)
            }
            .padding(.vertical, 10)
        }
        .frame(width: 64)
        .background(SidebarVibrancyBackground())
    }

    private func compactAccountIconCell(instance: WebAppInstance, index: Int) -> some View {
        let isActive = store.activeInstance?.id == instance.id
        let isSplitSecondary = store.secondarySplitInstanceID == instance.id
        let rtState = sessionManager.state(for: instance.id)
        let shortcutHint = index < 9 ? " (⌘\(index + 1))" : ""

        return ZStack(alignment: .leading) {
            // Active Accent Bar on Left Edge
            if isActive {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3.5, height: 22)
                    .offset(x: 2)
            } else if isSplitSecondary {
                Capsule()
                    .fill(Color.blue.opacity(0.65))
                    .frame(width: 3, height: 14)
                    .offset(x: 2)
            }

            HStack {
                Spacer(minLength: 0)

                ZStack(alignment: .topTrailing) {
                    AppInstanceAvatarView(instance: instance, size: 38, showBadgePill: true)
                        .opacity(rtState.isHibernated ? 0.55 : 1.0)
                        .padding(5)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(isActive ? Color.accentColor.opacity(0.16) : Color.clear)
                        )

                    if rtState.unreadCount > 0 {
                        Text(rtState.unreadCount > 99 ? "99+" : "\(rtState.unreadCount)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 3, y: -1)
                    } else if rtState.hasUnreadDot {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 9, height: 9)
                            .offset(x: 1, y: 0)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .frame(width: 64, height: 48)
        .contentShape(Rectangle())
        .help("\(instance.displayTitle)\(shortcutHint)")
        .onTapGesture {
            store.selectInstance(instance.id)
        }
        .contextMenu {
            instanceContextMenu(for: instance, rtState: rtState)
        }
    }

    @ViewBuilder
    private var sidebarUpdateStatusControl: some View {
        switch updater.state {
        case .available(let info):
            Button {
                updater.showUpdatePromptDialog = true
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .help(L10n.updateAvailableBanner(info.version))

        case .checking, .downloading, .installing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.75)
                .help(L10n.updateProcessing)

        default:
            Button {
                updater.checkForUpdatesManually()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.checkForUpdatesTooltip)
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
            if !store.isStandaloneMode {
                Button {
                    store.toggleSidebarCompactMode()
                } label: {
                    Image(systemName: store.preferences.isSidebarCompact && store.preferences.isSidebarVisible
                        ? "arrow.right.to.line.compact"
                        : "sidebar.squares.leading")
                }
                .help(
                    store.preferences.isSidebarCompact && store.preferences.isSidebarVisible
                        ? L10n.sidebarExpandTooltip
                        : L10n.sidebarCollapseTooltip
                )
            }

            Button {
                sessionManager.goBack(instanceID: active.id)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!rtState.canGoBack)
            .help(L10n.goBackTooltip)

            Button {
                sessionManager.goForward(instanceID: active.id)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!rtState.canGoForward)
            .help(L10n.goForwardTooltip)

            Button {
                sessionManager.reload(instanceID: active.id)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L10n.reloadWithCacheTip)

            Button {
                sessionManager.goHome(instanceID: active.id)
            } label: {
                Image(systemName: "house")
            }
            .help(L10n.homeTooltip)

            // Quick Account Switcher right in the toolbar when Left Sidebar is completely hidden!
            if !store.isStandaloneMode && !store.preferences.isSidebarVisible {
                Menu {
                    Section(L10n.quickSwitchAccount) {
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
                        store.setSidebarDisplayMode(.compactIcons)
                    } label: {
                        Label(L10n.sidebarCollapseTooltip, systemImage: "sidebar.squares.leading")
                    }

                    Button {
                        store.setSidebarDisplayMode(.expanded)
                    } label: {
                        Label(L10n.sidebarToggleFullTooltip, systemImage: "sidebar.leading")
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
                .help(L10n.quickSwitchWhenHidden)
            }
        }

        // Right / Primary Action Cluster
        ToolbarItemGroup(placement: .primaryAction) {
            if let updateInfo = updater.availableUpdateInfo {
                Button {
                    updater.showUpdatePromptDialog = true
                } label: {
                    Label(L10n.updateButton(updateInfo.version), systemImage: "arrow.down.circle.fill")
                }
                .tint(.green)
                .help(L10n.updateAvailableTooltip)
            }

            if !store.isStandaloneMode {
                Button {
                    store.addAnotherAccount(basedOn: active)
                } label: {
                    Label(L10n.addAnotherAccount(of: active.name), systemImage: "person.badge.plus")
                }
                .help(L10n.createAccountTooltip(active.name))
            }

            // Smart Link Routing Mode Menu
            Menu {
                Section(L10n.linkModeForAccount(active.displayTitle)) {
                    ForEach(LinkRoutingMode.allCases) { mode in
                        Button {
                            var updated = active
                            updated.linkRoutingMode = mode
                            store.updateInstance(updated)
                            store.showToast(L10n.linkModeCurrent(mode.title))
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
                    L10n.inAppBrowserSplitLayout,
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
            .help(L10n.linkModeHelp)

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
            .help(L10n.toggleInAppBrowserTooltip)

            // Side-by-Side 2 Accounts Split Menu
            if !store.isStandaloneMode && store.instances.count > 1 {
                Menu {
                    if store.secondarySplitInstanceID != nil {
                        Button(L10n.closeSplitScreen) {
                            store.secondarySplitInstanceID = nil
                        }
                        Divider()
                    }
                    Section(L10n.openSecondAccountSideBySide) {
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
                .help(L10n.splitScreenTooltip)
            }

            // Downloads Popover (Always accessible once downloads occur, or configure in Settings)
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
                .help(L10n.downloadsTooltip)
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
                .help(L10n.openCurrentInExternalBrowserTooltip)
            }

            // Account Settings
            Button {
                store.editingInstance = active
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help(L10n.accountSettingsTooltip)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func instanceContextMenu(for instance: WebAppInstance, rtState: InstanceRuntimeState) -> some View {
        Button {
            store.addAnotherAccount(basedOn: instance)
        } label: {
            Label(L10n.ctxAddAnotherAccount(instance.name), systemImage: "person.crop.circle.badge.plus")
        }

        Divider()

        Button {
            sessionManager.openDetachedWindow(for: instance)
        } label: {
            Label(L10n.ctxDetachWindow, systemImage: "macwindow.on.rectangle")
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
                        ? L10n.ctxCloseSideBySide
                        : L10n.ctxOpenSideBySide,
                    systemImage: "rectangle.split.2x1"
                )
            }
        }

        Button {
            _ = try? store.exportDedicatedDesktopApp(for: instance.id, launchAfterExport: false, pinToDock: false)
        } label: {
            Label(L10n.ctxExportDedicatedApp, systemImage: "app.badge.checkmark")
        }

        Divider()

        Button {
            sessionManager.reload(instanceID: instance.id)
        } label: {
            Label(L10n.ctxReloadPage, systemImage: "arrow.clockwise")
        }

        Button {
            Task { @MainActor in
                if let png = await AppIconFetcher.shared.fetchBestIcon(
                    catalogID: instance.catalogID,
                    appName: instance.name,
                    siteURL: instance.baseURL
                ) {
                    store.updateIconSilently(instanceID: instance.id, pngData: png)
                    store.showToast(L10n.iconUpdatedToast(instance.name))
                }
            }
        } label: {
            Label(L10n.ctxRefetchIcon, systemImage: "sparkles")
        }

        if rtState.isHibernated {
            Button {
                sessionManager.wakeInstance(instance)
            } label: {
                Label(L10n.ctxWakeAccount, systemImage: "bolt.fill")
            }
        } else {
            Button {
                sessionManager.hibernateInstance(instance.id)
            } label: {
                Label(L10n.ctxHibernateAccount, systemImage: "moon.zzz.fill")
            }
        }

        Button {
            store.editingInstance = instance
        } label: {
            Label(L10n.ctxCustomizeAccount, systemImage: "slider.horizontal.3")
        }

        Divider()

        Button(role: .destructive) {
            store.removeInstance(instance.id, clearWebsiteData: true)
        } label: {
            Label(L10n.ctxDeleteAccount, systemImage: "trash")
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
                            .help(L10n.reloadPaneTooltip)

                            Button {
                                store.secondarySplitInstanceID = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.closeSplitScreenTooltip)
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
            TextField(L10n.findPlaceholder, text: $store.findQuery)
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

            Button(L10n.done) {
                store.isFindBarVisible = false
            }
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - Downloads Popover (Click Row -> Reveal in Finder + Quick Folder Config)

    private var downloadsPopoverView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.downloadsPopoverTitle)
                    .font(.headline)
                Spacer()
                Button(L10n.clearList) {
                    sessionManager.downloads.removeAll()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sessionManager.downloads) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.state == .completed ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundStyle(item.state == .completed ? .green : .blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.filename)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let frac = item.progressFraction, item.state == .downloading {
                                    ProgressView(value: frac)
                                        .controlSize(.mini)
                                } else {
                                    Text(item.state == .completed ? L10n.downloadItemFinderHint(item.sourceInstanceTitle) : item.sourceInstanceTitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 4)

                            if let url = item.destinationURL, item.state == .completed {
                                Button(L10n.open) {
                                    NSWorkspace.shared.open(url)
                                }
                                .controlSize(.mini)

                                Button {
                                    store.revealFileInFinder(url)
                                    store.isDownloadsPopoverShown = false
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                }
                                .controlSize(.mini)
                                .help(L10n.revealInFinderItemHint)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let url = item.destinationURL, item.state == .completed {
                                store.revealFileInFinder(url)
                                store.isDownloadsPopoverShown = false
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 230)

            Divider()

            // Quick Download Folder Footer Bar
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.resolvedDownloadsDirectoryURL().lastPathComponent)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(store.preferences.downloadsDirectory)

                Spacer()

                Button(L10n.openFolder) {
                    store.openDownloadsDirectory()
                }
                .controlSize(.mini)

                Button(L10n.downloadsChangeFolder) {
                    store.chooseDownloadsDirectory()
                }
                .controlSize(.mini)
            }
        }
        .padding(14)
        .frame(width: 375)
    }

    // MARK: - Empty Workspace Welcome View

    private var emptyWorkspaceWelcomeView: some View {
        ContentUnavailableView {
            Label(L10n.welcomeTitle, systemImage: "macwindow.on.rectangle")
        } description: {
            Text(L10n.welcomeDescription)
        } actions: {
            Button {
                store.isCatalogPresented = true
            } label: {
                Label(L10n.welcomeAddAppButton, systemImage: "plus")
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
                        Text(L10n.updateDialogTitle)
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
                            Text(L10n.updateDialogCurrent(updater.currentVersion))
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))

                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            Text(L10n.updateDialogNew(info.version))
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
                            Text(L10n.updateDialogDesc)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button(L10n.updateDialogViewOnGitHub) {
                            NSWorkspace.shared.open(info.releasePageURL)
                        }
                        Spacer()
                        Button(L10n.updateDialogLater) {
                            updater.showUpdatePromptDialog = false
                        }
                        Button {
                            updater.installAvailableUpdate()
                        } label: {
                            Label(L10n.updateDialogAutoUpdate(info.version), systemImage: "bolt.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .keyboardShortcut(.defaultAction)
                    }

                case .downloading(let ver, let pct):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.updateDialogDownloading(ver))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text("\(Int(pct * 100))%")
                                .font(.callout.monospacedDigit().weight(.bold))
                        }
                        ProgressView(value: pct)
                            .progressViewStyle(.linear)
                        Text(L10n.updateDialogDownloadingDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .installing(let ver):
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.updateDialogInstalling(ver))
                                .font(.callout.weight(.semibold))
                            Text(L10n.updateDialogInstallingDesc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                default:
                    Text(L10n.updateDialogCurrent(updater.currentVersion))
                        .font(.callout)
                    HStack {
                        Spacer()
                        Button(L10n.close) {
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
