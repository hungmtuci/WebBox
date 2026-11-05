import SwiftUI
import AppKit

struct LinkChoiceOverlayCard: View {
    let prompt: PendingLinkPrompt
    @ObservedObject var store = WorkspaceStore.shared

    private var installedBrowsers: [ExternalBrowserInfo] {
        LinkRouter.installedExternalBrowsers()
    }

    private var sourceInstance: WebAppInstance? {
        store.instance(for: prompt.sourceInstanceID)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    store.pendingLinkPrompt = nil
                }

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    if let inst = sourceInstance {
                        AppInstanceAvatarView(instance: inst, size: 38)
                    } else {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(L10n.linkChoicePromptTitle)
                                .font(.headline)
                            if prompt.wasUnwrapped {
                                Text(L10n.linkChoiceCleanUnwrapped)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.14)))
                            }
                        }
                        Text(L10n.linkChoiceFromSource(prompt.sourceInstanceTitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        store.pendingLinkPrompt = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }

                // Destination URL preview box
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: prompt.resolvedURL.scheme == "https" ? "lock.fill" : "globe")
                            .font(.caption)
                            .foregroundStyle(prompt.resolvedURL.scheme == "https" ? .green : .secondary)
                        Text(prompt.hostDisplay)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(prompt.resolvedURL.absoluteString, forType: .string)
                            store.pendingLinkPrompt = nil
                            store.showToast(L10n.s("Đã sao chép liên kết", "Link copied to Clipboard"))
                        } label: {
                            Label(L10n.copy, systemImage: "doc.on.doc")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text(prompt.resolvedURL.absoluteString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Two Primary Choice Cards
                HStack(spacing: 12) {
                    // Option 1: Open inside App's Built-in Browser
                    Button {
                        applyRememberPreferenceIfNeeded(.inAppBrowser)
                        store.openLinkInAppBrowser(prompt.resolvedURL, for: prompt.sourceInstanceID)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sidebar.right")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("⏎ Return")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.white.opacity(0.18)))
                            }
                            Text(L10n.linkChoiceInAppTitle)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                            Text(L10n.linkChoiceInAppSubtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.86))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.blue.opacity(0.88)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)

                    // Option 2: Open in External macOS Browser
                    Button {
                        applyRememberPreferenceIfNeeded(.externalBrowser)
                        let preferred = sourceInstance?.preferredExternalBrowserBundleID
                        LinkRouter.openInExternalBrowser(prompt.resolvedURL, preferredBrowserBundleID: preferred)
                        store.pendingLinkPrompt = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "safari.fill")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.blue)
                                Spacer()
                                Text("⌘E")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                            Text(L10n.linkChoiceExternalTitle)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(String(format: L10n.linkChoiceExternalSubtitle("%@"), preferredBrowserLabel))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("e", modifiers: [.command])
                }

                // Quick Pick Specific Installed Browsers (Safari, Chrome, Cốc Cốc, Arc...)
                if installedBrowsers.count > 1 {
                    HStack(spacing: 8) {
                        Text(L10n.linkChoiceQuickOpenWith)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(installedBrowsers) { browser in
                                    Button {
                                        LinkRouter.openInExternalBrowser(
                                            prompt.resolvedURL,
                                            preferredBrowserBundleID: browser.bundleIdentifier
                                        )
                                        store.pendingLinkPrompt = nil
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(nsImage: LinkRouter.cachedIcon(for: browser, size: 14))
                                                .resizable()
                                                .frame(width: 14, height: 14)
                                            Text(browser.name)
                                                .font(.caption.weight(.medium))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color(nsColor: .controlBackgroundColor))
                                        )
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Footer: Remember preference & Modifier tips
                HStack {
                    Toggle(isOn: $store.rememberLinkChoiceForApp) {
                        Text(String(format: L10n.s("Ghi nhớ lựa chọn cho **%@**", "Remember choice for **%@**"), prompt.sourceInstanceTitle))
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)

                    Spacer()

                    Text(L10n.linkChoiceModifierTips)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .frame(width: 580)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var preferredBrowserLabel: String {
        if let prefID = sourceInstance?.preferredExternalBrowserBundleID,
           let matched = installedBrowsers.first(where: { $0.bundleIdentifier == prefID }) {
            return matched.name
        }
        return LinkRouter.defaultSystemBrowserName()
    }

    private func applyRememberPreferenceIfNeeded(_ chosenMode: LinkRoutingMode) {
        guard store.rememberLinkChoiceForApp, var inst = sourceInstance else { return }
        inst.linkRoutingMode = chosenMode
        store.updateInstance(inst)
    }
}
