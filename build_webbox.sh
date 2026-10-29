#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_WORKSPACE_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="WebBox"
BUNDLE_ID="com.hunglx.WebBox"
VERSION="${WEBBOX_VERSION:-1.0.0}"
BUILD_NUMBER="${WEBBOX_BUILD_NUMBER:-1}"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ROOT_APP_BUNDLE="$ROOT_WORKSPACE_DIR/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"

echo "==> [1/6] Đang biên dịch $APP_NAME (Universal Binary arm64 + x86_64 Release)..."
if swift build -c release --product "$APP_NAME" --arch arm64 --arch x86_64 2>/dev/null; then
    BIN_PATH="$(swift build -c release --product "$APP_NAME" --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
    swift build -c release --product "$APP_NAME"
    BIN_PATH="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"
fi

echo "==> [2/6] Đang tạo biểu tượng ứng dụng (AppIcon.icns)..."
ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" << 'SWIFT_ICON'
import AppKit

let outDir = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
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

for (px, name) in sizes {
    let rep = NSBitmapImageRep(
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
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
    let inset = CGFloat(px) * 0.08
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let radius = bgRect.width * 0.228

    // Rich Cobalt-Indigo-Cyan macOS squircle gradient
    let path = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.32, alpha: 1.0),
        NSColor(calibratedRed: 0.09, green: 0.36, blue: 0.86, alpha: 1.0),
        NSColor(calibratedRed: 0.04, green: 0.65, blue: 0.94, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -55)

    // Back layered glass window card (Multi-account symbolism)
    let backCard = NSRect(
        x: CGFloat(px) * 0.27,
        y: CGFloat(px) * 0.34,
        width: CGFloat(px) * 0.50,
        height: CGFloat(px) * 0.42
    )
    let backPath = NSBezierPath(roundedRect: backCard, xRadius: CGFloat(px) * 0.07, yRadius: CGFloat(px) * 0.07)
    NSColor.white.withAlphaComponent(0.22).setFill()
    backPath.fill()

    // Front glass window card
    let frontCard = NSRect(
        x: CGFloat(px) * 0.21,
        y: CGFloat(px) * 0.24,
        width: CGFloat(px) * 0.52,
        height: CGFloat(px) * 0.44
    )
    let frontPath = NSBezierPath(roundedRect: frontCard, xRadius: CGFloat(px) * 0.075, yRadius: CGFloat(px) * 0.075)
    NSColor.white.withAlphaComponent(0.92).setFill()
    frontPath.fill()

    // Globe symbol centered inside front card
    if let symbol = NSImage(systemSymbolName: "globe.asia.australia.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.25, weight: .semibold)
            .applying(.init(paletteColors: [NSColor(calibratedRed: 0.06, green: 0.38, blue: 0.88, alpha: 1.0)]))
        if let configured = symbol.withSymbolConfiguration(config) {
            let symSize = configured.size
            let drawRect = NSRect(
                x: frontCard.midX - symSize.width / 2.0,
                y: frontCard.midY - symSize.height / 2.0,
                width: symSize.width,
                height: symSize.height
            )
            configured.draw(in: drawRect)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }
}
SWIFT_ICON

echo "==> [3/6] Đang đóng gói $APP_NAME.app..."
STAGE_ROOT="$(mktemp -d /tmp/WebBoxBuildStage.XXXXXX)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
STAGE_APP="$STAGE_ROOT/$APP_NAME.app"
STAGE_CONTENTS="$STAGE_APP/Contents"
STAGE_MACOS="$STAGE_CONTENTS/MacOS"
STAGE_RESOURCES="$STAGE_CONTENTS/Resources"
mkdir -p "$STAGE_MACOS" "$STAGE_RESOURCES"

cp -X "$BIN_PATH" "$STAGE_MACOS/$APP_NAME"
chmod +x "$STAGE_MACOS/$APP_NAME"

iconutil -c icns "$ICONSET_DIR" -o "$STAGE_RESOURCES/AppIcon.icns" || true

cat > "$STAGE_CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>vi</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>WebBox</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>WebBox cần quyền Camera để thực hiện cuộc gọi video và chụp ảnh trong Zalo, Messenger, Google Meet.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>WebBox cần quyền Micro để thực hiện cuộc gọi thoại và gửi tin nhắn âm thanh trong các ứng dụng chat.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "==> [4/6] Đang ký số (Ad-hoc Codesign)..."
xattr -cr "$STAGE_APP" 2>/dev/null || true
codesign --force --deep --sign - "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP"

rm -rf "$APP_BUNDLE"
ditto --noextattr "$STAGE_APP" "$APP_BUNDLE"

echo "==> [5/6] Đang tạo bộ cài đặt .DMG và .ZIP tại thư mục dist/..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

DMG_STAGING="$STAGE_ROOT/dmg_staging"
mkdir -p "$DMG_STAGING"

ditto --noextattr "$STAGE_APP" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

cat > "$DMG_STAGING/Cai_Dat_WebBox.command" << 'INSTALLER_EOF'
#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$DIR/WebBox.app"
APP_DST="/Applications/WebBox.app"

echo "===================================================="
echo "  Đang cài đặt WebBox vào /Applications..."
echo "===================================================="

pkill -f "/Applications/WebBox.app" 2>/dev/null || true
rm -rf "$APP_DST"
ditto --noextattr "$APP_SRC" "$APP_DST"
xattr -cr "$APP_DST" 2>/dev/null || true

echo "✓ Đã cài đặt thành công tại: $APP_DST"
echo "✓ Đang khởi chạy WebBox..."
open "$APP_DST"
sleep 1
INSTALLER_EOF
chmod +x "$DMG_STAGING/Cai_Dat_WebBox.command"
xattr -cr "$DMG_STAGING" 2>/dev/null || true

DMG_PATH="$DIST_DIR/${APP_NAME}-Installer-v${VERSION}.dmg"
hdiutil create -volname "${APP_NAME} Installer" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

ZIP_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}-macOS.zip"
ditto -c -k --norsrc --noextattr --keepParent "$STAGE_APP" "$ZIP_PATH"

echo "==> [6/6] Đồng bộ $ROOT_APP_BUNDLE..."
if [ "$ROOT_WORKSPACE_DIR" != "$PROJECT_DIR" ]; then
    rm -rf "$ROOT_APP_BUNDLE"
    ditto --noextattr "$STAGE_APP" "$ROOT_APP_BUNDLE"
fi

echo "==> Hoàn tất!"
echo "    - Ứng dụng: $APP_BUNDLE"
echo "    - Bộ cài DMG: $DMG_PATH"
echo "    - Bản nén ZIP: $ZIP_PATH"
