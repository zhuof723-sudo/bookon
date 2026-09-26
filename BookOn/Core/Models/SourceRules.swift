import Foundation

// 与 Legado `data/entities/rule/*` 一一对应，字段名保持完全一致以兼容 JSON。

struct SearchRule: Codable, Equatable {
    var checkKeyWord: String?
    var bookList: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var bookUrl: String?
    var coverUrl: String?
    var wordCount: String?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkKeyWord = c.lenientString(.checkKeyWord)
        bookList = c.lenientString(.bookList)
        name = c.lenientString(.name)
        author = c.lenientString(.author)
        intro = c.lenientString(.intro)
        kind = c.lenientString(.kind)
        lastChapter = c.lenientString(.lastChapter)
        updateTime = c.lenientString(.updateTime)
        bookUrl = c.lenientString(.bookUrl)
        coverUrl = c.lenientString(.coverUrl)
        wordCount = c.lenientString(.wordCount)
    }
}

struct ExploreRule: Codable, Equatable {
    var bookList: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var bookUrl: String?
    var coverUrl: String?
    var wordCount: String?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookList = c.lenientString(.bookList)
        name = c.lenientString(.name)
        author = c.lenientString(.author)
        intro = c.lenientString(.intro)
        kind = c.lenientString(.kind)
        lastChapter = c.lenientString(.lastChapter)
        updateTime = c.lenientString(.updateTime)
        bookUrl = c.lenientString(.bookUrl)
        coverUrl = c.lenientString(.coverUrl)
        wordCount = c.lenientString(.wordCount)
    }
}

struct BookInfoRule: Codable, Equatable {
    var `init`: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var coverUrl: String?
    var tocUrl: String?
    var wordCount: String?
    var canReName: String?
    var downloadUrls: String?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        `init` = c.lenientString(.`init`)
        name = c.lenientString(.name)
        author = c.lenientString(.author)
        intro = c.lenientString(.intro)
        kind = c.lenientString(.kind)
        lastChapter = c.lenientString(.lastChapter)
        updateTime = c.lenientString(.updateTime)
        coverUrl = c.lenientString(.coverUrl)
        tocUrl = c.lenientString(.tocUrl)
        wordCount = c.lenientString(.wordCount)
        canReName = c.lenientString(.canReName)
        downloadUrls = c.lenientString(.downloadUrls)
    }
}

struct TocRule: Codable, Equatable {
    var preUpdateJs: String?
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var formatJs: String?
    var isVolume: String?
    var isVip: String?
    var isPay: String?
    var updateTime: String?
    var nextTocUrl: String?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preUpdateJs = c.lenientString(.preUpdateJs)
        chapterList = c.lenientString(.chapterList)
        chapterName = c.lenientString(.chapterName)
        chapterUrl = c.lenientString(.chapterUrl)
        formatJs = c.lenientString(.formatJs)
        isVolume = c.lenientString(.isVolume)
        isVip = c.lenientString(.isVip)
        isPay = c.lenientString(.isPay)
        updateTime = c.lenientString(.updateTime)
        nextTocUrl = c.lenientString(.nextTocUrl)
    }
}

struct ContentRule: Codable, Equatable {
    var content: String?
    var subContent: String?
    var title: String?
    var nextContentUrl: String?
    var webJs: String?
    var sourceRegex: String?
    var replaceRegex: String?
    var imageStyle: String?
    var imageDecode: String?
    var payAction: String?
    var callBackJs: String?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = c.lenientString(.content)
        subContent = c.lenientString(.subContent)
        title = c.lenientString(.title)
        nextContentUrl = c.lenientString(.nextContentUrl)
        webJs = c.lenientString(.webJs)
        sourceRegex = c.lenientString(.sourceRegex)
        replaceRegex = c.lenientString(.replaceRegex)
        imageStyle = c.lenientString(.imageStyle)
        imageDecode = c.lenientString(.imageDecode)
        payAction = c.lenientString(.payAction)
        callBackJs = c.lenientString(.callBackJs)
    }
}

struct ReviewRule: Codable, Equatable {
    var reviewUrl: String?
    var avatarRule: String?
    var contentRule: String?
    var postTimeRule: String?
    var reviewQuoteUrl: String?
    var voteUpUrl: String?
    var voteDownUrl: String?
    var postReviewUrl: String?
    var postQuoteUrl: String?
    var deleteUrl: String?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviewUrl = c.lenientString(.reviewUrl)
        avatarRule = c.lenientString(.avatarRule)
        contentRule = c.lenientString(.contentRule)
        postTimeRule = c.lenientString(.postTimeRule)
        reviewQuoteUrl = c.lenientString(.reviewQuoteUrl)
        voteUpUrl = c.lenientString(.voteUpUrl)
        voteDownUrl = c.lenientString(.voteDownUrl)
        postReviewUrl = c.lenientString(.postReviewUrl)
        postQuoteUrl = c.lenientString(.postQuoteUrl)
        deleteUrl = c.lenientString(.deleteUrl)
    }
}
