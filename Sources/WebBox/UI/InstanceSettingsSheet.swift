import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class InstanceSettingsUIState: ObservableObject {
    static let shared = InstanceSettingsUIState()

    @Published var draft: WebAppInstance = WebAppInstance(name: "App", baseURLString: "https://example.com")
    @Published var confirmClearSession: Bool = false
    @Published var confirmDeleteInstance: Bool = false
    @Published var isFetchingIcon: Bool = false

    func load(from instance: WebAppInstance) {
        self.draft = instance
        self.confirmClearSession = false
        self.confirmDeleteInstance = false
        self.isFetchingIcon = false
    }
}

@MainActor
final class GlobalSettingsUIState: ObservableObject {
    static let shared = GlobalSettingsUIState()

    @Published var newSpaceName: String = ""
    @Published var newSpaceColor: String = "#0A84FF"
}

// MARK: - Per-Account Settings Sheet (Native macOS Grouped Form)

struct InstanceSettingsSheetView: View {
    let initialDraft: WebAppInstance
    @ObservedObject var ui = InstanceSettingsUIState.shared
    @ObservedObject var store = WorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss

    init(draft: WebAppInstance) {
        self.initialDraft = draft
    }

    private let accentPalette = [
        "#0068FF", "#1877F2", "#24A1DE", "#25D366",
        "#EA4335", "#10A37F", "#D97757", "#EE4D2D",
        "#611F69", "#5865F2", "#E1306C", "#2F3437"
    ]

    private var installedBrowsers: [ExternalBrowserInfo] {
        LinkRouter.installedExternalBrowsers()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Native macOS Sheet Header
            HStack(spacing: 14) {
                AppInstanceAvatarView(instance: ui.draft, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ui.draft.displayTitle)
                        .font(.headline)
                    Text("Profile: \(ui.draft.profileID.uuidString.prefix(8)) • Phiên Cookie & dữ liệu đăng nhập độc lập")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(.bar)

            Divider()

            Form {
                Section("Nhận diện ứng dụng & Biểu tượng (Icon)") {
                    TextField("Tên ứng dụng:", text: $ui.draft.name)
                    TextField("Nhãn phân biệt tài khoản:", text: $ui.draft.accountLabel, prompt: Text("VD: Cá nhân, Công việc, Sale 1"))
                    TextField("Huy hiệu góc Icon:", text: $ui.draft.badgeShortText, prompt: Text("VD: 1, 2, CV"))
                    TextField("URL Trang chủ:", text: $ui.draft.baseURLString)
                        .font(.body.monospaced())

                    LabeledContent("Biểu tượng ứng dụng:") {
                        HStack(spacing: 8) {
                            Button {
                                autoFetchOfficialIcon()
                            } label: {
                                if ui.isFetchingIcon {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Lấy Icon gốc từ Web", systemImage: "sparkles")
                                }
                            }
                            .controlSize(.small)
                            .disabled(ui.isFetchingIcon)

                            Button("Chọn ảnh từ máy...") {
                                pickIconFile()
                            }
                            .controlSize(.small)

                            if ui.draft.customIconPNGData != nil {
                                Button("Đặt lại mặc định") {
                                    ui.draft.customIconPNGData = nil
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    LabeledContent("Màu nhấn dự phòng:") {
                        HStack(spacing: 6) {
                            ForEach(accentPalette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 17, height: 17)
                                    .overlay(
                                        Circle().strokeBorder(.white, lineWidth: ui.draft.accentHex == hex ? 2 : 0)
                                    )
                                    .onTapGesture { ui.draft.accentHex = hex }
                            }
                        }
                    }

                    if !store.isStandaloneMode {
                        Picker("Không gian (Space):", selection: $ui.draft.spaceID) {
                            Text("Hiện ở Tất cả").tag(UUID?.none)
                            ForEach(store.spaces) { sp in
                                Text(sp.name).tag(UUID?.some(sp.id))
                            }
                        }

                        Picker("Phiên Cookie (Profile):", selection: $ui.draft.profileID) {
                            ForEach(store.profiles) { prof in
                                Text(prof.name).tag(prof.id)
                            }
                        }
                    }
                }

                Section("Xử lý khi bấm đường link trong tin nhắn") {
                    Picker("Chế độ mở link:", selection: $ui.draft.linkRoutingMode) {
                        ForEach(LinkRoutingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker("Trình duyệt ngoài ưu tiên:", selection: $ui.draft.preferredExternalBrowserBundleID) {
                        Text("Mặc định của macOS (\(LinkRouter.defaultSystemBrowserName()))")
                            .tag(String?.none)
                        ForEach(installedBrowsers) { browser in
                            Text(browser.name).tag(String?.some(browser.bundleIdentifier))
                        }
                    }

                    Toggle("Tự động bóc tách link trung gian (l.facebook.com, l.messenger.com, Google Redirect...)", isOn: $ui.draft.unwrapRedirectLinks)
                    Toggle("Trình duyệt trong App dùng chung phiên Cookie với tài khoản này", isOn: $ui.draft.inAppShareSession)
                }

                Section("Trình duyệt, Thông báo & Hiệu năng") {
                    Picker("User-Agent:", selection: $ui.draft.userAgentPreset) {
                        ForEach(UserAgentPreset.allCases) { ua in
                            Text(ua.title).tag(ua)
                        }
                    }
                    if ui.draft.userAgentPreset == .custom {
                        TextField("Chuỗi User-Agent tuỳ chỉnh:", text: $ui.draft.customUserAgent)
                    }

                    LabeledContent("Tỷ lệ thu phóng (\(Int(round(ui.draft.pageZoom * 100)))%):") {
                        HStack(spacing: 8) {
                            Slider(value: $ui.draft.pageZoom, in: 0.6...1.8, step: 0.05)
                                .frame(width: 180)
                            Button("100%") { ui.draft.pageZoom = 1.0 }
                                .controlSize(.small)
                        }
                    }

                    Toggle("Tắt thông báo từ tài khoản này", isOn: $ui.draft.notificationsMuted)
                    Toggle("Giữ chạy nền để nhận tin nhắn tức thì", isOn: $ui.draft.keepAwakeInBackground)
                }

                Section("Dedicated .app & Dữ liệu phiên đăng nhập") {
                    if !store.isStandaloneMode {
                        HStack(spacing: 10) {
                            Button {
                                store.updateInstance(ui.draft)
                                _ = try? store.exportDedicatedDesktopApp(for: ui.draft.id, launchAfterExport: false, pinToDock: false)
                                if let refreshed = store.instance(for: ui.draft.id) {
                                    ui.draft = refreshed
                                }
                            } label: {
                                Label(
                                    ui.draft.exportedAppPath == nil ? "Xuất thành file .app độc lập" : "Cập nhật lại file .app",
                                    systemImage: "app.badge.checkmark"
                                )
                            }
                            .controlSize(.small)

                            if let path = ui.draft.exportedAppPath, FileManager.default.fileExists(atPath: path) {
                                Button("Hiện trong Finder") {
                                    DedicatedAppBuilder.revealInFinder(at: URL(fileURLWithPath: path))
                                }
                                .controlSize(.small)

                                Button("Ghim lên Dock") {
                                    DedicatedAppBuilder.pinToMacOSDock(appURL: URL(fileURLWithPath: path))
                                }
                                .controlSize(.small)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                ui.confirmClearSession = true
                            } label: {
                                Label("Đăng xuất / Xoá Cookie...", systemImage: "trash")
                            }
                            .controlSize(.small)
                        }
                    } else {
                        LabeledContent("Thư mục lưu tệp tải về:") {
                            HStack(spacing: 8) {
                                Text(store.preferences.downloadsDirectory)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Button("Mở") {
                                    store.openDownloadsDirectory()
                                }
                                .controlSize(.small)

                                Button("Thay đổi...") {
                                    store.chooseDownloadsDirectory()
                                }
                                .controlSize(.small)
                            }
                        }

                        Toggle("Hỏi vị trí lưu mỗi khi tải tệp xuống", isOn: $store.preferences.askWhereToSaveEachDownload)

                        Button(role: .destructive) {
                            ui.confirmClearSession = true
                        } label: {
                            Label("Đăng xuất & Xoá dữ liệu phiên này...", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if !store.isStandaloneMode {
                    Button(role: .destructive) {
                        ui.confirmDeleteInstance = true
                    } label: {
                        Label("Xoá tài khoản", systemImage: "trash")
                    }
                }

                Spacer()

                Button("Huỷ") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Lưu thay đổi") {
                    if let normalized = LinkRouter.normalizeUserEnteredURL(ui.draft.baseURLString) {
                        ui.draft.baseURLString = normalized.absoluteString
                    }
                    store.updateInstance(ui.draft)
                    store.showToast("Đã lưu cài đặt cho \(ui.draft.displayTitle)")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 680, height: 630)
        .onAppear {
            if let latest = store.instance(for: initialDraft.id) {
                ui.load(from: latest)
            } else {
                ui.load(from: initialDraft)
            }
        }
        .confirmationDialog(
            "Xoá toàn bộ Cookie & phiên đăng nhập của \(ui.draft.displayTitle)?",
            isPresented: $ui.confirmClearSession
        ) {
            Button("Xoá dữ liệu & Tải lại", role: .destructive) {
                let target = ui.draft
                Task {
                    await WebSessionManager.shared.clearSessionData(for: target)
                }
            }
            Button("Huỷ", role: .cancel) {}
        }
        .confirmationDialog(
            "Bạn muốn xoá \(ui.draft.displayTitle) khỏi Workspace?",
            isPresented: $ui.confirmDeleteInstance
        ) {
            Button("Xoá ứng dụng & Xoá sạch dữ liệu đăng nhập", role: .destructive) {
                store.removeInstance(ui.draft.id, clearWebsiteData: true)
                dismiss()
            }
            Button("Chỉ xoá khỏi danh sách (Giữ dữ liệu nếu dùng chung)", role: .destructive) {
                store.removeInstance(ui.draft.id, clearWebsiteData: false)
                dismiss()
            }
            Button("Huỷ", role: .cancel) {}
        }
    }

    private func autoFetchOfficialIcon() {
        guard let url = LinkRouter.normalizeUserEnteredURL(ui.draft.baseURLString) else { return }
        ui.isFetchingIcon = true
        let cid = ui.draft.catalogID
        let name = ui.draft.name
        Task { @MainActor in
            defer { ui.isFetchingIcon = false }
            if let png = await AppIconFetcher.shared.fetchBestIcon(catalogID: cid, appName: name, siteURL: url) {
                ui.draft.customIconPNGData = png
                store.updateIconSilently(instanceID: ui.draft.id, pngData: png)
                store.showToast("Đã tải thành công Icon chuẩn cho \(name)")
            } else {
                store.showToast("Không tìm thấy Icon độ phân giải cao cho trang này")
            }
        }
    }

    private func pickIconFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .icns, .tiff]
        if panel.runModal() == .OK, let url = panel.url,
           let img = NSImage(contentsOf: url),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            ui.draft.customIconPNGData = png
        }
    }
}

// MARK: - Global Workspace Settings Sheet (Native macOS System Settings Grouped Form)

struct GlobalSettingsSheetView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var ui = GlobalSettingsUIState.shared
    @ObservedObject var updater = UpdateCheckerService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cài Đặt Chung WebBox")
                        .font(.headline)
                    Text("Quản lý cập nhật GitHub, chế độ mở Link mặc định, giao diện macOS và Không gian")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(.bar)

            Divider()

            Form {
                Section("Cập nhật qua GitHub (hungmtuci/WebBox)") {
                    LabeledContent("Phiên bản đang chạy:") {
                        HStack(spacing: 8) {
                            Text("v\(updater.currentVersion)")
                                .font(.callout.monospacedDigit().weight(.semibold))

                            if case let .available(info) = updater.state {
                                Button {
                                    updater.installAvailableUpdate()
                                } label: {
                                    Label("Cập nhật v\(info.version)", systemImage: "arrow.down.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.small)
                            }

                            Button {
                                updater.checkForUpdatesManually()
                            } label: {
                                Label(
                                    updater.isBusy ? "Đang kiểm tra..." : "Kiểm tra cập nhật",
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                            }
                            .disabled(updater.isBusy)
                            .controlSize(.small)

                            Button {
                                updater.openGitHubRepoPage()
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .controlSize(.small)
                            .help("Mở kho mã nguồn trên GitHub")
                        }
                    }

                    Text(updateStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Tự động kiểm tra phiên bản mới từ GitHub khi khởi động", isOn: $updater.autoCheckOnLaunch)
                }

                Section {
                    Picker("Hành vi mặc định khi bấm link:", selection: $store.preferences.defaultLinkRoutingMode) {
                        ForEach(LinkRoutingMode.globalSelectableCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker("Bố cục trình duyệt tích hợp:", selection: $store.preferences.inAppBrowserLayout) {
                        ForEach(InAppBrowserLayoutMode.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                } header: {
                    Text("Đường link trong tin nhắn")
                } footer: {
                    Text("Mẹo: Giữ ⌘+Click để mở nhanh trong App hoặc ⌥+Click để mở thẳng bằng trình duyệt ngoài.")
                }

                Section("Giao diện, Biểu tượng & Hệ thống") {
                    Picker("Chế độ thanh bên trái:", selection: $store.preferences.sidebarDisplayMode) {
                        ForEach(SidebarDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if !store.preferences.isSidebarCompact {
                        Toggle("Hiện nhãn tên tài khoản phụ dưới tên ứng dụng ở thanh bên", isOn: $store.preferences.showAccountLabelsInSidebar)
                    }
                    Toggle("Chế độ Không làm phiền (Tạm tắt toàn bộ thông báo đẩy)", isOn: $store.preferences.globalDoNotDisturb)
                    Toggle("Bật công cụ Web Inspector (Inspect Element khi chuột phải)", isOn: $store.preferences.enableDeveloperExtras)

                    LabeledContent("Biểu tượng ứng dụng:") {
                        Button {
                            for inst in store.instances {
                                Task { @MainActor in
                                    if let png = await AppIconFetcher.shared.fetchBestIcon(
                                        catalogID: inst.catalogID,
                                        appName: inst.name,
                                        siteURL: inst.baseURL
                                    ) {
                                        store.updateIconSilently(instanceID: inst.id, pngData: png)
                                    }
                                }
                            }
                            store.showToast("Đang đồng bộ lại toàn bộ Icon độ phân giải cao...")
                        } label: {
                            Label("Đồng bộ lại Icon chuẩn cho tất cả App", systemImage: "sparkles")
                        }
                        .controlSize(.small)
                    }
                }

                Section {
                    LabeledContent("Thư mục lưu tệp tải về:") {
                        HStack(spacing: 8) {
                            Text(store.preferences.downloadsDirectory)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button("Mở") {
                                store.openDownloadsDirectory()
                            }
                            .controlSize(.small)

                            Button("Thay đổi...") {
                                store.chooseDownloadsDirectory()
                            }
                            .controlSize(.small)

                            if store.preferences.downloadsDirectory != GlobalWorkspacePreferences.defaultDownloadsDirectoryPath {
                                Button("Mặc định") {
                                    store.preferences.downloadsDirectory = GlobalWorkspacePreferences.defaultDownloadsDirectoryPath
                                    store.save()
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    Toggle("Hỏi vị trí lưu mỗi khi tải tệp xuống", isOn: $store.preferences.askWhereToSaveEachDownload)
                } header: {
                    Text("Tệp tải xuống (Downloads)")
                } footer: {
                    Text("Khi tải tệp hoàn tất, bấm trực tiếp vào thông báo ở cuối cửa sổ để mở nhanh và bôi đậm tệp trên Finder.")
                }

                Section("Thư mục lưu Dedicated Desktop Apps (.app)") {
                    LabeledContent("Thư mục cài đặt:") {
                        HStack(spacing: 8) {
                            Text(store.preferences.dedicatedAppsInstallDirectory)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button("Mở") {
                                let url = URL(fileURLWithPath: store.preferences.dedicatedAppsInstallDirectory)
                                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(url)
                            }
                            .controlSize(.small)

                            Button("Thay đổi...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let dir = panel.url {
                                    store.preferences.dedicatedAppsInstallDirectory = dir.path
                                    store.save()
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }

                if !store.isStandaloneMode {
                    Section("Không gian làm việc (Spaces)") {
                        ForEach(store.spaces) { space in
                            HStack {
                                Circle()
                                    .fill(Color(hex: space.colorHex))
                                    .frame(width: 9, height: 9)
                                Text(space.name)
                                Spacer()
                                Button(role: .destructive) {
                                    store.removeSpace(space.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("Thêm Space mới...", text: $ui.newSpaceName, prompt: Text("VD: Bán hàng, Dự án VIP..."))
                                .textFieldStyle(.roundedBorder)
                            Button("Thêm") {
                                store.addSpace(name: ui.newSpaceName, symbolName: "folder.fill", colorHex: ui.newSpaceColor)
                                ui.newSpaceName = ""
                            }
                            .controlSize(.small)
                            .disabled(ui.newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Xong") {
                    store.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 640, height: 610)
    }

    private var updateStatusDescription: String {
        switch updater.state {
        case .idle:
            return "Nhấn 'Kiểm tra cập nhật' (⌘U) để đối chiếu phiên bản mới nhất trên GitHub Releases."
        case .checking:
            return "Đang kết nối tới github.com/hungmtuci/WebBox..."
        case .upToDate(let ver):
            return "Bạn đang sử dụng phiên bản mới nhất (v\(ver))."
        case .available(let info):
            return "Đã có bản mới v\(info.version) trên GitHub! Sẵn sàng tải và nâng cấp tự động."
        case .downloading(let ver, let pct):
            return "Đang tải gói cập nhật v\(ver) (\(Int(pct * 100))%)..."
        case .installing(let ver):
            return "Đang cài đặt v\(ver) và chuẩn bị khởi động lại..."
        case .failed(let msg):
            return msg
        }
    }
}

// MARK: - Dedicated .app Manager Sheet

struct DedicatedAppsManagerSheetView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quản Lý Dedicated Desktop Apps (.app)")
                        .font(.headline)
                    Text("Xuất bất kỳ tài khoản Zalo, Facebook, Web nào thành tệp .app macOS độc lập trong ~/Applications")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Mở ~/Applications") {
                    let dir = URL(fileURLWithPath: store.preferences.dedicatedAppsInstallDirectory)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(.bar)

            Divider()

            Form {
                Section("Danh sách tài khoản trong Workspace") {
                    ForEach(store.instances) { inst in
                        let isInstalled = inst.exportedAppPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
                        HStack(spacing: 12) {
                            AppInstanceAvatarView(instance: inst, size: 38)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(inst.displayTitle)
                                        .font(.callout.weight(.semibold))
                                    if isInstalled {
                                        Text("Đã cài .app")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.green.opacity(0.14)))
                                    }
                                }
                                Text(DedicatedAppBuilder.suggestedAppBundleName(for: inst))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isInstalled, let path = inst.exportedAppPath {
                                let appURL = URL(fileURLWithPath: path)
                                Button("Mở") {
                                    DedicatedAppBuilder.launchDedicatedApp(at: appURL)
                                }
                                .controlSize(.small)

                                Button("Ghim Dock") {
                                    DedicatedAppBuilder.pinToMacOSDock(appURL: appURL)
                                    store.showToast("Đã ghim \(appURL.lastPathComponent) vào thanh Dock")
                                }
                                .controlSize(.small)

                                Button("Finder") {
                                    DedicatedAppBuilder.revealInFinder(at: appURL)
                                }
                                .controlSize(.small)

                                Button(role: .destructive) {
                                    try? DedicatedAppBuilder.trashDedicatedApp(at: path)
                                    store.verifyExportedAppPaths()
                                    store.showToast("Đã chuyển \(appURL.lastPathComponent) vào Thùng rác")
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .controlSize(.small)
                            } else {
                                Button {
                                    _ = try? store.exportDedicatedDesktopApp(for: inst.id, launchAfterExport: false, pinToDock: false)
                                } label: {
                                    Label("Xuất .app", systemImage: "arrow.down.app.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Xong") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 660, height: 500)
        .onAppear {
            store.verifyExportedAppPaths()
        }
    }
}
