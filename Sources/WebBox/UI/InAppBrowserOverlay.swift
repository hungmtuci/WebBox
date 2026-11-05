import SwiftUI
import AppKit

struct InAppBrowserPaneView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var sessionManager = WebSessionManager.shared

    private var tabs: [InAppBrowserTab] {
        store.visibleInAppTabs
    }

    private var currentTab: InAppBrowserTab? {
        store.activeInAppTab
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Multi-tab strip
            tabStripBar

            Divider()

            // 2. Navigation & External Handoff Toolbar
            if let tab = currentTab {
                navigationToolbar(for: tab)
                Divider()

                // 3. Loading progress indicator
                ZStack(alignment: .top) {
                    HostedWebViewContainer(webView: sessionManager.inAppWebView(for: tab))
                        .id(tab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if tab.isLoading {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(
                                    width: max(20, geo.size.width * max(0.08, tab.estimatedProgress)),
                                    height: 2.5
                                )
                        }
                        .frame(height: 2.5)
                    }
                }
                .onAppear {
                    store.inAppAddressBarText = tab.currentURL.absoluteString
                }
            } else {
                ContentUnavailableView(
                    L10n.inAppNoTabsOpen,
                    systemImage: "globe",
                    description: Text(L10n.inAppNoTabsDesc)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var tabStripBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe.asia.australia.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.leading, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs) { tab in
                        let isSelected = tab.id == currentTab?.id
                        HStack(spacing: 6) {
                            if tab.isLoading {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.75)
                            } else {
                                Image(systemName: "doc.richtext")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(tab.title)
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .frame(maxWidth: 165, alignment: .leading)

                            Button {
                                store.closeInAppTab(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(3)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.activeInAppTabID = tab.id
                            store.inAppAddressBarText = tab.currentURL.absoluteString
                        }
                    }

                    // New blank search tab button
                    Button {
                        if let activeID = store.activeInstanceID,
                           let google = URL(string: "https://www.google.com") {
                            store.openLinkInAppBrowser(google, for: activeID)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.inAppNewTabTooltip)
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 4)

            // Layout toggle: Split View vs Full View
            Button {
                let next: InAppBrowserLayoutMode = store.preferences.inAppBrowserLayout == .splitRight
                    ? .fullOverlay
                    : .splitRight
                store.preferences.inAppBrowserLayout = next
                store.save()
            } label: {
                Image(systemName: store.preferences.inAppBrowserLayout == .splitRight ? "arrow.up.left.and.arrow.down.right" : "rectangle.split.2x1")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(store.preferences.inAppBrowserLayout == .splitRight ? L10n.inAppExpandFullTooltip : L10n.inAppSplitRightTooltip)

            // Hide / Minimize In-App Browser (keeps tabs alive!)
            Button {
                store.isInAppBrowserVisible = false
            } label: {
                Image(systemName: "chevron.right.2")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.inAppMinimizeTooltip)

            // Close all tabs
            Button {
                store.closeAllInAppTabsForActiveInstance()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help(L10n.inAppCloseAllTabsTooltip)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    private func navigationToolbar(for tab: InAppBrowserTab) -> some View {
        HStack(spacing: 6) {
            Button {
                sessionManager.goBackInAppTab(tabID: tab.id)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!tab.canGoBack)

            Button {
                sessionManager.goForwardInAppTab(tabID: tab.id)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!tab.canGoForward)

            Button {
                sessionManager.reloadInAppTab(tabID: tab.id)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Address / Search Field
            HStack(spacing: 6) {
                Image(systemName: tab.currentURL.scheme == "https" ? "lock.fill" : "globe")
                    .font(.caption2)
                    .foregroundStyle(tab.currentURL.scheme == "https" ? .green : .secondary)

                TextField(L10n.inAppAddressPlaceholder, text: $store.inAppAddressBarText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .onSubmit {
                        submitAddressBar(for: tab)
                    }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tab.currentURL.absoluteString, forType: .string)
                    store.showToast(L10n.inAppCopiedURL)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.inAppCopyURLTooltip)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

            // Prominent 1-Click Handoff to External Browser + Browser Picker Menu!
            Menu {
                let defaultName = LinkRouter.defaultSystemBrowserName()
                Button {
                    let pref = store.instance(for: tab.ownerInstanceID)?.preferredExternalBrowserBundleID
                    LinkRouter.openInExternalBrowser(tab.currentURL, preferredBrowserBundleID: pref)
                } label: {
                    Label(L10n.inAppOpenExternalDefault(defaultName), systemImage: "safari")
                }

                let browsers = LinkRouter.installedExternalBrowsers()
                if !browsers.isEmpty {
                    Divider()
                    ForEach(browsers) { browser in
                        Button {
                            LinkRouter.openInExternalBrowser(tab.currentURL, preferredBrowserBundleID: browser.bundleIdentifier)
                        } label: {
                            Text(L10n.inAppOpenWithBrowser(browser.name))
                        }
                    }
                }
            } label: {
                Label(L10n.inAppOpenExternal, systemImage: "arrow.up.right.square.fill")
                    .font(.caption.weight(.semibold))
            } primaryAction: {
                let pref = store.instance(for: tab.ownerInstanceID)?.preferredExternalBrowserBundleID
                LinkRouter.openInExternalBrowser(tab.currentURL, preferredBrowserBundleID: pref)
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .help(L10n.inAppOpenExternalHelp)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func submitAddressBar(for tab: InAppBrowserTab) {
        let raw = store.inAppAddressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        let targetURL: URL?
        if raw.contains(" ") || (!raw.contains(".") && !raw.contains("://")) {
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            targetURL = URL(string: "https://www.google.com/search?q=\(encoded)")
        } else {
            targetURL = LinkRouter.normalizeUserEnteredURL(raw)
        }

        if let url = targetURL {
            store.inAppAddressBarText = url.absoluteString
            sessionManager.navigateInAppTab(tabID: tab.id, to: url)
        }
    }
}
