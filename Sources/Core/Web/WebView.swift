import Foundation
import SwiftUI
import AppKit
@preconcurrency import WebKit

package struct WebEnhancement: Equatable {
    let id: String
    let source: String
    let atStart: Bool
    let update: String
    package init(id: String, source: String, atStart: Bool = false, update: String) {
        self.id = id; self.source = source; self.atStart = atStart; self.update = update
    }
}

package struct WebResourceHandler {
    let scheme: String
    let handler: WKURLSchemeHandler
    package init(scheme: String, handler: WKURLSchemeHandler) { self.scheme = scheme; self.handler = handler }
}

/// Request/reply transport only. The feature owns validation and implementation.
package struct WebMessageHandler {
    let name: String
    let handle: (Any, @escaping (Any?, String?) -> Void) -> Void
    package init(name: String, handle: @escaping (Any, @escaping (Any?, String?) -> Void) -> Void) {
        self.name = name; self.handle = handle
    }
}

/// Features supply scripts and resource handlers; this host has no feature data access.
package struct WebView: NSViewRepresentable {
    let url: URL
    let enhancements: [WebEnhancement]
    let resourceHandlers: [WebResourceHandler]
    let messageHandlers: [WebMessageHandler]
    package init(url: URL, enhancements: [WebEnhancement] = [], resourceHandlers: [WebResourceHandler] = [],
                 messageHandlers: [WebMessageHandler] = []) {
        self.url = url; self.enhancements = enhancements; self.resourceHandlers = resourceHandlers
        self.messageHandlers = messageHandlers
    }
    package func makeCoordinator() -> Coordinator { Coordinator() }
    package func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        context.coordinator.messageHandlers = messageHandlers
        for handler in messageHandlers {
            configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: handler.name)
        }
        for resource in resourceHandlers { configuration.setURLSchemeHandler(resource.handler, forURLScheme: resource.scheme) }
        for enhancement in enhancements {
            configuration.userContentController.addUserScript(WKUserScript(
                source: enhancement.source, injectionTime: enhancement.atStart ? .atDocumentStart : .atDocumentEnd,
                forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        context.coordinator.lastURL = url
        context.coordinator.enhancements = enhancements
        context.coordinator.messageHandlers = messageHandlers
        web.load(URLRequest(url: url))
        return web
    }
    package func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.enhancements = enhancements
        context.coordinator.applyPreferences(to: nsView)
        guard context.coordinator.lastURL != url else { return }
        context.coordinator.lastURL = url
        nsView.load(URLRequest(url: url))
    }
    package final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
        var lastURL: URL?
        var enhancements: [WebEnhancement] = []
        var messageHandlers: [WebMessageHandler] = []
        package func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                          replyHandler: @escaping (Any?, String?) -> Void) {
            let origin = message.frameInfo.securityOrigin
            guard message.frameInfo.isMainFrame, let url = lastURL,
                  ["127.0.0.1", "localhost", "::1", "[::1]"].contains(url.host ?? ""),
                  origin.protocol == url.scheme, origin.host == url.host,
                  origin.port == (url.port ?? (url.scheme == "https" ? 443 : 80)),
                  let handler = messageHandlers.first(where: { $0.name == message.name }) else {
                replyHandler(nil, "此页面无法使用本机文件功能。"); return
            }
            handler.handle(message.body, replyHandler)
        }
        func applyPreferences(to webView: WKWebView) {
            for enhancement in enhancements { webView.evaluateJavaScript(enhancement.update) }
        }
        package func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { applyPreferences(to: webView) }
        package func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}
