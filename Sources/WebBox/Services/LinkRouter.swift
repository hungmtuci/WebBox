import Foundation
import AppKit

@MainActor
enum LinkRouter {
    private static let redirectorHosts: Set<String> = [
        "l.facebook.com",
        "lm.facebook.com",
        "l.messenger.com",
        "l.instagram.com",
        "t.umblr.com"
    ]

    private static let knownBrowserCandidates: [(bundleID: String, name: String)] = [
        ("com.apple.Safari", "Safari"),
        ("com.google.Chrome", "Google Chrome"),
        ("com.coccoc.Coccoc", "Cốc Cốc"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.brave.Browser", "Brave Browser"),
        ("org.mozilla.firefox", "Firefox"),
        ("app.zen-browser.zen", "Zen Browser"),
        ("com.operasoftware.Opera", "Opera"),
        ("com.vivaldi.Vivaldi", "Vivaldi")
    ]

    private static let authHosts: [String] = [
        "accounts.google.com",
        "id.zalo.me",
        "oauth.zaloapp.com",
        "sso.zalo.me",
        "appleid.apple.com",
        "login.microsoftonline.com",
        "login.live.com",
        "accounts.youtube.com",
        "auth0.com",
        "auth.openai.com"
    ]

    private static let twoPartSuffixes: Set<String> = [
        "com.vn", "net.vn", "org.vn", "edu.vn", "gov.vn", "co.uk", "com.au", "co.jp"
    ]

    private static let browserCacheTTL: CFAbsoluteTime = 30.0
    private static var cachedBrowsers: [ExternalBrowserInfo] = []
    private static var lastBrowserScanTime: CFAbsoluteTime = 0
    private static var cachedDefaultBrowserName: String = ""
    private static var lastDefaultBrowserCheckTime: CFAbsoluteTime = 0
    private static var browserIconCache: [String: NSImage] = [:]

    /// Returns all web browsers currently installed on this Mac (cached with 30s TTL to avoid LaunchServices stalls).
    static func installedExternalBrowsers() -> [ExternalBrowserInfo] {
        let now = CFAbsoluteTimeGetCurrent()
        if !cachedBrowsers.isEmpty && (now - lastBrowserScanTime) < browserCacheTTL {
            return cachedBrowsers
        }
        var found: [ExternalBrowserInfo] = []
        found.reserveCapacity(knownBrowserCandidates.count)
        for candidate in knownBrowserCandidates {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) {
                found.append(
                    ExternalBrowserInfo(
                        bundleIdentifier: candidate.bundleID,
                        name: candidate.name,
                        appURL: appURL
                    )
                )
            }
        }
        cachedBrowsers = found
        lastBrowserScanTime = now
        return found
    }

    /// Returns a cached, sized icon for an installed external browser without repeatedly reading disk bundles.
    static func cachedIcon(for browser: ExternalBrowserInfo, size: CGFloat = 16) -> NSImage {
        let key = "\(browser.bundleIdentifier)_\(Int(size))"
        if let existing = browserIconCache[key] {
            return existing
        }
        let icon = (NSWorkspace.shared.icon(forFile: browser.appURL.path).copy() as? NSImage)
            ?? NSWorkspace.shared.icon(forFile: browser.appURL.path)
        icon.size = NSSize(width: size, height: size)
        browserIconCache[key] = icon
        return icon
    }

    /// Returns the display name of the system default HTTPS browser (e.g., "Safari" or "Google Chrome").
    static func defaultSystemBrowserName() -> String {
        let now = CFAbsoluteTimeGetCurrent()
        if !cachedDefaultBrowserName.isEmpty && (now - lastDefaultBrowserCheckTime) < browserCacheTTL {
            return cachedDefaultBrowserName
        }
        guard let probeURL = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else {
            return "Trình duyệt mặc định"
        }
        let resolved = appURL.deletingPathExtension().lastPathComponent
        cachedDefaultBrowserName = resolved
        lastDefaultBrowserCheckTime = now
        return resolved
    }

    /// Unwraps common redirector URLs used in chat apps (Facebook, Messenger, Google, YouTube, Zalo redirects).
    static func unwrapRedirectURL(_ url: URL) -> URL {
        var current = url
        for _ in 0..<2 {
            guard let unwrapped = unwrapSinglePass(current), unwrapped != current else {
                break
            }
            current = unwrapped
        }
        return current
    }

    private static func unwrapSinglePass(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        // 1. Facebook / Messenger / Instagram link shim (l.facebook.com/l.php?u=...)
        if redirectorHosts.contains(host) {
            if let rawTarget = queryItems.first(where: { $0.name == "u" || $0.name == "url" })?.value,
               let targetURL = decodeValidHTTPURL(rawTarget) {
                return targetURL
            }
        }

        // 2. Google / Gmail / YouTube redirectors
        if (host == "www.google.com" || host == "google.com") && components.path == "/url" {
            if let rawTarget = queryItems.first(where: { $0.name == "q" || $0.name == "url" })?.value,
               let targetURL = decodeValidHTTPURL(rawTarget) {
                return targetURL
            }
        }
        if (host.hasSuffix("youtube.com")) && components.path == "/redirect" {
            if let rawTarget = queryItems.first(where: { $0.name == "q" })?.value,
               let targetURL = decodeValidHTTPURL(rawTarget) {
                return targetURL
            }
        }

        // 3. Zalo / Slack / Teams explicit external link wrappers (only when path suggests redirect)
        if host.hasSuffix("zalo.me") || host.hasSuffix("zaloapp.com") {
            let lowerPath = components.path.lowercased()
            if lowerPath.contains("redirect") || lowerPath.contains("link") || lowerPath.contains(" jump") {
                if let rawTarget = queryItems.first(where: {
                    $0.name == "url" || $0.name == "redirect_url" || $0.name == "target"
                })?.value,
                   let targetURL = decodeValidHTTPURL(rawTarget) {
                    return targetURL
                }
            }
        }

        return nil
    }

    private static func decodeValidHTTPURL(_ candidate: String) -> URL? {
        if let direct = URL(string: candidate),
           let scheme = direct.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           direct.host != nil {
            return direct
        }
        if let decoded = candidate.removingPercentEncoding,
           let url = URL(string: decoded),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           url.host != nil {
            return url
        }
        return nil
    }

    /// Checks whether a URL is explicitly a link-shim / redirector host (like l.facebook.com or l.messenger.com).
    static func isRedirectorShimURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if redirectorHosts.contains(host) { return true }
        if (host == "www.google.com" || host == "google.com") && url.path == "/url" { return true }
        return false
    }

    /// Identifies OAuth, SSO, and login popups that MUST remain inside an authenticated WKWebView sharing cookies/opener.
    static func isAuthenticationFlowURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()

        if authHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }

        if (host.hasSuffix("facebook.com") || host.hasSuffix("messenger.com")) &&
            (path.contains("/dialog/oauth") || path.contains("/login") || path.contains("/checkpoint") || path.contains("/two_step_verification")) {
            return true
        }

        if path.contains("/oauth/") || path.contains("/oauth2/") || path.contains("/sso/") || path.contains("/signin") || path.contains("/authorize") {
            return true
        }

        return false
    }

    /// Determines whether a main-frame URL belongs to the internal domain family of the given app instance.
    static func isInternalAppURL(_ url: URL, for instance: WebAppInstance) -> Bool {
        guard let targetHost = url.host?.lowercased() else { return true }
        if isRedirectorShimURL(url) {
            return false
        }
        if isAuthenticationFlowURL(url) {
            return true
        }

        if let preset = CatalogDirectory.preset(for: instance.catalogID) {
            for suffix in preset.internalHostSuffixes {
                let s = suffix.lowercased()
                if targetHost == s || targetHost.hasSuffix(".\(s)") {
                    return true
                }
            }
        }

        guard let baseHost = instance.baseURL.host?.lowercased() else { return false }
        if targetHost == baseHost { return true }

        let baseRoot = registrableRootDomain(of: baseHost)
        let targetRoot = registrableRootDomain(of: targetHost)
        return !baseRoot.isEmpty && baseRoot == targetRoot
    }

    private static func registrableRootDomain(of host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host }
        // Handle 2-part ccTLDs like .com.vn, .co.uk, .net.vn
        let lastTwo = "\(parts[parts.count - 2]).\(parts[parts.count - 1])"
        if twoPartSuffixes.contains(lastTwo), parts.count >= 3 {
            return "\(parts[parts.count - 3]).\(lastTwo)"
        }
        return lastTwo
    }

    /// Normalizes user-entered URL text (e.g., "chat.zalo.me" -> "https://chat.zalo.me").
    static func normalizeUserEnteredURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// Opens a URL in either the preferred external browser or macOS's system default browser.
    static func openInExternalBrowser(_ url: URL, preferredBrowserBundleID: String? = nil) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "http" && scheme != "https" {
            NSWorkspace.shared.open(url)
            return
        }

        if let bundleID = preferredBrowserBundleID,
           !bundleID.isEmpty,
           let browserAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: browserAppURL, configuration: config)
            return
        }

        NSWorkspace.shared.open(url)
    }
}
