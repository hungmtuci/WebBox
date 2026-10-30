import Foundation
import AppKit

/// Automatically fetches, validates, and caches high-resolution official app icons & favicons
/// for both Catalog presets (via Apple iTunes Search CDN 512px artwork) and any custom Website URL
/// (via HTML apple-touch-icon / rel="icon" parsing + Google FaviconV2 256px + origin fallback).
@MainActor
final class AppIconFetcher: ObservableObject {
    static let shared = AppIconFetcher()

    /// In-memory cache keyed by preset ID or normalized domain host
    @Published private(set) var cachedPresetIcons: [String: Data] = [:]
    private var inFlightKeys: Set<String> = []
    private let cacheDirectory: URL

    private static let appStoreSearchTerms: [String: (term: String, mustContain: String)] = [
        "zalo": ("Zalo", "zalo"),
        "messenger": ("Messenger", "messenger"),
        "telegram": ("Telegram Messenger", "telegram"),
        "whatsapp": ("WhatsApp Messenger", "whatsapp"),
        "discord": ("Discord", "discord"),
        "slack": ("Slack", "slack"),
        "lark": ("Lark", "lark"),
        "teams": ("Microsoft Teams", "teams"),
        "facebook": ("Facebook", "facebook"),
        "instagram": ("Instagram", "instagram"),
        "threads": ("Threads", "threads"),
        "x": ("X", "x"),
        "tiktok": ("TikTok", "tiktok"),
        "youtube": ("YouTube", "youtube"),
        "gmail": ("Gmail", "gmail"),
        "outlook": ("Microsoft Outlook", "outlook"),
        "gdrive": ("Google Drive", "drive"),
        "gcalendar": ("Google Calendar", "calendar"),
        "notion": ("Notion", "notion"),
        "figma": ("Figma", "figma"),
        "canva": ("Canva", "canva"),
        "github": ("GitHub", "github"),
        "chatgpt": ("ChatGPT", "chatgpt"),
        "claude": ("Claude by Anthropic", "claude"),
        "gemini": ("Google Gemini", "gemini"),
        "perplexity": ("Perplexity", "perplexity"),
        "meta_business": ("Meta Business Suite", "business"),
        "shopee_seller": ("Shopee VN", "shopee"),
        "tiktok_seller": ("TikTok Seller", "tiktok"),
        "pancake": ("Pancake", "pancake")
    ]

    private struct ITunesSearchResponse: Decodable {
        struct ResultItem: Decodable {
            let trackName: String?
            let artworkUrl512: String?
            let artworkUrl100: String?
        }
        let results: [ResultItem]
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WebBox/IconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDirectory = dir
        loadDiskCachedPresetIcons()
    }

    private func loadDiskCachedPresetIcons() {
        for preset in CatalogDirectory.presets {
            let fileURL = cacheDirectory.appendingPathComponent("preset_\(preset.id).png")
            if let data = try? Data(contentsOf: fileURL), NSImage(data: data) != nil {
                cachedPresetIcons[preset.id] = data
            }
        }
    }

    func cachedIcon(forPresetID id: String) -> Data? {
        cachedPresetIcons[id]
    }

    /// Automatically populates icons for all existing Workspace instances that don't have one yet,
    /// and pre-warms icons for Catalog presets in the background.
    func backfillMissingIcons(in store: WorkspaceStore) {
        for instance in store.instances where instance.customIconPNGData == nil {
            Task { @MainActor in
                if let iconData = await fetchBestIcon(
                    catalogID: instance.catalogID,
                    appName: instance.name,
                    siteURL: instance.baseURL
                ) {
                    if var latest = store.instance(for: instance.id), latest.customIconPNGData == nil {
                        latest.customIconPNGData = iconData
                        store.updateIconSilently(instanceID: latest.id, pngData: iconData)
                    }
                }
            }
        }
    }

    /// Preloads icons for visible catalog cards so the App Directory shows genuine official icons.
    func preloadCatalogIconsIfNeeded() {
        for preset in CatalogDirectory.presets where cachedPresetIcons[preset.id] == nil {
            let key = "preset_\(preset.id)"
            guard !inFlightKeys.contains(key) else { continue }
            inFlightKeys.insert(key)

            Task { @MainActor in
                defer { inFlightKeys.remove(key) }
                guard let url = URL(string: preset.baseURLString) else { return }
                if let data = await fetchBestIcon(catalogID: preset.id, appName: preset.name, siteURL: url) {
                    cachedPresetIcons[preset.id] = data
                    let fileURL = cacheDirectory.appendingPathComponent("preset_\(preset.id).png")
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        }
    }

    /// Multi-tier icon resolver returning clean normalized PNG data (up to 256x256).
    func fetchBestIcon(catalogID: String?, appName: String, siteURL: URL) async -> Data? {
        // 0. Check disk cache for preset first
        if let cid = catalogID, !cid.isEmpty {
            if let mem = cachedPresetIcons[cid] {
                return mem
            }
            let diskURL = cacheDirectory.appendingPathComponent("preset_\(cid).png")
            if let diskData = try? Data(contentsOf: diskURL), NSImage(data: diskData) != nil {
                cachedPresetIcons[cid] = diskData
                return diskData
            }
        }

        // 1. Try official 512px artwork from Apple iTunes / App Store Search API if preset or matching app name
        if let cid = catalogID, let mapping = Self.appStoreSearchTerms[cid] {
            if let png = await fetchFromITunesAPI(term: mapping.term, mustContain: mapping.mustContain) {
                cachedPresetIcons[cid] = png
                try? png.write(to: cacheDirectory.appendingPathComponent("preset_\(cid).png"), options: .atomic)
                return png
            }
        } else if let matchedPreset = CatalogDirectory.presets.first(where: {
            guard let pHost = URL(string: $0.baseURLString)?.host?.lowercased(),
                  let sHost = siteURL.host?.lowercased() else { return false }
            return sHost == pHost || sHost.hasSuffix(".\(pHost)") || pHost.hasSuffix(".\(sHost)")
        }), let mapping = Self.appStoreSearchTerms[matchedPreset.id] {
            if let png = await fetchFromITunesAPI(term: mapping.term, mustContain: mapping.mustContain) {
                cachedPresetIcons[matchedPreset.id] = png
                try? png.write(to: cacheDirectory.appendingPathComponent("preset_\(matchedPreset.id).png"), options: .atomic)
                return png
            }
        }

        // 2. Parse <link rel="apple-touch-icon"> / <link rel="icon"> directly from website HTML
        if let htmlIcon = await fetchIconFromWebpageHTML(siteURL: siteURL) {
            return htmlIcon
        }

        // 3. Try direct /apple-touch-icon.png on origin
        if let scheme = siteURL.scheme, let host = siteURL.host,
           let touchURL = URL(string: "\(scheme)://\(host)/apple-touch-icon.png"),
           let png = await downloadAndNormalizeIcon(from: touchURL, minPixelDimension: 48) {
            return png
        }

        // 4. Try Google Chrome's FaviconV2 256px service
        if let host = siteURL.host {
            let origin = "https://\(host)"
            if let encoded = origin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let gURL = URL(string: "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=\(encoded)&size=256"),
               let png = await downloadAndNormalizeIcon(from: gURL, minPixelDimension: 24) {
                return png
            }

            // 5. Fallback to DuckDuckGo icon service & origin /favicon.ico
            if let ddgURL = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
               let png = await downloadAndNormalizeIcon(from: ddgURL, minPixelDimension: 24) {
                return png
            }

            if let favURL = URL(string: "https://\(host)/favicon.ico"),
               let png = await downloadAndNormalizeIcon(from: favURL, minPixelDimension: 16) {
                return png
            }
        }

        return nil
    }

    // MARK: - Tier 1: Apple iTunes Search API (512x512 HD Official Icons)

    private func fetchFromITunesAPI(term: String, mustContain: String) async -> Data? {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=software&country=vn&limit=5") else {
            return nil
        }

        var req = URLRequest(url: searchURL, timeoutInterval: 8)
        req.setValue("WebBox/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ITunesSearchResponse.self, from: data) else {
            return nil
        }

        let chosen = decoded.results.first { item in
            guard let name = item.trackName?.lowercased() else { return false }
            return name.contains(mustContain.lowercased())
        } ?? decoded.results.first

        guard let artStr = chosen?.artworkUrl512 ?? chosen?.artworkUrl100,
              let artURL = URL(string: artStr) else {
            return nil
        }

        return await downloadAndNormalizeIcon(from: artURL, minPixelDimension: 64)
    }

    // MARK: - Tier 2: HTML <link rel="apple-touch-icon" / "icon"> Scraper

    private func fetchIconFromWebpageHTML(siteURL: URL) async -> Data? {
        var req = URLRequest(url: siteURL, timeoutInterval: 7)
        req.setValue(UserAgentPreset.safariMac.resolvedUserAgent(customValue: ""), forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let effectiveBase = response.url ?? siteURL
        let candidates = Self.extractIconLinks(fromHTML: html, baseURL: effectiveBase)

        for candidateURL in candidates.prefix(4) {
            if let png = await downloadAndNormalizeIcon(from: candidateURL, minPixelDimension: 28) {
                return png
            }
        }
        return nil
    }

    nonisolated static func extractIconLinks(fromHTML html: String, baseURL: URL) -> [URL] {
        // Scan <link ...> tags in <head>
        let headSlice = String(html.prefix(48_000))
        guard let regex = try? NSRegularExpression(pattern: #"<link\b[^>]+>"#, options: [.caseInsensitive]) else {
            return []
        }

        let nsStr = headSlice as NSString
        let matches = regex.matches(in: headSlice, range: NSRange(location: 0, length: nsStr.length))

        var touchIcons: [URL] = []
        var standardIcons: [URL] = []

        for match in matches {
            let tag = nsStr.substring(with: match.range)
            let lower = tag.lowercased()
            guard lower.contains("rel=") && lower.contains("icon") && !lower.contains("mask-icon") else {
                continue
            }
            guard let href = extractAttribute("href", fromTag: tag), !href.isEmpty else {
                continue
            }
            guard let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            if lower.contains("apple-touch-icon") {
                touchIcons.append(resolved)
            } else {
                standardIcons.append(resolved)
            }
        }

        return touchIcons + standardIcons
    }

    nonisolated private static func extractAttribute(_ attr: String, fromTag tag: String) -> String? {
        let pattern = "\(attr)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsTag = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: nsTag.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsTag.substring(with: match.range(at: 1))
    }

    // MARK: - Image Download & High-DPI PNG Normalization

    func downloadAndNormalizeIcon(from url: URL, minPixelDimension: Int = 24) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue(UserAgentPreset.safariMac.resolvedUserAgent(customValue: ""), forHTTPHeaderField: "User-Agent")

        guard let (rawBytes, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              !rawBytes.isEmpty,
              let image = NSImage(data: rawBytes) else {
            return nil
        }

        // Check actual pixel dimensions across representations
        var maxPx = Int(max(image.size.width, image.size.height))
        for rep in image.representations {
            maxPx = max(maxPx, max(rep.pixelsWide, rep.pixelsHigh))
        }
        guard maxPx >= minPixelDimension else { return nil }

        let targetPx = min(256, max(64, maxPx))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetPx,
            pixelsHigh: targetPx,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: CGFloat(targetPx), height: CGFloat(targetPx)),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
