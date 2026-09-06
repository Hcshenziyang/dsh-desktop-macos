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

/// Features supply scripts and resource handlers; this host has no feature data access.
package struct WebView: NSViewRepresentable {
    let url: URL
    let enhancements: [WebEnhancement]
    let resourceHandlers: [WebResourceHandler]
    package init(url: URL, enhancements: [WebEnhancement] = [], resourceHandlers: [WebResourceHandler] = []) {
        self.url = url; self.enhancements = enhancements; self.resourceHandlers = resourceHandlers
    }
    package func makeCoordinator() -> Coordinator { Coordinator() }
    package func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
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
    package final class Coordinator: NSObject, WKNavigationDelegate {
        var lastURL: URL?
        var enhancements: [WebEnhancement] = []
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
