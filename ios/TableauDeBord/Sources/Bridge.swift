import UIKit
import WebKit

/// Équivalent Swift du pont Java (Bridge_android.java) : réseau, réglages, batterie, veille, Bluetooth.
final class Bridge {
    weak var webView: WKWebView?

    private let defaults = UserDefaults.standard
    private let cfgKey = "tdb.cfg.v1"
    private let ble = BleLights()
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.waitsForConnectivity = false
        c.timeoutIntervalForResource = 90
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()
    private var sleeping = false
    private var brightnessBefore: CGFloat?
    private var timer: Timer?

    /// Valeur d'appCode() côté iPad : très haute pour que la page ne propose jamais d'APK Android.
    private let appCode = 9999

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        ble.onChange = { [weak self] in self?.pushState() }
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.pushState() }
        nc.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.pushState() }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if self.sleeping { self.applyBrightness(true) }
            self.pushState()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.pushState() }
        prepareDocumentsFolder()
    }

    // MARK: - état partagé avec la page

    private func cfgDict() -> [String: String] {
        return (defaults.dictionary(forKey: cfgKey) as? [String: String]) ?? [:]
    }

    private func batteryString() -> String {
        let l = UIDevice.current.batteryLevel
        if l < 0 { return "" }
        let st = UIDevice.current.batteryState
        let charging = (st == .charging || st == .full) ? 1 : 0
        return "\(Int((l * 100).rounded()));\(charging)"
    }

    /// Fichiers ical.txt / tuya.txt déposés dans le dossier de l'appli (app Fichiers) : lus ici, servis à readFile().
    private func droppedFiles() -> [String: String] {
        var out: [String: String] = [:]
        let fm = FileManager.default
        guard let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
              let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return out }
        for base in ["ical", "tuya"] {
            var best: (Date, URL)?
            for n in names {
                let low = n.lowercased()
                guard low.hasPrefix(base), low.hasSuffix(".txt") else { continue }
                let u = dir.appendingPathComponent(n)
                guard let attrs = try? fm.attributesOfItem(atPath: u.path),
                      let size = attrs[.size] as? Int, size <= 200_000,
                      let date = attrs[.modificationDate] as? Date else { continue }
                if best == nil || date > best!.0 { best = (date, u) }
            }
            if let b = best, var text = try? String(contentsOf: b.1, encoding: .utf8) {
                if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
                out[base] = text
            }
        }
        return out
    }

    private func prepareDocumentsFolder() {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let note = dir.appendingPathComponent("LISEZ-MOI.txt")
        if !fm.fileExists(atPath: note.path) {
            let t = "Dépose ici ical.txt (lien iCal de l'agenda) et tuya.txt (réglages Tuya), puis dans le tableau de bord : Autre > Réglages > Importer."
            try? t.write(to: note, atomically: true, encoding: .utf8)
        }
    }

    private func stateDict(includeCfg: Bool) -> [String: Any] {
        var d: [String: Any] = [
            "battery": batteryString(),
            "ble": ble.available,
            "files": droppedFiles(),
            "appCode": appCode
        ]
        if includeCfg { d["cfg"] = cfgDict() }
        return d
    }

    private func jsonString(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// Code JavaScript injecté au démarrage de la page : le pont window.Native avec l'état initial.
    func shimSource() -> String {
        guard let url = Bundle.main.url(forResource: "native-shim", withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            return "window.__tdbShimMissing = true;"
        }
        return src.replacingOccurrences(of: "__STATE__", with: jsonString(stateDict(includeCfg: true)))
    }

    func pushState() {
        let js = "window.__tdbState&&window.__tdbState(\(jsonString(stateDict(includeCfg: false))))"
        DispatchQueue.main.async { [weak self] in self?.webView?.evaluateJavaScript(js, completionHandler: nil) }
    }

    // MARK: - messages venant de la page

    private func int(_ x: Any?) -> Int {
        if let n = x as? NSNumber { return n.intValue }
        if let s = x as? String, let v = Int(s) { return v }
        return 0
    }

    private func str(_ x: Any?) -> String {
        if let s = x as? String { return s }
        if let n = x as? NSNumber { return n.stringValue }
        return ""
    }

    func handle(_ body: Any, reloadPage: @escaping () -> Void) {
        guard let d = body as? [String: Any], let m = d["m"] as? String, let a = d["a"] as? [Any] else { return }
        switch m {
        case "http":
            guard a.count >= 6 else { return }
            http(id: int(a[0]), method: str(a[1]), urlString: str(a[2]), headersJson: str(a[3]), body: str(a[4]), timeoutMs: int(a[5]))
        case "cfgSet":
            guard a.count >= 2 else { return }
            var c = cfgDict()
            c[str(a[0])] = str(a[1])
            defaults.set(c, forKey: cfgKey)
        case "bleWrite":
            guard a.count >= 4 else { return }
            let id = int(a[0])
            ble.write(addr: str(a[1]), csv: str(a[2])) { [weak self] err in
                self?.deliver(id: id, status: err == nil ? 200 : 0, body: "", error: err ?? "")
            }
        case "setSleep":
            sleeping = (a.first as? NSNumber)?.boolValue ?? false
            applyBrightness(sleeping)
        case "reloadUi":
            DispatchQueue.main.async { reloadPage() }
        default:
            break
        }
    }

    // MARK: - veille : luminosité minimale (l'écran reste allumé en permanence)

    private func applyBrightness(_ on: Bool) {
        DispatchQueue.main.async {
            if on {
                if self.brightnessBefore == nil { self.brightnessBefore = UIScreen.main.brightness }
                UIScreen.main.brightness = 0
            } else if let b = self.brightnessBefore {
                UIScreen.main.brightness = b
                self.brightnessBefore = nil
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    // MARK: - HTTP

    private func http(id: Int, method: String, urlString: String, headersJson: String, body: String, timeoutMs: Int) {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            deliver(id: id, status: 0, body: "", error: "adresse invalide")
            return
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: max(1, Double(timeoutMs) / 1000))
        req.httpMethod = method.uppercased()
        if let data = headersJson.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj { req.setValue("\(v)", forHTTPHeaderField: k) }
        }
        if !body.isEmpty, req.httpMethod != "GET", req.httpMethod != "HEAD" {
            req.httpBody = body.data(using: .utf8)
        }
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self else { return }
            if let err = err {
                self.deliver(id: id, status: 0, body: "", error: self.describe(err, url: url))
                return
            }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var text = ""
            if let data = data {
                text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            }
            self.deliver(id: id, status: status, body: text, error: "")
        }.resume()
    }

    private func isLocalHost(_ url: URL) -> Bool {
        guard let h = url.host?.lowercased() else { return false }
        if h.hasSuffix(".local") || !h.contains(".") { return true }
        let p = h.split(separator: ".").compactMap { Int($0) }
        if p.count == 4 {
            if p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 169 && p[1] == 254) { return true }
            if p[0] == 172 && p[1] >= 16 && p[1] <= 31 { return true }
        }
        return false
    }

    /// Les messages gardent les mots que la page reconnaît pour détecter « réseau coupé » (ENETUNREACH, UnknownHost).
    private func describe(_ e: Error, url: URL) -> String {
        let ns = e as NSError
        guard ns.domain == NSURLErrorDomain else { return "\(e.localizedDescription) (\(ns.domain) \(ns.code))" }
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
            if isLocalHost(url) {
                return "appareil du réseau local injoignable (code \(ns.code) : vérifie l'autorisation « Réseau local » de l'appli dans Réglages iPad)"
            }
            return "Network is unreachable (ENETUNREACH, code \(ns.code))"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "UnknownHostException : \(url.host ?? "?") (code \(ns.code))"
        case NSURLErrorTimedOut:
            return "délai dépassé (timeout, code \(ns.code))"
        case NSURLErrorCannotConnectToHost:
            return "connexion refusée ou impossible (code \(ns.code))"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "connexion non chiffrée refusée par iOS (code \(ns.code))"
        default:
            return "\(ns.localizedDescription) (code \(ns.code))"
        }
    }

    // MARK: - réponse vers la page : window.__nat(id, statut, corps, erreur)

    private func jsq(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              var j = String(data: data, encoding: .utf8) else { return "\"\"" }
        j.removeFirst()
        j.removeLast()
        return j.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private func deliver(id: Int, status: Int, body: String, error: String) {
        let js = "window.__nat&&window.__nat(\(id),\(status),\(jsq(body)),\(jsq(error)))"
        DispatchQueue.main.async { [weak self] in self?.webView?.evaluateJavaScript(js, completionHandler: nil) }
    }
}
