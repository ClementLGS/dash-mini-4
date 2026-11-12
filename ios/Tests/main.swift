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

if args.count >= 4, let html = try? Data(contentsOf: URL(fileURLWithPath: args[3])),
   let o = try? JSONSerialization.jsonObject(with: Data(vj.utf8)) as? [String: Any], let want = o["uisha"] as? String {
    // Pas bloquant : une autre discussion peut pousser index.html et version.json à quelques secondes d'écart.
    let same = Sig.sha256Hex(html).lowercased() == want.lowercased()
    print(same ? "OK      empreinte de index.html = uisha signé" : "AVERTISSEMENT empreinte de index.html différente de uisha (version.json pas encore à jour ?)")
}
exit(failed ? 1 : 0)
