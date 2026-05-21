import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .russian:
            return "RU"
        case .english:
            return "EN"
        }
    }

    func text(_ russian: String, _ english: String) -> String {
        switch self {
        case .russian:
            return russian
        case .english:
            return english
        }
    }
}

struct BSInfoEnvelope: Decodable {
    let tag: String?
    let timestamp: Int?
    let data: PlayerProfile
}

struct BrawlAPIEventsEnvelope: Decodable {
    let active: [CurrentMapEvent]
    let upcoming: [CurrentMapEvent]

    enum CodingKeys: String, CodingKey {
        case active
        case upcoming
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decodeIfPresent([CurrentMapEvent].self, forKey: .active) ?? []
        upcoming = try container.decodeIfPresent([CurrentMapEvent].self, forKey: .upcoming) ?? []
    }
}

struct EventRotation {
    let active: [CurrentMapEvent]
    let upcoming: [CurrentMapEvent]
}

struct TrackedAccount: Codable, Identifiable, Equatable {
    var id: String { tag }
    let tag: String
    var name: String
    var addedAt: Date
    var lastSyncedAt: Date?

    init(tag: String, name: String = "Player", addedAt: Date = .now, lastSyncedAt: Date? = nil) {
        self.tag = Self.normalizedTag(tag)
        self.name = name
        self.addedAt = addedAt
        self.lastSyncedAt = lastSyncedAt
    }

    static func normalizedTag(_ value: String) -> String {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "O", with: "0")
        guard !cleaned.isEmpty else { return "" }
        return cleaned.hasPrefix("#") ? cleaned : "#\(cleaned)"
    }
}

struct CurrentMapEvent: Codable, Identifiable {
    let slot: Int
    let map: EventMap?
    let mode: EventMode?
    let startTime: String
    let endTime: String

    var id: String {
        "\(slot)-\(map?.id ?? 0)-\(startTime)"
    }

    var title: String {
        map?.name ?? "Карта скрыта"
    }

    var modeName: String {
        mode?.displayName ?? "Special Event"
    }

    func localizedTitle(for language: AppLanguage) -> (primary: String, secondary: String?) {
        let english = map?.name ?? "Hidden Map"
        let russian = MapLocalizer.russianMapName(for: english)
        switch language {
        case .russian:
            return (russian, english == russian ? "EN: \(english)" : "EN: \(english)")
        case .english:
            return (english, russian == english ? "RU: \(russian)" : "RU: \(russian)")
        }
    }

    func localizedModeName(for language: AppLanguage) -> String {
        mode?.displayName(for: language) ?? language.text("Особое событие", "Special Event")
    }

    var accentColorHex: String {
        mode?.color ?? "#FFD34D"
    }

    var mapImageURL: URL? {
        guard let map else { return nil }
        return URL(string: "https://cdn.brawlify.com/maps/regular/\(map.id).png")
    }

    var mapPageURL: URL? {
        guard let map else { return nil }
        return URL(string: "https://brawlify.com/maps/\(map.id)")
    }

    var endDate: Date? {
        Self.date(from: endTime)
    }

    var startDate: Date? {
        Self.date(from: startTime)
    }

    static func date(from value: String) -> Date? {
        fractionalDateFormatter.date(from: value) ?? standardDateFormatter.date(from: value)
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct EventMap: Codable {
    let id: Int
    let name: String
}

struct EventMode: Codable {
    let id: Int
    let name: String
    let hash: String?
    let color: String?

    var displayName: String {
        name
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    func displayName(for language: AppLanguage) -> String {
        let english = displayName
        switch language {
        case .russian:
            return MapLocalizer.russianModeName(for: english)
        case .english:
            return english
        }
    }
}

enum MapLocalizer {
    static func russianModeName(for english: String) -> String {
        modeNames[english] ?? english
    }

    static func russianMapName(for english: String) -> String {
        mapNames[english] ?? english
    }

    private static let modeNames: [String: String] = [
        "Gem Grab": "Захват кристаллов",
        "Brawl Ball": "Броулбол",
        "Showdown": "Столкновение",
        "Duo Showdown": "Парное столкновение",
        "Heist": "Ограбление",
        "Bounty": "Награда за поимку",
        "Hot Zone": "Горячая зона",
        "Knockout": "Нокаут",
        "Wipeout": "Зачистка",
        "Basket Brawl": "Баскетбой",
        "Volley Brawl": "Волейбой",
        "Payload": "Груз",
        "Duels": "Дуэли",
        "Siege": "Осада",
        "Trophy Escape": "Побег с трофеями",
        "Hunters": "Охотники"
    ]

    private static let mapNames: [String: String] = [
        "Acute Angle": "Острый угол",
        "Backyard Bowl": "Дворовая арена",
        "Belle's Rock": "Скала Белль",
        "Bridge Too Far": "Далёкий мост",
        "Canal Grande": "Гранд-канал",
        "Center Stage": "Центральная сцена",
        "Cavern Churn": "Водоворот в пещере",
        "Dark Passage": "Тёмный проход",
        "Double Swoosh": "Двойной свист",
        "Double Trouble": "Двойная проблема",
        "Dry Season": "Сухой сезон",
        "Dueling Beetles": "Жуки-дуэлянты",
        "Eggshell": "Скорлупа",
        "Feast or Famine": "Пир или голод",
        "Field Goal": "Гол с поля",
        "Flaring Phoenix": "Пылающий феникс",
        "Four Levels": "Четыре уровня",
        "Goldarm Gulch": "Ущелье Золотой руки",
        "Hard Limits": "Жёсткие рамки",
        "Hard Rock Mine": "Каменистая шахта",
        "Hideout": "Укрытие",
        "Hot Potato": "Горячая картошка",
        "Island Invasion": "Вторжение на остров",
        "Kaboom Canyon": "Каньон Кабум",
        "Layer Cake": "Слоёный пирог",
        "New Horizons": "Новые горизонты",
        "Open Business": "Открытый бизнес",
        "Open Space": "Открытое пространство",
        "Out in the Open": "На открытом месте",
        "Parallel Plays": "Параллельные игры",
        "Penalty Kick": "Пенальти",
        "Pinball Dreams": "Пинбольные мечты",
        "Pit Stop": "Пит-стоп",
        "Ring of Fire": "Огненное кольцо",
        "Rockwall Brawl": "Скальная схватка",
        "Safe Zone": "Безопасная зона",
        "Scorched Stone": "Обожжённый камень",
        "Shooting Star": "Падающая звезда",
        "Skull Creek": "Черепной ручей",
        "Snake Prairie": "Змеиная степь",
        "Sneaky Fields": "Коварные поля",
        "Stormy Plains": "Бурные равнины",
        "Super Beach": "Суперпляж",
        "Undermine": "Подкоп"
    ]
}

struct PlayerProfile: Codable, Identifiable {
    var id: String { tag }

    let tag: String
    let name: String
    let trophies: Int
    let highestTrophies: Int
    let expLevel: Int
    let threeVsThreeVictories: Int
    let soloVictories: Int
    let duoVictories: Int
    let ranked: Int?
    let rankedPoints: Int?
    let highestWinStreak: Int?
    let playedHours: Double?
    let totalPrestigeLevel: Int?
    let club: Club?
    let brawlers: [Brawler]

    enum CodingKeys: String, CodingKey {
        case tag
        case name
        case trophies
        case highestTrophies
        case expLevel
        case threeVsThreeVictories = "3vs3Victories"
        case soloVictories
        case duoVictories
        case ranked
        case rankedPoints
        case highestWinStreak
        case playedHours
        case totalPrestigeLevel
        case club
        case brawlers
    }
}

extension PlayerProfile {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        trophies = try container.decodeIfPresent(Int.self, forKey: .trophies) ?? 0
        highestTrophies = try container.decodeIfPresent(Int.self, forKey: .highestTrophies) ?? 0
        expLevel = try container.decodeIfPresent(Int.self, forKey: .expLevel) ?? 0
        threeVsThreeVictories = try container.decodeIfPresent(Int.self, forKey: .threeVsThreeVictories) ?? 0
        soloVictories = try container.decodeIfPresent(Int.self, forKey: .soloVictories) ?? 0
        duoVictories = try container.decodeIfPresent(Int.self, forKey: .duoVictories) ?? 0
        ranked = try container.decodeIfPresent(Int.self, forKey: .ranked)
        rankedPoints = try container.decodeIfPresent(Int.self, forKey: .rankedPoints)
        highestWinStreak = try container.decodeIfPresent(Int.self, forKey: .highestWinStreak)
        playedHours = try container.decodeIfPresent(Double.self, forKey: .playedHours)
        totalPrestigeLevel = try container.decodeIfPresent(Int.self, forKey: .totalPrestigeLevel)
        club = try container.decodeIfPresent(Club.self, forKey: .club)
        brawlers = try container.decodeIfPresent([Brawler].self, forKey: .brawlers) ?? []
    }
}

struct Club: Codable {
    let tag: String?
    let name: String?
}

struct Brawler: Codable, Identifiable {
    let id: Int
    let name: String
    let power: Int
    let rank: Int
    let prestigeLevel: Int?
    let trophies: Int
    let highestTrophies: Int
    let highestSeasonTrophies: Int?
    let winStreak: Int?
    let highestWinStreak: Int?
    let mastery: Int?
    let buffies: BrawlerBuffies?
    let skin: BrawlerSkin?
    let gears: [BrawlerLoadoutItem]
    let hyperCharges: [BrawlerLoadoutItem]
    let starPowers: [BrawlerLoadoutItem]
    let gadgets: [BrawlerLoadoutItem]

    var imageURL: URL? {
        URL(string: "https://cdn.brawlify.com/brawlers/borderless/\(id).png")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case power
        case rank
        case prestigeLevel
        case trophies
        case highestTrophies
        case highestSeasonTrophies
        case winStreak
        case highestWinStreak
        case mastery
        case buffies
        case skin
        case gears
        case hyperCharges
        case starPowers
        case gadgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "UNKNOWN"
        power = try container.decodeIfPresent(Int.self, forKey: .power) ?? 0
        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        prestigeLevel = try container.decodeIfPresent(Int.self, forKey: .prestigeLevel)
        trophies = try container.decodeIfPresent(Int.self, forKey: .trophies) ?? 0
        highestTrophies = try container.decodeIfPresent(Int.self, forKey: .highestTrophies) ?? 0
        highestSeasonTrophies = try container.decodeIfPresent(Int.self, forKey: .highestSeasonTrophies)
        winStreak = try container.decodeIfPresent(Int.self, forKey: .winStreak)
        highestWinStreak = try container.decodeIfPresent(Int.self, forKey: .highestWinStreak)
        mastery = try container.decodeIfPresent(Int.self, forKey: .mastery)
        buffies = try container.decodeIfPresent(BrawlerBuffies.self, forKey: .buffies)
        skin = try container.decodeIfPresent(BrawlerSkin.self, forKey: .skin)
        gears = try container.decodeIfPresent([BrawlerLoadoutItem].self, forKey: .gears) ?? []
        hyperCharges = try container.decodeIfPresent([BrawlerLoadoutItem].self, forKey: .hyperCharges) ?? []
        starPowers = try container.decodeIfPresent([BrawlerLoadoutItem].self, forKey: .starPowers) ?? []
        gadgets = try container.decodeIfPresent([BrawlerLoadoutItem].self, forKey: .gadgets) ?? []
    }
}

struct BrawlerBuffies: Codable {
    let gadget: Bool
    let starPower: Bool
    let hyperCharge: Bool
}

struct BrawlerSkin: Codable {
    let id: Int
    let name: String
}

struct BrawlerLoadoutItem: Codable, Identifiable {
    let id: Int
    let name: String
    let level: Int?
}

struct PlayerSnapshot: Codable, Identifiable {
    let id: UUID
    let capturedAt: Date
    let profile: PlayerProfile
}

struct BrawlerDelta: Identifiable {
    let id: Int
    let name: String
    let previousTrophies: Int
    let currentTrophies: Int
    let power: Int
    let rank: Int

    var delta: Int {
        currentTrophies - previousTrophies
    }
}

struct DaySummary {
    let snapshotDelta: Int?
    let changedBrawlers: [BrawlerDelta]
    let victoryDelta: VictoryDelta
    let estimatedLosses: Int
    let visibleLostTrophies: Int
    let hiddenLostTrophies: Int
    let lossEstimateIsHidden: Bool

    var positiveCount: Int {
        changedBrawlers.filter { $0.delta > 0 }.count
    }

    var negativeCount: Int {
        changedBrawlers.filter { $0.delta < 0 }.count
    }

    static let empty = DaySummary(
        snapshotDelta: nil,
        changedBrawlers: [],
        victoryDelta: .zero,
        estimatedLosses: 0,
        visibleLostTrophies: 0,
        hiddenLostTrophies: 0,
        lossEstimateIsHidden: false
    )
}

struct VictoryDelta: Codable, Equatable {
    let threeVsThree: Int
    let solo: Int
    let duo: Int

    static let zero = VictoryDelta(threeVsThree: 0, solo: 0, duo: 0)

    var total: Int {
        threeVsThree + solo + duo
    }
}

struct BattleLogEntry: Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let trophyDelta: Int
    let victoryDelta: VictoryDelta
    let estimatedLosses: Int
    let visibleLostTrophies: Int
    let hiddenLostTrophies: Int
    let lossEstimateIsHidden: Bool
    let changedBrawlers: [BrawlerDelta]

    var isPositive: Bool {
        trophyDelta > 0 || victoryDelta.total > 0
    }
}

struct PushSuggestion: Identifiable {
    let id: Int
    let brawler: Brawler
    let targetTrophies: Int
    let neededTrophies: Int
    let reason: String
    let tintHex: UInt
}
