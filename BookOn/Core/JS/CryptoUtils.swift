import Foundation
import CommonCrypto

/// 摘要 / HMAC / 对称加解密（对应 Legado JsEncodeUtils + hutool SymmetricCrypto）
enum CryptoUtils {

    // MARK: - 摘要

    static func md5(_ data: Data) -> Data {
        var d = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &d) }
        return Data(d)
    }

    static func digest(_ algorithm: String, _ data: Data) -> Data? {
        switch algorithm.uppercased().replacingOccurrences(of: "-", with: "") {
        case "MD5": return md5(data)
        case "SHA1":
            var d = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &d) }; return Data(d)
        case "SHA256":
            var d = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &d) }; return Data(d)
        case "SHA384":
            var d = [UInt8](repeating: 0, count: Int(CC_SHA384_DIGEST_LENGTH))
            data.withUnsafeBytes { _ = CC_SHA384($0.baseAddress, CC_LONG(data.count), &d) }; return Data(d)
        case "SHA512":
            var d = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
            data.withUnsafeBytes { _ = CC_SHA512($0.baseAddress, CC_LONG(data.count), &d) }; return Data(d)
        default: return nil
        }
    }

    static func hmac(_ algorithm: String, key: Data, _ data: Data) -> Data? {
        let alg: CCHmacAlgorithm
        let len: Int
        switch algorithm.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "HMAC", with: "") {
        case "MD5": alg = CCHmacAlgorithm(kCCHmacAlgMD5); len = Int(CC_MD5_DIGEST_LENGTH)
        case "SHA1": alg = CCHmacAlgorithm(kCCHmacAlgSHA1); len = Int(CC_SHA1_DIGEST_LENGTH)
        case "SHA256": alg = CCHmacAlgorithm(kCCHmacAlgSHA256); len = Int(CC_SHA256_DIGEST_LENGTH)
        case "SHA384": alg = CCHmacAlgorithm(kCCHmacAlgSHA384); len = Int(CC_SHA384_DIGEST_LENGTH)
        case "SHA512": alg = CCHmacAlgorithm(kCCHmacAlgSHA512); len = Int(CC_SHA512_DIGEST_LENGTH)
        default: return nil
        }
        var out = [UInt8](repeating: 0, count: len)
        key.withUnsafeBytes { k in
            data.withUnsafeBytes { d in
                CCHmac(alg, k.baseAddress, key.count, d.baseAddress, data.count, &out)
            }
        }
        return Data(out)
    }

    // MARK: - Hex / Base64

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    static func fromHex(_ s: String) -> Data? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count % 2 == 0 else { return nil }
        var d = Data(capacity: t.count / 2)
        var idx = t.startIndex
        while idx < t.endIndex {
            let next = t.index(idx, offsetBy: 2)
            guard let b = UInt8(t[idx..<next], radix: 16) else { return nil }
            d.append(b); idx = next
        }
        return d
    }

    static func isHex(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.count % 2 == 0 && t.allSatisfy { $0.isHexDigit }
    }

    static func base64Decode(_ s: String) -> Data? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    // MARK: - 对称加解密（AES / DES / 3DES）

    struct Transformation {
        let algorithm: CCAlgorithm
        let blockSize: Int
        let keySize: Int?
        let mode: String      // ECB / CBC
        let padding: String   // PKCS5Padding / NoPadding / ZeroPadding
        let name: String

        /// 解析 "AES/CBC/PKCS5Padding"、"DESede/ECB/NoPadding"、"AES" 等
        init?(_ transformation: String) {
            let parts = transformation.split(separator: "/").map(String.init)
            guard let alg = parts.first?.uppercased() else { return nil }
            name = alg
            switch alg {
            case "AES": algorithm = CCAlgorithm(kCCAlgorithmAES); blockSize = kCCBlockSizeAES128; keySize = nil
            case "DES": algorithm = CCAlgorithm(kCCAlgorithmDES); blockSize = kCCBlockSizeDES; keySize = kCCKeySizeDES
            case "DESEDE", "3DES", "TRIPLEDES": algorithm = CCAlgorithm(kCCAlgorithm3DES); blockSize = kCCBlockSize3DES; keySize = kCCKeySize3DES
            default: return nil
            }
            mode = parts.count > 1 ? parts[1].uppercased() : "ECB"
            padding = parts.count > 2 ? parts[2] : "PKCS5Padding"
        }
    }

    static func symmetric(_ transformation: String, key: Data, iv: Data?, encrypt: Bool, data: Data) -> Data? {
        guard let t = Transformation(transformation) else { return nil }
        // Key 规整
        var k = key
        if t.name == "AES" {
            if ![16, 24, 32].contains(k.count) {
                // Java 会直接报错；这里按常见做法补/截到 16
                if k.count < 16 { k.append(Data(repeating: 0, count: 16 - k.count)) } else if k.count < 24 { k = k.prefix(16) } else if k.count < 32 { k = k.prefix(24) } else { k = k.prefix(32) }
            }
        } else if let ks = t.keySize {
            if k.count < ks { k.append(Data(repeating: 0, count: ks - k.count)) } else { k = k.prefix(ks) }
        }
        var options: CCOptions = 0
        if t.mode == "ECB" { options |= CCOptions(kCCOptionECBMode) }
        let pad = t.padding.uppercased()
        let usePKCS = pad.contains("PKCS")
        if usePKCS { options |= CCOptions(kCCOptionPKCS7Padding) }

        var input = data
        if encrypt && pad.contains("ZERO") {
            let r = input.count % t.blockSize
            if r != 0 { input.append(Data(repeating: 0, count: t.blockSize - r)) }
        }
        var ivData = iv ?? Data()
        if t.mode != "ECB" {
            if ivData.count < t.blockSize { ivData.append(Data(repeating: 0, count: t.blockSize - ivData.count)) }
            ivData = ivData.prefix(t.blockSize)
        }
        var out = Data(count: input.count + t.blockSize)
        var moved = 0
        let outCount = out.count
        let status = out.withUnsafeMutableBytes { o in
            input.withUnsafeBytes { i in
                k.withUnsafeBytes { kk in
                    ivData.withUnsafeBytes { v in
                        CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), t.algorithm, options,
                                kk.baseAddress, k.count, t.mode == "ECB" ? nil : v.baseAddress,
                                i.baseAddress, input.count, o.baseAddress, outCount, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.count = moved
        if !encrypt && pad.contains("ZERO") {
            while out.last == 0 { out.removeLast() }
        }
        return out
    }
}
