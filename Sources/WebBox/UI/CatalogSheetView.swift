import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class CatalogUIState: ObservableObject {
    static let shared = CatalogUIState()

    enum ModeTab: String, CaseIterable {
        case directory = "Kho ứng dụng phổ biến"
        case customURL = "Biến Website bất kỳ thành App"
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
        presetAccountLabel = sameCount == 0 ? "Cá nhân" : "Tài khoản \(nextNum)"
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
    @Environment(\.dismiss) private var dismiss

    private let accentPalette = [
        "#0068FF", "#1877F2", "#24A1DE", "#25D366",
        "#EA4335", "#10A37F", "#D97757", "#EE4D2D",
        "#611F69", "#5865F2", "#E1306C", "#2F3437"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thêm Ứng Dụng & Tài Khoản Mới")
                        .font(.title3.weight(.bold))
                    Text("Mỗi tài khoản mới tự động có vùng lưu trữ Cookie & phiên đăng nhập độc lập 100%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $ui.selectedMode) {
                    ForEach(CatalogUIState.ModeTab.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 400)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

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
            VStack(alignment: .leading, spacing: 4) {
                ForEach(CatalogCategory.allCases) { cat in
                    let isSelected = ui.selectedCategory == cat
                    Button {
                        ui.selectedCategory = cat
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cat.symbolName)
                                .frame(width: 18)
                                .foregroundStyle(isSelected ? .white : .accentColor)
                            Text(cat.rawValue)
                                .font(.callout.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .white : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    Label("Không thấy web bạn cần?", systemImage: "globe.badge.chevron.backward")
                        .font(.caption.weight(.semibold))
                    Text("Bạn có thể biến bất kỳ trang web, CRM nội bộ hoặc công cụ nào thành ứng dụng Desktop riêng.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Nhập URL bất kỳ...") {
                        ui.selectedMode = .customURL
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.09))
                )
            }
            .padding(14)
            .frame(width: 215)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Tìm Zalo, Facebook, Messenger, Shopee, Gmail, ChatGPT...", text: $ui.searchQuery)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
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
                            .font(.callout.weight(.bold))
                        if existingCount > 0 {
                            Text("\(existingCount) nick")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.blue.opacity(0.14)))
                        } else if preset.recommendedMultiAccount {
                            Text("Đa tài khoản")
                                .font(.caption2.weight(.medium))
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
                        existingCount == 0 ? "Thêm ngay" : "Thêm tài khoản #\(existingCount + 1)",
                        systemImage: "plus.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: preset.accentHex))
                .controlSize(.small)

                Button {
                    ui.configuringPreset = preset
                } label: {
                    Label("Tuỳ chỉnh / .app", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func quickAddPreset(_ preset: CatalogAppPreset, existingCount: Int) {
        let nextNum = existingCount + 1
        let label = existingCount == 0 ? "Cá nhân" : "Tài khoản \(nextNum)"
        let badge = "\(nextNum)"
        let inst = preset.makeInstance(
            accountLabel: label,
            badgeShortText: badge,
            spaceID: store.selectedSpaceID
        )
        store.addInstance(inst)
        dismiss()
    }

    // MARK: - Custom Website Builder View

    private var customWebsiteBuilderBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    VStack(spacing: 8) {
                        let previewInst = WebAppInstance(
                            name: ui.customAppName.isEmpty ? "Web" : ui.customAppName,
                            accountLabel: ui.customAccountLabel,
                            badgeShortText: ui.customBadgeText,
                            baseURLString: ui.customURLInput.isEmpty ? "https://example.com" : ui.customURLInput,
                            accentHex: ui.customAccentHex,
                            monogram: String((ui.customAppName.isEmpty ? "W" : ui.customAppName).prefix(2)).uppercased(),
                            customIconPNGData: ui.customIconData
                        )
                        AppInstanceAvatarView(instance: previewInst, size: 74)

                        Button("Chọn ảnh Icon...") {
                            chooseCustomIconImage()
                        }
                        .controlSize(.small)
                    }
                    .frame(width: 120)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Địa chỉ trang web (URL)")
                                .font(.caption.weight(.semibold))
                            HStack(spacing: 8) {
                                TextField("Ví dụ: https://chat.zalo.me hoặc crm.congty.vn", text: $ui.customURLInput)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    Task { await fetchSiteTitleAndFavicon() }
                                } label: {
                                    if ui.isFetchingMetadata {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Lấy tên & Icon", systemImage: "sparkles")
                                    }
                                }
                                .disabled(ui.customURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ui.isFetchingMetadata)
                            }
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tên ứng dụng")
                                    .font(.caption.weight(.semibold))
                                TextField("VD: CRM Nội Bộ, Gmail, Zalo...", text: $ui.customAppName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nhãn tài khoản (Phân biệt nhiều nick)")
                                    .font(.caption.weight(.semibold))
                                TextField("VD: Cá nhân, Công ty, Sale 1...", text: $ui.customAccountLabel)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Huy hiệu góc Icon")
                                    .font(.caption.weight(.semibold))
                                TextField("VD: 1, 2, CV", text: $ui.customBadgeText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 95)
                            }
                        }
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Màu nhận diện thương hiệu")
                            .font(.caption.weight(.semibold))
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 6), spacing: 8) {
                            ForEach(accentPalette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: ui.customAccentHex == hex ? 2.5 : 0)
                                    )
                                    .shadow(radius: 1)
                                    .onTapGesture {
                                        ui.customAccentHex = hex
                                    }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Khi bấm đường link trong tin nhắn / trang web:")
                                .font(.caption.weight(.semibold))
                            Picker("", selection: $ui.customLinkMode) {
                                ForEach(LinkRoutingMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Thuộc Không gian (Space):")
                                .font(.caption.weight(.semibold))
                            Picker("", selection: $ui.customSpaceID) {
                                Text("Không phân nhóm (Hiện ở Tất cả)").tag(UUID?.none)
                                ForEach(store.spaces) { sp in
                                    Text(sp.name).tag(UUID?.some(sp.id))
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $ui.customExportDedicatedApp) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Đồng thời xuất thành ứng dụng macOS độc lập (.app) giống WebCatalog")
                                .font(.callout.weight(.semibold))
                            Text("Tạo tệp .app riêng trong ~/Applications với Icon & phiên đăng nhập riêng để mở từ Spotlight hoặc thanh Dock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if ui.customExportDedicatedApp {
                        Toggle("Ghim luôn ứng dụng này vào thanh Dock của macOS", isOn: $ui.customPinToDock)
                            .font(.caption)
                            .padding(.leading, 22)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                if let err = ui.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Spacer()
                    Button("Huỷ") {
                        dismiss()
                    }
                    Button {
                        createCustomWebsiteApp()
                    } label: {
                        Label(
                            ui.customExportDedicatedApp ? "Tạo trong Workspace & Xuất .app" : "Thêm vào Workspace",
                            systemImage: "checkmark.circle.fill"
                        )
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
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

        if let host = normalized.host,
           let iconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") {
            if let (iconBytes, _) = try? await URLSession.shared.data(from: iconURL),
               NSImage(data: iconBytes) != nil {
                ui.customIconData = iconBytes
            }
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

// MARK: - Preset Customization Step

private struct PresetConfigurationDetailView: View {
    let preset: CatalogAppPreset
    let onBack: () -> Void
    let onCreated: () -> Void

    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var ui = CatalogUIState.shared

    var body: some View {
        let previewInstance = preset.makeInstance(
            accountLabel: ui.presetAccountLabel,
            badgeShortText: ui.presetBadgeShortText
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button {
                    onBack()
                } label: {
                    Label("Quay lại kho ứng dụng", systemImage: "chevron.left")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                HStack(spacing: 16) {
                    AppInstanceAvatarView(instance: previewInstance, size: 68)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cấu hình \(preset.name)")
                            .font(.title3.weight(.bold))
                        Text(preset.baseURLString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(preset.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nhãn phân biệt tài khoản")
                            .font(.caption.weight(.semibold))
                        TextField("VD: Cá nhân, Công việc, Nick Bán Hàng...", text: $ui.presetAccountLabel)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ký hiệu góc Icon (Hiện cả trên Dock)")
                            .font(.caption.weight(.semibold))
                        TextField("VD: 1, 2, CV, SALE", text: $ui.presetBadgeShortText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Không gian (Space)")
                            .font(.caption.weight(.semibold))
                        Picker("", selection: $ui.presetSelectedSpaceID) {
                            Text("Tất cả").tag(UUID?.none)
                            ForEach(store.spaces) { sp in
                                Text(sp.name).tag(UUID?.some(sp.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Cô lập phiên đăng nhập (Multi-Account Session)")
                        .font(.caption.weight(.semibold))

                    Picker("", selection: $ui.presetUseSharedProfile) {
                        Text("Tạo phiên độc lập hoàn toàn mới (Đăng nhập tài khoản riêng)").tag(false)
                        Text("Dùng chung phiên Cookie với một tài khoản khác (VD: chung Facebook & Messenger)").tag(true)
                    }
                    .pickerStyle(.radioGroup)

                    if ui.presetUseSharedProfile && !store.profiles.isEmpty {
                        Picker("Chọn phiên dùng chung:", selection: $ui.presetSelectedSharedProfileID) {
                            ForEach(store.profiles) { prof in
                                Text(prof.name).tag(UUID?.some(prof.id))
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Khi bấm đường link trong tin nhắn:")
                        .font(.caption.weight(.semibold))
                    Picker("", selection: $ui.presetLinkRoutingMode) {
                        ForEach(LinkRoutingMode.allCases) { mode in
                            Text("\(mode.title) — \(mode.subtitle)").tag(mode)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $ui.presetExportDedicatedApp) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Xuất thành ứng dụng macOS độc lập (.app) trong ~/Applications")
                                .font(.callout.weight(.semibold))
                            Text("Giống WebCatalog Dedicated Desktop Apps — chạy riêng trên thanh Dock, mở bằng Spotlight")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if ui.presetExportDedicatedApp {
                        HStack(spacing: 20) {
                            Toggle("Ghim vào thanh Dock macOS", isOn: $ui.presetPinDedicatedToDock)
                            Toggle("Khởi chạy ngay sau khi tạo", isOn: $ui.presetLaunchDedicatedImmediately)
                        }
                        .font(.caption)
                        .padding(.leading, 22)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )

                HStack {
                    Spacer()
                    Button("Huỷ") { onBack() }
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
                            linkRoutingMode: ui.presetLinkRoutingMode
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
                        Label(
                            ui.presetExportDedicatedApp ? "Tạo tài khoản & Xuất .app" : "Thêm tài khoản vào Workspace",
                            systemImage: "plus.circle.fill"
                        )
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }
}
