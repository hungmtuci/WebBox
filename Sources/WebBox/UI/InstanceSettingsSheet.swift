import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class InstanceSettingsUIState: ObservableObject {
    static let shared = InstanceSettingsUIState()

    @Published var draft: WebAppInstance = WebAppInstance(name: "App", baseURLString: "https://example.com")
    @Published var confirmClearSession: Bool = false
    @Published var confirmDeleteInstance: Bool = false

    func load(from instance: WebAppInstance) {
        self.draft = instance
        self.confirmClearSession = false
        self.confirmDeleteInstance = false
    }
}

@MainActor
final class GlobalSettingsUIState: ObservableObject {
    static let shared = GlobalSettingsUIState()

    @Published var newSpaceName: String = ""
    @Published var newSpaceColor: String = "#0A84FF"
}

// MARK: - Per-Account Settings Sheet

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
            HStack(spacing: 14) {
                AppInstanceAvatarView(instance: ui.draft, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tuỳ chỉnh: \(ui.draft.displayTitle)")
                        .font(.title3.weight(.bold))
                    Text("Profile ID: \(ui.draft.profileID.uuidString.prefix(8)) • Dữ liệu Cookie & IndexedDB cô lập")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Nhận diện ứng dụng & Đa tài khoản") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Tên ứng dụng").font(.caption.weight(.semibold))
                                    TextField("Tên ứng dụng", text: $ui.draft.name)
                                        .textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nhãn tài khoản").font(.caption.weight(.semibold))
                                    TextField("VD: Cá nhân, Công việc, Sale 1", text: $ui.draft.accountLabel)
                                        .textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Huy hiệu góc Icon").font(.caption.weight(.semibold))
                                    TextField("1, 2, CV", text: $ui.draft.badgeShortText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 90)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("URL Trang chủ").font(.caption.weight(.semibold))
                                TextField("https://...", text: $ui.draft.baseURLString)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }

                            HStack(spacing: 16) {
                                HStack(spacing: 6) {
                                    ForEach(accentPalette, id: \.self) { hex in
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Circle().strokeBorder(.white, lineWidth: ui.draft.accentHex == hex ? 2 : 0)
                                            )
                                            .onTapGesture { ui.draft.accentHex = hex }
                                    }
                                }
                                Spacer()
                                Button("Đổi ảnh Icon...") {
                                    pickIconFile()
                                }
                                .controlSize(.small)
                                if ui.draft.customIconPNGData != nil {
                                    Button("Khôi phục Icon gốc") {
                                        ui.draft.customIconPNGData = nil
                                    }
                                    .controlSize(.small)
                                }
                            }

                            if !store.isStandaloneMode {
                                HStack(spacing: 16) {
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
                        }
                        .padding(8)
                    }

                    GroupBox("Xử lý khi bấm đường link trong tin nhắn") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Chế độ mở link:", selection: $ui.draft.linkRoutingMode) {
                                ForEach(LinkRoutingMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }

                            Picker("Trình duyệt ngoài ưu tiên:", selection: $ui.draft.preferredExternalBrowserBundleID) {
                                Text("Trình duyệt mặc định của macOS (\(LinkRouter.defaultSystemBrowserName()))")
                                    .tag(String?.none)
                                ForEach(installedBrowsers) { browser in
                                    Text(browser.name).tag(String?.some(browser.bundleIdentifier))
                                }
                            }

                            Toggle("Tự động bóc tách link chuyển hướng trung gian (l.facebook.com, l.messenger.com, Google URL...)", isOn: $ui.draft.unwrapRedirectLinks)
                            Toggle("Trình duyệt trong App dùng chung phiên đăng nhập với tài khoản này (tiện xem link nội bộ FB/Docs)", isOn: $ui.draft.inAppShareSession)
                        }
                        .padding(8)
                    }

                    GroupBox("Trình duyệt, Thông báo & Hiệu năng") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("User-Agent:", selection: $ui.draft.userAgentPreset) {
                                ForEach(UserAgentPreset.allCases) { ua in
                                    Text(ua.title).tag(ua)
                                }
                            }
                            if ui.draft.userAgentPreset == .custom {
                                TextField("Nhập chuỗi User-Agent tuỳ chỉnh...", text: $ui.draft.customUserAgent)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("Tỷ lệ thu phóng (\(Int(round(ui.draft.pageZoom * 100)))%):")
                                Slider(value: $ui.draft.pageZoom, in: 0.6...1.8, step: 0.05)
                                Button("100%") { ui.draft.pageZoom = 1.0 }
                                    .controlSize(.small)
                            }

                            HStack(spacing: 24) {
                                Toggle("Tắt thông báo từ tài khoản này", isOn: $ui.draft.notificationsMuted)
                                Toggle("Giữ chạy nền để nhận tin nhắn tức thì", isOn: $ui.draft.keepAwakeInBackground)
                            }
                        }
                        .padding(8)
                    }

                    if !store.isStandaloneMode {
                        GroupBox("Ứng dụng macOS độc lập (.app) & Dữ liệu phiên") {
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

                                if let path = ui.draft.exportedAppPath, FileManager.default.fileExists(atPath: path) {
                                    Button("Hiện .app trong Finder") {
                                        DedicatedAppBuilder.revealInFinder(at: URL(fileURLWithPath: path))
                                    }
                                    Button("Ghim lên Dock") {
                                        DedicatedAppBuilder.pinToMacOSDock(appURL: URL(fileURLWithPath: path))
                                    }
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    ui.confirmClearSession = true
                                } label: {
                                    Label("Đăng xuất / Xoá Cookie", systemImage: "trash")
                                }
                            }
                            .padding(8)
                        }
                    } else {
                        HStack {
                            Button(role: .destructive) {
                                ui.confirmClearSession = true
                            } label: {
                                Label("Đăng xuất & Xoá dữ liệu phiên này", systemImage: "trash")
                            }
                            Spacer()
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                if !store.isStandaloneMode {
                    Button(role: .destructive) {
                        ui.confirmDeleteInstance = true
                    } label: {
                        Label("Xoá tài khoản này", systemImage: "trash")
                    }
                }

                Spacer()

                Button("Huỷ") { dismiss() }
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
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 720, height: 640)
        .onAppear {
            if ui.draft.id != initialDraft.id {
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

// MARK: - Global Workspace Settings Sheet

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
                        .font(.title3.weight(.bold))
                    Text("Quản lý hành vi mở Link mặc định, Trình duyệt trong App, Không gian và Dedicated Apps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Cập nhật tự động qua GitHub (hungmtuci/WebBox)") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Phiên bản đang chạy: v\(updater.currentVersion)")
                                        .font(.callout.weight(.semibold))
                                    Text(updateStatusDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if case let .available(info) = updater.state {
                                    Button {
                                        updater.installAvailableUpdate()
                                    } label: {
                                        Label("Cập nhật ngay v\(info.version)", systemImage: "arrow.down.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    .controlSize(.small)
                                }

                                Button {
                                    updater.checkForUpdatesManually()
                                } label: {
                                    Label(
                                        updater.isBusy ? "Đang xử lý..." : "Kiểm tra cập nhật",
                                        systemImage: "arrow.triangle.2.circlepath"
                                    )
                                }
                                .disabled(updater.isBusy)
                                .controlSize(.small)

                                Button {
                                    updater.openGitHubRepoPage()
                                } label: {
                                    Label("GitHub", systemImage: "arrow.up.right.square")
                                }
                                .controlSize(.small)
                            }

                            Toggle("Tự động kiểm tra phiên bản mới từ GitHub khi khởi động", isOn: $updater.autoCheckOnLaunch)
                                .font(.caption)
                        }
                        .padding(8)
                    }

                    GroupBox("Mặc định khi bấm đường link trong tin nhắn") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Hành vi mặc định toàn cục:", selection: $store.preferences.defaultLinkRoutingMode) {
                                ForEach(LinkRoutingMode.globalSelectableCases) { mode in
                                    Text("\(mode.title) — \(mode.subtitle)").tag(mode)
                                }
                            }

                            Picker("Bố cục Trình duyệt tích hợp trong App:", selection: $store.preferences.inAppBrowserLayout) {
                                ForEach(InAppBrowserLayoutMode.allCases) { layout in
                                    Text(layout.title).tag(layout)
                                }
                            }

                            Text("Lưu ý: Bạn vẫn có thể đặt chế độ mở link riêng cho từng tài khoản Zalo / Facebook, hoặc giữ ⌘+Click (mở trong App) và ⌥+Click (mở trình duyệt ngoài) bất cứ lúc nào.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }

                    GroupBox("Giao diện & Thông báo") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Hiện nhãn tên tài khoản bên dưới biểu tượng ở thanh bên", isOn: $store.preferences.showAccountLabelsInSidebar)
                            Toggle("Chế độ Không làm phiền (Tạm tắt toàn bộ thông báo đẩy)", isOn: $store.preferences.globalDoNotDisturb)
                            Toggle("Bật công cụ Web Inspector (Inspect Element khi chuột phải)", isOn: $store.preferences.enableDeveloperExtras)
                        }
                        .padding(8)
                    }

                    GroupBox("Thư mục lưu Dedicated Desktop Apps (.app)") {
                        HStack {
                            Text(store.preferences.dedicatedAppsInstallDirectory)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Mở thư mục") {
                                let url = URL(fileURLWithPath: store.preferences.dedicatedAppsInstallDirectory)
                                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(url)
                            }
                            .controlSize(.small)
                            Button("Đổi thư mục...") {
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
                        .padding(8)
                    }

                    if !store.isStandaloneMode {
                        GroupBox("Quản lý Không gian làm việc (Spaces)") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(store.spaces) { space in
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: space.colorHex))
                                            .frame(width: 10, height: 10)
                                        Text(space.name)
                                            .font(.callout.weight(.medium))
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

                                Divider()

                                HStack {
                                    TextField("Tên Space mới (VD: Dự án A, Khách hàng VIP...)", text: $ui.newSpaceName)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Thêm Space") {
                                        store.addSpace(name: ui.newSpaceName, symbolName: "folder.fill", colorHex: ui.newSpaceColor)
                                        ui.newSpaceName = ""
                                    }
                                    .disabled(ui.newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Đóng & Lưu") {
                    store.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 640, height: 620)
    }

    private var updateStatusDescription: String {
        switch updater.state {
        case .idle:
            return "Nhấn 'Kiểm tra cập nhật' để đối chiếu bản mới nhất trên GitHub Releases."
        case .checking:
            return "Đang kết nối tới github.com/hungmtuci/WebBox..."
        case .upToDate(let ver):
            return "Bạn đang sử dụng phiên bản mới nhất (v\(ver))."
        case .available(let info):
            return "Đã phát hiện bản mới v\(info.version) trên GitHub! Sẵn sàng tải và nâng cấp tự động."
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
                        .font(.title3.weight(.bold))
                    Text("Xuất bất kỳ tài khoản Zalo, Facebook, Web nào thành ứng dụng macOS độc lập trong ~/Applications")
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

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.instances) { inst in
                        let isInstalled = inst.exportedAppPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
                        HStack(spacing: 14) {
                            AppInstanceAvatarView(instance: inst, size: 44)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(inst.displayTitle)
                                        .font(.callout.weight(.bold))
                                    if isInstalled {
                                        Text("Đã cài .app")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.green.opacity(0.15)))
                                    }
                                }
                                Text(DedicatedAppBuilder.suggestedAppBundleName(for: inst))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isInstalled, let path = inst.exportedAppPath {
                                let appURL = URL(fileURLWithPath: path)
                                Button("Chạy .app") {
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
                                    Label("Tạo Dedicated .app", systemImage: "arrow.down.app.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 680, height: 500)
        .onAppear {
            store.verifyExportedAppPaths()
        }
    }
}
