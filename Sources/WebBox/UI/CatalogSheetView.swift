import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class CatalogUIState: ObservableObject {
    static let shared = CatalogUIState()

    enum ModeTab: String, CaseIterable {
        case directory = "directory"
        case customURL = "customURL"

        @MainActor
        var title: String {
            switch self {
            case .directory: return L10n.catalogPopularApps
            case .customURL: return L10n.catalogCustomWebsite
            }
        }
    }

    @Published var selectedMode: ModeTab = .directory
    @Published var searchQuery: String = ""
    @Published var selectedCategory: CatalogCategory = .all
    @Published var configuringPreset: CatalogAppPreset? = nil {
        didSet {
            if let preset = configuringPreset {
                preparePresetConfig(for: preset)
            }
        }
    }

    // Custom Website Builder fields
    @Published var customURLInput: String = ""
    @Published var customAppName: String = ""
    @Published var customAccountLabel: String = ""
    @Published var customBadgeText: String = ""
    @Published var customAccentHex: String = "#0A84FF"
    @Published var customIconData: Data? = nil
    @Published var customSpaceID: UUID? = nil
    @Published var customLinkMode: LinkRoutingMode = .useGlobal
    @Published var customExportDedicatedApp: Bool = false
    @Published var customPinToDock: Bool = false
    @Published var isFetchingMetadata: Bool = false
    @Published var errorMessage: String? = nil

    // Preset configuration fields
    @Published var presetAccountLabel: String = ""
    @Published var presetBadgeShortText: String = ""
    @Published var presetSelectedSpaceID: UUID? = nil
    @Published var presetUseSharedProfile: Bool = false
    @Published var presetSelectedSharedProfileID: UUID? = nil
    @Published var presetLinkRoutingMode: LinkRoutingMode = .useGlobal
    @Published var presetExportDedicatedApp: Bool = false
    @Published var presetLaunchDedicatedImmediately: Bool = false
    @Published var presetPinDedicatedToDock: Bool = false

    func resetForOpen(store: WorkspaceStore) {
        selectedMode = .directory
        searchQuery = ""
        selectedCategory = .all
        customURLInput = ""
        customAppName = ""
        customAccountLabel = ""
        customBadgeText = ""
        customAccentHex = "#0A84FF"
        customIconData = nil
        customSpaceID = store.selectedSpaceID
        customLinkMode = .useGlobal
        customExportDedicatedApp = false
        customPinToDock = false
        isFetchingMetadata = false
        errorMessage = nil

        if let initial = store.catalogInitialPreset {
            configuringPreset = initial
            store.catalogInitialPreset = nil
        } else {
            configuringPreset = nil
        }
    }

    func preparePresetConfig(for preset: CatalogAppPreset) {
        let store = WorkspaceStore.shared
        let sameCount = store.instances.filter { $0.catalogID == preset.id }.count
        let nextNum = sameCount + 1
        let defaultLabel = L10n.isVietnamese ? "Cá nhân" : "Personal"
        let acctPrefix = L10n.isVietnamese ? "Tài khoản" : "Account"
        presetAccountLabel = sameCount == 0 ? defaultLabel : "\(acctPrefix) \(nextNum)"
        presetBadgeShortText = "\(nextNum)"
        presetSelectedSpaceID = store.selectedSpaceID
        presetUseSharedProfile = false
        presetSelectedSharedProfileID = store.profiles.first?.id
        presetLinkRoutingMode = .useGlobal
        presetExportDedicatedApp = false
        presetLaunchDedicatedImmediately = false
        presetPinDedicatedToDock = false
    }
}

struct CatalogSheetView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var ui = CatalogUIState.shared
    @ObservedObject var iconFetcher = AppIconFetcher.shared
    @Environment(\.dismiss) private var dismiss

    private let accentPalette = [
        "#0068FF", "#1877F2", "#24A1DE", "#25D366",
        "#EA4335", "#10A37F", "#D97757", "#EE4D2D",
        "#611F69", "#5865F2", "#E1306C", "#2F3437"
    ]

    private var categorySelectionBinding: Binding<CatalogCategory?> {
        Binding(
            get: { ui.selectedCategory },
            set: { newCat in
                if let newCat {
                    ui.selectedCategory = newCat
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Native macOS Sheet Header Bar
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.catalogHeaderTitle)
                        .font(.headline)
                    Text(L10n.catalogHeaderSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if ui.configuringPreset == nil {
                    Picker("", selection: $ui.selectedMode) {
                        ForEach(CatalogUIState.ModeTab.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 390)
                }

                Button(L10n.close) {
                    dismiss()
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(.bar)

            Divider()

            if let preset = ui.configuringPreset {
                PresetConfigurationDetailView(
                    preset: preset,
                    onBack: { ui.configuringPreset = nil },
                    onCreated: { dismiss() }
                )
            } else if ui.selectedMode == .directory {
                catalogDirectoryBody
            } else {
                customWebsiteBuilderBody
            }
        }
        .frame(width: 880, height: 620)
        .onAppear {
            ui.resetForOpen(store: store)
            AppIconFetcher.shared.preloadCatalogIconsIfNeeded()
        }
    }

    // MARK: - Directory View

    private var filteredPresets: [CatalogAppPreset] {
        CatalogDirectory.presets.filter { item in
            let matchesCat = (ui.selectedCategory == .all) || (item.category == ui.selectedCategory)
            let q = ui.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = q.isEmpty
                || item.name.lowercased().contains(q)
                || item.subtitle.lowercased().contains(q)
                || item.baseURLString.lowercased().contains(q)
            return matchesCat && matchesSearch
        }
    }

    private var catalogDirectoryBody: some View {
        HStack(spacing: 0) {
            // Left Native Sidebar List for Categories
            List(selection: categorySelectionBinding) {
                Section(L10n.catalogCategories) {
                    ForEach(CatalogCategory.allCases) { cat in
                        Label(cat.displayName, systemImage: cat.symbolName)
                            .tag(cat)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.catalogCantFind)
                            .font(.caption.weight(.semibold))
                        Button {
                            ui.selectedMode = .customURL
                        } label: {
                            Label(L10n.catalogEnterAnyURL, systemImage: "globe")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.small)
                    }
                    .padding(12)
                }
                .background(.bar)
            }
            .frame(width: 215)

            Divider()

            // Right Search + App Cards Grid
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.catalogSearchPrompt, text: $ui.searchQuery)
                        .textFieldStyle(.plain)
                    if !ui.searchQuery.isEmpty {
                        Button {
                            ui.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
                .padding(.horizontal, 16)
                .padding(.top, 14)

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(filteredPresets) { preset in
                            catalogCard(for: preset)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }
            }
        }
    }

    private func catalogCard(for preset: CatalogAppPreset) -> some View {
        let existingCount = store.instances.filter { $0.catalogID == preset.id }.count
        let previewInstance = preset.makeInstance()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AppInstanceAvatarView(instance: previewInstance, size: 44, showBadgePill: false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(preset.name)
                            .font(.callout.weight(.semibold))
                        if existingCount > 0 {
                            Text(L10n.s("\(existingCount) nick", "\(existingCount) accounts"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.blue.opacity(0.14)))
                        } else if preset.recommendedMultiAccount {
                            Text(L10n.catalogMultiAccount)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                    }

                    Text(preset.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    quickAddPreset(preset, existingCount: existingCount)
                } label: {
                    Label(
                        existingCount == 0 ? L10n.catalogAddNow : L10n.catalogAddAccountNum(existingCount + 1),
                        systemImage: "plus.circle.fill"
                    )
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    ui.configuringPreset = preset
                } label: {
                    Label(L10n.catalogCustomize, systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    private func quickAddPreset(_ preset: CatalogAppPreset, existingCount: Int) {
        let nextNum = existingCount + 1
        let defaultLabel = L10n.isVietnamese ? "Cá nhân" : "Personal"
        let acctPrefix = L10n.isVietnamese ? "Tài khoản" : "Account"
        let label = existingCount == 0 ? defaultLabel : "\(acctPrefix) \(nextNum)"
        let badge = "\(nextNum)"
        let inst = preset.makeInstance(
            accountLabel: label,
            badgeShortText: badge,
            spaceID: store.selectedSpaceID,
            customIconPNGData: iconFetcher.cachedIcon(forPresetID: preset.id)
        )
        store.addInstance(inst)
        dismiss()
    }

    // MARK: - Custom Website Builder View (Native Grouped Form)

    private var customWebsiteBuilderBody: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.catalogWebsiteAndIcon) {
                    HStack(spacing: 16) {
                        let previewInst = WebAppInstance(
                            name: ui.customAppName.isEmpty ? "Web" : ui.customAppName,
                            accountLabel: ui.customAccountLabel,
                            badgeShortText: ui.customBadgeText,
                            baseURLString: ui.customURLInput.isEmpty ? "https://example.com" : ui.customURLInput,
                            accentHex: ui.customAccentHex,
                            monogram: String((ui.customAppName.isEmpty ? "W" : ui.customAppName).prefix(2)).uppercased(),
                            customIconPNGData: ui.customIconData
                        )
                        AppInstanceAvatarView(instance: previewInst, size: 60)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Địa chỉ URL (VD: chat.zalo.me hoặc crm.congty.vn)", text: $ui.customURLInput)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        Task { await fetchSiteTitleAndFavicon() }
                                    }

                                Button {
                                    Task { await fetchSiteTitleAndFavicon() }
                                } label: {
                                    if ui.isFetchingMetadata {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label(L10n.catalogAutoFetchNameAndIcon, systemImage: "sparkles")
                                    }
                                }
                                .disabled(ui.customURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ui.isFetchingMetadata)
                            }

                            HStack(spacing: 8) {
                                Button(L10n.catalogChooseIconFromDisk) {
                                    chooseCustomIconImage()
                                }
                                .controlSize(.small)

                                if ui.customIconData != nil {
                                    Button(L10n.catalogRemoveChosenIcon) {
                                        ui.customIconData = nil
                                    }
                                    .controlSize(.small)
                                }

                                Spacer()

                                HStack(spacing: 5) {
                                    ForEach(accentPalette.prefix(8), id: \.self) { hex in
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 16, height: 16)
                                            .overlay(
                                                Circle().strokeBorder(.white, lineWidth: ui.customAccentHex == hex ? 2 : 0)
                                            )
                                            .onTapGesture {
                                                ui.customAccentHex = hex
                                            }
                                    }
                                }
                            }
                        }
                    }

                    TextField(L10n.catalogAppNameLabel, text: $ui.customAppName, prompt: Text(L10n.catalogAppNamePrompt))
                    TextField(L10n.accountLabel, text: $ui.customAccountLabel, prompt: Text(L10n.catalogAccountLabelPrompt))
                    TextField(L10n.catalogBadgeCornerSymbol, text: $ui.customBadgeText, prompt: Text(L10n.catalogBadgePrompt))
                }

                Section(L10n.catalogGroupingAndLinks) {
                    Picker(L10n.catalogWhenClickingLink, selection: $ui.customLinkMode) {
                        ForEach(LinkRoutingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker(L10n.catalogSpaceLabel, selection: $ui.customSpaceID) {
                        Text(L10n.catalogShowInAllSpaces).tag(UUID?.none)
                        ForEach(store.spaces) { sp in
                            Text(sp.name).tag(UUID?.some(sp.id))
                        }
                    }
                }

                Section("Dedicated Desktop App (.app)") {
                    Toggle(L10n.catalogExportDedicatedToggle, isOn: $ui.customExportDedicatedApp)
                    if ui.customExportDedicatedApp {
                        Toggle(L10n.catalogPinToDockToggle, isOn: $ui.customPinToDock)
                    }
                }

                if let err = ui.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(L10n.cancel) {
                    dismiss()
                }
                Button {
                    createCustomWebsiteApp()
                } label: {
                    Text(ui.customExportDedicatedApp ? L10n.catalogCreateAndExportApp : L10n.catalogAddToWebBox)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func chooseCustomIconImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .icns, .tiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let img = NSImage(contentsOf: url),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            ui.customIconData = png
        }
    }

    private func fetchSiteTitleAndFavicon() async {
        guard let normalized = LinkRouter.normalizeUserEnteredURL(ui.customURLInput) else {
            ui.errorMessage = "URL không hợp lệ. Vui lòng nhập đúng định dạng tên miền (VD: chat.zalo.me)."
            return
        }
        ui.errorMessage = nil
        ui.customURLInput = normalized.absoluteString
        ui.isFetchingMetadata = true
        defer { ui.isFetchingMetadata = false }

        if ui.customAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let host = normalized.host {
            let parts = host.replacingOccurrences(of: "www.", with: "").split(separator: ".")
            if let first = parts.first {
                ui.customAppName = first.prefix(1).uppercased() + first.dropFirst()
            }
        }

        do {
            var req = URLRequest(url: normalized, timeoutInterval: 6)
            req.setValue(UserAgentPreset.safariMac.resolvedUserAgent(customValue: ""), forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            if let html = String(data: data, encoding: .utf8),
               let titleRange = html.range(of: #"<title[^>]*>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) {
                let rawTag = String(html[titleRange])
                let stripped = rawTag
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty {
                    ui.customAppName = String(stripped.prefix(32))
                }
            }
        } catch {}

        if let iconBytes = await AppIconFetcher.shared.fetchBestIcon(
            catalogID: nil,
            appName: ui.customAppName,
            siteURL: normalized
        ) {
            ui.customIconData = iconBytes
        }
    }

    private func createCustomWebsiteApp() {
        guard let validURL = LinkRouter.normalizeUserEnteredURL(ui.customURLInput) else {
            ui.errorMessage = "Vui lòng nhập địa chỉ trang web hợp lệ."
            return
        }
        let finalName = ui.customAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (validURL.host ?? "Web App")
            : ui.customAppName.trimmingCharacters(in: .whitespacesAndNewlines)

        let mono = String(finalName.prefix(2)).uppercased()
        let instance = WebAppInstance(
            name: finalName,
            accountLabel: ui.customAccountLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            badgeShortText: ui.customBadgeText.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURLString: validURL.absoluteString,
            accentHex: ui.customAccentHex,
            monogram: mono,
            customIconPNGData: ui.customIconData,
            spaceID: ui.customSpaceID,
            linkRoutingMode: ui.customLinkMode
        )

        let created = store.addInstance(instance)
        if ui.customExportDedicatedApp {
            do {
                _ = try store.exportDedicatedDesktopApp(
                    for: created.id,
                    launchAfterExport: false,
                    pinToDock: ui.customPinToDock
                )
            } catch {
                store.showToast("Lỗi xuất .app: \(error.localizedDescription)")
            }
        }
        dismiss()
    }
}

// MARK: - Preset Customization Step (Native Grouped Form)

private struct PresetConfigurationDetailView: View {
    let preset: CatalogAppPreset
    let onBack: () -> Void
    let onCreated: () -> Void

    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var ui = CatalogUIState.shared
    @ObservedObject var iconFetcher = AppIconFetcher.shared

    var body: some View {
        let previewInstance = preset.makeInstance(
            accountLabel: ui.presetAccountLabel,
            badgeShortText: ui.presetBadgeShortText,
            customIconPNGData: iconFetcher.cachedIcon(forPresetID: preset.id)
        )

        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppInstanceAvatarView(instance: previewInstance, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.name)
                                .font(.title3.weight(.semibold))
                            Text(preset.baseURLString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(preset.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L10n.catalogAccountIdentification) {
                    TextField(L10n.catalogAccountDistinguishLabel, text: $ui.presetAccountLabel, prompt: Text(L10n.catalogAccountDistinguishPrompt))
                    TextField(L10n.catalogBadgeCornerSymbol, text: $ui.presetBadgeShortText, prompt: Text("VD: 1, 2, CV"))

                    Picker(L10n.catalogSpaceLabel, selection: $ui.presetSelectedSpaceID) {
                        Text(L10n.catalogAllSpaces).tag(UUID?.none)
                        ForEach(store.spaces) { sp in
                            Text(sp.name).tag(UUID?.some(sp.id))
                        }
                    }
                }

                Section(L10n.catalogSessionAndCookies) {
                    Picker(L10n.catalogCookieIsolationMode, selection: $ui.presetUseSharedProfile) {
                        Text(L10n.catalogIsolatedSessionRecommended).tag(false)
                        Text(L10n.catalogSharedSession).tag(true)
                    }

                    if ui.presetUseSharedProfile && !store.profiles.isEmpty {
                        Picker(L10n.catalogChooseSharedSession, selection: $ui.presetSelectedSharedProfileID) {
                            ForEach(store.profiles) { prof in
                                Text(prof.name).tag(UUID?.some(prof.id))
                            }
                        }
                    }
                }

                Section(L10n.catalogLinkAndDedicatedSection) {
                    Picker(L10n.catalogWhenClickingLink, selection: $ui.presetLinkRoutingMode) {
                        ForEach(LinkRoutingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Toggle(L10n.catalogExportDedicatedInApps, isOn: $ui.presetExportDedicatedApp)

                    if ui.presetExportDedicatedApp {
                        Toggle(L10n.catalogPinDedicatedToDock, isOn: $ui.presetPinDedicatedToDock)
                        Toggle(L10n.catalogLaunchDedicatedImmediately, isOn: $ui.presetLaunchDedicatedImmediately)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button {
                    onBack()
                } label: {
                    Label(L10n.catalogBackToCatalog, systemImage: "chevron.left")
                }

                Spacer()

                Button {
                    let chosenProfileID: UUID
                    if ui.presetUseSharedProfile, let shared = ui.presetSelectedSharedProfileID {
                        chosenProfileID = shared
                    } else {
                        chosenProfileID = UUID()
                    }
                    let inst = preset.makeInstance(
                        accountLabel: ui.presetAccountLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        badgeShortText: ui.presetBadgeShortText.trimmingCharacters(in: .whitespacesAndNewlines),
                        spaceID: ui.presetSelectedSpaceID,
                        profileID: chosenProfileID,
                        linkRoutingMode: ui.presetLinkRoutingMode,
                        customIconPNGData: iconFetcher.cachedIcon(forPresetID: preset.id)
                    )
                    let added = store.addInstance(inst)
                    if ui.presetExportDedicatedApp {
                        _ = try? store.exportDedicatedDesktopApp(
                            for: added.id,
                            launchAfterExport: ui.presetLaunchDedicatedImmediately,
                            pinToDock: ui.presetPinDedicatedToDock
                        )
                    }
                    onCreated()
                } label: {
                    Text(ui.presetExportDedicatedApp ? L10n.catalogCreateAccountAndExportApp : L10n.catalogAddAccount)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}
