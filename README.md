# WebBox cho macOS — Biến Website thành Desktop App & Quản Lý Đa Tài Khoản

[![Release](https://img.shields.io/github/v/release/hungmtuci/WebBox?label=Release&color=blue)](https://github.com/hungmtuci/WebBox/releases/latest)
[![Platform](https://img.shields.io/badge/macOS-14.0%2B-0A84FF)](https://github.com/hungmtuci/WebBox)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**WebBox** là ứng dụng Native macOS (`Swift + AppKit/SwiftUI + WKWebView`, yêu cầu `macOS 14.0+`) lấy cảm hứng từ **WebCatalog Dedicated Desktop Apps** kết hợp **Multi-Account Workspace**, tối ưu cực nhẹ RAM khi chạy song song nhiều tài khoản **Zalo, Facebook, Messenger, Telegram, Shopee Seller, Gmail, ChatGPT...**

---

## 📥 Tải về & Tự động cập nhật (GitHub Releases)

- Tải bộ cài mới nhất (`.dmg` hoặc `.zip` Universal Binary `arm64 + x86_64`) tại: **[GitHub Releases — hungmtuci/WebBox](https://github.com/hungmtuci/WebBox/releases/latest)**
- **Cập nhật 1 chạm ngay trong ứng dụng**:
  - Bấm nút **`Kiểm tra Update (GitHub)`** ở góc trái dưới thanh bên, hoặc dùng phím tắt **`⌘U`** (`WebBox > Kiểm tra cập nhật từ GitHub...`), hoặc mở **`Cài đặt chung (⌘,)`**.
  - Khi có phiên bản mới trên GitHub Releases, WebBox tự động tải gói cập nhật, gỡ cờ Gatekeeper (`xattr -cr`), thay thế `WebBox.app` nguyên tử và khởi động lại ngay.

---

## ✨ Tính năng nổi bật

### 1. Đa tài khoản thực thụ (Isolated Multi-Account Containers)
- Sử dụng `WKWebsiteDataStore(forIdentifier:)` nguyên bản trên macOS 14+ giúp mỗi tài khoản có kho **Cookie, LocalStorage, IndexedDB, ServiceWorker** hoàn toàn cô lập.
- **Nhân bản 1 chạm (`+ Thêm nick Zalo / Facebook` hoặc `⌘⇧N`)**: Tạo ngay tài khoản thứ 2, thứ 3... không bao giờ bị đá phiên đăng nhập.
- Hỗ trợ **dùng chung phiên (Shared Profile)** khi cần (ví dụ: dùng chung 1 phiên đăng nhập giữa *Facebook* và *Messenger*).
- Hỗ trợ **Chia đôi màn hình 2 tài khoản song song**, **Tách ra cửa sổ riêng (Dedicated Window)** sang màn hình phụ, và **Ngủ đông thủ công / Tự động ngủ đông nền (Auto-Hibernate)** để giải phóng 100% RAM khi chưa dùng tới.

### 2. Xuất thành Ứng dụng macOS độc lập (`.app`) giống WebCatalog
- Bất kỳ trang web hoặc tài khoản nào trong WebBox đều có thể **xuất thành file `.app` độc lập** trong `~/Applications` (ví dụ: `Zalo - Cá nhân.app`, `Zalo - Công việc.app`, `Facebook Sale.app`).
- Mỗi file `.app` chỉ nặng **~2 MB**, có `CFBundleIdentifier` riêng, tự vẽ **huy hiệu góc trên Icon Dock** (`1`, `2`, `CV`, `SALE`) để không nhầm lẫn khi ghim nhiều nick Zalo/Facebook lên thanh Dock!

### 3. Xử lý thông minh khi bấm đường Link trong tin nhắn (Smart Link Routing)
- Bắt chính xác mọi liên kết bấm từ tin nhắn chat (`target="_blank"`, `window.open` đồng bộ & bất đồng bộ, link ngoài domain) mà không làm mất màn hình chat và không làm hỏng popup đăng nhập OAuth (Google / Facebook / Zalo QR).
- **Tự động lọc sạch link chuyển hướng trung gian** (`l.facebook.com`, `l.messenger.com`, `lm.facebook.com`, `google.com/url`...).
- Hỗ trợ **3 chế độ linh hoạt** (cấu hình chung hoặc riêng cho từng tài khoản ngay trên thanh công cụ):
  1. **Hỏi nhanh mỗi khi bấm link**: Hiện bảng chọn tức thì giữa **Mở trong Trình duyệt App** và **Mở bằng Trình duyệt ngoài** (Safari, Chrome, Cốc Cốc, Arc, Edge, Firefox...).
  2. **Mở bằng Trình duyệt tích hợp trong App (In-App Browser)**: Hỗ trợ mở nhiều tab ngay cạnh khung chat (**Chia đôi cạnh bên** vừa đọc link vừa nhắn tin, hoặc **Toàn khung**), kèm nút **Mở ngoài ↗** bất cứ lúc nào.
  3. **Mở bằng Trình duyệt ngoài**: Tự động đẩy sang trình duyệt mặc định macOS hoặc trình duyệt chỉ định riêng cho tài khoản đó.
- **Menu chuột phải chuẩn macOS trên Hình ảnh, Tệp & Đường link** (kể cả ảnh `blob:` / WebP mã hoá trong Zalo, Messenger, Telegram):
  - **Mở hình ảnh trong cửa sổ mới** (cửa sổ xem ảnh riêng hỗ trợ Pinch-to-Zoom, Xem trước Preview), **Tải về hình ảnh**, **Lưu hình ảnh thành...**, **Sao chép hình ảnh**, **Sao chép chủ thể (AI Vision tách nền)**, **Chia sẻ...** (AirDrop, Tin nhắn, Mail, Ảnh) và **Tải về tệp được liên kết**.
  - Cho phép tuỳ chỉnh **thư mục lưu tải xuống** và bấm trực tiếp vào thông báo tải xong để **hiện ngay tệp trên Finder**.
- **Phím tắt tiện lợi chuẩn macOS**:
  - `⌘R` / `⌘⇧R`: Tải lại trang hiện tại / Tải lại hoàn toàn bỏ qua bộ nhớ đệm.
  - `⌘⌥S`: Thu gọn / Mở rộng thanh bên trái dạng chỉ hiện biểu tượng Icon (Compact Rail).
  - `⌘\` hoặc `⌘⇧S`: Ẩn / Hiện hoàn toàn thanh bên trái (Sidebar).
  - `⌘1` … `⌘9`: Chuyển nhanh giữa các tài khoản.
  - `⌘N` / `⌘⇧N`: Thêm ứng dụng mới / Nhân bản nhanh tài khoản đang mở.
  - `⌘F`: Tìm nội dung trong trang • `⌘+` / `⌘-` / `⌘0`: Thu phóng trang • `⌘U`: Kiểm tra cập nhật GitHub.
  - Giữ `⌘ + Click` (mở link trong App) • `⌥ + Click` (mở link bằng trình duyệt ngoài).

---

## 🛠 Biên dịch từ mã nguồn

```bash
chmod +x build_webbox.sh
./build_webbox.sh
```

Sau khi chạy xong:
- Ứng dụng hoàn chỉnh: `WebBox.app`
- Bộ cài đặt DMG: `dist/WebBox-Installer-v1.0.5.dmg`
- Bản nén ZIP: `dist/WebBox-v1.0.5-macOS.zip`
