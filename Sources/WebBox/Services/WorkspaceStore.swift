import Foundation
import AppKit
import SwiftUI

enum ClickModifierOverride {
    case none
    case forceInApp
    case forceExternal
}

@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    // Mode flags
    let isStandaloneMode: Bool
    private var standaloneManifest: StandaloneAppManifest?

    // Persistent data
    @Published var spaces: [SpaceItem] = []
    @Published var profiles: [SessionProfileInfo] = []
    @Published var instances: [WebAppInstance] = []
    @Published var preferences = GlobalWorkspacePreferences()

    // Active navigation state
    @Published var selectedSpaceID: UUID? = nil // nil = Tất cả
    @Published var activeInstanceID: UUID? = nil
    @Published var secondarySplitInstanceID: UUID? = nil

    // Smart Link Routing & In-App Browser state
    @Published var pendingLinkPrompt: PendingLinkPrompt? = nil
    @Published var rememberLinkChoiceForApp: Bool = false
    @Published var inAppTabs: [InAppBrowserTab] = []
    @Published var activeInAppTabID: UUID? = nil
    @Published var isInAppBrowserVisible: Bool = false
    @Published var inAppAddressBarText: String = ""

    // UI Sheets & Overlays
    @Published var isDownloadsPopoverShown: Bool = false
    @Published var isCatalogPresented: Bool = false
    @Published var catalogInitialPreset: CatalogAppPreset? = nil
    @Published var editingInstance: WebAppInstance? = nil {
        didSet {
            if let inst = editingInstance {
                InstanceSettingsUIState.shared.load(from: inst)
            }
        }
    }
    @Published var isGlobalSettingsPresented: Bool = false
    @Published var isDedicatedAppsManagerPresented: Bool = false
    @Published var isFindBarVisible: Bool = false
    @Published var findQuery: String = ""
    @Published var showStandaloneToolbar: Bool = true
    @Published var toastMessage: String? = nil

    private let appSupportDir: URL
    private let stateFileURL: URL
    private var toastClearTask: Task<Void, Never>?

    private struct PersistedHubState: Codable {
        var spaces: [SpaceItem]
        var profiles: [SessionProfileInfo]
        var instances: [WebAppInstance]
        var preferences: GlobalWorkspacePreferences
        var selectedSpaceID: UUID?
        var activeInstanceID: UUID?
    }

    private init() {
        let baseSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = baseSupport.appendingPathComponent("WebBox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.appSupportDir = dir
        self.stateFileURL = dir.appendingPathComponent("workspace_v1.json")

        if let manifestURL = Bundle.main.url(forResource: "StandaloneApp", withExtension: "json"),
           let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(StandaloneAppManifest.self, from: data) {
            self.isStandaloneMode = true
            self.standaloneManifest = manifest
            loadStandaloneState(manifest: manifest)
        } else {
            self.isStandaloneMode = false
            loadHubState()
        }
    }

    // MARK: - Persistence

    private func loadStandaloneState(manifest: StandaloneAppManifest) {
        let overrideDir = appSupportDir.appendingPathComponent("StandaloneOverrides", isDirectory: true)
        try? FileManager.default.createDirectory(at: overrideDir, withIntermediateDirectories: true)
        let overrideFile = overrideDir.appendingPathComponent("\(manifest.instance.id.uuidString).json")

        var loadedInstance = manifest.instance
        if let data = try? Data(contentsOf: overrideFile),
           let saved = try? JSONDecoder().decode(WebAppInstance.self, from: data) {
            loadedInstance = saved
        }

        self.preferences.defaultLinkRoutingMode = manifest.defaultLinkRoutingMode
        self.preferences.inAppBrowserLayout = manifest.inAppBrowserLayout
        self.showStandaloneToolbar = manifest.showNavigationToolbar
        self.profiles = [
            SessionProfileInfo(
                id: loadedInstance.profileID,
                name: loadedInstance.displayTitle,
                colorHex: loadedInstance.accentHex
            )
        ]
        self.instances = [loadedInstance]
        self.activeInstanceID = loadedInstance.id
    }

    private func loadHubState() {
        if let data = try? Data(contentsOf: stateFileURL),
           let decoded = try? JSONDecoder().decode(PersistedHubState.self, from: data) {
            self.spaces = decoded.spaces
            self.profiles = decoded.profiles
            self.instances = decoded.instances.sorted { $0.sortOrder < $1.sortOrder }
            self.preferences = decoded.preferences
            self.selectedSpaceID = decoded.selectedSpaceID
            self.activeInstanceID = decoded.activeInstanceID ?? self.instances.first?.id
            verifyExportedAppPaths()
            return
        }

        // Seed starter workspace on first launch
        let personalSpace = SpaceItem(name: "Cá nhân", symbolName: "person.fill", colorHex: "#0A84FF")
        let workSpace = SpaceItem(name: "Công việc", symbolName: "briefcase.fill", colorHex: "#30D158")
        let salesSpace = SpaceItem(name: "Bán hàng & CSKH", symbolName: "bag.fill", colorHex: "#FF9F0A")
        self.spaces = [personalSpace, workSpace, salesSpace]

        let zaloProfile = SessionProfileInfo(name: "Zalo — Cá nhân", colorHex: "#0068FF")
        let fbProfile = SessionProfileInfo(name: "Facebook — Cá nhân", colorHex: "#1877F2")
        self.profiles = [zaloProfile, fbProfile]

        var starterInstances: [WebAppInstance] = []
        if let zaloPreset = CatalogDirectory.preset(for: "zalo") {
            starterInstances.append(
                zaloPreset.makeInstance(
                    accountLabel: "Cá nhân",
                    badgeShortText: "1",
                    spaceID: personalSpace.id,
                    profileID: zaloProfile.id,
                    sortOrder: 0
                )
            )
        }
        if let fbPreset = CatalogDirectory.preset(for: "facebook") {
            starterInstances.append(
                fbPreset.makeInstance(
                    accountLabel: "Cá nhân",
                    badgeShortText: "1",
                    spaceID: personalSpace.id,
                    profileID: fbProfile.id,
                    sortOrder: 1
                )
            )
        }

        self.instances = starterInstances
        self.activeInstanceID = starterInstances.first?.id
        save()
    }

    func save() {
        if isStandaloneMode {
            guard let first = instances.first else { return }
            let overrideDir = appSupportDir.appendingPathComponent("StandaloneOverrides", isDirectory: true)
            try? FileManager.default.createDirectory(at: overrideDir, withIntermediateDirectories: true)
            let overrideFile = overrideDir.appendingPathComponent("\(first.id.uuidString).json")
            if let data = try? JSONEncoder().encode(first) {
                try? data.write(to: overrideFile, options: .atomic)
            }
            return
        }

        let payload = PersistedHubState(
            spaces: spaces,
            profiles: profiles,
            instances: instances,
            preferences: preferences,
            selectedSpaceID: selectedSpaceID,
            activeInstanceID: activeInstanceID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(payload) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }

    func verifyExportedAppPaths() {
        var changed = false
        for idx in instances.indices {
            if let path = instances[idx].exportedAppPath,
               !FileManager.default.fileExists(atPath: path) {
                instances[idx].exportedAppPath = nil
                changed = true
            }
        }
        if changed { save() }
    }

    // MARK: - Computed Helpers

    var filteredInstances: [WebAppInstance] {
        guard let spaceID = selectedSpaceID else {
            return instances
        }
        return instances.filter { $0.spaceID == spaceID }
    }

    var activeInstance: WebAppInstance? {
        guard let id = activeInstanceID else { return filteredInstances.first ?? instances.first }
        return instances.first { $0.id == id }
    }

    var secondarySplitInstance: WebAppInstance? {
        guard let id = secondarySplitInstanceID, id != activeInstanceID else { return nil }
        return instances.first { $0.id == id }
    }

    func instance(for id: UUID) -> WebAppInstance? {
        instances.first { $0.id == id }
    }

    var visibleInAppTabs: [InAppBrowserTab] {
        guard let activeID = activeInstanceID else { return inAppTabs }
        return inAppTabs.filter { $0.ownerInstanceID == activeID }
    }

    var activeInAppTab: InAppBrowserTab? {
        let tabs = visibleInAppTabs
        if let activeTabID = activeInAppTabID,
           let matched = tabs.first(where: { $0.id == activeTabID }) {
            return matched
        }
        return tabs.last
    }

    // MARK: - Multi-Account & Instance Management

    func selectInstance(_ id: UUID) {
        activeInstanceID = id
        if secondarySplitInstanceID == id {
            secondarySplitInstanceID = nil
        }
        // Sync In-App Browser visibility to whether this instance has open in-app tabs
        let tabsForInstance = inAppTabs.filter { $0.ownerInstanceID == id }
        if let lastTab = tabsForInstance.last {
            activeInAppTabID = lastTab.id
        } else {
            isInAppBrowserVisible = false
        }
        save()
    }

    func selectInstanceByIndex(_ zeroBasedIndex: Int) {
        let list = filteredInstances
        guard zeroBasedIndex >= 0 && zeroBasedIndex < list.count else { return }
        selectInstance(list[zeroBasedIndex].id)
    }

    @discardableResult
    func addInstance(_ newInstance: WebAppInstance, ensureProfileName: String? = nil) -> WebAppInstance {
        var item = newInstance
        item.sortOrder = instances.count

        if !profiles.contains(where: { $0.id == item.profileID }) {
            let profName = ensureProfileName ?? item.displayTitle
            profiles.append(
                SessionProfileInfo(
                    id: item.profileID,
                    name: profName,
                    colorHex: item.accentHex
                )
            )
        }

        instances.append(item)
        activeInstanceID = item.id
        save()
        showToast("Đã thêm \(item.displayTitle)")
        return item
    }

    /// 1-Click Multi-Account Cloner: Creates an isolated new account of the same app (e.g., Zalo #2, Facebook #3).
    @discardableResult
    func addAnotherAccount(basedOn source: WebAppInstance) -> WebAppInstance {
        let sameAppCount = instances.filter {
            if let cat = source.catalogID, !cat.isEmpty {
                return $0.catalogID == cat
            }
            return $0.baseURL.host?.lowercased() == source.baseURL.host?.lowercased()
        }.count

        let nextNumber = sameAppCount + 1
        let newProfile = SessionProfileInfo(
            name: "\(source.name) — Tài khoản \(nextNumber)",
            colorHex: source.accentHex
        )
        profiles.append(newProfile)

        var cloned = source
        cloned.id = UUID()
        cloned.profileID = newProfile.id
        cloned.accountLabel = "Tài khoản \(nextNumber)"
        cloned.badgeShortText = "\(nextNumber)"
        cloned.exportedAppPath = nil
        cloned.createdAt = Date()
        cloned.sortOrder = instances.count

        instances.append(cloned)
        selectInstance(cloned.id)
        save()
        showToast("Đã tạo \(cloned.displayTitle) (Phiên đăng nhập độc lập mới)")
        return cloned
    }

    func updateInstance(_ updated: WebAppInstance) {
        guard let idx = instances.firstIndex(where: { $0.id == updated.id }) else { return }
        let old = instances[idx]
        instances[idx] = updated

        if !profiles.contains(where: { $0.id == updated.profileID }) {
            profiles.append(
                SessionProfileInfo(
                    id: updated.profileID,
                    name: updated.displayTitle,
                    colorHex: updated.accentHex
                )
            )
        }

        save()
        WebSessionManager.shared.applyUpdatedSettings(from: old, to: updated)
    }

    func removeInstance(_ id: UUID, clearWebsiteData: Bool = false) {
        guard let idx = instances.firstIndex(where: { $0.id == id }) else { return }
        let removed = instances.remove(at: idx)
        inAppTabs.removeAll { $0.ownerInstanceID == id }

        let otherSharingSameProfile = instances.contains { $0.profileID == removed.profileID }
        WebSessionManager.shared.destroyInstanceSession(
            instanceID: id,
            profileID: clearWebsiteData && !otherSharingSameProfile ? removed.profileID : nil
        )

        if secondarySplitInstanceID == id {
            secondarySplitInstanceID = nil
        }
        if activeInstanceID == id {
            activeInstanceID = filteredInstances.first?.id ?? instances.first?.id
        }
        save()
        showToast("Đã xoá \(removed.displayTitle)")
    }

    func moveInstances(from source: IndexSet, to destination: Int) {
        guard selectedSpaceID == nil else { return }
        instances.move(fromOffsets: source, toOffset: destination)
        for idx in instances.indices {
            instances[idx].sortOrder = idx
        }
        save()
    }

    // MARK: - Spaces & Sidebar Layout

    func toggleLeftSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) {
            preferences.isSidebarVisible.toggle()
        }
        save()
    }

    func toggleSidebarCompactMode() {
        withAnimation(.easeInOut(duration: 0.18)) {
            if !preferences.isSidebarVisible {
                preferences.isSidebarVisible = true
                preferences.isSidebarCompact = true
            } else {
                preferences.isSidebarCompact.toggle()
            }
        }
        save()
    }

    // MARK: - Spaces CRUD

    func addSpace(name: String, symbolName: String, colorHex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let space = SpaceItem(name: trimmed, symbolName: symbolName, colorHex: colorHex)
        spaces.append(space)
        selectedSpaceID = space.id
        save()
    }

    func removeSpace(_ spaceID: UUID) {
        spaces.removeAll { $0.id == spaceID }
        for idx in instances.indices where instances[idx].spaceID == spaceID {
            instances[idx].spaceID = nil
        }
        if selectedSpaceID == spaceID {
            selectedSpaceID = nil
        }
        save()
    }

    // MARK: - Smart Link Routing Engine

    func effectiveLinkRoutingMode(for instance: WebAppInstance) -> LinkRoutingMode {
        if instance.linkRoutingMode == .useGlobal {
            return preferences.defaultLinkRoutingMode == .useGlobal
                ? .askEveryTime
                : preferences.defaultLinkRoutingMode
        }
        return instance.linkRoutingMode
    }

    /// Central entry point whenever a user clicks a link in a chat message or external domain.
    func handleClickedLink(
        _ rawURL: URL,
        from instanceID: UUID,
        modifierOverride: ClickModifierOverride = .none
    ) {
        let scheme = rawURL.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            NSWorkspace.shared.open(rawURL)
            return
        }

        let sourceInstance = instance(for: instanceID)
        let shouldUnwrap = sourceInstance?.unwrapRedirectLinks ?? true
        let finalURL = shouldUnwrap ? LinkRouter.unwrapRedirectURL(rawURL) : rawURL

        // Keyboard modifier overrides: Cmd+Click -> In-App, Option+Click -> External
        switch modifierOverride {
        case .forceInApp:
            openLinkInAppBrowser(finalURL, for: instanceID)
            return
        case .forceExternal:
            LinkRouter.openInExternalBrowser(
                finalURL,
                preferredBrowserBundleID: sourceInstance?.preferredExternalBrowserBundleID
            )
            showToast("Đã mở liên kết bằng trình duyệt ngoài")
            return
        case .none:
            break
        }

        let mode = sourceInstance.map { effectiveLinkRoutingMode(for: $0) } ?? .askEveryTime
        switch mode {
        case .askEveryTime, .useGlobal:
            rememberLinkChoiceForApp = false
            pendingLinkPrompt = PendingLinkPrompt(
                sourceInstanceID: instanceID,
                sourceInstanceTitle: sourceInstance?.displayTitle ?? "Ứng dụng",
                originalURL: rawURL,
                resolvedURL: finalURL
            )
        case .inAppBrowser:
            openLinkInAppBrowser(finalURL, for: instanceID)
        case .externalBrowser:
            LinkRouter.openInExternalBrowser(
                finalURL,
                preferredBrowserBundleID: sourceInstance?.preferredExternalBrowserBundleID
            )
            showToast("Đã mở bằng trình duyệt ngoài: \(finalURL.host ?? "")")
        }
    }

    // MARK: - In-App Browser Tabs Management

    func openLinkInAppBrowser(_ url: URL, for instanceID: UUID) {
        if activeInstanceID != instanceID && secondarySplitInstanceID != instanceID {
            activeInstanceID = instanceID
        }
        let owner = instance(for: instanceID)
        let sharedProfileID: UUID? = (owner?.inAppShareSession ?? true) ? owner?.profileID : nil

        let tab = InAppBrowserTab(
            ownerInstanceID: instanceID,
            profileID: sharedProfileID,
            initialURL: url
        )
        inAppTabs.append(tab)
        activeInAppTabID = tab.id
        inAppAddressBarText = url.absoluteString
        isInAppBrowserVisible = true
        pendingLinkPrompt = nil
    }

    func closeInAppTab(_ tabID: UUID) {
        WebSessionManager.shared.destroyInAppTabWebView(tabID: tabID)
        inAppTabs.removeAll { $0.id == tabID }
        let remaining = visibleInAppTabs
        if remaining.isEmpty {
            activeInAppTabID = nil
            isInAppBrowserVisible = false
        } else if activeInAppTabID == tabID {
            activeInAppTabID = remaining.last?.id
        }
    }

    func closeAllInAppTabsForActiveInstance() {
        guard let activeID = activeInstanceID else { return }
        let toClose = inAppTabs.filter { $0.ownerInstanceID == activeID }.map(\.id)
        for id in toClose {
            WebSessionManager.shared.destroyInAppTabWebView(tabID: id)
        }
        inAppTabs.removeAll { $0.ownerInstanceID == activeID }
        activeInAppTabID = nil
        isInAppBrowserVisible = false
    }

    func updateInAppTabState(
        tabID: UUID,
        url: URL?,
        title: String?,
        isLoading: Bool?,
        progress: Double?,
        canGoBack: Bool?,
        canGoForward: Bool?
    ) {
        guard let idx = inAppTabs.firstIndex(where: { $0.id == tabID }) else { return }
        if let url {
            inAppTabs[idx].currentURL = url
            if activeInAppTab?.id == tabID {
                inAppAddressBarText = url.absoluteString
            }
        }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inAppTabs[idx].title = title
        }
        if let isLoading { inAppTabs[idx].isLoading = isLoading }
        if let progress { inAppTabs[idx].estimatedProgress = progress }
        if let canGoBack { inAppTabs[idx].canGoBack = canGoBack }
        if let canGoForward { inAppTabs[idx].canGoForward = canGoForward }
    }

    // MARK: - Dedicated .app Export Helper

    @discardableResult
    func exportDedicatedDesktopApp(for instanceID: UUID, launchAfterExport: Bool = false, pinToDock: Bool = false) throws -> URL {
        guard let idx = instances.firstIndex(where: { $0.id == instanceID }) else {
            throw DedicatedAppBuildError.packagingFailed("Không tìm thấy cấu hình ứng dụng.")
        }
        let appURL = try DedicatedAppBuilder.exportDedicatedApp(
            for: instances[idx],
            preferences: preferences
        )
        instances[idx].exportedAppPath = appURL.path
        save()

        if pinToDock {
            DedicatedAppBuilder.pinToMacOSDock(appURL: appURL)
        }
        if launchAfterExport {
            DedicatedAppBuilder.launchDedicatedApp(at: appURL)
        }
        showToast("Đã xuất ứng dụng độc lập: \(appURL.lastPathComponent)")
        return appURL
    }

    // MARK: - Toast Helper

    func showToast(_ message: String) {
        toastClearTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            toastMessage = message
        }
        toastClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                if self.toastMessage == message {
                    self.toastMessage = nil
                }
            }
        }
    }
}
