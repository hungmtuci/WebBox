import Foundation
import AppKit

enum DedicatedAppBuildError: LocalizedError {
    case executableNotFound
    case packagingFailed(String)
    case codesignFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Không tìm thấy tệp thực thi gốc của WebBox để đóng gói ứng dụng độc lập."
        case .packagingFailed(let detail):
            return "Lỗi khi đóng gói ứng dụng .app: \(detail)"
        case .codesignFailed(let detail):
            return "Lỗi ký số ứng dụng .app: \(detail)"
        }
    }
}

@MainActor
enum DedicatedAppBuilder {
    static func suggestedAppBundleName(for instance: WebAppInstance) -> String {
        let rawTitle: String
        let trimmedAccount = instance.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAccount.isEmpty {
            rawTitle = instance.name
        } else {
            rawTitle = "\(instance.name) - \(trimmedAccount)"
        }
        let invalidChars = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = rawTitle
            .components(separatedBy: invalidChars)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "WebApp.app" : "\(sanitized).app"
    }

    static func exportDedicatedApp(
        for instance: WebAppInstance,
        preferences: GlobalWorkspacePreferences,
        customDirectory: URL? = nil
    ) throws -> URL {
        guard let currentExecutableURL = Bundle.main.executableURL,
              FileManager.default.fileExists(atPath: currentExecutableURL.path) else {
            throw DedicatedAppBuildError.executableNotFound
        }

        let targetDir = customDirectory ?? URL(
            fileURLWithPath: preferences.dedicatedAppsInstallDirectory,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let bundleFileName = suggestedAppBundleName(for: instance)
        let finalAppURL = targetDir.appendingPathComponent(bundleFileName, isDirectory: true)

        // Stage inside temporary directory first for atomic swap
        let stageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebBoxDedicatedStage_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stageRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stageRoot) }

        let stageAppURL = stageRoot.appendingPathComponent(bundleFileName, isDirectory: true)
        let contentsURL = stageAppURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        // 1. Copy native executable
        let executableName = "WebBoxStandalone"
        let dstExecURL = macOSURL.appendingPathComponent(executableName)
        try FileManager.default.copyItem(at: currentExecutableURL, to: dstExecURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstExecURL.path)

        // 2. Render custom AppIcon.icns (with multi-account corner badge if present!)
        let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")
        try AppIconRenderer.writeICNSFile(for: instance, destinationICNSURL: icnsURL)

        // 3. Write StandaloneApp.json manifest
        let resolvedFallback: LinkRoutingMode = preferences.defaultLinkRoutingMode == .useGlobal
            ? .askEveryTime
            : preferences.defaultLinkRoutingMode
        var standaloneInstance = instance
        standaloneInstance.exportedAppPath = finalAppURL.path

        let manifest = StandaloneAppManifest(
            instance: standaloneInstance,
            defaultLinkRoutingMode: resolvedFallback,
            inAppBrowserLayout: preferences.inAppBrowserLayout,
            showNavigationToolbar: true,
            createdVersion: "1.0.0"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: resourcesURL.appendingPathComponent("StandaloneApp.json"))

        // 4. Write Info.plist with unique CFBundleIdentifier per instance
        let cleanUUID = instance.id.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(16)
        let bundleID = "com.hunglx.WebBox.dedicated.\(cleanUUID)"
        let displayName = bundleFileName.replacingOccurrences(of: ".app", with: "")
        let escapedDisplayName = xmlEscape(displayName)

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>vi</string>
            <key>CFBundleExecutable</key>
            <string>\(executableName)</string>
            <key>CFBundleIconFile</key>
            <string>AppIcon</string>
            <key>CFBundleIdentifier</key>
            <string>\(bundleID)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>\(escapedDisplayName)</string>
            <key>CFBundleDisplayName</key>
            <string>\(escapedDisplayName)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSMinimumSystemVersion</key>
            <string>14.0</string>
            <key>NSHighResolutionCapable</key>
            <true/>
            <key>NSCameraUsageDescription</key>
            <string>\(escapedDisplayName) cần quyền truy cập Camera cho cuộc gọi video hoặc gửi hình ảnh trực tiếp.</string>
            <key>NSMicrophoneUsageDescription</key>
            <string>\(escapedDisplayName) cần quyền truy cập Micro cho cuộc gọi thoại và tin nhắn âm thanh.</string>
            <key>NSAppTransportSecurity</key>
            <dict>
                <key>NSAllowsArbitraryLoads</key>
                <true/>
            </dict>
        </dict>
        </plist>
        """
        try infoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        // 5. Clear xattrs & Ad-hoc Codesign
        _ = runProcess("/usr/bin/xattr", arguments: ["-cr", stageAppURL.path])
        let signResult = runProcess("/usr/bin/codesign", arguments: ["--force", "--deep", "--sign", "-", stageAppURL.path])
        if signResult.exitCode != 0 {
            throw DedicatedAppBuildError.codesignFailed(signResult.output)
        }

        // 6. Install to final destination
        if FileManager.default.fileExists(atPath: finalAppURL.path) {
            try FileManager.default.removeItem(at: finalAppURL)
        }
        try FileManager.default.copyItem(at: stageAppURL, to: finalAppURL)
        _ = runProcess("/usr/bin/xattr", arguments: ["-cr", finalAppURL.path])

        return finalAppURL
    }

    static func launchDedicatedApp(at appURL: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
    }

    static func revealInFinder(at appURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    static func pinToMacOSDock(appURL: URL) {
        guard FileManager.default.fileExists(atPath: appURL.path) else { return }
        let tileXml = "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>\(xmlEscape(appURL.path))</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
        _ = runProcess("/usr/bin/defaults", arguments: ["write", "com.apple.dock", "persistent-apps", "-array-add", tileXml])
        _ = runProcess("/usr/bin/killall", arguments: ["Dock"])
    }

    static func trashDedicatedApp(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func runProcess(_ launchPath: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (proc.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
