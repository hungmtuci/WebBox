import Foundation
import AppKit
import SwiftUI

// MARK: - Link Routing & Browser Modes

enum LinkRoutingMode: String, Codable, CaseIterable, Identifiable {
    case useGlobal = "useGlobal"
    case askEveryTime = "askEveryTime"
    case inAppBrowser = "inAppBrowser"
    case externalBrowser = "externalBrowser"

    var id: String { rawValue }

    static var globalSelectableCases: [LinkRoutingMode] {
        [.askEveryTime, .inAppBrowser, .externalBrowser]
    }

    var title: String {
        switch self {
        case .useGlobal:
            return "Theo cài đặt chung"
        case .askEveryTime:
            return "Hỏi nhanh mỗi khi bấm link"
        case .inAppBrowser:
            return "Mở bằng Trình duyệt trong App"
        case .externalBrowser:
            return "Mở bằng Trình duyệt ngoài (macOS)"
        }
    }

    var shortTitle: String {
        switch self {
        case .useGlobal: return "Mặc định chung"
        case .askEveryTime: return "Hỏi mỗi lần"
        case .inAppBrowser: return "Trong App"
        case .externalBrowser: return "Trình duyệt ngoài"
        }
    }

    var subtitle: String {
        switch self {
        case .useGlobal:
            return "Sử dụng chế độ mở link mặc định của WebBox"
        case .askEveryTime:
            return "Hiện bảng chọn nhanh: Mở trong App hoặc Mở trình duyệt ngoài"
        case .inAppBrowser:
            return "Mở ngay trong khung trình duyệt tích hợp (có nút chuyển ra ngoài)"
        case .externalBrowser:
            return "Tự động mở bằng Safari, Chrome, Arc... trên hệ thống"
        }
    }

    var symbolName: String {
        switch self {
        case .useGlobal: return "gearshape.2"
        case .askEveryTime: return "questionmark.bubble.fill"
        case .inAppBrowser: return "sidebar.right"
        case .externalBrowser: return "safari.fill"
        }
    }
}

enum InAppBrowserLayoutMode: String, Codable, CaseIterable, Identifiable {
    case splitRight = "splitRight"
    case fullOverlay = "fullOverlay"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .splitRight: return "Chia đôi cạnh bên (Vừa xem link vừa chat)"
        case .fullOverlay: return "Toàn khung cửa sổ (Như tab trình duyệt)"
        }
    }

    var symbolName: String {
        switch self {
        case .splitRight: return "rectangle.split.2x1"
        case .fullOverlay: return "macwindow"
        }
    }
}

enum UserAgentPreset: String, Codable, CaseIterable, Identifiable {
    case safariMac = "safariMac"
    case chromeMac = "chromeMac"
    case mobileIOS = "mobileIOS"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safariMac:
            return "Safari macOS (Khuyên dùng - Chuẩn OAuth & Zalo/FB)"
        case .chromeMac:
            return "Google Chrome macOS"
        case .mobileIOS:
            return "Safari iPhone (Giao diện Mobile)"
        case .custom:
            return "Tuỳ chỉnh (Custom User-Agent)"
        }
    }

    func resolvedUserAgent(customValue: String) -> String {
        switch self {
        case .safariMac:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        case .chromeMac:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        case .mobileIOS:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
        case .custom:
            let trimmed = customValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? UserAgentPreset.safariMac.resolvedUserAgent(customValue: "")
                : trimmed
        }
    }
}

// MARK: - Spaces & Profiles

struct SpaceItem: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var symbolName: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "square.grid.2x2.fill",
        colorHex: String = "#0A84FF"
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
    }
}

struct SessionProfileInfo: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#0A84FF",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

// MARK: - Web App Instance (Multi-Account Unit)

struct WebAppInstance: Codable, Identifiable, Hashable {
    var id: UUID
    var catalogID: String?
    var name: String
    var accountLabel: String
    var badgeShortText: String
    var baseURLString: String
    var accentHex: String
    var monogram: String
    var symbolName: String?
    var customIconPNGData: Data?
    var profileID: UUID
    var spaceID: UUID?

    // Smart Link Handling
    var linkRoutingMode: LinkRoutingMode
    var preferredExternalBrowserBundleID: String?
    var unwrapRedirectLinks: Bool
    var inAppShareSession: Bool

    // Browser & Performance Options
    var userAgentPreset: UserAgentPreset
    var customUserAgent: String
    var pageZoom: Double
    var notificationsMuted: Bool
    var keepAwakeInBackground: Bool
    var customCSS: String

    // Dedicated .app Tracking
    var exportedAppPath: String?
    var createdAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        catalogID: String? = nil,
        name: String,
        accountLabel: String = "",
        badgeShortText: String = "",
        baseURLString: String,
        accentHex: String = "#0A84FF",
        monogram: String = "W",
        symbolName: String? = nil,
        customIconPNGData: Data? = nil,
        profileID: UUID = UUID(),
        spaceID: UUID? = nil,
        linkRoutingMode: LinkRoutingMode = .useGlobal,
        preferredExternalBrowserBundleID: String? = nil,
        unwrapRedirectLinks: Bool = true,
        inAppShareSession: Bool = true,
        userAgentPreset: UserAgentPreset = .safariMac,
        customUserAgent: String = "",
        pageZoom: Double = 1.0,
        notificationsMuted: Bool = false,
        keepAwakeInBackground: Bool = true,
        customCSS: String = "",
        exportedAppPath: String? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.catalogID = catalogID
        self.name = name
        self.accountLabel = accountLabel
        self.badgeShortText = badgeShortText
        self.baseURLString = baseURLString
        self.accentHex = accentHex
        self.monogram = monogram
        self.symbolName = symbolName
        self.customIconPNGData = customIconPNGData
        self.profileID = profileID
        self.spaceID = spaceID
        self.linkRoutingMode = linkRoutingMode
        self.preferredExternalBrowserBundleID = preferredExternalBrowserBundleID
        self.unwrapRedirectLinks = unwrapRedirectLinks
        self.inAppShareSession = inAppShareSession
        self.userAgentPreset = userAgentPreset
        self.customUserAgent = customUserAgent
        self.pageZoom = pageZoom
        self.notificationsMuted = notificationsMuted
        self.keepAwakeInBackground = keepAwakeInBackground
        self.customCSS = customCSS
        self.exportedAppPath = exportedAppPath
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    var displayTitle: String {
        let trimmed = accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return name
        }
        return "\(name) — \(trimmed)"
    }

    var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: "https://example.com")!
    }

    var resolvedUserAgent: String {
        userAgentPreset.resolvedUserAgent(customValue: customUserAgent)
    }
}

// MARK: - Standalone Dedicated .app Manifest

struct StandaloneAppManifest: Codable {
    var instance: WebAppInstance
    var defaultLinkRoutingMode: LinkRoutingMode
    var inAppBrowserLayout: InAppBrowserLayoutMode
    var showNavigationToolbar: Bool
    var createdVersion: String
}

// MARK: - Sidebar Display Mode & Actionable Toast

enum SidebarDisplayMode: String, Codable, CaseIterable, Identifiable {
    case expanded = "expanded"
    case compactIcons = "compactIcons"
    case hidden = "hidden"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expanded:
            return "Đầy đủ (Icon & Tên tài khoản)"
        case .compactIcons:
            return "Thu gọn (Chỉ hiện biểu tượng Icon)"
        case .hidden:
            return "Ẩn hoàn toàn"
        }
    }
}

struct WorkspaceToast: Equatable {
    let id = UUID()
    let message: String
    let revealFileURL: URL?
}

// MARK: - Global Preferences

struct GlobalWorkspacePreferences: Codable {
    var defaultLinkRoutingMode: LinkRoutingMode = .askEveryTime
    var inAppBrowserLayout: InAppBrowserLayoutMode = .splitRight
    var globalDoNotDisturb: Bool = false
    var autoHibernateMinutes: Int = 0 // 0 = Tắt ngủ đông tự động
    var confirmBeforeClosingModifiedForms: Bool = false
    var enableDeveloperExtras: Bool = true
    var isSidebarVisible: Bool = true
    var isSidebarCompact: Bool = false
    var showAccountLabelsInSidebar: Bool = true
    var downloadsDirectory: String = Self.defaultDownloadsDirectoryPath
    var askWhereToSaveEachDownload: Bool = false
    var dedicatedAppsInstallDirectory: String = {
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path
        return homeApps
    }()

    static var defaultDownloadsDirectoryPath: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true).path
    }

    var sidebarDisplayMode: SidebarDisplayMode {
        get {
            if !isSidebarVisible { return .hidden }
            return isSidebarCompact ? .compactIcons : .expanded
        }
        set {
            switch newValue {
            case .expanded:
                isSidebarVisible = true
                isSidebarCompact = false
            case .compactIcons:
                isSidebarVisible = true
                isSidebarCompact = true
            case .hidden:
                isSidebarVisible = false
            }
        }
    }

    init() {}

    enum CodingKeys: String, CodingKey {
        case defaultLinkRoutingMode
        case inAppBrowserLayout
        case globalDoNotDisturb
        case autoHibernateMinutes
        case confirmBeforeClosingModifiedForms
        case enableDeveloperExtras
        case isSidebarVisible
        case isSidebarCompact
        case showAccountLabelsInSidebar
        case downloadsDirectory
        case askWhereToSaveEachDownload
        case dedicatedAppsInstallDirectory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultLinkRoutingMode = try c.decodeIfPresent(LinkRoutingMode.self, forKey: .defaultLinkRoutingMode) ?? .askEveryTime
        inAppBrowserLayout = try c.decodeIfPresent(InAppBrowserLayoutMode.self, forKey: .inAppBrowserLayout) ?? .splitRight
        globalDoNotDisturb = try c.decodeIfPresent(Bool.self, forKey: .globalDoNotDisturb) ?? false
        autoHibernateMinutes = try c.decodeIfPresent(Int.self, forKey: .autoHibernateMinutes) ?? 0
        confirmBeforeClosingModifiedForms = try c.decodeIfPresent(Bool.self, forKey: .confirmBeforeClosingModifiedForms) ?? false
        enableDeveloperExtras = try c.decodeIfPresent(Bool.self, forKey: .enableDeveloperExtras) ?? true
        isSidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .isSidebarVisible) ?? true
        isSidebarCompact = try c.decodeIfPresent(Bool.self, forKey: .isSidebarCompact) ?? false
        showAccountLabelsInSidebar = try c.decodeIfPresent(Bool.self, forKey: .showAccountLabelsInSidebar) ?? true
        downloadsDirectory = try c.decodeIfPresent(String.self, forKey: .downloadsDirectory) ?? Self.defaultDownloadsDirectoryPath
        askWhereToSaveEachDownload = try c.decodeIfPresent(Bool.self, forKey: .askWhereToSaveEachDownload) ?? false
        let defaultDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path
        dedicatedAppsInstallDirectory = try c.decodeIfPresent(String.self, forKey: .dedicatedAppsInstallDirectory) ?? defaultDir
    }
}

// MARK: - Runtime Link Prompt, In-App Browser Tab & Downloads

struct PendingLinkPrompt: Identifiable, Equatable {
    let id = UUID()
    let sourceInstanceID: UUID
    let sourceInstanceTitle: String
    let originalURL: URL
    let resolvedURL: URL
    let timestamp: Date = Date()

    var hostDisplay: String {
        resolvedURL.host ?? resolvedURL.absoluteString
    }

    var wasUnwrapped: Bool {
        originalURL.absoluteString != resolvedURL.absoluteString
    }
}

struct InAppBrowserTab: Identifiable, Equatable {
    let id: UUID
    let ownerInstanceID: UUID
    let profileID: UUID?
    var currentURL: URL
    var title: String
    var isLoading: Bool
    var estimatedProgress: Double
    var canGoBack: Bool
    var canGoForward: Bool

    init(
        id: UUID = UUID(),
        ownerInstanceID: UUID,
        profileID: UUID?,
        initialURL: URL
    ) {
        self.id = id
        self.ownerInstanceID = ownerInstanceID
        self.profileID = profileID
        self.currentURL = initialURL
        self.title = initialURL.host ?? initialURL.absoluteString
        self.isLoading = true
        self.estimatedProgress = 0.1
        self.canGoBack = false
        self.canGoForward = false
    }
}

struct DownloadTaskItem: Identifiable {
    let id: UUID
    let sourceInstanceTitle: String
    var filename: String
    var destinationURL: URL?
    var bytesReceived: Int64
    var expectedBytes: Int64
    var state: State
    let startedAt: Date

    enum State: Equatable {
        case downloading
        case completed
        case failed(String)
    }

    var progressFraction: Double? {
        guard expectedBytes > 0 else { return nil }
        return min(1.0, max(0.0, Double(bytesReceived) / Double(expectedBytes)))
    }
}

struct ExternalBrowserInfo: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let appURL: URL
}

// MARK: - Color Hex Helper

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 3:
            (r, g, b) = (((int >> 8) & 0xF) * 17, ((int >> 4) & 0xF) * 17, (int & 0xF) * 17)
        default:
            (r, g, b) = (10, 132, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 3:
            (r, g, b) = (((int >> 8) & 0xF) * 17, ((int >> 4) & 0xF) * 17, (int & 0xF) * 17)
        default:
            (r, g, b) = (10, 132, 255)
        }
        return NSColor(
            calibratedRed: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: 1.0
        )
    }
}
