import Foundation

/// Mises à jour de l'interface : stockage de la nouvelle page, choix de la page à charger, enregistrement après vérification.
/// Même règles que l'appli Android : rien n'est enregistré sans une signature valide de version.json
/// et sans que l'empreinte (uisha) corresponde au fichier reçu.
enum Ota {
    /// Niveau du pont iPad : une interface qui exige plus (marqueur TDBA) est refusée plutôt que d'être cassée.
    static let bridgeLevel = 211

    private static let defaults = UserDefaults.standard
    private static let buildKey = "tdb.ota.build"
    private static var pending = ""

    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("www", isDirectory: true)
    }
    static var file: URL { dir.appendingPathComponent("index.html") }

    /// Valeur du marqueur « TDBV:123 » / « TDBA:123 » dans la page, ou -1.
    static func mark(_ text: String, _ key: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: key + ":(\\d+)"),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text), let v = Int(text[r]) else { return -1 }
        return v
    }

    /// Page à afficher et dossier qu'elle peut lire : l'interface mise à jour si elle est valide, sinon celle livrée avec l'appli.
    static func page() -> (page: URL, readAccess: URL)? {
        guard let bundled = Bundle.main.url(forResource: "index", withExtension: "html") else { return nil }
        let fallback = (page: bundled, readAccess: bundled.deletingLastPathComponent())
        let fm = FileManager.default
        // Nouvelle compilation de l'appli (interface livrée différente) : l'ancienne mise à jour est écartée.
        if let d = try? Data(contentsOf: bundled) {
            let id = Sig.sha256Hex(d)
            if defaults.string(forKey: buildKey) != id {
                try? fm.removeItem(at: file)
                defaults.set(id, forKey: buildKey)
            }
        }
        guard fm.fileExists(atPath: file.path) else { return fallback }
        guard let t = try? String(contentsOf: file, encoding: .utf8),
              t.contains("window.LOCAL"), mark(t, "TDBV") >= 0,
              mark(t, "TDBA") >= 0, mark(t, "TDBA") <= bridgeLevel else {
            try? fm.removeItem(at: file)
            return fallback
        }
        return (page: file, readAccess: dir)
    }

    static func clear() { try? FileManager.default.removeItem(at: file) }

    // L'interface arrive par morceaux (appels synchrones courts depuis la page), puis on valide le tout.
    static func begin() { pending = "" }
    static func chunk(_ s: String) { pending += s }

    static func commit(versionJson: String, signatureB64: String) -> String {
        let html = pending
        pending = ""
        guard Sig.verify(versionJson, signatureB64: signatureB64) else { return "err:signature invalide" }
        guard let data = versionJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "err:vérification impossible" }
        let want = (obj["uisha"] as? String) ?? ""
        let bytes = Data(html.utf8)
        guard want.count == 64, want.lowercased() == Sig.sha256Hex(bytes) else {
            return "err:empreinte de l'interface différente de celle signée"
        }
        guard bytes.count >= 20000, html.contains("window.LOCAL") else { return "err:fichier d'interface invalide" }
        let v = mark(html, "TDBV"), a = mark(html, "TDBA")
        guard v >= 0, a >= 0 else { return "err:fichier d'interface sans numéro de version" }
        if a > bridgeLevel {
            return "err:cette interface demande une appli iPad plus récente (niveau \(a), actuel \(bridgeLevel)) : recompile et réinstalle l'appli"
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try bytes.write(to: file, options: .atomic)
        } catch {
            return "err:écriture impossible"
        }
        return "ok:\(v)"
    }
}
