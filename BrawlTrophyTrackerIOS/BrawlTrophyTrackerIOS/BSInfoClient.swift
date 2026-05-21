import Foundation

enum TrackerError: LocalizedError {
    case missingTag
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .missingTag:
            return "Введите player tag."
        case .invalidResponse:
            return "BSInfo вернул неожиданный ответ."
        case .server(let code):
            return "BSInfo API ответил ошибкой \(code)."
        }
    }
}

struct BSInfoClient {
    private let baseURL = URL(string: "https://api.bsinfox.com")!
    private let eventsURL = URL(string: "https://api.brawlapi.com/v1/events")!

    func fetchPlayer(tag rawTag: String) async throws -> PlayerProfile {
        let normalizedTag = normalizeTag(rawTag)
        guard !normalizedTag.isEmpty else {
            throw TrackerError.missingTag
        }

        let pathTag = normalizedTag.dropFirst()
        let url = baseURL.appending(path: "players").appending(path: String(pathTag))
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BrawlTrophyTrackerIOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrackerError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TrackerError.server(httpResponse.statusCode)
        }

        let envelope = try JSONDecoder().decode(BSInfoEnvelope.self, from: data)
        var profile = envelope.data
        if profile.tag.isEmpty, let tag = envelope.tag {
            profile = PlayerProfile(
                tag: tag,
                name: profile.name,
                trophies: profile.trophies,
                highestTrophies: profile.highestTrophies,
                expLevel: profile.expLevel,
                threeVsThreeVictories: profile.threeVsThreeVictories,
                soloVictories: profile.soloVictories,
                duoVictories: profile.duoVictories,
                ranked: profile.ranked,
                rankedPoints: profile.rankedPoints,
                highestWinStreak: profile.highestWinStreak,
                playedHours: profile.playedHours,
                totalPrestigeLevel: profile.totalPrestigeLevel,
                club: profile.club,
                brawlers: profile.brawlers
            )
        }
        return profile
    }

    func fetchEventRotation() async throws -> EventRotation {
        var request = URLRequest(url: eventsURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BrawlTrophyTrackerIOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrackerError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TrackerError.server(httpResponse.statusCode)
        }

        let envelope = try JSONDecoder().decode(BrawlAPIEventsEnvelope.self, from: data)
        let now = Date()
        return EventRotation(
            active: activeEvents(from: envelope.active, now: now),
            upcoming: upcomingEvents(from: envelope.upcoming, now: now)
        )
    }

    func fetchCurrentEvents() async throws -> [CurrentMapEvent] {
        try await fetchEventRotation().active
    }

    private func activeEvents(from events: [CurrentMapEvent], now: Date) -> [CurrentMapEvent] {
        let playableEvents = events.filter { $0.map != nil || $0.mode != nil }
        let nonExpiredEvents = playableEvents.filter { event in
            guard let endDate = event.endDate else { return true }
            return endDate > now
        }
        return (nonExpiredEvents.isEmpty ? playableEvents : nonExpiredEvents)
            .sorted {
                let lhsEnd = $0.endDate ?? .distantFuture
                let rhsEnd = $1.endDate ?? .distantFuture
                if lhsEnd == rhsEnd {
                return $0.slot < $1.slot
            }
            return lhsEnd < rhsEnd
        }
    }

    private func upcomingEvents(from events: [CurrentMapEvent], now: Date) -> [CurrentMapEvent] {
        events
            .filter { $0.map != nil || $0.mode != nil }
            .filter { event in
                guard let startDate = event.startDate else { return true }
                return startDate > now
            }
            .sorted {
                let lhsStart = $0.startDate ?? .distantFuture
                let rhsStart = $1.startDate ?? .distantFuture
                if lhsStart == rhsStart {
                    return $0.slot < $1.slot
                }
                return lhsStart < rhsStart
            }
    }

    private func normalizeTag(_ value: String) -> String {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "O", with: "0")
        guard !cleaned.isEmpty else { return "" }
        return cleaned.hasPrefix("#") ? cleaned : "#\(cleaned)"
    }
}
