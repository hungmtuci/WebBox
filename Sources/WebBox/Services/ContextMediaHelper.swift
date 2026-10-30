import Foundation
import AppKit
import WebKit
import Vision
import CoreImage

// MARK: - Context Menu Hit Snapshot & Action Payload

struct ContextMenuHitSnapshot {
    let timestamp: CFAbsoluteTime
    let linkURL: URL?
    let linkDownloadFilename: String
    let hasImage: Bool
    let imageURLString: String
    let imageAlt: String
    let mediaURLString: String
    let frameInfo: WKFrameInfo?

    var isRecent: Bool {
        (CFAbsoluteTimeGetCurrent() - timestamp) < 2.0
    }
}

final class ContextMenuActionPayload: NSObject {
    let viewPoint: NSPoint
    let domPoint: CGPoint
    let linkURL: URL?
    let linkDownloadFilename: String
    let fallbackImageURLString: String
    let fallbackMediaURLString: String
    let frameInfo: WKFrameInfo?
    let instanceID: UUID?
    let sourceTitle: String
    var browserBundleID: String?

    init(
        viewPoint: NSPoint,
        domPoint: CGPoint,
        linkURL: URL?,
        linkDownloadFilename: String = "",
        fallbackImageURLString: String = "",
        fallbackMediaURLString: String = "",
        frameInfo: WKFrameInfo? = nil,
        instanceID: UUID?,
        sourceTitle: String,
        browserBundleID: String? = nil
    ) {
        self.viewPoint = viewPoint
        self.domPoint = domPoint
        self.linkURL = linkURL
        self.linkDownloadFilename = linkDownloadFilename
        self.fallbackImageURLString = fallbackImageURLString
        self.fallbackMediaURLString = fallbackMediaURLString
        self.frameInfo = frameInfo
        self.instanceID = instanceID
        self.sourceTitle = sourceTitle
        self.browserBundleID = browserBundleID
    }
}

struct ExtractedContextImage {
    let image: NSImage
    let rawData: Data
    let pngData: Data?
    let fileExtension: String
    let suggestedFilename: String
    let pixelWidth: Int
    let pixelHeight: Int
}

// MARK: - Context Media & Image Extraction Engine

enum ContextMediaExtractor {

    /// Generates the unified JS user script injected into Instance & In-App Browser WebViews.
    static func makeBridgeScriptSource(
        includeLinkClickInterception: Bool,
        includeNotificationsBridge: Bool,
        customCSS: String
    ) -> String {
        let escapedCSS = customCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let clickInterceptionBlock = includeLinkClickInterception ? """
            document.addEventListener('click', function(e) {
                const a = findAnchor(e.target);
                if (!a || !/^https?:\\/\\//i.test(a.href)) return;
                if (e.altKey) {
                    e.preventDefault();
                    e.stopPropagation();
                    post({ type: 'openLink', url: a.href, override: 'external' });
                } else if (e.metaKey) {
                    e.preventDefault();
                    e.stopPropagation();
                    post({ type: 'openLink', url: a.href, override: 'inApp' });
                }
            }, true);

            document.addEventListener('auxclick', function(e) {
                if (e.button !== 1) return;
                const a = findAnchor(e.target);
                if (a && /^https?:\\/\\//i.test(a.href)) {
                    e.preventDefault();
                    e.stopPropagation();
                    post({ type: 'openLink', url: a.href, override: 'inApp' });
                }
            }, true);
        """ : ""

        let notificationBlock = includeNotificationsBridge ? """
            const NativeNotification = function(title, options) {
                const opts = options || {};
                post({
                    type: 'webNotification',
                    title: String(title || ''),
                    body: String(opts.body || '')
                });
                this.close = function() {};
            };
            NativeNotification.permission = 'granted';
            NativeNotification.requestPermission = function(cb) {
                if (typeof cb === 'function') cb('granted');
                return Promise.resolve('granted');
            };
            window.Notification = NativeNotification;
        """ : ""

        return """
        (function() {
            if (window.__webboxBridgeInstalled) return;
            window.__webboxBridgeInstalled = true;

            function post(payload) {
                try {
                    window.webkit.messageHandlers.webboxBridge.postMessage(payload);
                } catch (_) {}
            }

            function findAnchor(el) {
                while (el && el !== document.documentElement) {
                    if (el.tagName && el.tagName.toLowerCase() === 'a' && el.href) {
                        return el;
                    }
                    el = el.parentElement;
                }
                return null;
            }

            function findMediaElement(el, x, y) {
                let cur = el;
                while (cur && cur !== document.documentElement) {
                    if (cur.tagName) {
                        const t = cur.tagName.toLowerCase();
                        if ((t === 'video' || t === 'audio') && (cur.currentSrc || cur.src)) {
                            return cur;
                        }
                    }
                    cur = cur.parentElement;
                }
                if (typeof x === 'number' && typeof y === 'number' && document.elementsFromPoint) {
                    const stack = document.elementsFromPoint(x, y);
                    for (let i = 0; i < stack.length && i < 8; i++) {
                        const node = stack[i];
                        if (!node || !node.tagName) continue;
                        const t = node.tagName.toLowerCase();
                        if ((t === 'video' || t === 'audio') && (node.currentSrc || node.src)) {
                            return node;
                        }
                    }
                }
                return null;
            }

            function extractBgImageUrl(el) {
                if (!el || el.nodeType !== 1) return '';
                try {
                    const bg = window.getComputedStyle(el).backgroundImage || '';
                    if (!bg || bg === 'none') return '';
                    const m = bg.match(/url\\((['"]?)(.*?)\\1\\)/i);
                    if (m && m[2] && !m[2].startsWith('about:')) {
                        return m[2];
                    }
                } catch (_) {}
                return '';
            }

            function findBestImage(target, x, y) {
                if (target && target.tagName) {
                    const tag = target.tagName.toLowerCase();
                    if (tag === 'img') {
                        const src = target.currentSrc || target.src || '';
                        if (src) return { el: target, kind: 'img', src: src, alt: target.alt || '' };
                    }
                    if (tag === 'canvas' && target.width >= 20 && target.height >= 20) {
                        return { el: target, kind: 'canvas', src: 'canvas://inline', alt: 'canvas' };
                    }
                }

                if (typeof x === 'number' && typeof y === 'number' && document.elementsFromPoint) {
                    const stack = document.elementsFromPoint(x, y);
                    for (let i = 0; i < stack.length && i < 14; i++) {
                        const node = stack[i];
                        if (!node || !node.tagName) continue;
                        const tag = node.tagName.toLowerCase();
                        if (tag === 'input' || tag === 'textarea') break;
                        if (tag === 'button' && i > 0) {
                            const br = node.getBoundingClientRect();
                            if (br.width < 64 && br.height < 64 && !(node.querySelector && node.querySelector('img'))) {
                                break;
                            }
                        }
                        if (tag === 'img') {
                            const src = node.currentSrc || node.src || '';
                            const r = node.getBoundingClientRect();
                            if (src && (r.width >= 20 || node.naturalWidth >= 20) && (r.height >= 20 || node.naturalHeight >= 20)) {
                                return { el: node, kind: 'img', src: src, alt: node.alt || '' };
                            }
                        }
                        if (tag === 'canvas' && node.width >= 24 && node.height >= 24) {
                            return { el: node, kind: 'canvas', src: 'canvas://inline', alt: 'canvas' };
                        }
                        if (tag === 'picture' && node.querySelector) {
                            const inner = node.querySelector('img');
                            if (inner && (inner.currentSrc || inner.src)) {
                                return { el: inner, kind: 'img', src: inner.currentSrc || inner.src, alt: inner.alt || '' };
                            }
                        }
                    }

                    for (let i = 0; i < stack.length && i < 6; i++) {
                        const node = stack[i];
                        if (!node || !node.tagName) continue;
                        const r = node.getBoundingClientRect();
                        if (r.width >= 44 && r.height >= 44) {
                            const bgUrl = extractBgImageUrl(node);
                            if (bgUrl) {
                                return { el: node, kind: 'bg', src: bgUrl, alt: '' };
                            }
                        }
                    }
                }

                if (target && target.querySelectorAll && typeof x === 'number' && typeof y === 'number') {
                    const imgs = target.querySelectorAll('img');
                    for (let i = 0; i < imgs.length && i < 6; i++) {
                        const im = imgs[i];
                        const r = im.getBoundingClientRect();
                        if (r.width >= 20 && r.height >= 20 && x >= r.left - 6 && x <= r.right + 6 && y >= r.top - 6 && y <= r.bottom + 6) {
                            const src = im.currentSrc || im.src || '';
                            if (src) return { el: im, kind: 'img', src: src, alt: im.alt || '' };
                        }
                    }
                }

                return null;
            }

            window.__webboxFindBestImage = findBestImage;
            window.__webboxFindAnchor = findAnchor;
            window.__webboxFindMedia = findMediaElement;

            function recordContextHit(e) {
                const a = findAnchor(e.target);
                const imgInfo = findBestImage(e.target, e.clientX, e.clientY);
                const mediaEl = findMediaElement(e.target, e.clientX, e.clientY);
                const linkHref = (a && a.href) ? String(a.href) : '';
                const linkDownload = (a && a.getAttribute) ? String(a.getAttribute('download') || '') : '';
                const mediaSrc = mediaEl ? String(mediaEl.currentSrc || mediaEl.src || '') : '';

                window.__webboxLastContext = {
                    time: Date.now(),
                    x: e.clientX,
                    y: e.clientY,
                    target: e.target,
                    imgEl: imgInfo ? imgInfo.el : null,
                    imgKind: imgInfo ? imgInfo.kind : '',
                    imgSrc: imgInfo ? imgInfo.src : '',
                    imgAlt: imgInfo ? imgInfo.alt : '',
                    linkHref: linkHref,
                    linkDownload: linkDownload,
                    mediaSrc: mediaSrc
                };

                post({
                    type: 'contextMenuHit',
                    linkURL: linkHref,
                    linkDownload: linkDownload,
                    hasImage: Boolean(imgInfo),
                    imageURL: imgInfo ? String(imgInfo.src || '') : '',
                    imageAlt: imgInfo ? String(imgInfo.alt || '') : '',
                    mediaURL: mediaSrc
                });
            }

            document.addEventListener('mousedown', function(e) {
                if (e.button === 2 || (e.button === 0 && e.ctrlKey)) {
                    recordContextHit(e);
                }
            }, true);

            document.addEventListener('contextmenu', function(e) {
                recordContextHit(e);
            }, true);

            \(clickInterceptionBlock)

            \(notificationBlock)

            const cssText = `\(escapedCSS)`;
            if (cssText.trim().length > 0) {
                const applyCSS = function() {
                    if (!document.head) return;
                    const style = document.createElement('style');
                    style.textContent = cssText;
                    document.head.appendChild(style);
                };
                if (document.head) {
                    applyCSS();
                } else {
                    document.addEventListener('DOMContentLoaded', applyCSS);
                }
            }
        })();
        """
    }

    // MARK: - Full-Resolution Image Extraction (4-Layer Fallback)

    @MainActor
    static func extractImage(
        from webView: WKWebView,
        payload: ContextMenuActionPayload
    ) async -> ExtractedContextImage? {
        let jsBody = """
        function blobToDataURL(blob) {
            return new Promise((resolve) => {
                const reader = new FileReader();
                reader.onloadend = () => resolve(typeof reader.result === 'string' ? reader.result : '');
                reader.onerror = () => resolve('');
                reader.readAsDataURL(blob);
            });
        }

        function exportImgElementViaCanvas(imgEl) {
            try {
                const w = imgEl.naturalWidth || imgEl.width || 0;
                const h = imgEl.naturalHeight || imgEl.height || 0;
                if (w <= 0 || h <= 0) return '';
                const c = document.createElement('canvas');
                c.width = w;
                c.height = h;
                const ctx = c.getContext('2d');
                ctx.drawImage(imgEl, 0, 0, w, h);
                return c.toDataURL('image/png');
            } catch (_) {
                return '';
            }
        }

        let ctx = window.__webboxLastContext;
        let el = null;
        let kind = '';
        let src = fallbackSrc || '';
        let alt = '';

        if (ctx && (Date.now() - (ctx.time || 0)) < 45000 && ctx.imgEl && ctx.imgEl.isConnected) {
            el = ctx.imgEl;
            kind = ctx.imgKind || (el.tagName ? el.tagName.toLowerCase() : 'img');
            src = ctx.imgSrc || (el.currentSrc || el.src || src);
            alt = ctx.imgAlt || el.alt || '';
        }

        if (!el && typeof window.__webboxFindBestImage === 'function') {
            const hit = window.__webboxFindBestImage(null, fallbackX, fallbackY);
            if (hit) {
                el = hit.el;
                kind = hit.kind;
                src = hit.src || src;
                alt = hit.alt || '';
            }
        }

        // Lightbox fallback: find the most prominent visible <img> near click point or screen center
        if (!el) {
            const allImgs = Array.from(document.querySelectorAll('img'));
            let bestScore = 0;
            for (const im of allImgs) {
                const r = im.getBoundingClientRect();
                if (r.width < 40 || r.height < 40) continue;
                const style = window.getComputedStyle(im);
                if (style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity || '1') < 0.05) continue;
                const containsPoint = fallbackX >= r.left - 12 && fallbackX <= r.right + 12 && fallbackY >= r.top - 12 && fallbackY <= r.bottom + 12;
                const area = r.width * r.height * (containsPoint ? 10 : 1);
                if (area > bestScore) {
                    bestScore = area;
                    el = im;
                    kind = 'img';
                    src = im.currentSrc || im.src || src;
                    alt = im.alt || '';
                }
            }
        }

        let rectInfo = null;
        if (el && el.getBoundingClientRect) {
            const r = el.getBoundingClientRect();
            rectInfo = { x: r.left, y: r.top, width: r.width, height: r.height };
        }

        if (kind === 'canvas' && el && el.toDataURL) {
            try {
                const pngUrl = el.toDataURL('image/png');
                return {
                    dataURL: pngUrl,
                    mimeType: 'image/png',
                    src: '',
                    alt: alt || 'canvas',
                    width: el.width || 0,
                    height: el.height || 0,
                    rect: rectInfo
                };
            } catch (_) {}
        }

        if (src && src.startsWith('data:image/')) {
            const m = src.match(/^data:(image\\/[a-zA-Z0-9.+-]+);/i);
            return {
                dataURL: src,
                mimeType: m ? m[1].toLowerCase() : 'image/png',
                src: src,
                alt: alt,
                width: (el && el.naturalWidth) || 0,
                height: (el && el.naturalHeight) || 0,
                rect: rectInfo
            };
        }

        // Primary path: fetch(src) in page origin (handles blob:, same-origin, CORS CDN)
        if (src && !src.startsWith('canvas://')) {
            try {
                const resp = await fetch(src, { credentials: 'include', cache: 'force-cache' });
                if (resp.ok) {
                    const blob = await resp.blob();
                    if (blob && blob.size > 0) {
                        const mime = (blob.type || '').toLowerCase();
                        if (mime === 'image/jpeg' || mime === 'image/jpg' || mime === 'image/png' || mime === 'image/gif') {
                            const dUrl = await blobToDataURL(blob);
                            if (dUrl) {
                                return {
                                    dataURL: dUrl,
                                    mimeType: mime === 'image/jpg' ? 'image/jpeg' : mime,
                                    src: src,
                                    alt: alt,
                                    width: (el && el.naturalWidth) || 0,
                                    height: (el && el.naturalHeight) || 0,
                                    rect: rectInfo
                                };
                            }
                        } else {
                            // WebP / AVIF / SVG -> export lossless PNG at full naturalWidth x naturalHeight if possible
                            if (el && el.tagName && el.tagName.toLowerCase() === 'img') {
                                const canvasPng = exportImgElementViaCanvas(el);
                                if (canvasPng) {
                                    return {
                                        dataURL: canvasPng,
                                        mimeType: 'image/png',
                                        src: src,
                                        alt: alt,
                                        width: el.naturalWidth || 0,
                                        height: el.naturalHeight || 0,
                                        rect: rectInfo
                                    };
                                }
                            }
                            const rawDataUrl = await blobToDataURL(blob);
                            if (rawDataUrl) {
                                return {
                                    dataURL: rawDataUrl,
                                    mimeType: mime || 'application/octet-stream',
                                    src: src,
                                    alt: alt,
                                    width: (el && el.naturalWidth) || 0,
                                    height: (el && el.naturalHeight) || 0,
                                    rect: rectInfo
                                };
                            }
                        }
                    }
                }
            } catch (_) {
                // Revoked blob: URL (very common in Zalo/WhatsApp/Telegram!) or CORS error -> fall through to Canvas!
            }
        }

        // Fallback 2: Draw decoded HTMLImageElement at full naturalWidth x naturalHeight onto offscreen <canvas>
        if (el && el.tagName && el.tagName.toLowerCase() === 'img') {
            const canvasPng = exportImgElementViaCanvas(el);
            if (canvasPng) {
                return {
                    dataURL: canvasPng,
                    mimeType: 'image/png',
                    src: src,
                    alt: alt,
                    width: el.naturalWidth || 0,
                    height: el.naturalHeight || 0,
                    rect: rectInfo
                };
            }
        }

        return {
            dataURL: '',
            mimeType: '',
            src: src,
            alt: alt,
            width: (el && el.naturalWidth) || 0,
            height: (el && el.naturalHeight) || 0,
            rect: rectInfo
        };
        """

        let args: [String: Any] = [
            "fallbackX": Double(payload.domPoint.x),
            "fallbackY": Double(payload.domPoint.y),
            "fallbackSrc": payload.fallbackImageURLString
        ]

        var jsDict: [String: Any]? = nil
        if let raw = try? await webView.callAsyncJavaScript(
            jsBody,
            arguments: args,
            in: payload.frameInfo,
            contentWorld: .page
        ) as? [String: Any] {
            jsDict = raw
        } else if payload.frameInfo != nil,
                  let rawMain = try? await webView.callAsyncJavaScript(
                      jsBody,
                      arguments: args,
                      in: nil,
                      contentWorld: .page
                  ) as? [String: Any] {
            jsDict = rawMain
        }

        let dataURLString = (jsDict?["dataURL"] as? String) ?? ""
        let jsMime = ((jsDict?["mimeType"] as? String) ?? "").lowercased()
        let resolvedSrc = (jsDict?["src"] as? String) ?? payload.fallbackImageURLString
        let altText = (jsDict?["alt"] as? String) ?? ""

        // Decode Tier 1 / Tier 2 JS result
        if !dataURLString.isEmpty,
           let (decodedBytes, parsedMime) = decodeDataURL(dataURLString),
           let nsImage = NSImage(data: decodedBytes) {
            let effectiveMime = !jsMime.isEmpty ? jsMime : parsedMime
            return buildExtractedImage(
                nsImage: nsImage,
                originalData: decodedBytes,
                mimeType: effectiveMime,
                sourceURLString: resolvedSrc,
                altText: altText,
                sourceTitle: payload.sourceTitle
            )
        }

        // Tier 3: Native Swift authenticated URLSession download (bypasses browser CORS!)
        if let remoteURL = URL(string: resolvedSrc),
           let scheme = remoteURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           let (remoteData, remoteMime) = await downloadAuthenticatedResource(url: remoteURL, from: webView),
           let nsImage = NSImage(data: remoteData) {
            return buildExtractedImage(
                nsImage: nsImage,
                originalData: remoteData,
                mimeType: remoteMime,
                sourceURLString: resolvedSrc,
                altText: altText,
                sourceTitle: payload.sourceTitle
            )
        }

        // Tier 4: Viewport element snapshot fallback (guaranteed pixel capture even on offline/DRM-free canvas)
        if let rectDict = jsDict?["rect"] as? [String: Any],
           let rx = rectDict["x"] as? Double,
           let ry = rectDict["y"] as? Double,
           let rw = rectDict["width"] as? Double,
           let rh = rectDict["height"] as? Double,
           rw > 8, rh > 8 {
            let zoom = max(0.25, Double(webView.pageZoom))
            let snapConfig = WKSnapshotConfiguration()
            snapConfig.rect = CGRect(x: rx * zoom, y: ry * zoom, width: rw * zoom, height: rh * zoom)
            if let snapImg = try? await webView.takeSnapshot(configuration: snapConfig),
               let png = encodePNG(from: snapImg) {
                return buildExtractedImage(
                    nsImage: snapImg,
                    originalData: png,
                    mimeType: "image/png",
                    sourceURLString: resolvedSrc,
                    altText: altText,
                    sourceTitle: payload.sourceTitle
                )
            }
        }

        return nil
    }

    // MARK: - Blob / Linked File / Media Extraction

    @MainActor
    static func extractBlobOrMedia(
        from webView: WKWebView,
        payload: ContextMenuActionPayload,
        preferMedia: Bool = false
    ) async -> (blobData: Data?, mimeType: String, remoteURL: URL?, suggestedFilename: String) {
        let explicitCandidate = preferMedia
            ? payload.fallbackMediaURLString
            : (payload.linkURL?.absoluteString ?? payload.fallbackMediaURLString)

        if let directURL = URL(string: explicitCandidate),
           let scheme = directURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {
            let name = suggestedFilenameForURL(
                directURL,
                explicitDownloadAttr: payload.linkDownloadFilename,
                mimeType: "",
                defaultPrefix: "Tep_tai_ve"
            )
            return (nil, "", directURL, name)
        }

        let jsBody = """
        function blobToDataURL(blob) {
            return new Promise((resolve) => {
                const reader = new FileReader();
                reader.onloadend = () => resolve(typeof reader.result === 'string' ? reader.result : '');
                reader.onerror = () => resolve('');
                reader.readAsDataURL(blob);
            });
        }

        let targetUrl = explicitUrl || '';
        let downloadName = explicitDownload || '';
        const ctx = window.__webboxLastContext;

        if (!targetUrl && ctx && (Date.now() - (ctx.time || 0)) < 45000) {
            targetUrl = preferMedia ? (ctx.mediaSrc || ctx.linkHref || '') : (ctx.linkHref || ctx.mediaSrc || '');
            if (!downloadName) downloadName = ctx.linkDownload || '';
        }

        if (!targetUrl && document.elementsFromPoint) {
            const stack = document.elementsFromPoint(fallbackX, fallbackY);
            for (const el of stack) {
                if (!el || !el.tagName) continue;
                const t = el.tagName.toLowerCase();
                if (t === 'a' && el.href) {
                    targetUrl = el.href;
                    downloadName = el.getAttribute('download') || '';
                    break;
                }
                if ((t === 'video' || t === 'audio') && (el.currentSrc || el.src)) {
                    targetUrl = el.currentSrc || el.src;
                    break;
                }
            }
        }

        if (!targetUrl) return { dataURL: '', mimeType: '', url: '', downloadName: downloadName };

        if (/^https?:\\/\\//i.test(targetUrl)) {
            return { dataURL: '', mimeType: '', url: targetUrl, downloadName: downloadName };
        }

        if (targetUrl.startsWith('data:')) {
            const m = targetUrl.match(/^data:([^;,]+)[;,]/i);
            return { dataURL: targetUrl, mimeType: m ? m[1].toLowerCase() : '', url: targetUrl, downloadName: downloadName };
        }

        if (targetUrl.startsWith('blob:')) {
            try {
                const resp = await fetch(targetUrl);
                if (resp.ok) {
                    const blob = await resp.blob();
                    const dUrl = await blobToDataURL(blob);
                    return {
                        dataURL: dUrl,
                        mimeType: (blob.type || '').toLowerCase(),
                        url: targetUrl,
                        downloadName: downloadName
                    };
                }
            } catch (_) {}
        }

        return { dataURL: '', mimeType: '', url: targetUrl, downloadName: downloadName };
        """

        let args: [String: Any] = [
            "explicitUrl": explicitCandidate,
            "explicitDownload": payload.linkDownloadFilename,
            "preferMedia": preferMedia,
            "fallbackX": Double(payload.domPoint.x),
            "fallbackY": Double(payload.domPoint.y)
        ]

        let dict = (try? await webView.callAsyncJavaScript(
            jsBody,
            arguments: args,
            in: payload.frameInfo,
            contentWorld: .page
        )) as? [String: Any]

        let dataURLStr = (dict?["dataURL"] as? String) ?? ""
        let mime = (dict?["mimeType"] as? String) ?? ""
        let foundURLStr = (dict?["url"] as? String) ?? explicitCandidate
        let dlAttr = (dict?["downloadName"] as? String) ?? payload.linkDownloadFilename

        if !dataURLStr.isEmpty, let (bytes, parsedMime) = decodeDataURL(dataURLStr) {
            let finalMime = !mime.isEmpty ? mime : parsedMime
            let fname = suggestedFilenameForURL(
                URL(string: foundURLStr),
                explicitDownloadAttr: dlAttr,
                mimeType: finalMime,
                defaultPrefix: preferMedia ? "Video_WebBox" : "Tep_WebBox"
            )
            return (bytes, finalMime, nil, fname)
        }

        if let httpURL = URL(string: foundURLStr),
           let scheme = httpURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {
            let fname = suggestedFilenameForURL(
                httpURL,
                explicitDownloadAttr: dlAttr,
                mimeType: mime,
                defaultPrefix: preferMedia ? "Video_WebBox" : "Tep_WebBox"
            )
            return (nil, mime, httpURL, fname)
        }

        return (nil, "", nil, "Tep_tai_xuong")
    }

    @MainActor
    static func extractDirectBlobURL(
        _ blobURL: URL,
        from webView: WKWebView
    ) async -> (data: Data, mimeType: String, filename: String)? {
        let jsBody = """
        try {
            const resp = await fetch(targetUrl);
            if (!resp.ok) return null;
            const blob = await resp.blob();
            const dUrl = await new Promise((resolve) => {
                const r = new FileReader();
                r.onloadend = () => resolve(typeof r.result === 'string' ? r.result : '');
                r.onerror = () => resolve('');
                r.readAsDataURL(blob);
            });
            return { dataURL: dUrl, mimeType: (blob.type || '').toLowerCase() };
        } catch (_) {
            return null;
        }
        """
        guard let dict = (try? await webView.callAsyncJavaScript(
            jsBody,
            arguments: ["targetUrl": blobURL.absoluteString],
            in: nil,
            contentWorld: .page
        )) as? [String: Any],
        let dUrl = dict["dataURL"] as? String,
        let (bytes, parsedMime) = decodeDataURL(dUrl) else {
            return nil
        }
        let mime = ((dict["mimeType"] as? String) ?? "").isEmpty ? parsedMime : (dict["mimeType"] as! String)
        let fname = suggestedFilenameForURL(nil, explicitDownloadAttr: "", mimeType: mime, defaultPrefix: "Tep_WebBox")
        return (bytes, mime, fname)
    }

    // MARK: - Clipboard & Vision Foreground Subject Lifting ("Sao chép chủ thể")

    static func copyImageToPasteboard(_ image: NSImage, preferredPNGData: Data? = nil) {
        let png = preferredPNGData ?? encodePNG(from: image)
        let tiff = image.tiffRepresentation

        let pb = NSPasteboard.general
        pb.clearContents()

        var types: [NSPasteboard.PasteboardType] = []
        if png != nil { types.append(.png) }
        if tiff != nil { types.append(.tiff) }

        if !types.isEmpty {
            pb.declareTypes(types, owner: nil)
            if let png { pb.setData(png, forType: .png) }
            if let tiff { pb.setData(tiff, forType: .tiff) }
        } else {
            pb.writeObjects([image])
        }
    }

    /// Uses Apple's Vision Neural Engine (`VNGenerateForegroundInstanceMaskRequest`, macOS 14+)
    /// to cut out people/objects from the background into a crisp transparent PNG!
    static func liftForegroundSubject(from image: NSImage) async -> (image: NSImage, pngData: Data)? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let maskedCGImage: CGImage? = await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first,
                      !observation.allInstances.isEmpty else {
                    return nil
                }
                let pixelBuffer = try observation.generateMaskedImage(
                    ofInstances: observation.allInstances,
                    from: handler,
                    croppedToInstancesExtent: true
                )
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let ciContext = CIContext(options: nil)
                return ciContext.createCGImage(ciImage, from: ciImage.extent)
            } catch {
                return nil
            }
        }.value

        guard let outCG = maskedCGImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: outCG)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return nil }
        let liftedImage = NSImage(cgImage: outCG, size: NSSize(width: outCG.width, height: outCG.height))
        return (liftedImage, pngData)
    }

    // MARK: - Save to Configured Downloads Folder & Share Temp File

    @MainActor
    @discardableResult
    static func saveDataToDownloads(
        _ data: Data,
        suggestedFilename: String,
        sourceTitle: String,
        forceSavePanel: Bool,
        parentWindow: NSWindow?
    ) -> URL? {
        let store = WorkspaceStore.shared
        let downloadsDir = store.resolvedDownloadsDirectoryURL()

        if forceSavePanel || store.preferences.askWhereToSaveEachDownload {
            let panel = NSSavePanel()
            panel.title = "Lưu tệp tải xuống"
            panel.prompt = "Lưu"
            panel.canCreateDirectories = true
            panel.directoryURL = downloadsDir
            panel.nameFieldStringValue = suggestedFilename

            let response: NSApplication.ModalResponse
            if let win = parentWindow, win.isVisible && win.sheetParent == nil {
                response = panel.runModal()
            } else {
                response = panel.runModal()
            }
            guard response == .OK, let chosenURL = panel.url else {
                return nil
            }
            do {
                try data.write(to: chosenURL, options: .atomic)
                WebSessionManager.shared.recordCompletedDirectDownload(
                    filename: chosenURL.lastPathComponent,
                    destinationURL: chosenURL,
                    byteCount: Int64(data.count),
                    sourceTitle: sourceTitle
                )
                return chosenURL
            } catch {
                store.showToast("Không thể lưu tệp: \(error.localizedDescription)")
                return nil
            }
        }

        let targetURL = uniqueFileURL(in: downloadsDir, suggestedName: suggestedFilename)
        do {
            try data.write(to: targetURL, options: .atomic)
            WebSessionManager.shared.recordCompletedDirectDownload(
                filename: targetURL.lastPathComponent,
                destinationURL: targetURL,
                byteCount: Int64(data.count),
                sourceTitle: sourceTitle
            )
            return targetURL
        } catch {
            store.showToast("Không thể lưu tệp: \(error.localizedDescription)")
            return nil
        }
    }

    static func makeTemporaryShareFile(for extracted: ExtractedContextImage) -> URL? {
        let shareDir = FileManager.default.temporaryDirectory.appendingPathComponent("WebBoxMediaPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: shareDir, withIntermediateDirectories: true)
        let fileURL = shareDir.appendingPathComponent(extracted.suggestedFilename)
        do {
            try extracted.rawData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Private Utilities

    @MainActor
    private static func downloadAuthenticatedResource(
        url: URL,
        from webView: WKWebView
    ) async -> (Data, String)? {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        if let storage = config.httpCookieStorage {
            for cookie in cookies {
                storage.setCookie(cookie)
            }
        }

        var req = URLRequest(url: url)
        if let referer = webView.url?.absoluteString, !referer.isEmpty {
            req.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let ua = webView.customUserAgent, !ua.isEmpty {
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
        }
        req.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              !data.isEmpty else {
            return nil
        }
        let mime = (http.mimeType ?? "").lowercased()
        return (data, mime)
    }

    private static func buildExtractedImage(
        nsImage: NSImage,
        originalData: Data,
        mimeType: String,
        sourceURLString: String,
        altText: String,
        sourceTitle: String
    ) -> ExtractedContextImage {
        let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let pw = cg?.width ?? max(1, Int(nsImage.size.width))
        let ph = cg?.height ?? max(1, Int(nsImage.size.height))

        let cleanMime = mimeType.lowercased()
        let finalExt: String
        let finalData: Data
        let pngBytes = encodePNG(from: nsImage)

        if cleanMime == "image/jpeg" || cleanMime == "image/jpg" {
            finalExt = "jpg"
            finalData = originalData
        } else if cleanMime == "image/gif" {
            finalExt = "gif"
            finalData = originalData
        } else if cleanMime == "image/png" {
            finalExt = "png"
            finalData = originalData
        } else {
            // Convert WebP / TIFF / BMP / unknown to universally compatible lossless PNG
            finalExt = "png"
            finalData = pngBytes ?? originalData
        }

        let safeAppPrefix = sanitizeFilenameToken(sourceTitle.components(separatedBy: "—").first ?? "WebBox")
        let stamp = timestampToken()
        let filename = "Anh_\(safeAppPrefix)_\(stamp).\(finalExt)"

        return ExtractedContextImage(
            image: nsImage,
            rawData: finalData,
            pngData: finalExt == "png" ? finalData : pngBytes,
            fileExtension: finalExt,
            suggestedFilename: filename,
            pixelWidth: pw,
            pixelHeight: ph
        )
    }

    static func encodePNG(from image: NSImage) -> Data? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        }
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    private static func decodeDataURL(_ raw: String) -> (Data, String)? {
        guard raw.hasPrefix("data:"),
              let commaIdx = raw.firstIndex(of: ",") else {
            return nil
        }
        let header = String(raw[raw.index(raw.startIndex, offsetBy: 5)..<commaIdx])
        let payload = String(raw[raw.index(after: commaIdx)...])
        let parts = header.split(separator: ";").map(String.init)
        let mime = parts.first?.lowercased() ?? "application/octet-stream"
        let isBase64 = parts.contains { $0.lowercased() == "base64" }

        if isBase64 {
            let cleaned = payload.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            guard let data = Data(base64Encoded: cleaned, options: [.ignoreUnknownCharacters]), !data.isEmpty else {
                return nil
            }
            return (data, mime)
        } else if let decodedStr = payload.removingPercentEncoding,
                  let data = decodedStr.data(using: .utf8), !data.isEmpty {
            return (data, mime)
        }
        return nil
    }

    private static func suggestedFilenameForURL(
        _ url: URL?,
        explicitDownloadAttr: String,
        mimeType: String,
        defaultPrefix: String
    ) -> String {
        let trimmedAttr = explicitDownloadAttr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAttr.isEmpty {
            let safe = sanitizeFullFilename(trimmedAttr)
            if !safe.isEmpty {
                return ensureExtension(on: safe, mimeType: mimeType)
            }
        }

        if let url, (url.scheme == "http" || url.scheme == "https") {
            let last = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !last.isEmpty && last != "/" && last.count <= 96 {
                let safe = sanitizeFullFilename(last)
                if !safe.isEmpty {
                    return ensureExtension(on: safe, mimeType: mimeType)
                }
            }
        }

        let ext = fileExtension(forMimeType: mimeType) ?? "bin"
        return "\(defaultPrefix)_\(timestampToken()).\(ext)"
    }

    private static func ensureExtension(on name: String, mimeType: String) -> String {
        let currentExt = (name as NSString).pathExtension
        if !currentExt.isEmpty { return name }
        if let ext = fileExtension(forMimeType: mimeType) {
            return "\(name).\(ext)"
        }
        return name
    }

    private static func fileExtension(forMimeType mime: String) -> String? {
        switch mime.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/svg+xml": return "svg"
        case "application/pdf": return "pdf"
        case "video/mp4": return "mp4"
        case "video/webm": return "webm"
        case "video/quicktime": return "mov"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/x-m4a": return "m4a"
        case "audio/ogg": return "ogg"
        case "application/zip": return "zip"
        case "text/plain": return "txt"
        case "text/csv": return "csv"
        case "application/json": return "json"
        default: return nil
        }
    }

    private static func sanitizeFilenameToken(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>: ")
        let parts = trimmed.components(separatedBy: invalid).filter { !$0.isEmpty }
        let joined = parts.joined(separator: "_")
        return joined.isEmpty ? "WebBox" : String(joined.prefix(24))
    }

    private static func sanitizeFullFilename(_ input: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = input.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(110))
    }

    private static func timestampToken() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return fmt.string(from: Date())
    }

    static func uniqueFileURL(in directory: URL, suggestedName: String) -> URL {
        let baseURL = directory.appendingPathComponent(suggestedName)
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            return baseURL
        }
        let ext = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        for idx in 1...999 {
            let candidateName = ext.isEmpty ? "\(stem) (\(idx))" : "\(stem) (\(idx)).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        return directory.appendingPathComponent("\(UUID().uuidString)_\(suggestedName)")
    }
}

// MARK: - Centered Clip View for Smooth Pinch-to-Zoom Image Preview

private final class CenteredImageClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let docView = documentView else { return rect }
        let docFrame = docView.frame

        if docFrame.width < rect.width {
            rect.origin.x = (docFrame.width - rect.width) / 2.0
        }
        if docFrame.height < rect.height {
            rect.origin.y = (docFrame.height - rect.height) / 2.0
        }
        return rect
    }
}

// MARK: - Native macOS Standalone Image Preview Window ("Mở hình ảnh trong cửa sổ mới")

@MainActor
final class ImagePreviewWindow: NSObject, NSWindowDelegate {
    let id = UUID()
    let window: NSWindow
    private let extracted: ExtractedContextImage
    private let sourceTitle: String
    private let scrollView = NSScrollView()
    private let imageView = NSImageView()
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private var activeSharingPicker: NSSharingServicePicker?
    private var keyMonitor: Any?
    var onClose: ((UUID) -> Void)?

    init(extracted: ExtractedContextImage, sourceTitle: String, onClose: @escaping (UUID) -> Void) {
        self.extracted = extracted
        self.sourceTitle = sourceTitle
        self.onClose = onClose

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = min(1060.0, screenFrame.width * 0.78)
        let maxH = min(800.0, screenFrame.height * 0.82)

        let imgW = max(120.0, CGFloat(extracted.pixelWidth))
        let imgH = max(120.0, CGFloat(extracted.pixelHeight))
        let fitScale = min(1.0, min(maxW / imgW, (maxH - 52.0) / imgH))
        let winW = max(560.0, min(maxW, round(imgW * fitScale + 48.0)))
        let winH = max(420.0, min(maxH, round(imgH * fitScale + 88.0)))

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Xem hình ảnh — \(sourceTitle) (\(extracted.pixelWidth) × \(extracted.pixelHeight))"
        win.minSize = NSSize(width: 480, height: 340)
        win.isReleasedWhenClosed = false
        win.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1.0)
        win.center()
        self.window = win

        super.init()
        setupUI(fittedCanvasSize: NSSize(width: round(imgW * fitScale), height: round(imgH * fitScale)))
        installKeyboardShortcuts()
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupUI(fittedCanvasSize: NSSize) {
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]

        // Top Unified Control Bar
        let topBarHeight: CGFloat = 46
        let topBar = NSVisualEffectView(frame: NSRect(
            x: 0,
            y: root.bounds.height - topBarHeight,
            width: root.bounds.width,
            height: topBarHeight
        ))
        topBar.autoresizingMask = [.width, .minYMargin]
        topBar.material = .headerView
        topBar.blendingMode = .withinWindow
        topBar.state = .active

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])

        // Zoom controls
        let zoomOutBtn = makeBarButton(title: "", symbol: "minus.magnifyingglass", action: #selector(zoomOutAction))
        zoomOutBtn.toolTip = "Thu nhỏ (⌘-)"

        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.alignment = .center
        zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true

        let zoomInBtn = makeBarButton(title: "", symbol: "plus.magnifyingglass", action: #selector(zoomInAction))
        zoomInBtn.toolTip = "Phóng to (⌘+)"

        let fitBtn = makeBarButton(title: "Vừa khung", symbol: "arrow.up.left.and.arrow.down.right", action: #selector(resetZoomAction))
        fitBtn.toolTip = "Thu phóng vừa khung cửa sổ (⌘0)"

        stack.addArrangedSubview(zoomOutBtn)
        stack.addArrangedSubview(zoomLabel)
        stack.addArrangedSubview(zoomInBtn)
        stack.addArrangedSubview(fitBtn)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        // Action buttons
        let copyBtn = makeBarButton(title: "Sao chép", symbol: "doc.on.doc", action: #selector(copyImageAction))
        copyBtn.toolTip = "Sao chép hình ảnh vào Clipboard (⌘C)"

        let subjectBtn = makeBarButton(title: "Sao chép chủ thể", symbol: "sparkles", action: #selector(copySubjectAction))
        subjectBtn.toolTip = "Tách nền AI và sao chép chủ thể"

        let downloadBtn = makeBarButton(title: "Tải về", symbol: "arrow.down.circle.fill", action: #selector(downloadImageAction))
        downloadBtn.bezelColor = .controlAccentColor
        downloadBtn.toolTip = "Lưu ngay vào thư mục Tải xuống (⌘S)"

        let saveAsBtn = makeBarButton(title: "Lưu thành...", symbol: "folder", action: #selector(saveAsAction))
        saveAsBtn.toolTip = "Chọn thư mục lưu hình ảnh"

        let openPreviewBtn = makeBarButton(title: "Xem trước", symbol: "eye", action: #selector(openInMacOSPreviewAction))
        openPreviewBtn.toolTip = "Mở bằng ứng dụng Xem trước (Preview) của macOS"

        let shareBtn = makeBarButton(title: "Chia sẻ", symbol: "square.and.arrow.up", action: #selector(shareAction(_:)))
        shareBtn.toolTip = "Chia sẻ qua AirDrop, Tin nhắn, Mail, Ảnh..."

        stack.addArrangedSubview(copyBtn)
        stack.addArrangedSubview(subjectBtn)
        stack.addArrangedSubview(downloadBtn)
        stack.addArrangedSubview(saveAsBtn)
        stack.addArrangedSubview(openPreviewBtn)
        stack.addArrangedSubview(shareBtn)

        // Scrollable / Pinch-Zoomable Dark Canvas
        scrollView.frame = NSRect(
            x: 0,
            y: 0,
            width: root.bounds.width,
            height: root.bounds.height - topBarHeight
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1.0)
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.2
        scrollView.maxMagnification = 8.0

        let centeredClip = CenteredImageClipView(frame: scrollView.bounds)
        centeredClip.drawsBackground = true
        centeredClip.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1.0)
        scrollView.contentView = centeredClip

        imageView.frame = NSRect(origin: .zero, size: fittedCanvasSize)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = extracted.image
        scrollView.documentView = imageView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(magnificationDidChange),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        root.addSubview(scrollView)
        root.addSubview(topBar)
        window.contentView = root
        updateZoomLabel()
    }

    private func makeBarButton(title: String, symbol: String, action: Selector) -> NSButton {
        let btn: NSButton
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            if title.isEmpty {
                btn = NSButton(image: img, target: self, action: action)
            } else {
                btn = NSButton(title: title, image: img, target: self, action: action)
                btn.imagePosition = .imageLeading
            }
        } else {
            btn = NSButton(title: title, target: self, action: action)
        }
        btn.bezelStyle = .rounded
        btn.controlSize = .regular
        btn.font = .systemFont(ofSize: 12, weight: .medium)
        return btn
    }

    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 53 { // Escape
                self.window.close()
                return nil
            }
            if flags == .command, let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "c":
                    self.copyImageAction()
                    return nil
                case "s":
                    self.downloadImageAction()
                    return nil
                case "=", "+":
                    self.zoomInAction()
                    return nil
                case "-":
                    self.zoomOutAction()
                    return nil
                case "0":
                    self.resetZoomAction()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    private func updateZoomLabel() {
        let pct = Int(round(scrollView.magnification * 100.0))
        zoomLabel.stringValue = "\(pct)%"
    }

    @objc private func magnificationDidChange() {
        updateZoomLabel()
    }

    @objc private func zoomInAction() {
        let next = min(8.0, scrollView.magnification * 1.25)
        scrollView.animator().magnification = next
        zoomLabel.stringValue = "\(Int(round(next * 100.0)))%"
    }

    @objc private func zoomOutAction() {
        let next = max(0.2, scrollView.magnification / 1.25)
        scrollView.animator().magnification = next
        zoomLabel.stringValue = "\(Int(round(next * 100.0)))%"
    }

    @objc private func resetZoomAction() {
        let availW = max(160.0, scrollView.bounds.width - 32.0)
        let availH = max(160.0, scrollView.bounds.height - 32.0)
        let imgW = max(1.0, CGFloat(extracted.pixelWidth))
        let imgH = max(1.0, CGFloat(extracted.pixelHeight))
        let scale = min(1.0, min(availW / imgW, availH / imgH))
        scrollView.magnification = 1.0
        imageView.frame = NSRect(x: 0, y: 0, width: round(imgW * scale), height: round(imgH * scale))
        updateZoomLabel()
    }

    @objc private func copyImageAction() {
        ContextMediaExtractor.copyImageToPasteboard(extracted.image, preferredPNGData: extracted.pngData)
        WorkspaceStore.shared.showToast("Đã sao chép hình ảnh vào Clipboard")
    }

    @objc private func copySubjectAction() {
        let srcImg = extracted.image
        let fallbackPNG = extracted.pngData
        Task { @MainActor in
            if let lifted = await ContextMediaExtractor.liftForegroundSubject(from: srcImg) {
                ContextMediaExtractor.copyImageToPasteboard(lifted.image, preferredPNGData: lifted.pngData)
                WorkspaceStore.shared.showToast("Đã tách nền & sao chép chủ thể vào Clipboard")
            } else {
                ContextMediaExtractor.copyImageToPasteboard(srcImg, preferredPNGData: fallbackPNG)
                WorkspaceStore.shared.showToast("Không phát hiện chủ thể tách rời — đã sao chép toàn bộ ảnh")
            }
        }
    }

    @objc private func downloadImageAction() {
        _ = ContextMediaExtractor.saveDataToDownloads(
            extracted.rawData,
            suggestedFilename: extracted.suggestedFilename,
            sourceTitle: sourceTitle,
            forceSavePanel: false,
            parentWindow: window
        )
    }

    @objc private func saveAsAction() {
        _ = ContextMediaExtractor.saveDataToDownloads(
            extracted.rawData,
            suggestedFilename: extracted.suggestedFilename,
            sourceTitle: sourceTitle,
            forceSavePanel: true,
            parentWindow: window
        )
    }

    @objc private func openInMacOSPreviewAction() {
        guard let tempURL = ContextMediaExtractor.makeTemporaryShareFile(for: extracted) else { return }
        if let previewAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            NSWorkspace.shared.open(
                [tempURL],
                withApplicationAt: previewAppURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            NSWorkspace.shared.open(tempURL)
        }
    }

    @objc private func shareAction(_ sender: NSButton) {
        guard let tempURL = ContextMediaExtractor.makeTemporaryShareFile(for: extracted) else { return }
        let picker = NSSharingServicePicker(items: [tempURL])
        activeSharingPicker = picker
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
        onClose?(id)
    }
}
