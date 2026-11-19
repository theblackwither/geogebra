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
        case examState
        case examLockRequired
    }

    private var webView: WKWebView!
    private var selectedCalculator = "suite"
    private let lockButton = UIBarButtonItem()
    private var examActive = false
    private var ownsExamLock = false
    private var examInterrupted = false
    private var engineExamStarted = false
    private let examDefaults = UserDefaults.standard
    private let examStatus = UILabel()
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
        view = UIView()
        view.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNativeControls()
        configureExamIntegration()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openDocumentNotification(_:)),
            name: .openGeoGebraDocument,
            object: nil
        )
        loadGeoGebra()
        #if !targetEnvironment(macCatalyst)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateGuidedAccessStatus),
            name: UIAccessibility.guidedAccessStatusDidChangeNotification, object: nil
        )
        #endif
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
                forResource: selectedCalculator + "-offline",
                withExtension: "html",
                subdirectory: "WebAssets"
              ) ?? Bundle.main.url(
                forResource: "missing-assets",
                withExtension: "html",
                subdirectory: "WebAssets"
              )
        guard let entryPoint = entryPoint else { return }
        if examActive && !examInterrupted {
            var components = URLComponents(url: entryPoint, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "examMode", value: "generic")]
            webView.loadFileURL(components?.url ?? entryPoint, allowingReadAccessTo: assetDirectory)
        } else {
            webView.loadFileURL(entryPoint, allowingReadAccessTo: assetDirectory)
        }
    }

    private func configureNativeControls() {
        title = "GeoGebra · Rechner Suite"
        let calculators = [
            ("suite", "Rechner Suite"), ("classic", "Classic"),
            ("graphing", "Grafikrechner"), ("geometry", "Geometrie"),
            ("cas", "CAS"), ("3d", "3D"), ("scientific", "Wissenschaftlich")
        ]
        let actions = calculators.map { id, name in
            UIAction(title: name) { [weak self] _ in
                guard let self = self, self.selectedCalculator != id else { return }
                guard !self.examActive else { return }
                let alert = UIAlertController(
                    title: "Rechner wechseln?",
                    message: "Exportiere deine Konstruktion zuerst. Beim Wechsel wird die aktuelle Ansicht neu geladen.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
                alert.addAction(UIAlertAction(title: "Wechseln", style: .destructive) { _ in
                    self.selectedCalculator = id
                    self.title = "GeoGebra · " + name
                    self.loadGeoGebra()
                })
                self.present(alert, animated: true)
            }
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Rechner", menu: UIMenu(children: actions)
        )
        lockButton.target = self
        lockButton.action = #selector(explainGuidedAccess)
        lockButton.accessibilityLabel = "Status des Geführten Zugriffs"
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Prüfung", menu: UIMenu(children: [
                UIAction(title: "Prüfung vorbereiten") { [weak self] _ in self?.prepareNativeExam() },
                UIAction(title: "Protokoll anzeigen") { [weak self] _ in self?.showExamLog() }
            ])),
            UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(exportConstruction)),
            UIBarButtonItem(title: "Öffnen", style: .plain, target: self, action: #selector(openConstruction)),
            lockButton
        ]
        updateGuidedAccessStatus()
    }

    @objc private func openConstruction() {
        guard !examActive else { return }
        presentDocumentPicker()
    }

    @objc private func exportConstruction() {
        guard !examActive else { return }
        let script = """
        if (!window.ggbApplet || typeof window.ggbApplet.getBase64 !== 'function') {
            throw new Error('GeoGebra wird noch geladen. Bitte erneut versuchen.');
        }
        return await new Promise((resolve, reject) => {
            const timeout = setTimeout(() => reject(new Error('Exportzeit überschritten.')), 30000);
            window.ggbApplet.getBase64(data => { clearTimeout(timeout); resolve(data); });
        });
        """
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            switch result {
            case .success(let value):
                guard let data = value as? String else { return }
                self?.share(["data": data, "name": "Konstruktion", "fileType": "ggb"])
            case .failure(let error):
                self?.showError(title: "Export nicht möglich", message: error.localizedDescription)
            }
        }
    }

    @objc private func updateGuidedAccessStatus() {
        #if targetEnvironment(macCatalyst)
        lockButton.image = UIImage(systemName: "info.circle")
        #else
        lockButton.image = UIImage(systemName: UIAccessibility.isGuidedAccessEnabled ? "lock.fill" : "lock.open")
        #endif
        if examActive {
            #if !targetEnvironment(macCatalyst)
            if !UIAccessibility.isGuidedAccessEnabled {
                examInterrupted = true
                appendExamEvent("Gerätesperre aufgehoben")
            }
            #endif
            publishExamLock()
            refreshExamStatus()
        }
    }

    private func configureExamIntegration() {
        ownsExamLock = examDefaults.bool(forKey: "GeoGebra.ownsExamLock")
        examStatus.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        examStatus.textAlignment = .center
        examStatus.textColor = .white
        examStatus.backgroundColor = .systemRed
        examStatus.isHidden = true
        examStatus.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(examStatus)
        NSLayoutConstraint.activate([
            examStatus.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            examStatus.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            examStatus.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            examStatus.heightAnchor.constraint(equalToConstant: 30)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(examWillResign),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(examDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        if examDefaults.bool(forKey: "GeoGebra.examActive") {
            // A new engine cannot restore a previous in-memory ExamController safely.
            // Preserve its record and explicitly mark the session interrupted.
            examActive = true
            examInterrupted = true
            appendExamEvent("App-Neustart: Prüfung unterbrochen, keine automatische Fortsetzung")
            refreshExamStatus()
        }
    }

    private func appendExamEvent(_ text: String) {
        var events = examDefaults.stringArray(forKey: "GeoGebra.examLog") ?? []
        events.append(ISO8601DateFormatter().string(from: Date()) + " · " + text)
        examDefaults.set(events, forKey: "GeoGebra.examLog")
        examDefaults.set(examActive, forKey: "GeoGebra.examActive")
        examDefaults.set(examInterrupted, forKey: "GeoGebra.examInterrupted")
    }

    private func refreshExamStatus() {
        examStatus.isHidden = !examActive
        examStatus.text = examInterrupted ? "PRÜFUNG UNTERBROCHEN · siehe Protokoll"
            : (engineExamStarted ? "PRÜFUNG · Gerätesperre aktiv" : "PRÜFUNG VORBEREITET · Start in GeoGebra bestätigen")
        examStatus.backgroundColor = examInterrupted ? .systemRed : .systemBlue
        navigationItem.leftBarButtonItem?.isEnabled = !examActive
    }

    private func publishExamLock() {
        #if targetEnvironment(macCatalyst)
        let locked = false
        #else
        let locked = UIAccessibility.isGuidedAccessEnabled && examActive && !examInterrupted
        #endif
        webView.evaluateJavaScript("window.GeoGebraIOSExamLockReady = \(locked ? "true" : "false");")
    }

    private func prepareNativeExam() {
        #if targetEnvironment(macCatalyst)
        showError(title: "Prüfungssperre nicht verfügbar", message: "Eine gesperrte Prüfung benötigt ein echtes iPad. Mac Catalyst unterstützt Geführten Zugriff nicht.")
        #else
        guard !examActive else {
            showExamLog()
            return
        }
        let alert = UIAlertController(title: "Prüfung vorbereiten?",
            message: "Die aktuelle Konstruktion wird verworfen. Auf verwalteten iPads wird die Gerätesperre angefordert. Andernfalls aktiviere zuerst den Geführten Zugriff per Dreifachklick.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        alert.addAction(UIAlertAction(title: "Vorbereiten", style: .default) { [weak self] _ in
            guard let self = self else { return }
            if UIAccessibility.isGuidedAccessEnabled {
                self.launchExamPage()
            } else {
                UIAccessibility.requestGuidedAccessSession(enabled: true) { [weak self] success in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if success && UIAccessibility.isGuidedAccessEnabled {
                            self.ownsExamLock = true
                            self.examDefaults.set(true, forKey: "GeoGebra.ownsExamLock")
                            self.launchExamPage()
                        } else {
                            self.showError(title: "Manuelle Sperre erforderlich", message: "Die automatische Sperre wurde von iPadOS abgelehnt. Aktiviere Geführten Zugriff und wähle danach erneut Prüfung vorbereiten.")
                        }
                    }
                }
            }
        })
        present(alert, animated: true)
        #endif
    }

    private func launchExamPage() {
        examActive = true
        examInterrupted = false
        selectedCalculator = "suite"
        appendExamEvent("Prüfung vorbereitet; Gerätesperre bestätigt")
        refreshExamStatus()
        loadGeoGebra()
    }

    private func receiveExamState(_ state: String) {
        guard ["ACTIVE", "FINISHED", "IDLE", "PREPARING"].contains(state) else { return }
        appendExamEvent("GeoGebra: " + state)
        if state == "ACTIVE" {
            examActive = true
            engineExamStarted = true
            #if !targetEnvironment(macCatalyst)
            if !UIAccessibility.isGuidedAccessEnabled {
                examInterrupted = true
                appendExamEvent("Start ohne bestätigte Sperre: Sitzung unterbrochen")
            }
            #endif
            examDefaults.set(true, forKey: "GeoGebra.examActive")
        } else if state == "IDLE" {
            examActive = false
            examDefaults.set(false, forKey: "GeoGebra.examActive")
            releaseOwnedExamLock()
        }
        refreshExamStatus()
    }

    private func releaseOwnedExamLock() {
        #if !targetEnvironment(macCatalyst)
        guard ownsExamLock else { return }
        UIAccessibility.requestGuidedAccessSession(enabled: false) { [weak self] success in
            DispatchQueue.main.async {
                self?.appendExamEvent(success ? "Automatische Sperre beendet" : "Entsperren abgelehnt; manuell beenden")
                if success {
                    self?.ownsExamLock = false
                    self?.examDefaults.set(false, forKey: "GeoGebra.ownsExamLock")
                }
            }
        }
        #endif
    }

    @objc private func examWillResign() {
        guard examActive else { return }
        examInterrupted = true
        appendExamEvent("App nicht mehr aktiv")
        publishExamLock()
        refreshExamStatus()
    }

    @objc private func examDidBecomeActive() {
        guard examActive else { return }
        appendExamEvent("Zur App zurückgekehrt")
        updateGuidedAccessStatus()
    }

    private func showExamLog() {
        let events = examDefaults.stringArray(forKey: "GeoGebra.examLog") ?? []
        let alert = UIAlertController(title: "Prüfungsprotokoll", message: events.suffix(60).joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Schließen", style: .cancel))
        if examActive && (examInterrupted || !engineExamStarted) {
            alert.addAction(UIAlertAction(title: "Unterbrochene Sitzung abschließen", style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                self.examActive = false
                self.engineExamStarted = false
                self.appendExamEvent("Unterbrochene Sitzung abgeschlossen")
                self.releaseOwnedExamLock()
                self.refreshExamStatus()
                self.loadGeoGebra()
            })
        }
        present(alert, animated: true)
    }

    @objc private func explainGuidedAccess() {
        #if targetEnvironment(macCatalyst)
        showError(title: "Geführter Zugriff", message: "Geführter Zugriff ist eine iPadOS-Funktion und auf diesem Mac nicht verfügbar.")
        #else
        let active = UIAccessibility.isGuidedAccessEnabled
        showError(
            title: active ? "Geführter Zugriff aktiv" : "Geführter Zugriff nicht aktiv",
            message: "Aktiviere ihn unter Einstellungen > Bedienungshilfen > Geführter Zugriff. Starte oder beende ihn mit dem Dreifachklick auf die obere Taste bzw. Home-Taste. Der Prüfungsmodus und die Gerätesperre sind getrennte Zustände."
        )
        #endif
    }

    @objc private func openDocumentNotification(_ notification: Notification) {
        guard !examActive else {
            appendExamEvent("Externer Dateiimport während Prüfung blockiert")
            return
        }
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
        guard !examActive else { return }
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
        window.GeoGebraIOSExamLockReady = false;
        window.GeoGebraIOSExamBridge = {
            canStart: () => {
                if (window.GeoGebraIOSExamLockReady === true) return true;
                post('examLockRequired');
                return false;
            },
            stateChanged: state => post('examState', { state })
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
        guard !examActive else { return }
        #if !targetEnvironment(macCatalyst)
        if UIAccessibility.isGuidedAccessEnabled {
            showError(
                title: "Guided Access is active",
                message: "End Guided Access with the device owner's passcode before testing app switching."
            )
            return
        }
        #endif
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
            guard !examActive else {
                appendExamEvent("Externer Link während Prüfung blockiert")
                return
            }
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
        case .examState:
            guard let payload = message.body as? [String: Any],
                  let state = payload["state"] as? String else { return }
            receiveExamState(state)
        case .examLockRequired:
            showError(title: "Prüfungssperre fehlt", message: "Wähle Prüfung > Prüfung vorbereiten. Der Start ist erst nach bestätigter Gerätesperre möglich. Eine unterbrochene Sitzung muss zuerst über das Protokoll abgeschlossen werden.")
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
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        publishExamLock()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard examActive else { return }
        examInterrupted = true
        appendExamEvent("GeoGebra-Webprozess beendet: Sitzung unterbrochen")
        refreshExamStatus()
    }

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
        if examActive {
            appendExamEvent("Navigation zu externer Seite während Prüfung blockiert")
            decisionHandler(.cancel)
            return
        }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }
}
