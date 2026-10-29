import SwiftUI
import AppKit
import WebKit

/// Hosts a persistent WebBoxWKWebView inside an AppKit container so switching between multiple
/// Zalo / Facebook / Gmail accounts happens in 0ms without unloading or reloading the DOM.
struct HostedWebViewContainer: NSViewRepresentable {
    let webView: WebBoxWKWebView

    func makeNSView(context: Context) -> WebHostWrapperNSView {
        let host = WebHostWrapperNSView()
        host.attach(webView: webView)
        return host
    }

    func updateNSView(_ nsView: WebHostWrapperNSView, context: Context) {
        nsView.attach(webView: webView)
    }
}

final class WebHostWrapperNSView: NSView {
    private weak var currentWebView: WebBoxWKWebView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(webView: WebBoxWKWebView) {
        if currentWebView === webView && webView.superview === self {
            return
        }

        subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        currentWebView = webView
    }
}

/// Complete pane for one WebAppInstance (handles Active WebView, Hibernated state, and Detached Window state).
struct InstanceWebPaneView: View {
    let instance: WebAppInstance
    @ObservedObject var sessionManager = WebSessionManager.shared
    @ObservedObject var store = WorkspaceStore.shared

    var body: some View {
        let state = sessionManager.state(for: instance.id)

        ZStack(alignment: .top) {
            if state.isDetachedInWindow {
                detachedPlaceholderView
            } else if state.isHibernated {
                hibernatedPlaceholderView
            } else {
                HostedWebViewContainer(webView: sessionManager.webView(for: instance))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if state.isLoading && !state.isHibernated && !state.isDetachedInWindow {
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: instance.accentHex), .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(24, geo.size.width * max(0.08, state.estimatedProgress)),
                            height: 2.5
                        )
                        .animation(.easeOut(duration: 0.18), value: state.estimatedProgress)
                }
                .frame(height: 2.5)
            }
        }
    }

    private var hibernatedPlaceholderView: some View {
        VStack(spacing: 16) {
            AppInstanceAvatarView(instance: instance, size: 72)
                .opacity(0.85)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.indigo)
                    Text("\(instance.displayTitle) đang ngủ đông")
                        .font(.title3.weight(.semibold))
                }
                Text("WebView tạm ngưng để giải phóng RAM. Phiên đăng nhập (Cookie & IndexedDB) vẫn được giữ nguyên 100%.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                sessionManager.wakeInstance(instance)
            } label: {
                Label("Đánh thức tài khoản ngay", systemImage: "bolt.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: instance.accentHex))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var detachedPlaceholderView: some View {
        VStack(spacing: 16) {
            AppInstanceAvatarView(instance: instance, size: 68)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow.on.rectangle")
                        .foregroundStyle(.blue)
                    Text("\(instance.displayTitle) đang mở ở cửa sổ riêng")
                        .font(.title3.weight(.semibold))
                }
                Text("Bạn có thể đặt cửa sổ này sang màn hình thứ hai để theo dõi nhiều tài khoản cùng lúc.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 12) {
                Button {
                    sessionManager.focusDetachedWindow(instanceID: instance.id)
                } label: {
                    Label("Chuyển tới cửa sổ riêng", systemImage: "macwindow")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    sessionManager.reattachWindowToWorkspace(instanceID: instance.id)
                } label: {
                    Label("Đưa về cửa sổ chính", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
