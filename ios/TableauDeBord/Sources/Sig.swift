import Foundation
import CryptoKit
import Security

/// Vérification des mises à jour : version.json est signé (RSA-3072, PKCS#1 v1.5, SHA-256) avec la clé privée de Clément.
/// Seule la clé publique est ici ; c'est la même que dans l'appli Android (classe Sig).
enum Sig {
    /// Clé publique RSA (PKCS#1, DER, base64).
    static let publicKeyB64 = "MIIBigKCAYEAt0yfDLyG0iDMTR/eFwh9Ya4sC/c3N45k2GA5w1H2emtR3xMwOXZ2AzexeoacO+a4hd3/UDEjZ4zBAbGR84Ym4PHc5quWJkvGEiJS3LvRFdj3BOz80itec2lIWyCiAyClPYfXiXkqaLmDyHnvcwjCFNYQKnjxa8RfH1SVDI6y/dv4J427brw0cl9cVCnN55D7PD9XYe9N8z5P0sVkIo4Lh7xegfs+ZhQXhPkhbGsInouqOfcFU1ITiLVAOsHLx26aP3/gkOQ1DYDV9rFeWWdkGDvOnCwVTds3DXb/vAhyltb/3Y2PsEq0M/w3sZbtgPcTUDrhtWujiLF1xFER4p7BJwg1AldERs2Mkwzv31xjMcI/VgjKpys5S0rq1aSqZo697559M37nQy4pbYdyWAStPogedOj+FO8C44EBmrmsl+kCXPDuSDN4Ihx+psEBdO9huqWzB3FVlwePon/fefO1zPerUbSW7NLlFiR3nbTwKZPBRU/q4KRpPTX07OuGLRIfAgMBAAE="

    static func sha256Hex(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// true seulement si `signatureB64` est une signature valide de `message` (octets UTF-8) par la clé de Clément.
    static func verify(_ message: String, signatureB64: String) -> Bool {
        let clean = signatureB64.filter { !$0.isWhitespace }
        guard let sig = Data(base64Encoded: clean), sig.count == 384,
              let keyData = Data(base64Encoded: publicKeyB64) else { return false }
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 3072
        ]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, &err) else { return false }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                     Data(message.utf8) as CFData, sig as CFData, &err)
    }
}
