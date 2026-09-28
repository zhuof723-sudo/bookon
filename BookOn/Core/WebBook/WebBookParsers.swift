import Foundation

/// 详情页解析（对应 Legado `BookInfo.analyzeBookInfo`）
enum BookInfoParser {
    static func parse(source: BookSource, book: inout Book, baseUrl: String, redirectUrl: String, body: String,
                      js: JSEvaluator = JSCoreEvaluator.shared) throws {
        guard let rule = source.ruleBookInfo else { return }
        let analyzer = AnalyzeRule(ruleData: RuleData(variable: book.variable), source: source, js: js)
        analyzer.book = book
        analyzer.setContent(body, baseUrl: baseUrl)
        analyzer.setRedirectUrl(redirectUrl)

        // init 规则：先定位详情内容块
        if let ini = rule.`init`, !ini.trimmingCharacters(in: .whitespaces).isEmpty {
            if let el = try analyzer.getElement(ini) { analyzer.setContent(el, baseUrl: baseUrl) }
        }

        let name = try analyzer.getString(rule.name).trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { book.name = name }
        let author = try analyzer.getString(rule.author).trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty { book.author = author }
        if let kinds = try analyzer.getStringList(rule.kind), !kinds.isEmpty {
            book.kind = kinds.joined(separator: ",")
        }
        let words = try analyzer.getString(rule.wordCount)
        if !words.isEmpty { book.wordCount = words }
        let last = try analyzer.getString(rule.lastChapter)
        if !last.isEmpty { book.latestChapterTitle = last }
        let intro = try analyzer.getString(rule.intro)
        let it = intro.drop { $0 == " " || $0 == "\n" }
        if it.hasPrefix("<usehtml>") || it.hasPrefix("<md>") || it.hasPrefix("<useweb>") {
            book.intro = String(it)
        } else {
            let f = HTMLFormatter.format(intro)
            if !f.isEmpty { book.intro = f }
        }
        let cover = try analyzer.getString(rule.coverUrl)
        if !cover.isEmpty { book.coverUrl = NetworkUtils.getAbsoluteURL(redirectUrl, cover) }

        var tocUrl = try analyzer.getString(rule.tocUrl, isUrl: true)
        if tocUrl.isEmpty { tocUrl = baseUrl }
        book.tocUrl = tocUrl
        book.variable = analyzer.ruleData?.variable
    }
}

/// 目录解析（对应 Legado `BookChapterList.analyzeChapterList`）
enum BookChapterListParser {
    static func parse(source: BookSource, book: Book, baseUrl: String, redirectUrl: String, body: String,
                      js: JSEvaluator = JSCoreEvaluator.shared) async throws -> [BookChapter] {
        guard let tocRule = source.ruleToc else { return [] }
        var reverse = false
        var listRule = tocRule.chapterList ?? ""
        if listRule.hasPrefix("-") { reverse = true; listRule.removeFirst() }
        if listRule.hasPrefix("+") { listRule.removeFirst() }

        var chapters: [BookChapter] = []
        var visited = Set([redirectUrl])

        var (list, nextUrls) = try parsePage(source: source, book: book, baseUrl: baseUrl, redirectUrl: redirectUrl,
                                             body: body, tocRule: tocRule, listRule: listRule, js: js)
        chapters += list

        // 翻页目录（顺序抓取，保证章节顺序）
        var pending = nextUrls.filter { !visited.contains($0) }
        while let next = pending.first {
            pending.removeFirst()
            guard visited.insert(next).inserted else { continue }
            let a = try AnalyzeUrl(next, source: source, js: js)
            let res = try await HTTPClient.shared.strResponse(a)
            let (l2, n2) = try parsePage(source: source, book: book, baseUrl: next, redirectUrl: res.url,
                                        body: res.body, tocRule: tocRule, listRule: listRule, js: js)
            chapters += l2
            pending += n2.filter { !visited.contains($0) }
        }

        if chapters.isEmpty { throw JSError(message: "目录为空") }
        // 去重（按 url+title）
        var seen = Set<String>()
        chapters = chapters.filter { seen.insert("\($0.url)#\($0.title)").inserted }
        if reverse { chapters.reverse() }
        for i in chapters.indices { chapters[i].index = i; chapters[i].bookUrl = book.bookUrl }

        // formatJs
        if let fjs = tocRule.formatJs, !fjs.trimmingCharacters(in: .whitespaces).isEmpty {
            for i in chapters.indices {
                if let t = try? js.eval(fjs, bindings: ["index": i + 1, "title": chapters[i].title, "chapter": chapters[i]]),
                   let s = t as? String, !s.isEmpty { chapters[i].title = s }
            }
        }
        return chapters
    }

    private static func parsePage(source: BookSource, book: Book, baseUrl: String, redirectUrl: String, body: String,
                                  tocRule: TocRule, listRule: String, js: JSEvaluator) throws -> ([BookChapter], [String]) {
        let analyzer = AnalyzeRule(ruleData: RuleData(variable: book.variable), source: source, js: js)
        analyzer.book = book
        analyzer.setContent(body, baseUrl: baseUrl)
        analyzer.setRedirectUrl(redirectUrl)

        var nextUrls: [String] = []
        if let nextTocRule = tocRule.nextTocUrl, !nextTocRule.isEmpty {
            for u in (try analyzer.getStringList(nextTocRule, isUrl: true)) ?? [] where u != redirectUrl {
                nextUrls.append(u)
            }
        }

        let elements = try analyzer.getElements(listRule)
        guard !elements.isEmpty else { return ([], nextUrls) }

        let nameRule = analyzer.splitSourceRule(tocRule.chapterName)
        let urlRule = analyzer.splitSourceRule(tocRule.chapterUrl)
        let vipRule = analyzer.splitSourceRule(tocRule.isVip)
        let payRule = analyzer.splitSourceRule(tocRule.isPay)
        let upTimeRule = analyzer.splitSourceRule(tocRule.updateTime)
        let volumeRule = analyzer.splitSourceRule(tocRule.isVolume)

        var list: [BookChapter] = []
        for (index, item) in elements.enumerated() {
            analyzer.setContent(item)
            var c = BookChapter()
            c.bookUrl = book.bookUrl
            c.baseUrl = redirectUrl
            analyzer.chapterData = RuleData()
            analyzer.chapter = c
            c.title = try analyzer.getString(nameRule).trimmingCharacters(in: .whitespacesAndNewlines)
            c.url = try analyzer.getString(urlRule, isUrl: true)
            let info = try analyzer.getString(upTimeRule)
            if isTrue(try analyzer.getString(volumeRule)) { c.isVolume = true; c.tag = info }
            else { c.tag = info }
            if c.url.isEmpty { c.url = c.isVolume ? "\(c.title)\(index)" : baseUrl }
            if !c.title.isEmpty {
                if isTrue(try analyzer.getString(vipRule)) { c.isVip = true }
                if isTrue(try analyzer.getString(payRule)) { c.isPay = true }
                c.variable = analyzer.chapterData?.variable
                list.append(c)
            }
        }
        return (list, nextUrls)
    }

    private static func isTrue(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        return !(t.isEmpty || t == "false" || t == "0" || t == "null" || t == "no")
    }
}

/// 正文解析（对应 Legado `BookContent.analyzeContent`）
enum BookContentParser {
    static func parse(source: BookSource, book: Book, chapter: BookChapter, baseUrl: String, redirectUrl: String,
                      body: String, nextChapterUrl: String?, js: JSEvaluator = JSCoreEvaluator.shared) async throws -> String {
        guard let rule = source.ruleContent else { return body }
        var contentList: [String] = []
        var visited = Set([redirectUrl])

        var (content, nextUrls) = try parsePage(source: source, book: book, chapter: chapter, baseUrl: baseUrl,
                                               redirectUrl: redirectUrl, body: body, rule: rule,
                                               nextChapterUrl: nextChapterUrl, js: js)
        contentList.append(content)

        var pending = nextUrls.filter { !visited.contains($0) }
        while let next = pending.first {
            pending.removeFirst()
            guard visited.insert(next).inserted else { continue }
            // 到达下一章地址则停止
            if let ncu = nextChapterUrl, !ncu.isEmpty,
               NetworkUtils.getAbsoluteURL(redirectUrl, next) == NetworkUtils.getAbsoluteURL(redirectUrl, ncu) { break }
            let a = try AnalyzeUrl(next, source: source, js: js)
            let res = try await HTTPClient.shared.strResponse(a)
            let (c2, n2) = try parsePage(source: source, book: book, chapter: chapter, baseUrl: next,
                                        redirectUrl: res.url, body: res.body, rule: rule,
                                        nextChapterUrl: nextChapterUrl, js: js)
            contentList.append(c2)
            pending = n2.filter { !visited.contains($0) }  // 正文翻页链式，只跟第一个
        }

        var contentStr = contentList.joined(separator: "\n")
        // 净化替换
        if let rr = rule.replaceRegex, !rr.isEmpty {
            let analyzer = AnalyzeRule(source: source, js: js)
            analyzer.book = book; analyzer.chapter = chapter
            contentStr = contentStr.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            contentStr = try analyzer.getString(rr, contentStr)
        }
        if contentStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chapter.isVolume {
            throw JSError(message: "正文内容为空")
        }
        return contentStr
    }

    private static func parsePage(source: BookSource, book: Book, chapter: BookChapter, baseUrl: String, redirectUrl: String,
                                  body: String, rule: ContentRule, nextChapterUrl: String?, js: JSEvaluator) throws -> (String, [String]) {
        let analyzer = AnalyzeRule(ruleData: RuleData(variable: book.variable), source: source, js: js)
        analyzer.book = book
        analyzer.chapter = chapter
        analyzer.chapterData = RuleData(variable: chapter.variable)
        analyzer.extraBindings["nextChapterUrl"] = nextChapterUrl
        analyzer.setContent(body, baseUrl: baseUrl)
        let rUrl = analyzer.setRedirectUrl(redirectUrl)

        var content: String
        if let cr = rule.content, !cr.trimmingCharacters(in: .whitespaces).isEmpty {
            content = try analyzer.getString(cr, unescape: false)
            // 规则取不到时退回整页文本（部分书源正文即整页）
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content = (try? analyzer.getString("body@html", unescape: false)) ?? body
            }
        } else {
            // 空 content 规则：取整页 body（Legado element.data 行为的近似）
            content = (try? analyzer.getString("body@html", unescape: false)) ?? body
        }
        // 文本类才做 HTML 格式化（音视频取到的是链接）
        if source.sourceType == .text || source.sourceType == .file {
            content = HTMLFormatter.formatKeepImg(content, redirectUrl: rUrl?.absoluteString)
            if content.contains("&") { content = AnalyzeRule.unescapeHtml(content) }
        }

        var nextUrls: [String] = []
        if let nr = rule.nextContentUrl, !nr.isEmpty {
            nextUrls = (try analyzer.getStringList(nr, isUrl: true)) ?? []
        }
        return (content, nextUrls)
    }
}
