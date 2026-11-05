import Foundation
import AppKit

// MARK: - App Language Mode

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case vietnamese = "vi"
    case english = "en"

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .system:
            return L10n.isVietnamese ? "Theo ngôn ngữ hệ thống (Mặc định)" : "Follow System Language (Default)"
        case .vietnamese:
            return "Tiếng Việt"
        case .english:
            return "English"
        }
    }
}

// MARK: - Localization Service (Bilingual Vietnamese & English)

@MainActor
enum L10n {
    /// Determines whether the effective UI language should be Vietnamese.
    static var isVietnamese: Bool {
        let pref = WorkspaceStore.shared.preferences.appLanguage
        switch pref {
        case .vietnamese:
            return true
        case .english:
            return false
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
            if preferred.hasPrefix("vi") {
                return true
            }
            if let langCode = Locale.current.language.languageCode?.identifier.lowercased(), langCode.hasPrefix("vi") {
                return true
            }
            return false
        }
    }

    /// Selects the localized string based on the effective language.
    @inline(__always)
    static func s(_ vi: String, _ en: String) -> String {
        isVietnamese ? vi : en
    }

    // MARK: - Common Actions
    static var ok: String { s("OK", "OK") }
    static var cancel: String { s("Huỷ", "Cancel") }
    static var save: String { s("Lưu", "Save") }
    static var done: String { s("Xong", "Done") }
    static var close: String { s("Đóng", "Close") }
    static var delete: String { s("Xoá", "Delete") }
    static var copy: String { s("Sao chép", "Copy") }
    static var share: String { s("Chia sẻ...", "Share...") }
    static var download: String { s("Tải về", "Download") }
    static var saveAs: String { s("Lưu thành...", "Save As...") }
    static var open: String { s("Mở", "Open") }
    static var defaultText: String { s("Mặc định", "Default") }
    static var change: String { s("Thay đổi...", "Change...") }
    static var openFolder: String { s("Mở thư mục", "Open Folder") }
    static var clearList: String { s("Xoá danh sách", "Clear List") }
    static var settings: String { s("Cài đặt...", "Settings...") }

    // MARK: - Menu Bar
    static var menuAbout: String { s("Giới thiệu về %@", "About %@") }
    static var menuCheckUpdates: String { s("Kiểm tra cập nhật từ GitHub...", "Check for Updates from GitHub...") }
    static var menuOpenGitHubRepo: String { s("Mở trang GitHub dự án...", "Open GitHub Repository...") }
    static var menuDedicatedApps: String { s("Quản lý Dedicated .app độc lập...", "Manage Dedicated .apps...") }
    static var menuHide: String { s("Ẩn %@", "Hide %@") }
    static var menuHideOthers: String { s("Ẩn các ứng dụng khác", "Hide Others") }
    static var menuShowAll: String { s("Hiện tất cả", "Show All") }
    static var menuQuit: String { s("Thoát %@", "Quit %@") }

    static var menuAppCategory: String { s("Ứng dụng", "App") }
    static var menuNewApp: String { s("Thêm Ứng dụng / Website mới...", "New App / Website...") }
    static var menuCloneAccount: String { s("Nhân bản thêm Tài khoản mới của App hiện tại", "Duplicate Current App Account") }
    static var menuExportDedicated: String { s("Xuất tài khoản hiện tại thành Dedicated .app", "Export Current Account as Dedicated .app") }
    static var menuOpenMainWindow: String { s("Mở cửa sổ chính", "Open Main Window") }
    static var menuCloseWindow: String { s("Đóng cửa sổ", "Close Window") }

    static var menuEditCategory: String { s("Chỉnh sửa", "Edit") }
    static var menuUndo: String { s("Hoàn tác", "Undo") }
    static var menuRedo: String { s("Làm lại", "Redo") }
    static var menuCut: String { s("Cắt", "Cut") }
    static var menuCopy: String { s("Sao chép", "Copy") }
    static var menuPaste: String { s("Dán", "Paste") }
    static var menuSelectAll: String { s("Chọn tất cả", "Select All") }
    static var menuFindInPage: String { s("Tìm trong trang...", "Find in Page...") }

    static var menuViewCategory: String { s("Hiển thị", "View") }
    static var menuReload: String { s("Tải lại trang", "Reload Page") }
    static var menuHardReload: String { s("Tải lại trang (Bỏ qua bộ nhớ đệm)", "Reload Page (Ignore Cache)") }
    static var menuBack: String { s("Quay lại", "Back") }
    static var menuForward: String { s("Tiến tới", "Forward") }
    static var menuZoomIn: String { s("Phóng to nội dung", "Zoom In") }
    static var menuZoomOut: String { s("Thu nhỏ nội dung", "Zoom Out") }
    static var menuZoomReset: String { s("Kích thước mặc định (100%)", "Actual Size (100%)") }
    static var menuToggleCompactSidebar: String { s("Thu gọn / Mở rộng thanh bên chỉ hiện Icon", "Toggle Compact Icon-Only Sidebar") }
    static var menuToggleSidebar: String { s("Ẩn / Hiện hoàn toàn thanh bên trái", "Toggle Full Left Sidebar") }
    static func menuSwitchAccount(number: Int) -> String {
        s("Chuyển sang Tài khoản #\(number)", "Switch to Account #\(number)")
    }

    static var menuWindowCategory: String { s("Cửa sổ", "Window") }
    static var menuMinimize: String { s("Thu nhỏ", "Minimize") }
    static var menuZoomFullScreen: String { s("Phóng to toàn màn hình", "Zoom Full Screen") }

    // MARK: - Sidebar & Top Bar
    static var accounts: String { s("Tài khoản", "Accounts") }
    static var all: String { s("Tất cả", "All") }
    static func allCount(_ count: Int) -> String { s("Tất cả (\(count))", "All (\(count))") }
    static var manageSpaces: String { s("Quản lý Không gian...", "Manage Spaces...") }
    static var filterBySpace: String { s("Lọc theo Không gian làm việc (Spaces)", "Filter by Spaces") }
    static var collapseSidebarHint: String { s("Thu gọn menu bên trái chỉ hiện biểu tượng Icon (⌘⌥S)", "Collapse sidebar to compact icon rail (⌘⌥S)") }
    static var expandSidebarHint: String { s("Mở rộng lại thanh bên đầy đủ (⌘⌥S)", "Expand to full sidebar (⌘⌥S)") }
    static var sidebarCollapseTooltip: String { s("Thu gọn menu bên trái chỉ hiện biểu tượng Icon (⌘⌥S)", "Collapse sidebar to compact icon rail (⌘⌥S)") }
    static var sidebarExpandTooltip: String { s("Mở rộng lại thanh bên đầy đủ (⌘⌥S)", "Expand to full sidebar (⌘⌥S)") }
    static var sidebarToggleFullTooltip: String { s("Ẩn / Hiện hoàn toàn thanh bên trái (⌘\\)", "Toggle full left sidebar (⌘\\)") }
    static var addApp: String { s("Thêm App", "Add App") }
    static var addAppTooltip: String { s("Mở kho ứng dụng hoặc thêm Website bất kỳ (⌘N)", "Open app catalog or add any website (⌘N)") }
    static var newAppAccountTooltip: String { s("Thêm ứng dụng / Tài khoản mới (⌘N)", "Add new App / Account (⌘N)") }
    static var dedicatedAppTooltip: String { s("Quản lý và xuất thành ứng dụng macOS độc lập (.app)", "Manage and export as standalone macOS .app") }
    static var newAppDedicatedTooltip: String { s("Quản lý Dedicated .app độc lập", "Manage Dedicated .apps") }
    static var globalSettingsTooltip: String { s("Cài đặt chung WebBox (⌘,)", "WebBox General Settings (⌘,)") }

    // MARK: - Navigation Toolbar
    static var goBackTooltip: String { s("Quay lại trang trước (⌘[)", "Go back to previous page (⌘[)") }
    static var goForwardTooltip: String { s("Tiến tới trang sau (⌘])", "Go forward to next page (⌘])") }
    static var reloadTooltip: String { s("Tải lại trang (⌘R)", "Reload page (⌘R)") }
    static var reloadWithCacheTip: String { s("Tải lại trang (⌘R • ⌘⇧R tải lại bỏ qua cache)", "Reload page (⌘R • ⌘⇧R to hard reload)") }
    static var homeTooltip: String { s("Về trang chủ của ứng dụng", "Go to app home page") }
    static var quickSwitchAccount: String { s("Chuyển nhanh tài khoản:", "Quick switch account:") }
    static var quickSwitchWhenHidden: String { s("Chuyển nhanh tài khoản khi đang ẩn thanh bên", "Quick switch account when sidebar is hidden") }
    static func addAnotherAccount(of name: String) -> String {
        s("Thêm nick \(name)", "Add \(name) Account")
    }
    static func addAnotherAccountTooltip(of name: String) -> String {
        s("Tạo thêm phiên đăng nhập độc lập mới của \(name) (⌘⇧N)", "Create an isolated new login session for \(name) (⌘⇧N)")
    }
    static func createAccountTooltip(_ name: String) -> String {
        s("Tạo ngay một tài khoản \(name) độc lập mới (⌘⇧N)", "Create an isolated new login session for \(name) (⌘⇧N)")
    }
    static var openCurrentInExternalBrowserTooltip: String { s("Mở trang hiện tại ra trình duyệt ngoài", "Open current page in external browser") }
    static var splitScreenTooltip: String { s("Chia đôi màn hình để dùng 2 tài khoản cùng lúc", "Split screen to use 2 accounts side-by-side") }
    static var openSecondAccountSideBySide: String { s("Mở song song tài khoản thứ 2 bên cạnh:", "Open 2nd account side-by-side:") }
    static var closeSplitScreen: String { s("Đóng chế độ xem song song 2 tài khoản", "Close side-by-side split view") }
    static var closeSplitScreenTooltip: String { s("Đóng khung xem song song", "Close split screen view") }
    static var reloadPaneTooltip: String { s("Tải lại khung này", "Reload this pane") }
    static var downloadsTooltip: String { s("Danh sách tệp tải xuống & Thư mục lưu", "Downloads list & destination folder") }
    static var toggleInAppBrowserTooltip: String { s("Mở / Ẩn khung Trình duyệt tích hợp ngay trong WebBox", "Toggle In-App Browser pane inside WebBox") }
    static var accountSettingsTooltip: String { s("Tuỳ chỉnh tài khoản, Icon, Chế độ mở Link & Xuất .app", "Customize account, icon, link mode & export .app") }

    // MARK: - Update Banner & Buttons
    static func updateAvailableBanner(_ version: String) -> String {
        s("Đã có bản mới v\(version) trên GitHub — Bấm để cập nhật tự động", "New version v\(version) on GitHub — Click to auto-update")
    }
    static var updateProcessing: String { s("Đang xử lý cập nhật từ GitHub...", "Processing update from GitHub...") }
    static var checkForUpdatesTooltip: String { s("Kiểm tra bản cập nhật mới từ GitHub (⌘U)", "Check for updates from GitHub (⌘U)") }
    static func updateButton(_ version: String) -> String { s("Cập nhật v\(version)", "Update v\(version)") }
    static var updateAvailableTooltip: String { s("Đã có phiên bản mới trên GitHub Releases — Bấm để tự động cập nhật", "New version available on GitHub Releases — Click to auto-update") }

    // MARK: - Link Routing Modes
    static var linkModeAskEveryTime: String { s("Hỏi nhanh mỗi khi bấm link", "Ask every time a link is clicked") }
    static var linkModeAskEveryTimeShort: String { s("Hỏi mỗi lần", "Ask Every Time") }
    static var linkModeInAppBrowser: String { s("Mở trong Trình duyệt App (In-App Browser)", "Open in In-App Browser") }
    static var linkModeInAppBrowserShort: String { s("Mở trong App", "In-App Browser") }
    static var linkModeExternalBrowser: String { s("Mở bằng Trình duyệt ngoài (Safari, Chrome...)", "Open in External Browser (Safari, Chrome...)") }
    static var linkModeExternalBrowserShort: String { s("Trình duyệt ngoài", "External Browser") }
    static var linkModeUseGlobal: String { s("Dùng theo Cài Đặt Chung", "Use Global Preference") }
    static var linkModeUseGlobalShort: String { s("Theo Cài đặt", "Use Global") }
    static var linkModeHeader: String { s("Đường link trong tin nhắn", "Links in Messages") }
    static var linkModeMenuTitle: String { s("Chọn cách mở link trong tin nhắn:", "Choose how to open message links:") }
    static func linkModeForAccount(_ title: String) -> String {
        s("Khi bấm đường link trong tin nhắn (\(title)):", "When clicking link in messages (\(title)):")
    }
    static func linkModeCurrent(_ modeTitle: String) -> String {
        s("Chế độ mở link: \(modeTitle)", "Link routing mode: \(modeTitle)")
    }
    static var linkModeHelp: String { s("Chọn cách mở khi bấm đường link trong tin nhắn: Hỏi mỗi lần, Mở trong App, hoặc Trình duyệt ngoài", "Choose how to handle clicked links: Ask Every Time, In-App Browser, or External Browser") }
    static var inAppBrowserSplitLayout: String { s("Trình duyệt trong App dạng Chia đôi cạnh bên", "In-App Browser in Split View") }

    // MARK: - Link Choice Overlay Card
    static var linkChoicePromptTitle: String { s("Bạn muốn mở đường dẫn này ở đâu?", "Where would you like to open this link?") }
    static var linkChoiceCleanUnwrapped: String { s("Đã lọc link sạch", "Clean link unwrapped") }
    static func linkChoiceFromSource(_ source: String) -> String {
        s("Từ tin nhắn trong \(source)", "From a message in \(source)")
    }
    static var linkChoiceInAppTitle: String { s("Mở trong Trình duyệt App", "Open in In-App Browser") }
    static var linkChoiceInAppSubtitle: String { s("Xem ngay cạnh cuộc trò chuyện (giữ phiên đăng nhập, có nút mở ra ngoài)", "View next to chat (keeps login session, with external browser handoff)") }
    static var linkChoiceExternalTitle: String { s("Mở bằng Trình duyệt ngoài", "Open in External Browser") }
    static func linkChoiceExternalSubtitle(_ browser: String) -> String {
        s("Chuyển sang \(browser) trên macOS để xem trong tab độc lập", "Switch to \(browser) on macOS to view in a standalone tab")
    }
    static var linkChoiceQuickOpenWith: String { s("Mở nhanh với:", "Quick open with:") }
    static func linkChoiceRememberForApp(_ appName: String) -> String {
        s("Ghi nhớ lựa chọn cho **\(appName)**", "Remember choice for **\(appName)**")
    }
    static var linkChoiceModifierTips: String { s("Mẹo: Giữ ⌘+Click mở trong App • ⌥+Click mở trình duyệt ngoài", "Tip: Hold ⌘+Click to open in App • ⌥+Click for external browser") }

    // MARK: - In-App Browser Pane
    static var inAppNoTabsOpen: String { s("Chưa có trang nào mở", "No tabs open") }
    static var inAppNoTabsDesc: String { s("Bấm vào bất kỳ đường link nào trong tin nhắn để xem ngay tại đây.", "Click any link in chat messages to view it here.") }
    static var inAppAddressPlaceholder: String { s("Nhập địa chỉ web hoặc từ khoá tìm kiếm...", "Search or enter website address...") }
    static var inAppNewTabTooltip: String { s("Mở thêm tab mới trong trình duyệt App", "Open new tab in In-App Browser") }
    static var inAppCopiedURL: String { s("Đã sao chép URL hiện tại", "Current URL copied") }
    static var inAppCopyURLTooltip: String { s("Sao chép đường dẫn hiện tại", "Copy current URL") }
    static var inAppOpenExternal: String { s("Mở ngoài", "Open External") }
    static var inAppOpenExternalHelp: String { s("Mở trang đang xem ra trình duyệt ngoài của macOS (bấm mũi tên để chọn trình duyệt)", "Open current page in macOS external browser (click arrow to choose browser)") }
    static func inAppOpenExternalDefault(_ browser: String) -> String {
        s("Mở bằng trình duyệt mặc định (\(browser))", "Open with default browser (\(browser))")
    }
    static func inAppOpenWithBrowser(_ browser: String) -> String {
        s("Mở bằng \(browser)", "Open with \(browser)")
    }
    static var inAppExpandFullTooltip: String { s("Mở rộng toàn khung cửa sổ", "Expand to full window") }
    static var inAppSplitRightTooltip: String { s("Thu về dạng Chia đôi cạnh cuộc trò chuyện", "Split side-by-side with chat") }
    static var inAppMinimizeTooltip: String { s("Thu gọn khung trình duyệt (giữ lại các tab đang mở)", "Minimize browser pane (keeps open tabs)") }
    static var inAppCloseAllTabsTooltip: String { s("Đóng tất cả tab trình duyệt trong App", "Close all in-app browser tabs") }

    // MARK: - Context Menu
    static var ctxOpenImageInNewWindow: String { s("Mở hình ảnh trong cửa sổ mới", "Open Image in New Window") }
    static var ctxDownloadImage: String { s("Tải về hình ảnh", "Download Image") }
    static var ctxSaveImageAs: String { s("Lưu hình ảnh thành...", "Save Image As...") }
    static var ctxCopyImage: String { s("Sao chép hình ảnh", "Copy Image") }
    static var ctxCopySubject: String { s("Sao chép chủ thể", "Copy Subject") }
    static var ctxShare: String { s("Chia sẻ...", "Share...") }
    static var ctxDownloadLinkedFile: String { s("Tải về tệp được liên kết", "Download Linked File") }
    static var ctxDownloadMedia: String { s("Tải về tệp phương tiện", "Download Media File") }
    static var ctxOpenMediaInNewWindow: String { s("Mở trong cửa sổ mới", "Open Media in New Window") }
    static var ctxOpenLinkInApp: String { s("Mở liên kết trong Trình duyệt WebBox", "Open Link in WebBox Browser") }
    static func ctxOpenLinkExternalDefault(_ browser: String) -> String {
        s("Mở bằng Trình duyệt ngoài (\(browser))", "Open in External Browser (\(browser))")
    }
    static var ctxOpenLinkAnotherBrowser: String { s("Mở liên kết bằng trình duyệt khác", "Open Link in Another Browser") }
    static var ctxCopyCleanLink: String { s("Sao chép liên kết sạch", "Copy Clean Link") }

    // MARK: - Account Context Menu in Sidebar
    static func ctxAddAnotherAccount(_ name: String) -> String {
        s("Thêm tài khoản \(name) mới (Độc lập)", "Add New \(name) Account (Isolated)")
    }
    static var ctxDetachWindow: String { s("Tách ra cửa sổ riêng (Dedicated Window)", "Detach to Separate Window") }
    static var ctxCloseSideBySide: String { s("Tắt xem song song tài khoản này", "Close side-by-side view") }
    static var ctxOpenSideBySide: String { s("Xem song song cạnh tài khoản hiện tại", "Open side-by-side with active account") }
    static var ctxExportDedicatedApp: String { s("Xuất thành ứng dụng .app độc lập", "Export as Standalone .app") }
    static var ctxReloadPage: String { s("Tải lại trang (⌘R)", "Reload Page (⌘R)") }
    static var ctxRefetchIcon: String { s("Tải lại Icon gốc độ phân giải cao", "Refetch Official High-Res Icon") }
    static var ctxWakeAccount: String { s("Đánh thức tài khoản", "Wake Account") }
    static var ctxHibernateAccount: String { s("Ngủ đông để giải phóng RAM", "Hibernate to Free RAM") }
    static var ctxCustomizeAccount: String { s("Tuỳ chỉnh tài khoản & Chế độ mở Link...", "Customize Account & Link Routing...") }
    static var ctxDeleteAccount: String { s("Xoá tài khoản này", "Delete This Account") }
    static func iconUpdatedToast(_ name: String) -> String {
        s("Đã cập nhật Icon cho \(name)", "Icon updated for \(name)")
    }

    // MARK: - Image Preview Window
    static func imagePreviewTitle(source: String, width: Int, height: Int) -> String {
        s("Xem hình ảnh — \(source) (\(width) × \(height))", "Image Preview — \(source) (\(width) × \(height))")
    }
    static var imgZoomInTooltip: String { s("Phóng to (⌘+)", "Zoom In (⌘+)") }
    static var imgZoomOutTooltip: String { s("Thu nhỏ (⌘-)", "Zoom Out (⌘-)") }
    static var imgFitTooltip: String { s("Thu phóng vừa khung cửa sổ (⌘0)", "Fit to window (⌘0)") }
    static var imgFitTitle: String { s("Vừa khung", "Fit") }
    static var imgCopyTooltip: String { s("Sao chép hình ảnh vào Clipboard (⌘C)", "Copy image to Clipboard (⌘C)") }
    static var imgSubjectTooltip: String { s("Tách nền AI và sao chép chủ thể", "AI background removal and subject copy") }
    static var imgDownloadTooltip: String { s("Lưu ngay vào thư mục Tải xuống (⌘S)", "Save to Downloads folder (⌘S)") }
    static var imgSaveAsTooltip: String { s("Chọn thư mục lưu hình ảnh", "Choose destination folder for image") }
    static var imgPreviewAppTooltip: String { s("Mở bằng ứng dụng Xem trước (Preview) của macOS", "Open with macOS Preview app") }
    static var imgPreviewAppTitle: String { s("Xem trước", "Preview") }
    static var imgShareTooltip: String { s("Chia sẻ qua AirDrop, Tin nhắn, Mail, Ảnh...", "Share via AirDrop, Messages, Mail, Photos...") }

    // MARK: - Save & Open Dialogs
    static var saveDownloadedFile: String { s("Lưu tệp tải xuống", "Save Downloaded File") }
    static var chooseDownloadsFolderTitle: String { s("Chọn thư mục lưu tệp tải xuống", "Choose Downloads Folder") }
    static var chooseFolderPrompt: String { s("Chọn thư mục", "Choose Folder") }
    static var chooseAttachmentPrompt: String { s("Chọn tệp đính kèm", "Choose File Attachment") }

    // MARK: - Downloads Popover & Toast Banners
    static var downloadsPopoverTitle: String { s("Tệp tải xuống", "Downloads") }
    static var revealInFinder: String { s("Hiện trên Finder", "Reveal in Finder") }
    static var revealInFinderBannerHint: String { s("Bấm vào thông báo này để hiện tệp trên Finder", "Click this notification to reveal in Finder") }
    static var revealInFinderItemHint: String { s("Hiện tệp này trên Finder", "Reveal this file in Finder") }
    static var toastRevealTooltip: String { s("Bấm để mở Finder và bôi đậm tệp vừa tải xuống", "Click to reveal and highlight downloaded file in Finder") }
    static var toastDismiss: String { s("Đóng thông báo", "Dismiss notification") }
    static func downloadCompletedToast(_ filename: String) -> String {
        s("Đã tải xong: \(filename)", "Downloaded: \(filename)")
    }
    static func downloadCompletedNotificationBody(_ filename: String) -> String {
        s("\(filename) — Bấm vào thông báo để hiện trên Finder", "\(filename) — Click notification to reveal in Finder")
    }
    static func downloadItemFinderHint(_ title: String) -> String {
        s("\(title) • Bấm để hiện trên Finder", "\(title) • Click to reveal in Finder")
    }
    static var downloadsChangeFolder: String { s("Đổi nơi lưu...", "Change...") }

    // MARK: - Global Settings Sheet
    static var globalSettingsTitle: String { s("Cài Đặt Chung WebBox", "WebBox Settings") }
    static var globalSettingsSubtitle: String { s("Quản lý cập nhật GitHub, chế độ mở Link mặc định, giao diện macOS và Không gian", "Manage GitHub updates, link routing behavior, macOS appearance and Spaces") }
    static var sectionGitHubUpdate: String { s("Cập nhật qua GitHub (hungmtuci/WebBox)", "GitHub Updates (hungmtuci/WebBox)") }
    static var currentRunningVersion: String { s("Phiên bản đang chạy:", "Current Version:") }
    static var checkingUpdate: String { s("Đang kiểm tra...", "Checking...") }
    static var checkForUpdates: String { s("Kiểm tra cập nhật", "Check for Updates") }
    static var openGitHubRepoTooltip: String { s("Mở kho mã nguồn trên GitHub", "Open GitHub repository") }
    static var autoCheckUpdatesOnLaunch: String { s("Tự động kiểm tra phiên bản mới từ GitHub khi khởi động", "Automatically check for updates from GitHub on launch") }

    static var defaultLinkBehaviorLabel: String { s("Hành vi mặc định khi bấm link:", "Default link behavior:") }
    static var inAppBrowserLayoutLabel: String { s("Bố cục trình duyệt tích hợp:", "In-App Browser layout:") }
    static var layoutSplitRight: String { s("Chia đôi cạnh bên (Vừa xem link vừa chat)", "Split View (Read link next to chat)") }
    static var layoutFullOverlay: String { s("Toàn khung cửa sổ (Mở rộng tối đa)", "Full Window (Maximum space)") }
    static var linkModifierTip: String { s("Mẹo: Giữ ⌘+Click để mở nhanh trong App hoặc ⌥+Click để mở thẳng bằng trình duyệt ngoài.", "Tip: Hold ⌘+Click to open in App, or ⌥+Click to open in external browser.") }

    static var sectionAppearance: String { s("Giao diện, Biểu tượng & Hệ thống", "Appearance, Icons & System") }
    static var interfaceLanguageLabel: String { s("Ngôn ngữ giao diện:", "Interface Language:") }
    static var sidebarModeLabel: String { s("Chế độ thanh bên trái:", "Left sidebar mode:") }
    static var sidebarModeExpanded: String { s("Đầy đủ (Icon & Tên tài khoản)", "Full (Icons & Account names)") }
    static var sidebarModeCompact: String { s("Thu gọn (Chỉ hiện biểu tượng Icon)", "Compact (Icon rail only)") }
    static var sidebarModeHidden: String { s("Ẩn hoàn toàn", "Hidden completely") }
    static var showAccountSubtitleInSidebar: String { s("Hiện nhãn tên tài khoản phụ dưới tên ứng dụng ở thanh bên", "Show account label under app name in sidebar") }
    static var doNotDisturbToggle: String { s("Chế độ Không làm phiền (Tạm tắt toàn bộ thông báo đẩy)", "Do Not Disturb (Mute all push notifications)") }
    static var autoHibernateLabel: String { s("Tự động ngủ đông nền (Giải phóng RAM):", "Auto-hibernate in background (Free RAM):") }
    static var autoHibernateOff: String { s("Tắt (Luôn giữ hoạt động)", "Off (Keep running)") }
    static var autoHibernate15m: String { s("Sau 15 phút không dùng", "After 15 minutes of inactivity") }
    static var autoHibernate30m: String { s("Sau 30 phút không dùng", "After 30 minutes of inactivity") }
    static var autoHibernate60m: String { s("Sau 1 giờ không dùng", "After 1 hour of inactivity") }
    static var autoHibernate120m: String { s("Sau 2 giờ không dùng", "After 2 hours of inactivity") }
    static var enableInspectorToggle: String { s("Bật công cụ Web Inspector (Inspect Element khi chuột phải)", "Enable Web Inspector (Inspect Element in right-click menu)") }
    static var appIconsLabel: String { s("Biểu tượng ứng dụng:", "App Icons:") }
    static var syncAllIconsButton: String { s("Đồng bộ lại Icon chuẩn cho tất cả App", "Sync official HD icons for all apps") }

    static var sectionDownloads: String { s("Tệp tải xuống (Downloads)", "Downloads") }
    static var downloadsDirectoryLabel: String { s("Thư mục lưu tệp tải về:", "Downloads folder:") }
    static var askWhereToSaveEachDownloadToggle: String { s("Hỏi vị trí lưu mỗi khi tải tệp xuống", "Ask where to save each download") }
    static var downloadsSectionFooter: String { s("Khi tải tệp hoàn tất, bấm trực tiếp vào thông báo ở cuối cửa sổ để mở nhanh và bôi đậm tệp trên Finder.", "When a download completes, click the notification banner to reveal and highlight the file in Finder.") }

    static var sectionDedicatedAppsDir: String { s("Thư mục lưu Dedicated Desktop Apps (.app)", "Dedicated Desktop Apps (.app) Folder") }
    static var installDirectoryLabel: String { s("Thư mục cài đặt:", "Install folder:") }

    // MARK: - Instance Settings Sheet
    static func instanceSettingsTitle(_ name: String) -> String {
        s("Cài đặt tài khoản: \(name)", "Account Settings: \(name)")
    }
    static var displayNameLabel: String { s("Tên hiển thị:", "Display Name:") }
    static var accountLabel: String { s("Nhãn tài khoản:", "Account Label:") }
    static var accountLabelPlaceholder: String { s("Ví dụ: Cá nhân, Công việc, Bán hàng", "E.g. Personal, Work, Support") }
    static var dockBadgeLabel: String { s("Huy hiệu góc icon:", "Badge text:") }
    static var startURLLabel: String { s("Địa chỉ URL:", "Start URL:") }
    static var autoFetchIcon: String { s("Tự động tìm Icon chuẩn", "Auto-fetch High-Res Icon") }
    static var chooseImageFile: String { s("Chọn ảnh từ máy...", "Choose image file...") }
    static var keepAwakeToggle: String { s("Luôn giữ thức dưới nền (Không tự động ngủ đông)", "Keep awake in background (Prevent auto-hibernate)") }
    static var muteAccountNotificationsToggle: String { s("Tắt âm thanh thông báo của tài khoản này", "Mute notification sounds for this account") }
    static var clearSessionDataButton: String { s("Xoá sạch Cookie & Phiên đăng nhập...", "Clear all Cookies & Login Session...") }
    static var deleteAccountButton: String { s("Xoá tài khoản", "Delete Account") }
    static var saveChangesButton: String { s("Lưu thay đổi", "Save Changes") }

    // MARK: - Welcome / Empty State
    static var welcomeTitle: String { s("Chào mừng đến với WebBox", "Welcome to WebBox") }
    static var welcomeDescription: String { s("Biến mọi trang web thành ứng dụng macOS độc lập và đăng nhập nhiều tài khoản Zalo, Facebook, Messenger, Gmail hoàn toàn tách biệt.", "Turn websites into dedicated desktop apps and run multiple accounts of Zalo, Facebook, Messenger, and Gmail completely isolated.") }
    static var welcomeAddAppButton: String { s("Thêm Ứng Dụng hoặc Website Mới", "Add New App or Website") }

    // MARK: - Find Bar
    static var findPlaceholder: String { s("Tìm nội dung trong trang hiện tại...", "Find in current page...") }

    // MARK: - GitHub Update Overlay Card
    static var updateDialogTitle: String { s("Cập nhật WebBox từ GitHub", "Update WebBox from GitHub") }
    static func updateDialogCurrent(_ ver: String) -> String { s("Hiện tại: v\(ver)", "Current: v\(ver)") }
    static func updateDialogNew(_ ver: String) -> String { s("Bản mới: v\(ver)", "New: v\(ver)") }
    static var updateDialogDesc: String {
        s("Bản phát hành mới đã sẵn sàng trên GitHub Releases. WebBox sẽ tự động tải về, thay thế ứng dụng và khởi động lại ngay.",
          "A new release is ready on GitHub Releases. WebBox will download, install, and relaunch automatically.")
    }
    static var updateDialogViewOnGitHub: String { s("Xem trên GitHub", "View on GitHub") }
    static var updateDialogLater: String { s("Để sau", "Later") }
    static func updateDialogAutoUpdate(_ ver: String) -> String { s("Cập nhật tự động v\(ver)", "Auto-Update v\(ver)") }
    static func updateDialogDownloading(_ ver: String) -> String { s("Đang tải WebBox v\(ver)...", "Downloading WebBox v\(ver)...") }
    static var updateDialogDownloadingDesc: String { s("Đang tải trực tiếp gói cài đặt từ GitHub Releases...", "Downloading package directly from GitHub Releases...") }
    static func updateDialogInstalling(_ ver: String) -> String { s("Đang cài đặt WebBox v\(ver)...", "Installing WebBox v\(ver)...") }
    static var updateDialogInstallingDesc: String { s("Ứng dụng sẽ tự động mở lại ngay sau khi hoàn tất.", "The app will relaunch automatically when done.") }

    // MARK: - Web Container View
    static func hibernatingTitle(_ title: String) -> String { s("\(title) đang ngủ đông", "\(title) is hibernating") }
    static var hibernatingDesc: String {
        s("WebView tạm ngưng để giải phóng RAM. Phiên đăng nhập (Cookie & IndexedDB) vẫn được giữ nguyên 100%.",
          "WebView suspended to free RAM. Login session (Cookies & IndexedDB) preserved 100%.")
    }
    static var hibernatingWake: String { s("Đánh thức tài khoản ngay", "Wake Account Now") }
    static func detachedTitle(_ title: String) -> String { s("\(title) đang mở ở cửa sổ riêng", "\(title) is open in dedicated window") }
    static var detachedDesc: String {
        s("Bạn có thể đặt cửa sổ này sang màn hình thứ hai để theo dõi nhiều tài khoản cùng lúc.",
          "You can place this window on a second monitor to monitor multiple accounts simultaneously.")
    }
    static var detachedSwitchTo: String { s("Chuyển tới cửa sổ riêng", "Switch to Dedicated Window") }
    static var detachedBringBack: String { s("Đưa về cửa sổ chính", "Bring Back to Main Window") }

    // MARK: - Catalog Sheet
    static var catalogPopularApps: String { s("Kho ứng dụng phổ biến", "Popular Apps") }
    static var catalogCustomWebsite: String { s("Biến Website bất kỳ thành App", "Turn Any Website into App") }
    static var catalogHeaderTitle: String { s("Thêm Ứng Dụng & Tài Khoản Mới", "Add New App & Account") }
    static var catalogHeaderSubtitle: String {
        s("Mỗi tài khoản mới tự động có vùng lưu trữ Cookie & phiên đăng nhập độc lập",
          "Each new account automatically has an isolated Cookie & session store")
    }
    static var catalogCategories: String { s("Danh mục", "Categories") }
    static var catalogMultiAccount: String { s("Đa tài khoản", "Multi-account") }
    static var catalogCantFind: String { s("Không thấy trang web cần tìm?", "Can't find your website?") }
    static var catalogEnterAnyURL: String { s("Nhập URL bất kỳ...", "Enter any URL...") }
    static var catalogSearchPrompt: String { s("Tìm Zalo, Facebook, Messenger, Shopee, Gmail, ChatGPT...", "Search Zalo, Facebook, Messenger, Shopee, Gmail, ChatGPT...") }
    static var catalogAddNow: String { s("Thêm ngay", "Add Now") }
    static func catalogAddAccountNum(_ num: Int) -> String { s("Thêm tài khoản #\(num)", "Add Account #\(num)") }
    static var catalogCustomize: String { s("Tuỳ chỉnh", "Customize") }
    static var catalogWebsiteAndIcon: String { s("Trang web & Biểu tượng ứng dụng", "Website & App Icon") }
    static var catalogAutoFetchNameAndIcon: String { s("Tự lấy Tên & Icon", "Auto Fetch Name & Icon") }
    static var catalogChooseIconFromDisk: String { s("Chọn ảnh Icon từ máy...", "Choose image file...") }
    static var catalogRemoveChosenIcon: String { s("Xoá ảnh đã chọn", "Remove chosen icon") }
    static var catalogAppNameLabel: String { s("Tên ứng dụng:", "App Name:") }
    static var catalogAppNamePrompt: String { s("VD: CRM Nội Bộ, Gmail, Zalo...", "E.g. Internal CRM, Gmail, Zalo...") }
    static var catalogAccountLabelPrompt: String { s("VD: Cá nhân, Công ty, Sale 1...", "E.g. Personal, Work, Support...") }
    static var catalogBadgePrompt: String { s("VD: 1, 2, CV (Không bắt buộc)", "E.g. 1, 2, W (Optional)") }
    static var catalogGroupingAndLinks: String { s("Phân nhóm & Chế độ mở đường link", "Grouping & Link Routing") }
    static var catalogWhenClickingLink: String { s("Khi bấm link trong tin nhắn:", "When clicking links:") }
    static var catalogSpaceLabel: String { s("Không gian (Space):", "Space:") }
    static var catalogShowInAllSpaces: String { s("Hiện ở Tất cả", "Show in All Spaces") }
    static var catalogExportDedicatedToggle: String { s("Đồng thời xuất thành tệp ứng dụng .app riêng trong ~/Applications", "Also export as standalone .app in ~/Applications") }
    static var catalogPinToDockToggle: String { s("Ghim ứng dụng này vào thanh Dock của macOS", "Pin this app to macOS Dock") }
    static var catalogCreateAndExportApp: String { s("Tạo & Xuất .app", "Create & Export .app") }
    static var catalogAddToWebBox: String { s("Thêm vào WebBox", "Add to WebBox") }
    static var catalogInvalidURLError: String { s("URL không hợp lệ. Vui lòng nhập đúng định dạng tên miền (VD: chat.zalo.me).", "Invalid URL. Please enter a valid domain (e.g. chat.zalo.me).") }
    static var catalogEnterValidURLError: String { s("Vui lòng nhập địa chỉ trang web hợp lệ.", "Please enter a valid website address.") }
    static func catalogExportAppError(_ detail: String) -> String { s("Lỗi xuất .app: \(detail)", "Failed to export .app: \(detail)") }
    static var catalogAccountIdentification: String { s("Nhận diện tài khoản", "Account Identification") }
    static var catalogAccountDistinguishLabel: String { s("Nhãn phân biệt tài khoản:", "Account label:") }
    static var catalogAccountDistinguishPrompt: String { s("VD: Cá nhân, Công việc, Nick Bán Hàng...", "E.g. Personal, Work, Sales...") }
    static var catalogBadgeCornerSymbol: String { s("Ký hiệu góc Icon:", "Badge text:") }
    static var catalogSessionAndCookies: String { s("Phiên đăng nhập & Cookie", "Session & Cookies") }
    static var catalogCookieIsolationMode: String { s("Chế độ cô lập Cookie:", "Cookie Isolation Mode:") }
    static var catalogIsolatedSessionRecommended: String { s("Tạo phiên độc lập hoàn toàn mới (Khuyên dùng)", "Create new isolated session (Recommended)") }
    static var catalogSharedSession: String { s("Dùng chung Cookie với tài khoản có sẵn (VD: chung FB & Messenger)", "Share Cookies with existing account (e.g. shared FB & Messenger)") }
    static var catalogChooseSharedSession: String { s("Chọn phiên dùng chung:", "Choose shared session:") }
    static var catalogLinkAndDedicatedSection: String { s("Mở đường link & Xuất ứng dụng độc lập", "Link Routing & Dedicated Apps") }
    static var catalogExportDedicatedInApps: String { s("Xuất thành ứng dụng macOS độc lập (.app) trong ~/Applications", "Export as standalone macOS .app in ~/Applications") }
    static var catalogPinDedicatedToDock: String { s("Ghim vào thanh Dock macOS", "Pin to macOS Dock") }
    static var catalogLaunchDedicatedImmediately: String { s("Khởi chạy ngay sau khi tạo", "Launch immediately after creating") }
    static var catalogBackToCatalog: String { s("Quay lại kho ứng dụng", "Back to Catalog") }
    static var catalogCreateAccountAndExportApp: String { s("Tạo tài khoản & Xuất .app", "Create Account & Export .app") }
    static var catalogAddAccount: String { s("Thêm tài khoản", "Add Account") }
    static var catalogAllSpaces: String { s("Tất cả", "All") }
}
