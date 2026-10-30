import AppKit
import SwiftUI

enum AppIconRenderer {
    /// Renders a macOS squircle app icon as an NSImage at the requested pixel dimension,
    /// using the full-bleed official app icon when available + optional multi-account corner badge pill.
    @MainActor
    static func renderAppIconImage(
        for instance: WebAppInstance,
        pixelSize: Int = 256,
        includeAccountBadge: Bool = true
    ) -> NSImage {
        let px = max(32, pixelSize)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px,
            pixelsHigh: px,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: NSSize(width: px, height: px))
        }

        let resolvedIconData = instance.customIconPNGData
            ?? instance.catalogID.flatMap { AppIconFetcher.shared.cachedIcon(forPresetID: $0) }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high

        let canvas = NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
        let inset = CGFloat(px) * 0.08
        let bgRect = canvas.insetBy(dx: inset, dy: inset)
        let cornerRadius = bgRect.width * 0.225
        let squircle = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

        let baseColor = NSColor.fromHex(instance.accentHex)

        if let pngData = resolvedIconData, let customImg = NSImage(data: pngData) {
            var imgMaxPx = Int(max(customImg.size.width, customImg.size.height))
            for r in customImg.representations {
                imgMaxPx = max(imgMaxPx, max(r.pixelsWide, r.pixelsHigh))
            }

            NSGraphicsContext.saveGraphicsState()
            squircle.addClip()

            if imgMaxPx >= 96 {
                // Full-bleed high-resolution app icon inside macOS squircle
                NSColor.white.setFill()
                bgRect.fill()
                customImg.draw(in: bgRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            } else {
                // Smaller website favicon centered on clean white squircle card
                NSColor.white.setFill()
                bgRect.fill()
                let pad = bgRect.width * 0.18
                let iconBox = bgRect.insetBy(dx: pad, dy: pad)
                customImg.draw(in: iconBox, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            NSGraphicsContext.restoreGraphicsState()

            NSColor.black.withAlphaComponent(0.10).setStroke()
            squircle.lineWidth = max(1.0, CGFloat(px) * 0.01)
            squircle.stroke()
        } else {
            let topColor = baseColor.blended(withFraction: 0.22, of: .white) ?? baseColor
            let bottomColor = baseColor.blended(withFraction: 0.26, of: .black) ?? baseColor
            if let gradient = NSGradient(colors: [topColor, baseColor, bottomColor]) {
                gradient.draw(in: squircle, angle: -60)
            } else {
                baseColor.setFill()
                squircle.fill()
            }

            NSColor.white.withAlphaComponent(0.22).setStroke()
            squircle.lineWidth = max(1.0, CGFloat(px) * 0.012)
            squircle.stroke()

            if let symbolName = instance.symbolName,
               let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.38, weight: .semibold)
                    .applying(.init(paletteColors: [.white]))
                if let configured = symbol.withSymbolConfiguration(config) {
                    let symSize = configured.size
                    let drawRect = NSRect(
                        x: canvas.midX - symSize.width / 2.0,
                        y: canvas.midY - symSize.height / 2.0,
                        width: symSize.width,
                        height: symSize.height
                    )
                    configured.draw(in: drawRect)
                }
            } else {
                let text = instance.monogram.isEmpty
                    ? String(instance.name.prefix(2)).uppercased()
                    : String(instance.monogram.prefix(3))
                let fontSize = text.count == 1 ? CGFloat(px) * 0.46 : CGFloat(px) * 0.33
                let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraph
                ]
                let attrStr = NSAttributedString(string: text, attributes: attrs)
                let strSize = attrStr.size()
                let textRect = NSRect(
                    x: canvas.midX - strSize.width / 2.0,
                    y: canvas.midY - strSize.height / 2.0,
                    width: strSize.width,
                    height: strSize.height
                )
                attrStr.draw(in: textRect)
            }
        }

        // Draw multi-account corner badge on icon if configured
        let badgeRaw = instance.badgeShortText.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeAccountBadge && !badgeRaw.isEmpty {
            let badgeText = String(badgeRaw.prefix(4)).uppercased()
            let badgeHeight = CGFloat(px) * 0.25
            let badgeFont = NSFont.systemFont(ofSize: badgeHeight * 0.56, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1.0)
            ]
            let textSize = (badgeText as NSString).size(withAttributes: attrs)
            let badgeWidth = max(badgeHeight, textSize.width + badgeHeight * 0.58)
            let badgeRect = NSRect(
                x: bgRect.maxX - badgeWidth + CGFloat(px) * 0.03,
                y: bgRect.minY - CGFloat(px) * 0.02,
                width: badgeWidth,
                height: badgeHeight
            )
            let badgePath = NSBezierPath(
                roundedRect: badgeRect,
                xRadius: badgeHeight * 0.5,
                yRadius: badgeHeight * 0.5
            )
            NSColor.white.setFill()
            badgePath.fill()

            baseColor.setStroke()
            badgePath.lineWidth = max(1.5, CGFloat(px) * 0.018)
            badgePath.stroke()

            let textDrawRect = NSRect(
                x: badgeRect.midX - textSize.width / 2.0,
                y: badgeRect.midY - textSize.height / 2.0,
                width: textSize.width,
                height: textSize.height
            )
            (badgeText as NSString).draw(in: textDrawRect, withAttributes: attrs)
        }

        NSGraphicsContext.restoreGraphicsState()

        let finalImage = NSImage(size: NSSize(width: px, height: px))
        finalImage.addRepresentation(rep)
        return finalImage
    }

    @MainActor
    static func writeICNSFile(for instance: WebAppInstance, destinationICNSURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebBoxIcon_\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let iconSpecs: [(Int, String)] = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png")
        ]

        for (px, filename) in iconSpecs {
            let img = renderAppIconImage(for: instance, pixelSize: px, includeAccountBadge: true)
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let pngData = rep.representation(using: .png, properties: [:]) {
                try pngData.write(to: tempDir.appendingPathComponent(filename))
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", tempDir.path, "-o", destinationICNSURL.path]
        try process.run()
        process.waitUntilExit()
    }
}

/// SwiftUI view for displaying an instance's icon with authentic macOS Sonoma/Sequoia squircle styling.
struct AppInstanceAvatarView: View {
    let instance: WebAppInstance
    var size: CGFloat = 32
    var showBadgePill: Bool = true
    @ObservedObject private var iconFetcher = AppIconFetcher.shared

    private var effectiveIconData: Data? {
        if let custom = instance.customIconPNGData {
            return custom
        }
        if let cid = instance.catalogID {
            return iconFetcher.cachedPresetIcons[cid]
        }
        return nil
    }

    var body: some View {
        let corner = size * 0.225

        ZStack(alignment: .bottomTrailing) {
            Group {
                if let data = effectiveIconData, let nsImage = NSImage(data: data) {
                    let isHighRes = Self.maxPixelDimension(of: nsImage) >= 96
                    ZStack {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(Color.white)

                        if isHighRes {
                            Image(nsImage: nsImage)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                                .frame(width: size, height: size)
                                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        } else {
                            Image(nsImage: nsImage)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .padding(size * 0.16)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                    )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: instance.accentHex).opacity(0.88),
                                        Color(hex: instance.accentHex)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: corner, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                            )

                        if let symbol = instance.symbolName {
                            Image(systemName: symbol)
                                .font(.system(size: size * 0.44, weight: .semibold))
                                .foregroundStyle(.white)
                        } else {
                            let label = instance.monogram.isEmpty
                                ? String(instance.name.prefix(2)).uppercased()
                                : String(instance.monogram.prefix(3))
                            Text(label)
                                .font(.system(size: label.count > 1 ? size * 0.36 : size * 0.48, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(width: size, height: size)

            let badge = instance.badgeShortText.trimmingCharacters(in: .whitespacesAndNewlines)
            if showBadgePill && !badge.isEmpty {
                Text(String(badge.prefix(4)).uppercased())
                    .font(.system(size: max(8, size * 0.24), weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 0.5)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.8)
                    )
                    .offset(x: 3, y: 2)
            }
        }
    }

    private static func maxPixelDimension(of image: NSImage) -> Int {
        var m = Int(max(image.size.width, image.size.height))
        for rep in image.representations {
            m = max(m, max(rep.pixelsWide, rep.pixelsHigh))
        }
        return m
    }
}
