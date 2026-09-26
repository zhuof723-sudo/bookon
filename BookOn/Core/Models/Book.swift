import Foundation

/// Legado `BookType`：type 字段是位标志
enum BookType {
    static let text = 0b1000
    static let updateError = 0b10000
    static let audio = 0b100000
    static let image = 0b1000000
    static let webFile = 0b10000000
    static let local = 0b100000000
    static let archive = 0b1000000000
    static let notShelf = 0b10000000000
    static let video = 0b100000000000
    static let localTag = "loc_book"
    static let webDavTag = "webDav::"
}

/// 与 Legado `data/entities/Book.kt` 对应
struct Book: Codable, Identifiable, Equatable, Hashable {
    var id: String { bookUrl }

    var bookUrl: String = ""
    var tocUrl: String = ""
    var origin: String = BookType.localTag
    var originName: String = ""
    var name: String = ""
    var author: String = ""
    var kind: String?
    var customTag: String?
    var coverUrl: String?
    var customCoverUrl: String?
    var intro: String?
    var customIntro: String?
    var charset: String?
    var type: Int = BookType.text
    var group: Int64 = 0
    var latestChapterTitle: String?
    var latestChapterTime: Int64 = Date.nowMillis
    var lastCheckTime: Int64 = Date.nowMillis
    var lastCheckCount: Int = 0
    var totalChapterNum: Int = 0
    var durChapterTitle: String?
    var durChapterIndex: Int = 0
    var durVolumeIndex: Int = 0
    var chapterInVolumeIndex: Int = 0
    var durChapterPos: Int = 0
    var durChapterTime: Int64 = Date.nowMillis
    var wordCount: String?
    var canUpdate: Bool = true
    var order: Int = 0
    var originOrder: Int = 0
    var variable: String?
    var syncTime: Int64 = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookUrl = c.lenientString(.bookUrl) ?? ""
        tocUrl = c.lenientString(.tocUrl) ?? ""
        origin = c.lenientString(.origin) ?? BookType.localTag
        originName = c.lenientString(.originName) ?? ""
        name = c.lenientString(.name) ?? ""
        author = c.lenientString(.author) ?? ""
        kind = c.lenientString(.kind)
        customTag = c.lenientString(.customTag)
        coverUrl = c.lenientString(.coverUrl)
        customCoverUrl = c.lenientString(.customCoverUrl)
        intro = c.lenientString(.intro)
        customIntro = c.lenientString(.customIntro)
        charset = c.lenientString(.charset)
        type = c.lenientInt(.type) ?? BookType.text
        group = Int64(c.lenientInt(.group) ?? 0)
        latestChapterTitle = c.lenientString(.latestChapterTitle)
        latestChapterTime = Int64(c.lenientInt(.latestChapterTime) ?? Int(Date.nowMillis))
        lastCheckTime = Int64(c.lenientInt(.lastCheckTime) ?? Int(Date.nowMillis))
        lastCheckCount = c.lenientInt(.lastCheckCount) ?? 0
        totalChapterNum = c.lenientInt(.totalChapterNum) ?? 0
        durChapterTitle = c.lenientString(.durChapterTitle)
        durChapterIndex = c.lenientInt(.durChapterIndex) ?? 0
        durVolumeIndex = c.lenientInt(.durVolumeIndex) ?? 0
        chapterInVolumeIndex = c.lenientInt(.chapterInVolumeIndex) ?? 0
        durChapterPos = c.lenientInt(.durChapterPos) ?? 0
        durChapterTime = Int64(c.lenientInt(.durChapterTime) ?? Int(Date.nowMillis))
        wordCount = c.lenientString(.wordCount)
        canUpdate = c.lenientBool(.canUpdate) ?? true
        order = c.lenientInt(.order) ?? 0
        originOrder = c.lenientInt(.originOrder) ?? 0
        variable = c.lenientString(.variable)
        syncTime = Int64(c.lenientInt(.syncTime) ?? 0)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(bookUrl) }
    static func == (lhs: Book, rhs: Book) -> Bool { lhs.bookUrl == rhs.bookUrl }

    var isLocal: Bool { origin == BookType.localTag || type & BookType.local != 0 }
    var displayCover: String? { customCoverUrl?.isEmpty == false ? customCoverUrl : coverUrl }
    var displayIntro: String? { customIntro?.isEmpty == false ? customIntro : intro }
    var unreadCount: Int { max(0, totalChapterNum - durChapterIndex - 1) }
}

/// 与 Legado `BookChapter.kt` 对应，主键 (url, bookUrl)
struct BookChapter: Codable, Identifiable, Equatable {
    var id: String { "\(bookUrl)#\(index)" }

    var url: String = ""
    var title: String = ""
    var isVolume: Bool = false
    var baseUrl: String = ""
    var bookUrl: String = ""
    var index: Int = 0
    var isVip: Bool = false
    var isPay: Bool = false
    var resourceUrl: String?
    var tag: String?
    var wordCount: String?
    var start: Int64?
    var end: Int64?
    var startFragmentId: String?
    var endFragmentId: String?
    var variable: String?
    var imgUrl: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = c.lenientString(.url) ?? ""
        title = c.lenientString(.title) ?? ""
        isVolume = c.lenientBool(.isVolume) ?? false
        baseUrl = c.lenientString(.baseUrl) ?? ""
        bookUrl = c.lenientString(.bookUrl) ?? ""
        index = c.lenientInt(.index) ?? 0
        isVip = c.lenientBool(.isVip) ?? false
        isPay = c.lenientBool(.isPay) ?? false
        resourceUrl = c.lenientString(.resourceUrl)
        tag = c.lenientString(.tag)
        wordCount = c.lenientString(.wordCount)
        start = c.lenientInt(.start).map(Int64.init)
        end = c.lenientInt(.end).map(Int64.init)
        startFragmentId = c.lenientString(.startFragmentId)
        endFragmentId = c.lenientString(.endFragmentId)
        variable = c.lenientString(.variable)
        imgUrl = c.lenientString(.imgUrl)
    }
}

/// 与 Legado `BookGroup.kt` 对应
struct BookGroup: Codable, Identifiable, Equatable {
    var id: Int64 { groupId }

    var groupId: Int64 = 1
    var groupName: String = ""
    var cover: String?
    var order: Int = 0
    var enableRefresh: Bool = true
    var show: Bool = true
    var bookSort: Int = -1
    var onlyUpdateRead: Bool = false

    // 内置分组 id，与 Legado 一致
    static let idRoot: Int64 = -100
    static let idAll: Int64 = -1
    static let idLocal: Int64 = -2
    static let idAudio: Int64 = -3
    static let idNetNone: Int64 = -4
    static let idLocalNone: Int64 = -5
    static let idError: Int64 = -11
}

/// 与 Legado `ReplaceRule.kt` 对应
struct ReplaceRule: Codable, Identifiable, Equatable {
    var id: Int64 = Date.nowMillis
    var name: String = ""
    var group: String?
    var pattern: String = ""
    var replacement: String = ""
    var scope: String?
    var scopeTitle: Bool = false
    var scopeContent: Bool = true
    var excludeScope: String?
    var isEnabled: Bool = true
    var isRegex: Bool = true
    var timeoutMillisecond: Int64 = 3000
    var order: Int = Int(Int32.min)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Int64(c.lenientInt(.id) ?? Int(Date.nowMillis))
        name = c.lenientString(.name) ?? ""
        group = c.lenientString(.group)
        pattern = c.lenientString(.pattern) ?? ""
        replacement = c.lenientString(.replacement) ?? ""
        scope = c.lenientString(.scope)
        scopeTitle = c.lenientBool(.scopeTitle) ?? false
        scopeContent = c.lenientBool(.scopeContent) ?? true
        excludeScope = c.lenientString(.excludeScope)
        isEnabled = c.lenientBool(.isEnabled) ?? true
        isRegex = c.lenientBool(.isRegex) ?? true
        timeoutMillisecond = Int64(c.lenientInt(.timeoutMillisecond) ?? 3000)
        order = c.lenientInt(.order) ?? Int(Int32.min)
    }
}

/// 与 Legado `Bookmark.kt` 对应
struct Bookmark: Codable, Identifiable, Equatable {
    var id: Int64 { time }
    var time: Int64 = Date.nowMillis
    var bookName: String = ""
    var bookAuthor: String = ""
    var chapterIndex: Int = 0
    var chapterPos: Int = 0
    var chapterName: String = ""
    var bookText: String = ""
    var content: String = ""
}

extension Date {
    static var nowMillis: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
