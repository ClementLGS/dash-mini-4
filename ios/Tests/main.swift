import Foundation

// Test de l'import automatique des réglages (SettingsImport.swift, le même code que l'appli).
var failed = false
func check(_ name: String, _ ok: Bool) { print((ok ? "OK      " : "ECHEC   ") + name); if !ok { failed = true } }
check("sha256 de « abc »", SettingsImport.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

// --- import automatique des réglages (SettingsImport.swift) ---
let base: [String: Any] = ["airzone": "ancien:3000", "zone": "2", "lat": "44.8"]
let r1 = SettingsImport.apply(ical: "# lien\r\nhttps://exemple.test/a.ics?x=1\r\n", tuya: "id=AAA\nSecret = S=3\n# x\nregion=eu\nbidule=1\n",
                              reglages: "airzone=192.168.1.9:3000\r\nzone=\nlat = 44.9\nlum=\nzonne=3\n", to: base)
check("reglages.txt remplace une valeur", (r1.cfg["airzone"] as? String) == "192.168.1.9:3000" && (r1.cfg["lat"] as? String) == "44.9")
check("valeur vide ne remplace rien", (r1.cfg["zone"] as? String) == "2" && r1.cfg["lum"] == nil)
check("ical.txt : 1re ligne utile, CRLF géré", (r1.cfg["ical"] as? String) == "https://exemple.test/a.ics?x=1")
check("tuya.txt : correspondance des noms, « = » dans la valeur", (r1.cfg["tyid"] as? String) == "AAA" && (r1.cfg["tysecret"] as? String) == "S=3" && (r1.cfg["tyregion"] as? String) == "eu")
check("clés inconnues signalées", r1.message.contains("ignoré") && r1.message.contains("bidule") && r1.message.contains("zonne"))
check("nombre de réglages modifiés", r1.changed == 6)
let r2 = SettingsImport.apply(ical: nil, tuya: nil, reglages: "airzone=192.168.1.9:3000\n", to: r1.cfg)
check("deuxième import identique : rien à changer", r2.changed == 0 && r2.message.hasPrefix("Réglages déjà à jour"))
let r3 = SettingsImport.apply(ical: nil, tuya: nil, reglages: "n'importe quoi\n", to: base)
check("fichier sans ligne valide", r3.changed == 0 && r3.message.hasPrefix("Fichier de réglages lu"))
check("empreinte change avec le contenu", SettingsImport.digest(ical: nil, tuya: nil, reglages: "a=1") != SettingsImport.digest(ical: nil, tuya: nil, reglages: "a=2"))

exit(failed ? 1 : 0)
