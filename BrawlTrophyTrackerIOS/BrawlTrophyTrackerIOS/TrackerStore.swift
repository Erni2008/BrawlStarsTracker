import Foundation

@MainActor
final class TrackerStore: ObservableObject {
    @Published var playerTag: String = ""
    @Published var newAccountTag: String = ""
    @Published var trophyGoalText: String = "" {
        didSet {
            UserDefaults.standard.set(trophyGoalText, forKey: goalKey)
        }
    }
    @Published var language: AppLanguage = .russian {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: languageKey)
            rebuildDerivedStats()
            refreshStaticMessagesForLanguage()
        }
    }
    @Published private(set) var accounts: [TrackedAccount] = []
    @Published private(set) var selectedAccountTag: String = ""
    @Published private(set) var snapshots: [PlayerSnapshot] = []
    @Published private(set) var currentEvents: [CurrentMapEvent] = []
    @Published private(set) var upcomingEvents: [CurrentMapEvent] = []
    @Published private(set) var todaySummary: DaySummary = .empty
    @Published private(set) var recentChanges: [BrawlerDelta] = []
    @Published private(set) var battleLog: [BattleLogEntry] = []
    @Published private(set) var history: [(day: Date, delta: Int)] = []
    @Published private(set) var chartSnapshots: [PlayerSnapshot] = []
    @Published private(set) var topBrawlers: [Brawler] = []
    @Published private(set) var pushSuggestions: [PushSuggestion] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var isLoadingEvents = false
    @Published var statusMessage = "Введите player tag и сделайте первый снимок."
    @Published var eventsStatusMessage = "Загружаю текущие карты..."

    private let client = BSInfoClient()
    private let languageKey = "brawl_tracker_language"
    private let tagKey = "brawl_tracker_player_tag"
    private let accountsKey = "brawl_tracker_accounts"
    private let selectedAccountKey = "brawl_tracker_selected_account_tag"
    private let goalKey = "brawl_tracker_trophy_goal"
    private let snapshotsKey = "brawl_tracker_snapshots"
    private let eventsKey = "brawl_tracker_current_events"
    private let upcomingEventsKey = "brawl_tracker_upcoming_events"
    private let eventsLoadedAtKey = "brawl_tracker_events_loaded_at"
    private let maxSnapshots = 500
    private let minForegroundSyncInterval: TimeInterval = 120
    private let minEventsRefreshInterval: TimeInterval = 300
    private let minUnchangedSnapshotInterval: TimeInterval = 1_800
    private var autoSyncTask: Task<Void, Never>?
    private var lastEventsLoadedAt: Date?
    private var allSnapshots: [PlayerSnapshot] = []

    init() {
        if let rawLanguage = UserDefaults.standard.string(forKey: languageKey),
           let savedLanguage = AppLanguage(rawValue: rawLanguage) {
            language = savedLanguage
        }
        trophyGoalText = UserDefaults.standard.string(forKey: goalKey) ?? ""
        allSnapshots = loadSnapshots()
        accounts = loadAccounts()
        migrateSingleAccountIfNeeded()
        selectedAccountTag = savedSelectedAccountTag()
        playerTag = selectedAccountTag.isEmpty ? UserDefaults.standard.string(forKey: tagKey) ?? "" : selectedAccountTag
        refreshActiveSnapshots()
        currentEvents = loadEvents(forKey: eventsKey)
        upcomingEvents = loadEvents(forKey: upcomingEventsKey)
        lastEventsLoadedAt = UserDefaults.standard.object(forKey: eventsLoadedAtKey) as? Date
        rebuildDerivedStats()
        if let latest {
            statusMessage = language.text(
                "Последний снимок: \(Self.dateFormatter.string(from: latest.capturedAt))",
                "Last snapshot: \(Self.dateFormatter.string(from: latest.capturedAt))"
            )
        }
        if !currentEvents.isEmpty || !upcomingEvents.isEmpty {
            eventsStatusMessage = language.text("Карты загружены из кэша.", "Maps loaded from cache.")
        }
        refreshStaticMessagesForLanguage()
    }

    var latest: PlayerSnapshot? {
        snapshots.last
    }

    var previous: PlayerSnapshot? {
        guard snapshots.count > 1 else { return nil }
        return snapshots[snapshots.count - 2]
    }

    var selectedAccount: TrackedAccount? {
        accounts.first { $0.tag == selectedAccountTag }
    }

    func latestSnapshot(for tag: String) -> PlayerSnapshot? {
        let normalized = TrackedAccount.normalizedTag(tag)
        return allSnapshots
            .filter { TrackedAccount.normalizedTag($0.profile.tag) == normalized }
            .max { $0.capturedAt < $1.capturedAt }
    }

    func todayDelta(for tag: String) -> Int? {
        let normalized = TrackedAccount.normalizedTag(tag)
        let accountSnapshots = allSnapshots
            .filter { TrackedAccount.normalizedTag($0.profile.tag) == normalized }
            .sorted { $0.capturedAt < $1.capturedAt }
        guard let current = accountSnapshots.last else { return nil }
        let baseline = baselineSnapshotForToday(in: accountSnapshots, current: current)
        return baseline.map { current.profile.trophies - $0.profile.trophies }
    }

    var trophyGoal: Int? {
        let digits = trophyGoalText.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    var eventsUpdatedText: String {
        guard let lastEventsLoadedAt else { return language.text("ещё не обновлялись", "not updated yet") }
        return language.text(
            "обновлено \(Self.timeOnlyFormatter.string(from: lastEventsLoadedAt))",
            "updated \(Self.timeOnlyFormatter.string(from: lastEventsLoadedAt))"
        )
    }

    private func makeTodaySummary() -> DaySummary {
        guard let current = latest else {
            return .empty
        }
        let baseline = baselineSnapshotForToday(in: snapshots, current: current)
        let snapshotDelta = baseline.map { current.profile.trophies - $0.profile.trophies }
        let deltas = baseline.map { Self.deltas(from: $0, to: current) } ?? []
        let victories = baseline.map { Self.victoryDelta(from: $0, to: current) } ?? .zero
        let lossEstimate = baseline.map {
            Self.lossEstimate(from: $0, to: current, deltas: deltas, victories: victories)
        } ?? LossEstimate.empty
        return DaySummary(
            snapshotDelta: snapshotDelta,
            changedBrawlers: deltas,
            victoryDelta: victories,
            estimatedLosses: lossEstimate.count,
            visibleLostTrophies: lossEstimate.visibleLostTrophies,
            hiddenLostTrophies: lossEstimate.hiddenLostTrophies,
            lossEstimateIsHidden: lossEstimate.hasHiddenLosses
        )
    }

    private func baselineSnapshotForToday(in sourceSnapshots: [PlayerSnapshot], current: PlayerSnapshot) -> PlayerSnapshot? {
        let sortedSnapshots = sourceSnapshots.sorted { $0.capturedAt < $1.capturedAt }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let firstToday = sortedSnapshots.first { calendar.isDate($0.capturedAt, inSameDayAs: Date()) }
        let previousBeforeToday = sortedSnapshots.last { $0.capturedAt < startOfToday }

        if let firstToday, firstToday.id != current.id {
            return firstToday
        }
        return previousBeforeToday
    }

    private func makeRecentChanges() -> [BrawlerDelta] {
        guard let previous, let latest else { return [] }
        return Self.deltas(from: previous, to: latest)
    }

    private func makeBattleLog() -> [BattleLogEntry] {
        guard snapshots.count > 1 else { return [] }
        return snapshots.indices.dropFirst().compactMap { index in
            let previous = snapshots[index - 1]
            let current = snapshots[index]
            let deltas = Self.deltas(from: previous, to: current)
            let victories = Self.victoryDelta(from: previous, to: current)
            let lossEstimate = Self.lossEstimate(from: previous, to: current, deltas: deltas, victories: victories)
            guard current.profile.trophies != previous.profile.trophies || victories.total > 0 || !deltas.isEmpty else {
                return nil
            }
            return BattleLogEntry(
                id: current.id,
                startedAt: previous.capturedAt,
                endedAt: current.capturedAt,
                trophyDelta: current.profile.trophies - previous.profile.trophies,
                victoryDelta: victories,
                estimatedLosses: lossEstimate.count,
                visibleLostTrophies: lossEstimate.visibleLostTrophies,
                hiddenLostTrophies: lossEstimate.hiddenLostTrophies,
                lossEstimateIsHidden: lossEstimate.hasHiddenLosses,
                changedBrawlers: deltas
            )
        }
        .suffix(40)
        .reversed()
    }

    private func makeHistory() -> [(day: Date, delta: Int)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: snapshots) { calendar.startOfDay(for: $0.capturedAt) }
        return grouped.keys.sorted().suffix(35).compactMap { day in
            guard let daySnapshots = grouped[day]?.sorted(by: { $0.capturedAt < $1.capturedAt }),
                  let first = daySnapshots.first,
                  let last = daySnapshots.last else {
                return nil
            }
            return (day, last.profile.trophies - first.profile.trophies)
        }
    }

    private func rebuildDerivedStats() {
        todaySummary = makeTodaySummary()
        recentChanges = makeRecentChanges()
        battleLog = makeBattleLog()
        history = makeHistory()
        chartSnapshots = Array(snapshots.suffix(30))
        topBrawlers = latest?.profile.brawlers.sorted(by: { $0.trophies > $1.trophies }) ?? []
        pushSuggestions = makePushSuggestions()
    }

    func syncNow(force: Bool = true) async {
        let tag = TrackedAccount.normalizedTag(playerTag)
        guard !tag.isEmpty else {
            statusMessage = language.text("Введите player tag.", "Enter player tag.")
            return
        }

        if !accounts.contains(where: { $0.tag == tag }) {
            accounts.append(TrackedAccount(tag: tag))
            saveAccounts()
        }
        selectAccount(tag)

        if !force, let latest = latestSnapshot(for: tag), Date().timeIntervalSince(latest.capturedAt) < minForegroundSyncInterval {
            statusMessage = language.text(
                "Профиль уже свежий: \(Self.dateFormatter.string(from: latest.capturedAt))",
                "Profile is fresh: \(Self.dateFormatter.string(from: latest.capturedAt))"
            )
            return
        }

        isSyncing = true
        statusMessage = language.text("Запрашиваю BSInfo...", "Requesting BSInfo...")
        defer { isSyncing = false }

        _ = await syncAccount(tag: tag, force: force, selectAfterSync: true)
    }

    func addAccountFromInput() async {
        let tag = TrackedAccount.normalizedTag(newAccountTag)
        guard !tag.isEmpty else {
            statusMessage = language.text("Введите тег второго аккаунта.", "Enter the second account tag.")
            return
        }
        if !accounts.contains(where: { $0.tag == tag }) {
            accounts.append(TrackedAccount(tag: tag))
            saveAccounts()
        }
        newAccountTag = ""
        selectAccount(tag)
        await syncNow()
    }

    func selectAccount(_ account: TrackedAccount) {
        selectAccount(account.tag)
    }

    func removeAccount(_ account: TrackedAccount) {
        let normalized = account.tag
        accounts.removeAll { $0.tag == normalized }
        allSnapshots.removeAll { TrackedAccount.normalizedTag($0.profile.tag) == normalized }
        if selectedAccountTag == normalized {
            selectedAccountTag = accounts.first?.tag ?? ""
            playerTag = selectedAccountTag
        }
        saveAccounts()
        saveSnapshots()
        saveSelectedAccount()
        refreshActiveSnapshots()
        rebuildDerivedStats()
        statusMessage = language.text("Аккаунт удалён из локального списка.", "Account removed from the local list.")
    }

    func syncAllAccounts() async {
        let tags = accounts.map(\.tag)
        guard !tags.isEmpty else {
            await syncNow(force: false)
            return
        }

        isSyncing = true
        statusMessage = language.text("Обновляю все аккаунты...", "Updating all accounts...")
        defer { isSyncing = false }

        var errors: [String] = []
        for tag in tags {
            let ok = await syncAccount(tag: tag, force: false, selectAfterSync: false)
            if !ok {
                errors.append(tag)
            }
        }
        refreshActiveSnapshots()
        rebuildDerivedStats()
        statusMessage = errors.isEmpty
            ? language.text("Все аккаунты обновлены.", "All accounts updated.")
            : language.text("Не обновились: \(errors.joined(separator: ", ")).", "Could not update: \(errors.joined(separator: ", ")).")
    }

    func refreshEvents(force: Bool = false) async {
        guard !isLoadingEvents else { return }
        if !force,
           (!currentEvents.isEmpty || !upcomingEvents.isEmpty),
           let lastEventsLoadedAt,
           Date().timeIntervalSince(lastEventsLoadedAt) < minEventsRefreshInterval,
           !eventCacheNeedsRefresh() {
            eventsStatusMessage = language.text("Карты уже свежие.", "Maps are already fresh.")
            return
        }
        isLoadingEvents = true
        eventsStatusMessage = language.text("Обновляю карты...", "Updating maps...")
        defer { isLoadingEvents = false }

        do {
            let rotation = try await client.fetchEventRotation()
            currentEvents = rotation.active
            upcomingEvents = rotation.upcoming
            lastEventsLoadedAt = Date()
            saveEvents()
            if currentEvents.isEmpty && upcomingEvents.isEmpty {
                eventsStatusMessage = language.text("Карты пока не найдены.", "No maps found yet.")
            } else {
                eventsStatusMessage = language.text(
                    "Сейчас: \(currentEvents.count) · следующие: \(upcomingEvents.count). \(eventsUpdatedText)",
                    "Now: \(currentEvents.count) · next: \(upcomingEvents.count). \(eventsUpdatedText)"
                )
            }
        } catch {
            eventsStatusMessage = language.text(
                "Не удалось загрузить карты: \(error.localizedDescription)",
                "Could not load maps: \(error.localizedDescription)"
            )
        }
    }

    func startAutoSync() {
        guard autoSyncTask == nil else { return }
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                guard let self else { return }
                if !self.accounts.isEmpty {
                    await self.syncAllAccounts()
                } else if !self.playerTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await self.syncNow(force: false)
                }
                await self.refreshEvents()
            }
        }
    }

    func syncOnForeground() async {
        await refreshEvents()
        if !accounts.isEmpty {
            await syncAllAccounts()
        } else if !playerTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await syncNow(force: false)
        }
    }

    func clearLocalHistory() {
        let activeTag = selectedAccountTag
        if activeTag.isEmpty {
            allSnapshots.removeAll()
            UserDefaults.standard.removeObject(forKey: snapshotsKey)
        } else {
            allSnapshots.removeAll { TrackedAccount.normalizedTag($0.profile.tag) == activeTag }
            saveSnapshots()
        }
        refreshActiveSnapshots()
        rebuildDerivedStats()
        statusMessage = language.text(
            "История активного аккаунта очищена. Можно сделать новый снимок.",
            "Active account history cleared. You can take a new snapshot."
        )
    }

    func setTrophyGoal(_ value: Int) {
        trophyGoalText = "\(max(0, value))"
    }

    private func selectAccount(_ tag: String) {
        let normalized = TrackedAccount.normalizedTag(tag)
        guard !normalized.isEmpty else { return }
        selectedAccountTag = normalized
        playerTag = normalized
        UserDefaults.standard.set(normalized, forKey: tagKey)
        saveSelectedAccount()
        refreshActiveSnapshots()
        rebuildDerivedStats()
    }

    private func syncAccount(tag rawTag: String, force: Bool, selectAfterSync: Bool) async -> Bool {
        let tag = TrackedAccount.normalizedTag(rawTag)
        guard !tag.isEmpty else { return false }

        do {
            let fetchedProfile = try await client.fetchPlayer(tag: tag)
            let resolvedTag = TrackedAccount.normalizedTag(fetchedProfile.tag.isEmpty ? tag : fetchedProfile.tag)
            let profile = fetchedProfile
            upsertAccount(tag: resolvedTag, name: profile.name, lastSyncedAt: Date())

            if selectAfterSync {
                selectedAccountTag = resolvedTag
                playerTag = resolvedTag
                UserDefaults.standard.set(resolvedTag, forKey: tagKey)
                saveSelectedAccount()
            }

            let now = Date()
            let latestForAccount = latestSnapshot(for: resolvedTag)
            if shouldStoreSnapshot(profile, at: now, force: force, latestSnapshot: latestForAccount) {
                let snapshot = PlayerSnapshot(id: UUID(), capturedAt: now, profile: profile)
                allSnapshots.append(snapshot)
                trimSnapshots()
                saveSnapshots()
                statusMessage = language.text(
                    "Готово: \(profile.name) · \(profile.trophies.formatted()) кубков.",
                    "Done: \(profile.name) · \(profile.trophies.formatted()) trophies."
                )
            } else {
                statusMessage = language.text(
                    "Без изменений: \(profile.name) · \(profile.trophies.formatted()) кубков.",
                    "No changes: \(profile.name) · \(profile.trophies.formatted()) trophies."
                )
            }

            refreshActiveSnapshots()
            rebuildDerivedStats()
            return true
        } catch {
            statusMessage = "\(tag): \(error.localizedDescription)"
            return false
        }
    }

    private func upsertAccount(tag: String, name: String, lastSyncedAt: Date?) {
        if let index = accounts.firstIndex(where: { $0.tag == tag }) {
            accounts[index].name = name
            accounts[index].lastSyncedAt = lastSyncedAt
        } else {
            accounts.append(TrackedAccount(tag: tag, name: name, lastSyncedAt: lastSyncedAt))
        }
        saveAccounts()
    }

    private func refreshActiveSnapshots() {
        let activeTag = selectedAccountTag.isEmpty ? TrackedAccount.normalizedTag(playerTag) : selectedAccountTag
        guard !activeTag.isEmpty else {
            snapshots = []
            return
        }
        snapshots = allSnapshots
            .filter { TrackedAccount.normalizedTag($0.profile.tag) == activeTag }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func trimSnapshots() {
        let grouped = Dictionary(grouping: allSnapshots) { TrackedAccount.normalizedTag($0.profile.tag) }
        allSnapshots = grouped.values.flatMap { accountSnapshots in
            accountSnapshots
                .sorted { $0.capturedAt < $1.capturedAt }
                .suffix(maxSnapshots)
        }
        .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func loadAccounts() -> [TrackedAccount] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TrackedAccount].self, from: data)) ?? []
    }

    private func saveAccounts() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }

    private func migrateSingleAccountIfNeeded() {
        guard accounts.isEmpty else { return }
        let savedTag = TrackedAccount.normalizedTag(UserDefaults.standard.string(forKey: tagKey) ?? allSnapshots.last?.profile.tag ?? "")
        guard !savedTag.isEmpty else { return }
        let latestSnapshot = latestSnapshot(for: savedTag) ?? allSnapshots.last
        accounts = [
            TrackedAccount(
                tag: savedTag,
                name: latestSnapshot?.profile.name ?? "Player",
                lastSyncedAt: latestSnapshot?.capturedAt
            )
        ]
        saveAccounts()
    }

    private func savedSelectedAccountTag() -> String {
        let saved = TrackedAccount.normalizedTag(UserDefaults.standard.string(forKey: selectedAccountKey) ?? "")
        if accounts.contains(where: { $0.tag == saved }) {
            return saved
        }
        return accounts.first?.tag ?? ""
    }

    private func saveSelectedAccount() {
        UserDefaults.standard.set(selectedAccountTag, forKey: selectedAccountKey)
    }

    private func loadSnapshots() -> [PlayerSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: snapshotsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PlayerSnapshot].self, from: data)) ?? []
    }

    private func loadEvents(forKey key: String) -> [CurrentMapEvent] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([CurrentMapEvent].self, from: data)) ?? []
    }

    private func saveSnapshots() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(allSnapshots) {
            UserDefaults.standard.set(data, forKey: snapshotsKey)
        }
    }

    private func saveEvents() {
        if let data = try? JSONEncoder().encode(currentEvents) {
            UserDefaults.standard.set(data, forKey: eventsKey)
        }
        if let data = try? JSONEncoder().encode(upcomingEvents) {
            UserDefaults.standard.set(data, forKey: upcomingEventsKey)
        }
        UserDefaults.standard.set(lastEventsLoadedAt, forKey: eventsLoadedAtKey)
    }

    private func shouldStoreSnapshot(_ profile: PlayerProfile, at date: Date, force: Bool, latestSnapshot: PlayerSnapshot?) -> Bool {
        guard let latest = latestSnapshot else { return true }
        let elapsed = date.timeIntervalSince(latest.capturedAt)
        if hasMeaningfulChange(from: latest.profile, to: profile) {
            return true
        }
        return force || elapsed >= minUnchangedSnapshotInterval
    }

    private func hasMeaningfulChange(from old: PlayerProfile, to new: PlayerProfile) -> Bool {
        if old.trophies != new.trophies ||
            old.threeVsThreeVictories != new.threeVsThreeVictories ||
            old.soloVictories != new.soloVictories ||
            old.duoVictories != new.duoVictories ||
            old.rankedPoints != new.rankedPoints ||
            old.highestWinStreak != new.highestWinStreak {
            return true
        }
        let oldBrawlers = Dictionary(uniqueKeysWithValues: old.brawlers.map { ($0.id, $0.trophies) })
        return new.brawlers.contains { oldBrawlers[$0.id] != $0.trophies }
    }

    private func eventCacheNeedsRefresh() -> Bool {
        let now = Date()
        let hasExpiredActive = currentEvents.contains { event in
            guard let endDate = event.endDate else { return false }
            return endDate <= now
        }
        let hasStartedUpcoming = upcomingEvents.contains { event in
            guard let startDate = event.startDate else { return false }
            return startDate <= now
        }
        return hasExpiredActive || hasStartedUpcoming
    }

    private func makePushSuggestions() -> [PushSuggestion] {
        guard let profile = latest?.profile else { return [] }
        let recentPositiveIds = Set(recentChanges.filter { $0.delta > 0 }.map(\.id))
        return profile.brawlers.map { brawler in
            let target = nextMilestone(after: brawler.trophies)
            let needed = max(1, target - brawler.trophies)
            let isHot = recentPositiveIds.contains(brawler.id)
            let isClose = needed <= 25
            let score = (isClose ? 100 : 0) + (isHot ? 45 : 0) + max(0, 80 - needed)
            let reason: String
            let tint: UInt
            if isClose {
                reason = language.text("близко к \(target)", "close to \(target)")
                tint = 0xFFD34D
            } else if isHot {
                reason = language.text("уже идёт вверх", "already climbing")
                tint = 0x48D889
            } else {
                reason = language.text("стабильный ап", "steady push")
                tint = 0x52B6FF
            }
            return (score, PushSuggestion(
                id: brawler.id,
                brawler: brawler,
                targetTrophies: target,
                neededTrophies: needed,
                reason: reason,
                tintHex: tint
            ))
        }
        .sorted {
            if $0.0 == $1.0 {
                return $0.1.brawler.trophies > $1.1.brawler.trophies
            }
            return $0.0 > $1.0
        }
        .prefix(5)
        .map(\.1)
    }

    private func nextMilestone(after trophies: Int) -> Int {
        if trophies < 500 {
            return ((trophies / 50) + 1) * 50
        }
        if trophies < 1_000 {
            return ((trophies / 100) + 1) * 100
        }
        return ((trophies / 250) + 1) * 250
    }

    private static func deltas(from previous: PlayerSnapshot, to current: PlayerSnapshot) -> [BrawlerDelta] {
        let previousById = Dictionary(uniqueKeysWithValues: previous.profile.brawlers.map { ($0.id, $0) })
        return current.profile.brawlers.compactMap { brawler in
            guard let old = previousById[brawler.id], old.trophies != brawler.trophies else {
                return nil
            }
            return BrawlerDelta(
                id: brawler.id,
                name: brawler.name,
                previousTrophies: old.trophies,
                currentTrophies: brawler.trophies,
                power: brawler.power,
                rank: brawler.rank
            )
        }
        .sorted { abs($0.delta) == abs($1.delta) ? $0.name < $1.name : abs($0.delta) > abs($1.delta) }
    }

    private static func victoryDelta(from previous: PlayerSnapshot, to current: PlayerSnapshot) -> VictoryDelta {
        VictoryDelta(
            threeVsThree: max(0, current.profile.threeVsThreeVictories - previous.profile.threeVsThreeVictories),
            solo: max(0, current.profile.soloVictories - previous.profile.soloVictories),
            duo: max(0, current.profile.duoVictories - previous.profile.duoVictories)
        )
    }

    private static func estimatedLosses(from deltas: [BrawlerDelta]) -> Int {
        deltas
            .filter { $0.delta < 0 }
            .reduce(0) { total, change in
                let lostTrophies = abs(change.delta)
                let lossSize = estimatedTrophyLossPerDefeat(around: max(change.previousTrophies, change.currentTrophies))
                return total + max(1, Int(ceil(Double(lostTrophies) / Double(lossSize))))
            }
    }

    private static func lossEstimate(
        from previous: PlayerSnapshot,
        to current: PlayerSnapshot,
        deltas: [BrawlerDelta],
        victories: VictoryDelta
    ) -> LossEstimate {
        let visibleLostTrophies = visibleLostTrophies(from: deltas)
        let visibleLosses = estimatedLosses(from: deltas)
        let trophyDelta = current.profile.trophies - previous.profile.trophies
        let likelyWinGain = 10
        let likelyLossSize = 10
        let expectedGainFromWins = victories.total * likelyWinGain
        let hiddenLostTrophies = max(0, expectedGainFromWins - trophyDelta - visibleLostTrophies)
        let hiddenLosses = hiddenLostTrophies == 0 ? 0 : max(1, Int(ceil(Double(hiddenLostTrophies) / Double(likelyLossSize))))

        return LossEstimate(
            count: max(visibleLosses, visibleLosses + hiddenLosses),
            visibleLostTrophies: visibleLostTrophies,
            hiddenLostTrophies: hiddenLostTrophies,
            hasHiddenLosses: hiddenLosses > 0 && victories.total > 0
        )
    }

    private static func visibleLostTrophies(from deltas: [BrawlerDelta]) -> Int {
        deltas.filter { $0.delta < 0 }.reduce(0) { $0 + abs($1.delta) }
    }

    private static func estimatedTrophyLossPerDefeat(around trophies: Int) -> Int {
        switch trophies {
        case ..<100:
            return 4
        case ..<200:
            return 5
        case ..<300:
            return 6
        case ..<500:
            return 7
        case ..<700:
            return 8
        case ..<900:
            return 9
        case ..<1_100:
            return 10
        default:
            return 12
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func refreshStaticMessagesForLanguage() {
        if let latest {
            statusMessage = language.text(
                "Последний снимок: \(Self.dateFormatter.string(from: latest.capturedAt))",
                "Last snapshot: \(Self.dateFormatter.string(from: latest.capturedAt))"
            )
        } else {
            statusMessage = language.text(
                "Введите player tag и сделайте первый снимок.",
                "Enter player tag and take the first snapshot."
            )
        }

        if currentEvents.isEmpty && upcomingEvents.isEmpty {
            eventsStatusMessage = language.text("Загружаю текущие карты...", "Loading current maps...")
        } else {
            eventsStatusMessage = language.text("Карты загружены из кэша.", "Maps loaded from cache.")
        }
    }
}

private struct LossEstimate {
    let count: Int
    let visibleLostTrophies: Int
    let hiddenLostTrophies: Int
    let hasHiddenLosses: Bool

    static let empty = LossEstimate(count: 0, visibleLostTrophies: 0, hiddenLostTrophies: 0, hasHiddenLosses: false)
}
