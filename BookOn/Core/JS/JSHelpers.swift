import Foundation
import UIKit

/// 对应 Legado `HtmlFormatter.format`：HTML → 纯文本段落（每段以 　　 缩进）
enum HTMLFormatter {
    private static let nbsp = try! NSRegularExpression(pattern: "(&nbsp;)+")
    private static let esp = try! NSRegularExpression(pattern: "(&ensp;|&emsp;)")
    private static let noPrint = try! NSRegularExpression(pattern: "(&thinsp;|&zwnj;|&zwj;|\u{2009}|\u{200C}|\u{200D})")
    private static let wrap = try! NSRegularExpression(pattern: "</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>", options: .caseInsensitive)
    private static let comment = try! NSRegularExpression(pattern: "<!--[^>]*-->")
    private static let otherHtml = try! NSRegularExpression(pattern: "</?[a-zA-Z]+(?=[ >])[^<>]*>")
    private static let notImgHtml = try! NSRegularExpression(pattern: "</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>")
    private static let indent1 = try! NSRegularExpression(pattern: "\\s*\\n+\\s*")
    private static let indent2 = try! NSRegularExpression(pattern: "^[\\n\\s]+")
    private static let last = try! NSRegularExpression(pattern: "[\\n\\s]+$")
    /// 与 Legado `HtmlFormatter.formatImagePattern` 完全一致：
    /// 分支1匹配 src 后面带 `,{...}` 点击/样式选项（如段评气泡 `data:...,{"click":"..."}"）的情况，
    /// 要求捕获到平衡的花括号，不能用简单的“遇到引号就停”，否则这类图片的 JSON 选项会被截断丢失。
    /// 分支2匹配懒加载的 data-src/data-original/data-srcset。
    /// 分支3/4是普通 src（双引号/单引号）兜底。
    private static let imgTag = try! NSRegularExpression(
        pattern: "<img[^>]*\\ssrc\\s*=\\s*['\"]([^'\"{>]*\\{(?:[^{}]|\\{[^}>]+\\})+\\})['\"][^>]*>"
               + "|<img[^>]*\\sdata-(?:src|original|srcset)\\s*=\\s*['\"]([^'\">]+)['\"][^>]*>"
               + "|<img[^>]*\\ssrc\\s*=\\s*\"([^\">]+)\"[^>]*>"
               + "|<img[^>]*\\s(?:data-[^=>]*|src)=\\s*['\"]([^'\">]*)['\"][^>]*>",
        options: .caseInsensitive)

    private static func r(_ s: String, _ re: NSRegularExpression, _ t: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: t)
    }

    static func format(_ html: String?, keepImg: Bool = false) -> String {
        guard var s = html else { return "" }
        s = r(s, nbsp, " "); s = r(s, esp, " "); s = r(s, noPrint, "")
        s = r(s, wrap, "\n"); s = r(s, comment, "")
        s = r(s, keepImg ? notImgHtml : otherHtml, "")
        s = r(s, indent1, "\n　　"); s = r(s, indent2, "　　"); s = r(s, last, "")
        return s
    }

    /// 保留 <img>，并把 src 转成绝对地址。
    /// 对应 Legado `HtmlFormatter.formatKeepImg`：分支1（带 `,{...}` 选项的 src）要把选项完整保留，
    /// 只对选项前的地址部分做绝对化；分支2/3/4是普通 src，直接绝对化。
    static func formatKeepImg(_ html: String?, redirectUrl: String?) -> String {
        let s = format(html, keepImg: true)
        let ns = s as NSString
        var out = ""
        var pos = 0
        for m in imgTag.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: pos, length: m.range.location - pos))
            var raw: String
            var param = ""
            if m.range(at: 1).location != NSNotFound {
                raw = ns.substring(with: m.range(at: 1))
                // raw 形如 "地址,{...}"：地址与选项以 AnalyzeUrl 的 ",（后跟 {）" 规则切开
                if let pr = AnalyzeUrl.paramRegex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                   let rr = Range(pr.range, in: raw) {
                    param = "," + String(raw[rr.upperBound...])
                    raw = String(raw[..<rr.lowerBound])
                }
            } else if m.range(at: 2).location != NSNotFound {
                raw = ns.substring(with: m.range(at: 2))
            } else if m.range(at: 3).location != NSNotFound {
                raw = ns.substring(with: m.range(at: 3))
            } else {
                raw = ns.substring(with: m.range(at: 4))
            }
            out += "<img src=\"\(NetworkUtils.getAbsoluteURL(redirectUrl, raw))\(param)\">"
            pos = m.range.location + m.range.length
        }
        out += ns.substring(from: pos)
        return out
    }
}

/// 中文数字 ↔ 阿拉伯数字（对应 StringUtils.chineseNumToInt / stringToInt）
enum ChineseNumber {
    private static let map: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
        "壹": 1, "贰": 2, "叁": 3, "肆": 4, "伍": 5, "陆": 6, "柒": 7, "捌": 8, "玖": 9,
        "十": 10, "拾": 10, "百": 100, "佰": 100, "千": 1000, "仟": 1000, "万": 10000, "萬": 10000, "亿": 100_000_000, "億": 100_000_000,
    ]

    static func toInt(_ str: String) -> Int? {
        let s = fullToHalf(str).replacingOccurrences(of: " ", with: "")
        if let n = Int(s) { return n }
        let chars = Array(s)
        guard !chars.isEmpty, chars.allSatisfy({ map[$0] != nil }) else { return nil }
        // 纯数字字形 "一零二五"
        if chars.count > 1, chars.allSatisfy({ (map[$0] ?? 10) < 10 }) {
            return Int(chars.map { String(map[$0]!) }.joined())
        }
        var result = 0, tmp = 0, billion = 0
        for c in chars {
            let n = map[c]!
            switch n {
            case 100_000_000: result += tmp; result *= n; billion = billion * 100_000_000 + result; result = 0; tmp = 0
            case 10000: result += tmp; result *= n; tmp = 0
            case 10, 100, 1000: result += (tmp == 0 ? 1 : tmp) * n; tmp = 0
            default: tmp = tmp * 10 + n
            }
        }
        return result + tmp + billion
    }

    static func fullToHalf(_ s: String) -> String {
        String(s.unicodeScalars.map { u -> Character in
            if u.value >= 0xFF10 && u.value <= 0xFF19 { return Character(UnicodeScalar(u.value - 0xFF10 + 0x30)!) }
            return Character(u)
        })
    }

    private static let titleNum = try! NSRegularExpression(pattern: "(第)(.+?)(章)")

    /// "第一百二十章 xx" → "第120章 xx"
    static func convertChapterTitle(_ s: String) -> String {
        let ns = s as NSString
        guard let m = titleNum.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return s }
        let mid = ns.substring(with: m.range(at: 2))
        guard let n = toInt(mid) else { return s }
        return ns.replacingCharacters(in: m.range, with: "第\(n)章")
    }
}

/// 繁简转换（系统 CFStringTransform 近似实现，不如 OpenCC 精确但无需词库）
enum ChineseConverter {
    static func toSimplified(_ s: String) -> String {
        let m = NSMutableString(string: s)
        CFStringTransform(m, nil, "Traditional-Simplified" as CFString, false)
        return m as String
    }
    static func toTraditional(_ s: String) -> String {
        let m = NSMutableString(string: s)
        CFStringTransform(m, nil, "Simplified-Traditional" as CFString, false)
        return m as String
    }
}

/// 稳定的设备 ID（对应 androidId），首次生成后存 UserDefaults
enum DeviceID {
    static let value: String = {
        let key = "bookon.deviceId"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = (UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)
            .replacingOccurrences(of: "-", with: "").lowercased().prefix(16)
        UserDefaults.standard.set(String(v), forKey: key)
        return String(v)
    }()
}

/// 轻量 toast（主线程弹出短提示）
enum Toast {
    static func show(_ msg: String) {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                  let window = scene.windows.first(where: \.isKeyWindow) else { return }
            let label = UILabel()
            label.text = msg
            label.numberOfLines = 3
            label.textColor = .white
            label.font = .systemFont(ofSize: 14)
            label.textAlignment = .center
            label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
            label.layer.cornerRadius = 10
            label.clipsToBounds = true
            let maxW = window.bounds.width - 60
            let size = label.sizeThatFits(CGSize(width: maxW - 24, height: 200))
            label.frame = CGRect(x: (window.bounds.width - size.width - 24) / 2,
                                 y: window.bounds.height - 140, width: size.width + 24, height: size.height + 16)
            label.alpha = 0
            window.addSubview(label)
            UIView.animate(withDuration: 0.2) { label.alpha = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                UIView.animate(withDuration: 0.3, animations: { label.alpha = 0 }) { _ in label.removeFromSuperview() }
            }
        }
    }
}
