import Foundation

enum CatalogCategory: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case messaging = "Nhắn tin & Chat"
    case social = "Mạng xã hội"
    case productivity = "Email & Công việc"
    case ai = "Trí tuệ nhân tạo (AI)"
    case business = "Bán hàng & Quản trị"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .messaging: return "bubble.left.and.bubble.right.fill"
        case .social: return "person.2.fill"
        case .productivity: return "briefcase.fill"
        case .ai: return "sparkles"
        case .business: return "bag.fill"
        }
    }
}

struct CatalogAppPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let baseURLString: String
    let category: CatalogCategory
    let accentHex: String
    let monogram: String
    let symbolName: String?
    let internalHostSuffixes: [String]
    let recommendedMultiAccount: Bool
    let defaultKeepAwake: Bool

    func makeInstance(
        accountLabel: String = "",
        badgeShortText: String = "",
        spaceID: UUID? = nil,
        profileID: UUID = UUID(),
        linkRoutingMode: LinkRoutingMode = .useGlobal,
        customIconPNGData: Data? = nil,
        sortOrder: Int = 0
    ) -> WebAppInstance {
        WebAppInstance(
            catalogID: id,
            name: name,
            accountLabel: accountLabel,
            badgeShortText: badgeShortText,
            baseURLString: baseURLString,
            accentHex: accentHex,
            monogram: monogram,
            symbolName: symbolName,
            customIconPNGData: customIconPNGData,
            profileID: profileID,
            spaceID: spaceID,
            linkRoutingMode: linkRoutingMode,
            keepAwakeInBackground: defaultKeepAwake,
            sortOrder: sortOrder
        )
    }
}

enum CatalogDirectory {
    static let presets: [CatalogAppPreset] = [
        // MARK: - Messaging & Chat (Multi-account heroes)
        CatalogAppPreset(
            id: "zalo",
            name: "Zalo",
            subtitle: "Zalo Web — Đăng nhập song song nhiều tài khoản cá nhân & công việc",
            baseURLString: "https://chat.zalo.me",
            category: .messaging,
            accentHex: "#0068FF",
            monogram: "Z",
            symbolName: nil,
            internalHostSuffixes: ["zalo.me", "zaloapp.com", "zadn.vn", "zdn.vn", "zing.vn"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "messenger",
            name: "Messenger",
            subtitle: "Trò chuyện Facebook Messenger độc lập, hỗ trợ nhiều nick",
            baseURLString: "https://www.messenger.com",
            category: .messaging,
            accentHex: "#0084FF",
            monogram: "M",
            symbolName: "bolt.horizontal.circle.fill",
            internalHostSuffixes: ["messenger.com", "facebook.com", "fbcdn.net"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "telegram",
            name: "Telegram",
            subtitle: "Nhắn tin tốc độ cao với nhiều số điện thoại độc lập",
            baseURLString: "https://web.telegram.org/k/",
            category: .messaging,
            accentHex: "#24A1DE",
            monogram: "TG",
            symbolName: "paperplane.fill",
            internalHostSuffixes: ["telegram.org", "t.me"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "whatsapp",
            name: "WhatsApp",
            subtitle: "WhatsApp Web cho nhiều thiết bị & số điện thoại khác nhau",
            baseURLString: "https://web.whatsapp.com",
            category: .messaging,
            accentHex: "#25D366",
            monogram: "WA",
            symbolName: "phone.bubble.fill",
            internalHostSuffixes: ["whatsapp.com", "whatsapp.net"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "discord",
            name: "Discord",
            subtitle: "Cộng đồng, voice chat và làm việc nhóm đa tài khoản",
            baseURLString: "https://discord.com/app",
            category: .messaging,
            accentHex: "#5865F2",
            monogram: "DC",
            symbolName: "gamecontroller.fill",
            internalHostSuffixes: ["discord.com", "discordapp.com", "discord.gg"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "slack",
            name: "Slack",
            subtitle: "Quản lý nhiều Workspace công ty & khách hàng riêng biệt",
            baseURLString: "https://app.slack.com/client",
            category: .messaging,
            accentHex: "#611F69",
            monogram: "SL",
            symbolName: "number",
            internalHostSuffixes: ["slack.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "lark",
            name: "Lark Messenger",
            subtitle: "Nền tảng chat & cộng tác doanh nghiệp Lark Suite",
            baseURLString: "https://www.larksuite.com/messenger/",
            category: .messaging,
            accentHex: "#3370FF",
            monogram: "LK",
            symbolName: "bird.fill",
            internalHostSuffixes: ["larksuite.com", "feishu.cn"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "teams",
            name: "Microsoft Teams",
            subtitle: "Họp trực tuyến & nhắn tin nội bộ nhiều tổ chức Microsoft 365",
            baseURLString: "https://teams.microsoft.com",
            category: .messaging,
            accentHex: "#5059C9",
            monogram: "MT",
            symbolName: "person.3.fill",
            internalHostSuffixes: ["microsoft.com", "live.com", "office.com", "sharepoint.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),

        // MARK: - Social Media
        CatalogAppPreset(
            id: "facebook",
            name: "Facebook",
            subtitle: "Chạy song song nhiều nick Facebook, Fanpage & Group không bị đá phiên",
            baseURLString: "https://www.facebook.com",
            category: .social,
            accentHex: "#1877F2",
            monogram: "f",
            symbolName: nil,
            internalHostSuffixes: ["facebook.com", "fb.com", "fbcdn.net"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "instagram",
            name: "Instagram",
            subtitle: "Quản lý Direct Message & nhiều tài khoản thương hiệu Instagram",
            baseURLString: "https://www.instagram.com",
            category: .social,
            accentHex: "#E1306C",
            monogram: "IG",
            symbolName: "camera.fill",
            internalHostSuffixes: ["instagram.com", "facebook.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "threads",
            name: "Threads",
            subtitle: "Mạng xã hội thảo luận văn bản của Meta",
            baseURLString: "https://www.threads.net",
            category: .social,
            accentHex: "#1C1C1E",
            monogram: "@",
            symbolName: "at",
            internalHostSuffixes: ["threads.net", "instagram.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "x",
            name: "X (Twitter)",
            subtitle: "Cập nhật tin tức & quản lý nhiều tài khoản X",
            baseURLString: "https://x.com",
            category: .social,
            accentHex: "#14171A",
            monogram: "X",
            symbolName: nil,
            internalHostSuffixes: ["x.com", "twitter.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "tiktok",
            name: "TikTok",
            subtitle: "Xem video, tin nhắn và quản lý nhiều kênh TikTok",
            baseURLString: "https://www.tiktok.com",
            category: .social,
            accentHex: "#FE2C55",
            monogram: "TT",
            symbolName: "music.note",
            internalHostSuffixes: ["tiktok.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "youtube",
            name: "YouTube",
            subtitle: "Xem video và quản lý nhiều kênh YouTube / YouTube Studio",
            baseURLString: "https://www.youtube.com",
            category: .social,
            accentHex: "#FF0000",
            monogram: "YT",
            symbolName: "play.rectangle.fill",
            internalHostSuffixes: ["youtube.com", "youtu.be", "google.com"],
            recommendedMultiAccount: false,
            defaultKeepAwake: false
        ),

        // MARK: - Email & Productivity
        CatalogAppPreset(
            id: "gmail",
            name: "Gmail",
            subtitle: "Tách biệt hộp thư Gmail cá nhân và Gmail công ty",
            baseURLString: "https://mail.google.com",
            category: .productivity,
            accentHex: "#EA4335",
            monogram: "GM",
            symbolName: "envelope.fill",
            internalHostSuffixes: ["mail.google.com", "accounts.google.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "outlook",
            name: "Outlook Mail",
            subtitle: "Email và lịch làm việc Microsoft Outlook",
            baseURLString: "https://outlook.office.com/mail/",
            category: .productivity,
            accentHex: "#0078D4",
            monogram: "OL",
            symbolName: "tray.full.fill",
            internalHostSuffixes: ["outlook.office.com", "outlook.live.com", "microsoft.com", "live.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "gdrive",
            name: "Google Drive",
            subtitle: "Quản lý tài liệu đám mây nhiều tài khoản Google độc lập",
            baseURLString: "https://drive.google.com",
            category: .productivity,
            accentHex: "#34A853",
            monogram: "GD",
            symbolName: "externaldrive.fill.badge.icloud",
            internalHostSuffixes: ["drive.google.com", "docs.google.com", "accounts.google.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "gcalendar",
            name: "Google Calendar",
            subtitle: "Lịch biểu thông minh và nhắc hẹn sự kiện",
            baseURLString: "https://calendar.google.com",
            category: .productivity,
            accentHex: "#4285F4",
            monogram: "31",
            symbolName: "calendar",
            internalHostSuffixes: ["calendar.google.com", "accounts.google.com"],
            recommendedMultiAccount: false,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "notion",
            name: "Notion",
            subtitle: "Ghi chú, Wiki và quản lý dự án đa không gian",
            baseURLString: "https://www.notion.so",
            category: .productivity,
            accentHex: "#2F3437",
            monogram: "N",
            symbolName: "doc.text.fill",
            internalHostSuffixes: ["notion.so", "notion.site"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "figma",
            name: "Figma",
            subtitle: "Thiết kế giao diện UI/UX cộng tác trực tuyến",
            baseURLString: "https://www.figma.com",
            category: .productivity,
            accentHex: "#A259FF",
            monogram: "Fg",
            symbolName: "paintbrush.pointed.fill",
            internalHostSuffixes: ["figma.com"],
            recommendedMultiAccount: false,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "canva",
            name: "Canva",
            subtitle: "Thiết kế đồ họa, banner và bài đăng mạng xã hội nhanh chóng",
            baseURLString: "https://www.canva.com",
            category: .productivity,
            accentHex: "#00C4CC",
            monogram: "Cv",
            symbolName: "sparkles.rectangle.stack.fill",
            internalHostSuffixes: ["canva.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "github",
            name: "GitHub",
            subtitle: "Quản lý mã nguồn cá nhân & doanh nghiệp tách biệt",
            baseURLString: "https://github.com",
            category: .productivity,
            accentHex: "#24292F",
            monogram: "GH",
            symbolName: "chevron.left.forwardslash.chevron.right",
            internalHostSuffixes: ["github.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),

        // MARK: - AI Assistants
        CatalogAppPreset(
            id: "chatgpt",
            name: "ChatGPT",
            subtitle: "Trợ lý AI OpenAI (hỗ trợ chạy song song tài khoản Plus / Team)",
            baseURLString: "https://chatgpt.com",
            category: .ai,
            accentHex: "#10A37F",
            monogram: "AI",
            symbolName: "sparkles",
            internalHostSuffixes: ["chatgpt.com", "openai.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "claude",
            name: "Claude",
            subtitle: "Trợ lý lập trình & phân tích chuyên sâu từ Anthropic",
            baseURLString: "https://claude.ai",
            category: .ai,
            accentHex: "#D97757",
            monogram: "Cl",
            symbolName: "brain.head.profile",
            internalHostSuffixes: ["claude.ai", "anthropic.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "gemini",
            name: "Google Gemini",
            subtitle: "Trợ lý AI đa phương thức của Google",
            baseURLString: "https://gemini.google.com",
            category: .ai,
            accentHex: "#4E82EE",
            monogram: "Gm",
            symbolName: "wand.and.stars",
            internalHostSuffixes: ["gemini.google.com", "accounts.google.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: false
        ),
        CatalogAppPreset(
            id: "perplexity",
            name: "Perplexity",
            subtitle: "Công cụ tìm kiếm & nghiên cứu trích dẫn nguồn bằng AI",
            baseURLString: "https://www.perplexity.ai",
            category: .ai,
            accentHex: "#20808D",
            monogram: "Px",
            symbolName: "magnifyingglass.circle.fill",
            internalHostSuffixes: ["perplexity.ai"],
            recommendedMultiAccount: false,
            defaultKeepAwake: false
        ),

        // MARK: - Business, Seller & CSKH (Super useful in VN!)
        CatalogAppPreset(
            id: "meta_business",
            name: "Meta Business Suite",
            subtitle: "Quản lý hộp thư nhiều Fanpage, Instagram & trình quản lý quảng cáo",
            baseURLString: "https://business.facebook.com",
            category: .business,
            accentHex: "#0668E1",
            monogram: "MB",
            symbolName: "building.2.fill",
            internalHostSuffixes: ["facebook.com", "fb.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "shopee_seller",
            name: "Shopee Kênh Người Bán",
            subtitle: "Quản lý nhiều gian hàng Shopee cùng lúc không lo trùng cookie",
            baseURLString: "https://banhang.shopee.vn",
            category: .business,
            accentHex: "#EE4D2D",
            monogram: "SP",
            symbolName: "bag.fill",
            internalHostSuffixes: ["shopee.vn"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "tiktok_seller",
            name: "TikTok Shop Seller",
            subtitle: "Vận hành song song nhiều cửa hàng TikTok Shop Việt Nam",
            baseURLString: "https://seller-vn.tiktok.com",
            category: .business,
            accentHex: "#111111",
            monogram: "TS",
            symbolName: "cart.fill",
            internalHostSuffixes: ["tiktok.com"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        ),
        CatalogAppPreset(
            id: "pancake",
            name: "Pancake CSKH",
            subtitle: "Phần mềm quản lý chat đa kênh cho chủ shop & đội sale",
            baseURLString: "https://pancake.vn",
            category: .business,
            accentHex: "#2563EB",
            monogram: "PK",
            symbolName: "text.bubble.fill",
            internalHostSuffixes: ["pancake.vn", "pages.fm"],
            recommendedMultiAccount: true,
            defaultKeepAwake: true
        )
    ]

    static func preset(for id: String?) -> CatalogAppPreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }
}
