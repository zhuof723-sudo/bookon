import Foundation

/// 书源类型，对应 Legado `BookSourceType`
enum BookSourceType: Int, Codable {
    case text = 0
    case audio = 1
    case image = 2
    case file = 3
    case video = 4

    var label: String {
        switch self {
        case .text: return "文本"
        case .audio: return "音频"
        case .image: return "图片"
        case .file: return "文件"
        case .video: return "视频"
        }
    }
}

/// 与 Legado `data/entities/BookSource.kt` 字段一一对应。
/// 主键为 bookSourceUrl。
struct BookSource: Codable, Identifiable, Equatable, Hashable {
    var id: String { bookSourceUrl }

    var bookSourceUrl: String = ""
    var bookSourceName: String = ""
    var bookSourceGroup: String?
    var bookSourceType: Int = 0
    var bookUrlPattern: String?
    var customOrder: Int = 0
    var enabled: Bool = true
    var enabledExplore: Bool = true
    var jsLib: String?
    var enabledCookieJar: Bool? = true
    var concurrentRate: String?
    var header: String?
    var loginUrl: String?
    var loginUi: String?
    var loginCheckJs: String?
    var coverDecodeJs: String?
    var bookSourceComment: String?
    var variableComment: String?
    var lastUpdateTime: Int64 = 0
    var respondTime: Int64 = 180_000
    var weight: Int = 0
    var exploreUrl: String?
    var exploreScreen: String?
    var ruleExplore: ExploreRule?
    var searchUrl: String?
    var ruleSearch: SearchRule?
    var ruleBookInfo: BookInfoRule?
    var ruleToc: TocRule?
    var ruleContent: ContentRule?
    var ruleReview: ReviewRule?
    var eventListener: Bool = false
    var customButton: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookSourceUrl = c.lenientString(.bookSourceUrl) ?? ""
        bookSourceName = c.lenientString(.bookSourceName) ?? ""
        bookSourceGroup = c.lenientString(.bookSourceGroup)
        bookSourceType = c.lenientInt(.bookSourceType) ?? 0
        bookUrlPattern = c.lenientString(.bookUrlPattern)
        customOrder = c.lenientInt(.customOrder) ?? 0
        enabled = c.lenientBool(.enabled) ?? true
        enabledExplore = c.lenientBool(.enabledExplore) ?? true
        jsLib = c.lenientString(.jsLib)
        enabledCookieJar = c.lenientBool(.enabledCookieJar) ?? true
        concurrentRate = c.lenientString(.concurrentRate)
        header = c.lenientString(.header)
        loginUrl = c.lenientString(.loginUrl)
        loginUi = c.lenientString(.loginUi)
        loginCheckJs = c.lenientString(.loginCheckJs)
        coverDecodeJs = c.lenientString(.coverDecodeJs)
        bookSourceComment = c.lenientString(.bookSourceComment)
        variableComment = c.lenientString(.variableComment)
        lastUpdateTime = Int64(c.lenientInt(.lastUpdateTime) ?? 0)
        respondTime = Int64(c.lenientInt(.respondTime) ?? 180_000)
        weight = c.lenientInt(.weight) ?? 0
        exploreUrl = c.lenientString(.exploreUrl)
        exploreScreen = c.lenientString(.exploreScreen)
        ruleExplore = c.lenientObject(ExploreRule.self, .ruleExplore)
        searchUrl = c.lenientString(.searchUrl)
        ruleSearch = c.lenientObject(SearchRule.self, .ruleSearch)
        ruleBookInfo = c.lenientObject(BookInfoRule.self, .ruleBookInfo)
        ruleToc = c.lenientObject(TocRule.self, .ruleToc)
        ruleContent = c.lenientObject(ContentRule.self, .ruleContent)
        ruleReview = c.lenientObject(ReviewRule.self, .ruleReview)
        eventListener = c.lenientBool(.eventListener) ?? false
        customButton = c.lenientBool(.customButton) ?? false
    }

    func hash(into hasher: inout Hasher) { hasher.combine(bookSourceUrl) }
    static func == (lhs: BookSource, rhs: BookSource) -> Bool { lhs.bookSourceUrl == rhs.bookSourceUrl }

    var sourceType: BookSourceType { BookSourceType(rawValue: bookSourceType) ?? .text }

    /// 分组用 `,;，；` 等分隔，与 Legado 一致
    var groups: [String] {
        (bookSourceGroup ?? "")
            .components(separatedBy: CharacterSet(charactersIn: ",;，；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var hasSearch: Bool { !(searchUrl ?? "").isEmpty }
    var hasExplore: Bool { !(exploreUrl ?? "").isEmpty }
    var hasLogin: Bool { !(loginUrl ?? "").isEmpty }
}
