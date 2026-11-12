import Foundation
import CryptoKit

/// Import automatique des réglages : lit le texte de reglages.txt / ical.txt / tuya.txt et le fusionne dans les réglages.
/// Fonction pure (sans interface) pour pouvoir la tester sur GitHub Actions.
enum SettingsImport {
    /// Champs de la page Réglages (Autre > Réglages).
    static let settingKeys = ["updurl", "diagrepo", "diagtok", "airzone", "system", "zone", "lat", "lon", "ical",
                              "lum", "lum2", "tyname", "tyregion", "tyid", "tysecret", "tydevice", "tycode"]
    /// Noms utilisés dans l'ancien tuya.txt.
    static let tuyaKeys = ["id": "tyid", "secret": "tysecret", "device": "tydevice",
                           "region": "tyregion", "code": "tycode", "name": "tyname"]

    struct Result {
        var cfg: [String: Any]
        var changed: Int
        var message: String
    }

    /// Empreinte du contenu des trois fichiers : permet de ne ré-importer que s'ils ont changé.
    static func digest(ical: String?, tuya: String?, reglages: String?) -> String {
        return sha256Hex(Data(("ical:" + (ical ?? "") + "\ntuya:" + (tuya ?? "") + "\nreglages:" + (reglages ?? "")).utf8))
    }

    static func sha256Hex(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func parsePairs(_ text: String) -> [(key: String, value: String)] {
        var out: [(key: String, value: String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") { continue }
            guard let eq = l.firstIndex(of: "=") else { continue }
            out.append((l[..<eq].trimmingCharacters(in: .whitespaces).lowercased(),
                        l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces)))
        }
        return out
    }

    /// Fusionne les fichiers dans `cfg` : ical.txt (1re ligne utile = lien iCal), puis tuya.txt, puis reglages.txt (qui l'emporte).
    /// Une valeur vide ne remplace rien ; les clés inconnues sont ignorées et signalées dans le message.
    static func apply(ical: String?, tuya: String?, reglages: String?, to cfg: [String: Any]) -> Result {
        var found: [String: String] = [:]
        var ignored: [String] = []
        if let t = ical {
            for raw in t.components(separatedBy: .newlines) {
                let l = raw.trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l.hasPrefix("#") { continue }
                found["ical"] = l
                break
            }
        }
        if let t = tuya {
            for p in parsePairs(t) {
                if let k = tuyaKeys[p.key] { if !p.value.isEmpty { found[k] = p.value } } else { ignored.append(p.key) }
            }
        }
        if let t = reglages {
            for p in parsePairs(t) {
                if settingKeys.contains(p.key) { if !p.value.isEmpty { found[p.key] = p.value } } else { ignored.append(p.key) }
            }
        }
        var out = cfg
        var changed = 0
        for (k, v) in found where (out[k] as? String) != v {
            out[k] = v
            changed += 1
        }
        var msg = found.isEmpty ? "Fichier de réglages lu, mais aucune ligne « clé=valeur » reconnue"
            : (changed > 0 ? "Réglages importés (\(changed) modifié\(changed > 1 ? "s" : ""))" : "Réglages déjà à jour")
        if !ignored.isEmpty { msg += " · ignoré : " + ignored.prefix(5).joined(separator: ", ") }
        return Result(cfg: out, changed: changed, message: msg)
    }
}
