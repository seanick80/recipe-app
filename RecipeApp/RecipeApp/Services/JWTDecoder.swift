import Foundation

/// Decodes the *claims* of a JWT locally, without verifying the signature.
///
/// The server is the only party that can verify the HS256 signature (it holds
/// the secret). This decoder exists purely so the app can read the cached
/// identity (`sub`/`name`/`role`) at launch and render an optimistic,
/// signed-in UI immediately — the token is still validated against the server
/// in the background. Never trust these claims for authorization decisions.
enum JWTDecoder {
    struct Claims: Sendable {
        let email: String
        let name: String
        let role: String
        /// Expiry as seconds since 1970, if present.
        let exp: TimeInterval?

        /// True when `exp` is present and already in the past.
        /// Callers still revalidate with the server; this is only a hint.
        func isExpired(now: Date = Date()) -> Bool {
            guard let exp else { return false }
            return now.timeIntervalSince1970 >= exp
        }
    }

    /// Decode the claims payload of a JWT (`header.payload.signature`).
    /// Returns nil if the token is malformed or missing the required claims.
    static func decode(_ token: String) -> Claims? {
        let segments = token.split(separator: ".")
        guard segments.count == 3,
            let payloadData = base64URLDecode(String(segments[1])),
            let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            return nil
        }

        // Server issues `sub` = email; `name`/`role` are best-effort.
        guard let email = json["sub"] as? String else { return nil }
        let name = json["name"] as? String ?? ""
        let role = json["role"] as? String ?? "user"
        let exp = (json["exp"] as? NSNumber)?.doubleValue

        return Claims(email: email, name: name, role: role, exp: exp)
    }

    /// Base64URL decode (RFC 7515): URL-safe alphabet, padding stripped.
    private static func base64URLDecode(_ input: String) -> Data? {
        var base64 =
            input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingNeeded = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: paddingNeeded)
        return Data(base64Encoded: base64)
    }
}
