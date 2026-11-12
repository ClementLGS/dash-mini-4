import Foundation

// Test de la vérification de signature (même code Sig.swift que l'appli) sur les vrais fichiers du dépôt.
// Usage : sigtest version.json version.sig [index.html]
let args = CommandLine.arguments
guard args.count >= 3,
      let vj = try? String(contentsOfFile: args[1], encoding: .utf8),
      let sg = try? String(contentsOfFile: args[2], encoding: .utf8) else {
    print("usage : sigtest version.json version.sig [index.html]")
    exit(2)
}
var failed = false
func check(_ name: String, _ ok: Bool) { print((ok ? "OK      " : "ECHEC   ") + name); if !ok { failed = true } }

check("signature de version.json valide", Sig.verify(vj, signatureB64: sg))
check("version.json modifié refusé", !Sig.verify(vj + " ", signatureB64: sg))
check("signature vide refusée", !Sig.verify(vj, signatureB64: ""))
check("signature tronquée refusée", !Sig.verify(vj, signatureB64: String(sg.prefix(200))))
check("sha256 de « abc »", Sig.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

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

if args.count >= 4, let html = try? Data(contentsOf: URL(fileURLWithPath: args[3])),
   let o = try? JSONSerialization.jsonObject(with: Data(vj.utf8)) as? [String: Any], let want = o["uisha"] as? String {
    // Pas bloquant : une autre discussion peut pousser index.html et version.json à quelques secondes d'écart.
    let same = Sig.sha256Hex(html).lowercased() == want.lowercased()
    print(same ? "OK      empreinte de index.html = uisha signé" : "AVERTISSEMENT empreinte de index.html différente de uisha (version.json pas encore à jour ?)")
}
exit(failed ? 1 : 0)
