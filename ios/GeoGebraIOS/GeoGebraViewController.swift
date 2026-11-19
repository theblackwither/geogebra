import UniformTypeIdentifiers
import UIKit
import WebKit

final class GeoGebraViewController: UIViewController {
    private enum Message: String, CaseIterable {
        case share
        case openFile
        case openURL
        case savePreference
        case debug
        case testToggle
    }

    private var webView: WKWebView!
    #if DEBUG
    private var testingOutsideApp = false
    private let testLabel = UILabel()
    #endif
    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        let contentController = WKUserContentController()
        Message.allCases.forEach { contentController.add(self, name: $0.rawValue) }
        contentController.addUserScript(
            WKUserScript(
                source: Self.nativeBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        #if DEBUG
        contentController.addUserScript(WKUserScript(
            source: Self.examTestScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        #endif
        configuration.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openDocumentNotification(_:)),
            name: .openGeoGebraDocument,
            object: nil
        )
        loadGeoGebra()
        #if DEBUG
        testLabel.text = "TESTBUILD · keine Prüfungssperre"
        testLabel.textAlignment = .center
        testLabel.textColor = .white
        testLabel.backgroundColor = .systemOrange
        testLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        testLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(testLabel)
        NSLayoutConstraint.activate([
            testLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            testLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            testLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            testLabel.heightAnchor.constraint(equalToConstant: 30)
        ])
        #endif
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        Message.allCases.forEach {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: $0.rawValue)
        }
    }

    private func loadGeoGebra() {
        guard let assetDirectory = Bundle.main.resourceURL?.appendingPathComponent("WebAssets", isDirectory: true) else {
            return
        }
        let entryPoint = Bundle.main.url(
                forResource: "graphing-offline",
                withExtension: "html",
                subdirectory: "WebAssets"
              ) ?? Bundle.main.url(
                forResource: "missing-assets",
                withExtension: "html",
                subdirectory: "WebAssets"
              )
        guard let entryPoint = entryPoint else { return }
        webView.loadFileURL(entryPoint, allowingReadAccessTo: assetDirectory)
    }

    @objc private func openDocumentNotification(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        importDocument(at: url)
    }

    private func importDocument(at url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            openGeoGebraData(data)
        } catch {
            showError(title: "Could not open file", message: error.localizedDescription)
        }
    }

    private func openGeoGebraData(_ data: Data) {
        let base64 = data.base64EncodedString()
        let script = """
        const base64 = arguments.base64;
        const openWhenReady = (remaining) => {
            if (window.ggbApplet && typeof window.ggbApplet.setBase64 === 'function') {
                window.ggbApplet.setBase64(base64);
                return true;
            }
            if (remaining > 0) {
                setTimeout(() => openWhenReady(remaining - 1), 250);
            }
            return false;
        };
        return openWhenReady(120);
        """
        webView.callAsyncJavaScript(
            script,
            arguments: ["base64": base64],
            in: nil,
            in: .page
        ) { [weak self] result in
            if case let .failure(error) = result {
                self?.showError(title: "Could not load construction", message: error.localizedDescription)
            }
        }
    }

    private func presentDocumentPicker() {
        let ggbType = UTType(importedAs: "org.geogebra.ggb", conformingTo: .data)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [ggbType, .data])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func share(_ body: Any) {
        guard let payload = body as? [String: Any],
              let encodedValue = payload["data"] as? String else { return }

        let name = Self.safeFilename(payload["name"] as? String ?? "GeoGebra")
        let fileType = payload["fileType"] as? String ?? "ggb"
        let (data, inferredMIME) = Self.decodeDataValue(encodedValue)
        guard let data = data else {
            showError(title: "Could not export file", message: "GeoGebra returned invalid file data.")
            return
        }

        let fileExtension = Self.fileExtension(for: fileType, dataMIME: inferredMIME)
        let filename = name.lowercased().hasSuffix(".\(fileExtension)") ? name : "\(name).\(fileExtension)"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: destination, options: .atomic)
            let controller = UIActivityViewController(activityItems: [destination], applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            }
            present(controller, animated: true)
        } catch {
            showError(title: "Could not export file", message: error.localizedDescription)
        }
    }

    private func showError(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static func decodeDataValue(_ value: String) -> (Data?, String?) {
        if value.hasPrefix("data:"), let comma = value.firstIndex(of: ",") {
            let metadata = String(value[value.index(value.startIndex, offsetBy: 5)..<comma])
            let payload = String(value[value.index(after: comma)...])
            let mime = metadata.split(separator: ";").first.map(String.init)
            if metadata.contains(";base64") {
                return (Data(base64Encoded: payload), mime)
            }
            return (payload.removingPercentEncoding?.data(using: .utf8), mime)
        }
        return (Data(base64Encoded: value), nil)
    }

    private static func fileExtension(for type: String, dataMIME: String?) -> String {
        let value = type.lowercased()
        if value.contains("png") { return "png" }
        if value.contains("jpeg") || value.contains("jpg") { return "jpg" }
        if value.contains("svg") { return "svg" }
        if value.contains("pdf") { return "pdf" }
        if value.contains("gif") { return "gif" }
        if value.contains("html") { return "html" }
        if value.contains("txt") || value.contains("plain") { return "txt" }
        if let dataMIME = dataMIME, dataMIME != type {
            return fileExtension(for: dataMIME, dataMIME: nil)
        }
        return value == "ggt" ? "ggt" : "ggb"
    }

    private static func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "GeoGebra" : cleaned
    }

    private static let nativeBridgeScript = #"""
    (() => {
        const post = (name, body = {}) => {
            const handler = window.webkit && window.webkit.messageHandlers[name];
            if (handler) handler.postMessage(body);
        };
        window.GeoGebraJSNativeBridge = {
            share: (data, name, fileType) => post('share', { data, name, fileType }),
            savePreference: (key, value) => post('savePreference', { key, value }),
            openFromFileClickedNative: () => post('openFile'),
            openUrlInBrowser: (url) => post('openURL', { url }),
            debug: (message) => post('debug', { message }),
            login: () => post('openURL', { url: 'https://accounts.geogebra.org/' }),
            callPlugin: () => {},
            getCameraPictureNative: () => {},
            listLocalFiles: () => {},
            getMetaData: () => {},
            getBase64: () => {},
            saveFile: () => {},
            createFileFromTube: () => {},
            updateFileFromTube: () => {},
            rename: () => {},
            overwriteMetaData: () => {},
            deleteGgb: () => {},
            open: () => {}
        };
    })();
    """#

    #if DEBUG
    private static let examTestScript = #"""
    document.addEventListener('keydown', event => {
        if (event.key !== 'Enter' || event.isComposing) return;
        const input = event.target.closest('input, textarea, [contenteditable="true"]');
        if (!input) return;
        const value = (input.value ?? input.textContent ?? '').trim();
        if (value !== 'Skibidi') return;
        event.preventDefault();
        event.stopImmediatePropagation();
        if ('value' in input) input.value = '';
        else input.textContent = '';
        window.webkit.messageHandlers.testToggle.postMessage({});
    }, true);
    """#

    private func toggleExamTest() {
        testingOutsideApp.toggle()
        let time = ISO8601DateFormatter().string(from: Date())
        let event = testingOutsideApp ? "left app" : "returned to app"
        var events = UserDefaults.standard.stringArray(forKey: "GeoGebra.examTestEvents") ?? []
        events.append("\(time): \(event)")
        UserDefaults.standard.set(events, forKey: "GeoGebra.examTestEvents")
        testLabel.text = testingOutsideApp
            ? "TESTBUILD · App-Wechsel protokolliert"
            : "TESTBUILD · zurück in GeoGebra"
        if testingOutsideApp, let url = URL(string: "https://example.com") {
            UIApplication.shared.open(url)
        }
    }
    #endif
}

extension GeoGebraViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let messageType = Message(rawValue: message.name) else { return }
        switch messageType {
        case .share:
            share(message.body)
        case .openFile:
            presentDocumentPicker()
        case .openURL:
            guard let payload = message.body as? [String: Any],
                  let value = payload["url"] as? String,
                  let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            UIApplication.shared.open(url)
        case .savePreference:
            guard let payload = message.body as? [String: Any],
                  let key = payload["key"] as? String,
                  let value = payload["value"] else { return }
            UserDefaults.standard.set(value, forKey: "GeoGebra.\(key)")
        case .debug:
            #if DEBUG
            print("GeoGebra:", message.body)
            #endif
        case .testToggle:
            #if DEBUG
            toggleExamTest()
            #endif
        }
    }
}

extension GeoGebraViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importDocument(at: url)
    }
}

extension GeoGebraViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.allow)
            return
        }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }
}
