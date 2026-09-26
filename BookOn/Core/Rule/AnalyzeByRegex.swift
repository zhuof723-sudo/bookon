import Foundation

/// 对应 Legado `AnalyzeByRegex`：多级正则，最后一级取分组
enum AnalyzeByRegex {

    static func getElement(_ res: String, _ regs: [String], _ index: Int = 0) -> [String]? {
        guard index < regs.count, let re = try? NSRegularExpression(pattern: regs[index], options: []) else { return nil }
        let ns = res as NSString
        let matches = re.matches(in: res, range: NSRange(location: 0, length: ns.length))
        guard let first = matches.first else { return nil }
        if index + 1 == regs.count {
            return (0..<first.numberOfRanges).map { g in
                let r = first.range(at: g)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
        let joined = matches.map { ns.substring(with: $0.range) }.joined()
        return getElement(joined, regs, index + 1)
    }

    static func getElements(_ res: String, _ regs: [String], _ index: Int = 0) -> [[String]] {
        guard index < regs.count, let re = try? NSRegularExpression(pattern: regs[index], options: []) else { return [] }
        let ns = res as NSString
        let matches = re.matches(in: res, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }
        if index + 1 == regs.count {
            return matches.map { m in
                (0..<m.numberOfRanges).map { g in
                    let r = m.range(at: g)
                    return r.location == NSNotFound ? "" : ns.substring(with: r)
                }
            }
        }
        let joined = matches.map { ns.substring(with: $0.range) }.joined()
        return getElements(joined, regs, index + 1)
    }
}
