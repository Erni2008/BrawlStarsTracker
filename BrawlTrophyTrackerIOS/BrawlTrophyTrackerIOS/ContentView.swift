import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingResetConfirmation = false
    @State private var didRequestInitialRefresh = false
    @State private var selectedMapEvent: CurrentMapEvent?
    @State private var selectedBrawler: Brawler?
    @State private var brawlerSearchText = ""
    @State private var brawlerFilter: BrawlerFilter = .all
    @State private var brawlerSort: BrawlerSort = .trophies
    @AppStorage("brawl_tracker_favorite_brawlers") private var favoriteBrawlersRaw = ""
    @AppStorage("brawl_tracker_brawler_goals") private var brawlerGoalsRaw = "{}"
    @AppStorage("brawl_tracker_show_advanced") private var showAdvancedBlocks = true
    @AppStorage("brawl_tracker_compact_ui") private var compactUI = true
    @AppStorage("brawl_tracker_history_limit") private var visibleHistoryLimit = 30
    @AppStorage("brawl_tracker_collapse_upgrade") private var collapseUpgradePlanner = false
    @AppStorage("brawl_tracker_collapse_quality") private var collapseQualityScore = false
    @AppStorage("brawl_tracker_collapse_changes") private var collapseBrawlerChanges = true
    @AppStorage("brawl_tracker_collapse_tier") private var collapseTierList = false
    @AppStorage("brawl_tracker_collapse_profile") private var collapseProfileStats = true
    @AppStorage("brawl_tracker_collapse_battlelog") private var collapseBattleLog = true

    private var summary: DaySummary {
        store.todaySummary
    }

    private var latestProfile: PlayerProfile? {
        store.latest?.profile
    }

    private var favoriteBrawlerIds: Set<Int> {
        Set(favoriteBrawlersRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var brawlerGoals: [Int: Int] {
        guard let data = brawlerGoalsRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let id = Int(key) else { return nil }
            return (id, value)
        })
    }

    private var favoriteBrawlers: [Brawler] {
        store.topBrawlers.filter { favoriteBrawlerIds.contains($0.id) }
    }

    private var droppedBrawlerIds: Set<Int> {
        Set(store.recentChanges.filter { $0.delta < 0 }.map(\.id))
    }

    private var closeMilestoneBrawlers: [Brawler] {
        store.topBrawlers
            .filter { trophiesToNextMilestone($0.trophies) <= 25 }
            .sorted { trophiesToNextMilestone($0.trophies) < trophiesToNextMilestone($1.trophies) }
    }

    private var upgradeCandidates: [Brawler] {
        store.topBrawlers
            .filter { missingLoadoutScore($0) > 0 || $0.power < 11 }
            .sorted {
                let lhs = missingLoadoutScore($0) + max(0, 11 - $0.power) * 2
                let rhs = missingLoadoutScore($1) + max(0, 11 - $1.power) * 2
                return lhs == rhs ? $0.trophies > $1.trophies : lhs > rhs
            }
    }

    private var accountQuality: AccountQuality {
        AccountQuality(brawlers: store.topBrawlers)
    }

    private var shareReportText: String {
        let profile = latestProfile
        let today = deltaText(summary.snapshotDelta)
        let close = closeMilestoneBrawlers.prefix(3).map { "\($0.name) +\(trophiesToNextMilestone($0.trophies))" }.joined(separator: ", ")
        return """
        Brawl Tracker report
        Player: \(profile?.name ?? "Player") \(profile?.tag ?? normalizedPreviewTag)
        Trophies: \(profile?.trophies.formatted() ?? "-")
        Today: \(today)
        Wins: +\(summary.victoryDelta.total), Losses: ~\(summary.estimatedLosses)
        Quality score: \(accountQuality.score)/100
        Close milestones: \(close.isEmpty ? "-" : close)
        """
    }

    private var displayedBrawlers: [Brawler] {
        let query = brawlerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let negativeIds = Set(store.recentChanges.filter { $0.delta < 0 }.map(\.id))
        let filtered = store.topBrawlers.filter { brawler in
            let matchesQuery = query.isEmpty || brawler.name.lowercased().contains(query)
            guard matchesQuery else { return false }
            switch brawlerFilter {
            case .all:
                return true
            case .hyper:
                return !brawler.hyperCharges.isEmpty || brawler.buffies?.hyperCharge == true
            case .missingGears:
                return brawler.power >= 10 && brawler.gears.count < 2
            case .power11:
                return brawler.power >= 11
            case .nearMilestone:
                return trophiesToNextMilestone(brawler.trophies) <= 25
            case .dropped:
                return negativeIds.contains(brawler.id)
            }
        }

        return filtered.sorted { lhs, rhs in
            let lhsFavorite = favoriteBrawlerIds.contains(lhs.id)
            let rhsFavorite = favoriteBrawlerIds.contains(rhs.id)
            if lhsFavorite != rhsFavorite {
                return lhsFavorite
            }
            switch brawlerSort {
            case .trophies:
                return lhs.trophies == rhs.trophies ? lhs.name < rhs.name : lhs.trophies > rhs.trophies
            case .power:
                return lhs.power == rhs.power ? lhs.trophies > rhs.trophies : lhs.power > rhs.power
            case .rank:
                return lhs.rank == rhs.rank ? lhs.trophies > rhs.trophies : lhs.rank > rhs.rank
            case .loadout:
                let lhsMissing = missingLoadoutScore(lhs)
                let rhsMissing = missingLoadoutScore(rhs)
                return lhsMissing == rhsMissing ? lhs.trophies > rhs.trophies : lhsMissing > rhsMissing
            case .name:
                return lhs.name < rhs.name
            }
        }
    }

    var body: some View {
        NavigationStack {
            TabView {
                tabScreen {
                        accountSwitcherSection
                        heroSection
                        metricsSection
                        goalSection
                        progressCalendarSection
                    }
                    .tabItem {
                        Label(t("Главная", "Home"), systemImage: "house.fill")
                    }

                tabScreen {
                    coachFeedSection
                    smartMapAdvisorSection
                    if showAdvancedBlocks {
                        collapsibleSlot(
                            title: t("Что докачать", "Upgrade Planner"),
                            icon: "hammer.fill",
                            tint: .brawlBlue,
                            isCollapsed: $collapseUpgradePlanner
                        ) {
                            upgradePlannerSection
                        }
                        collapsibleSlot(
                            title: "Quality Score",
                            icon: "gauge.with.dots.needle.67percent",
                            tint: .brawlGreen,
                            isCollapsed: $collapseQualityScore
                        ) {
                            accountQualitySection
                        }
                    }
                }
                .tabItem {
                    Label("Coach", systemImage: "sparkles")
                }

                tabScreen {
                    currentMapsSection
                }
                .tabItem {
                    Label(t("Карты", "Maps"), systemImage: "map.fill")
                }

                tabScreen {
                    brawlerGoalsSection
                    pushPlanSection
                    brawlerListSection
                    collapsibleSlot(
                        title: t("Последние изменения", "Recent Changes"),
                        icon: "waveform.path.ecg",
                        tint: .brawlYellow,
                        isCollapsed: $collapseBrawlerChanges
                    ) {
                        brawlerChangesSection
                    }
                }
                .tabItem {
                    Label(t("Бравлеры", "Brawlers"), systemImage: "star.fill")
                }

                tabScreen {
                    historySection
                    progressCalendarSection
                    if showAdvancedBlocks {
                        collapsibleSlot(
                            title: t("Личный тир-лист", "Personal Tier List"),
                            icon: "square.stack.3d.up.fill",
                            tint: .brawlYellow,
                            isCollapsed: $collapseTierList
                        ) {
                            personalTierSection
                        }
                    }
                    collapsibleSlot(
                        title: t("Профиль", "Profile"),
                        icon: "person.crop.circle",
                        tint: .brawlBlue,
                        isCollapsed: $collapseProfileStats
                    ) {
                        profileSection
                    }
                    collapsibleSlot(
                        title: t("Батл лог", "Battle Log"),
                        icon: "list.bullet.rectangle",
                        tint: .brawlPurple,
                        isCollapsed: $collapseBattleLog
                    ) {
                        battleLogSection
                    }
                }
                .tabItem {
                    Label(t("История", "History"), systemImage: "chart.xyaxis.line")
                }

                tabScreen {
                    exportAndSettingsSection
                }
                .tabItem {
                    Label(t("Настройки", "Settings"), systemImage: "gearshape.fill")
                }
            }
            .tint(.brawlYellow)
            .environment(\.compactLayout, compactUI)
            .toolbarBackground(Color.surfaceDeep.opacity(0.94), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
            .navigationTitle("Brawl Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    LanguageSwitch(language: $store.language)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.white.opacity(store.snapshots.isEmpty ? 0.3 : 0.9))
                    }
                    .disabled(store.snapshots.isEmpty)
                }
            }
            .confirmationDialog(t("Очистить локальную историю?", "Clear local history?"), isPresented: $showingResetConfirmation) {
                Button(t("Очистить", "Clear"), role: .destructive) {
                    store.clearLocalHistory()
                }
            }
            .sheet(item: $selectedMapEvent) { event in
                MapDetailView(event: event, language: store.language)
            }
            .sheet(item: $selectedBrawler) { brawler in
                BrawlerDetailView(
                    brawler: brawler,
                    snapshots: store.snapshots,
                    recentChanges: store.recentChanges,
                    targetGoal: brawlerGoals[brawler.id],
                    isFavorite: favoriteBrawlerIds.contains(brawler.id),
                    language: store.language
                )
            }
            .onAppear {
                store.startAutoSync()
                guard !didRequestInitialRefresh else { return }
                didRequestInitialRefresh = true
                Task { await store.syncOnForeground() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await store.syncOnForeground() }
                }
            }
        }
    }

    private func tabScreen<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: compactUI ? 10 : 16) {
                    content()
                }
                .padding(.horizontal, compactUI ? 10 : 16)
                .padding(.top, compactUI ? 8 : 12)
                .padding(.bottom, compactUI ? 18 : 28)
            }
        }
    }

    private func collapsibleSlot<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        isCollapsed: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isCollapsed.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.caption)
                        .fontWeight(.black)
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(tint, in: RoundedRectangle(cornerRadius: 7))

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer()

                    Text(isCollapsed.wrappedValue ? t("Открыть", "Open") : t("Свернуть", "Collapse"))
                        .font(.caption2)
                        .fontWeight(.black)
                        .foregroundStyle(.white.opacity(0.46))

                    Image(systemName: isCollapsed.wrappedValue ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .fontWeight(.black)
                        .foregroundStyle(tint)
                }
                .padding(13)
                .background(Color.cardBase.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if !isCollapsed.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: compactUI ? 10 : 18) {
            HStack(alignment: .top, spacing: compactUI ? 10 : 14) {
                AccountMark(name: latestProfile?.name ?? "BS")

                VStack(alignment: .leading, spacing: 5) {
                    Text(latestProfile?.name ?? "Player")
                        .font(.title2)
                        .fontWeight(.black)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(latestProfile?.tag ?? normalizedPreviewTag)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    StatusPill(
                        icon: store.latest == nil ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                        text: store.statusMessage,
                        tint: store.latest == nil ? .orange : .green
                    )
                    .padding(.top, 4)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(latestProfile?.trophies.formatted() ?? "-")
                        .font(.system(size: compactUI ? 25 : 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)

                    Text(t("кубков", "trophies"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.58))
                }
                .frame(width: 112, alignment: .trailing)
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "number")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))

                    TextField("#R2UCLQVRU", text: $store.playerTag)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .submitLabel(.go)
                        .onSubmit {
                            Task { await store.syncNow() }
                        }
                }
                .padding(.horizontal, 12)
                .frame(height: compactUI ? 40 : 48)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )

                Button {
                    Task { await store.syncNow() }
                } label: {
                    ZStack {
                        if store.isSyncing {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .black))
                        }
                    }
                    .frame(width: compactUI ? 40 : 48, height: compactUI ? 40 : 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(Color.brawlYellow, in: RoundedRectangle(cornerRadius: 8))
                .disabled(store.isSyncing)
            }
        }
        .padding(compactUI ? 12 : 18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.cardBase)

                LinearGradient(
                    colors: [.brawlBlue.opacity(0.34), .brawlPink.opacity(0.22), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var accountSwitcherSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: compactUI ? 10 : 14) {
                HStack(spacing: 10) {
                    SectionTitle(
                        t("Аккаунты", "Accounts"),
                        detail: t("выбор профиля", "profile switcher"),
                        icon: "person.2.fill"
                    )

                    Button {
                        Task { await store.syncAllAccounts() }
                    } label: {
                        ZStack {
                            if store.isSyncing {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.72)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 13, weight: .black))
                            }
                        }
                        .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)
                    .background(Color.brawlYellow, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(store.isSyncing)
                }

                if store.accounts.isEmpty {
                    InfoText(t("Добавь первый или второй аккаунт по player tag. Приложение будет обновлять статистику по всем аккаунтам в фоне.", "Add the first or second account by player tag. The app will keep every account updated in the background."))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.accounts) { account in
                                let latest = store.latestSnapshot(for: account.tag)
                                let delta = store.todayDelta(for: account.tag)
                                Button {
                                    store.selectAccount(account)
                                } label: {
                                    AccountSwitchTile(
                                        name: latest?.profile.name ?? account.name,
                                        tag: account.tag,
                                        trophies: latest?.profile.trophies,
                                        delta: delta,
                                        isSelected: account.tag == store.selectedAccountTag
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.removeAccount(account)
                                    } label: {
                                        Label(t("Удалить", "Remove"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }

                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.brawlGreen)

                        TextField(t("#ТЕГ второго аккаунта", "#Second account tag"), text: $store.newAccountTag)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .submitLabel(.go)
                            .onSubmit {
                                Task { await store.addAccountFromInput() }
                            }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )

                    Button {
                        Task { await store.addAccountFromInput() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .black))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)
                    .background(Color.brawlGreen, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(store.isSyncing)
                }
            }
        }
    }

    private var metricsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: compactUI ? 7 : 10) {
            MetricCard(
                title: t("Сегодня", "Today"),
                value: deltaText(summary.snapshotDelta),
                subtitle: t("по снимкам", "by snapshots"),
                symbol: "chart.line.uptrend.xyaxis",
                tint: deltaColor(summary.snapshotDelta ?? 0)
            )
            MetricCard(
                title: t("Победы", "Wins"),
                value: "+\(summary.victoryDelta.total)",
                subtitle: "3v3 \(summary.victoryDelta.threeVsThree) · solo \(summary.victoryDelta.solo) · duo \(summary.victoryDelta.duo)",
                symbol: "checkmark.seal.fill",
                tint: .brawlGreen
            )
            MetricCard(
                title: t("Поражения", "Losses"),
                value: "~\(summary.estimatedLosses)",
                subtitle: lossMetricSubtitle,
                symbol: "xmark.octagon.fill",
                tint: summary.estimatedLosses > 0 ? .brawlRed : .white.opacity(0.7)
            )
            MetricCard(
                title: t("Пик", "Best"),
                value: latestProfile?.highestTrophies.formatted() ?? "-",
                subtitle: t("лучший результат", "highest result"),
                symbol: "crown.fill",
                tint: .brawlYellow
            )
        }
    }

    private var currentMapsSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SectionTitle(t("Карты", "Maps"), detail: t("ротация Brawl Stars", "Brawl Stars rotation"), icon: "map.fill")

                    Button {
                        Task { await store.refreshEvents(force: true) }
                    } label: {
                        ZStack {
                            if store.isLoadingEvents {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.72)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .black))
                            }
                        }
                        .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)
                    .background(Color.brawlYellow, in: RoundedRectangle(cornerRadius: 8))
                }

                InfoText(t("Карты разделены на активные сейчас и следующие. Активные показывают время до смены, будущие - время до старта.", "Maps are split into active and next. Active cards show time until rotation, upcoming cards show time until start."))
                Text(store.eventsUpdatedText)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.38))

                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    VStack(alignment: .leading, spacing: 16) {
                        MapEventLane(
                            title: t("Сейчас", "Now"),
                            detail: t("активные слоты", "active slots"),
                            emptyText: store.eventsStatusMessage,
                            events: Array(store.currentEvents.prefix(10)),
                            phase: .active,
                            now: timeline.date,
                            language: store.language
                        ) { event in
                            selectedMapEvent = event
                        }

                        MapEventLane(
                            title: t("Следующие", "Next"),
                            detail: t("после ротации", "after rotation"),
                            emptyText: t("BrawlAPI пока не отдал следующие карты. Обнови позже, когда появится будущая ротация.", "BrawlAPI has not returned upcoming maps yet. Refresh later when the next rotation appears."),
                            events: Array(store.upcomingEvents.prefix(10)),
                            phase: .upcoming,
                            now: timeline.date,
                            language: store.language
                        ) { event in
                            selectedMapEvent = event
                        }
                    }
                }
            }
        }
    }

    private var coachFeedSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(t("Coach Feed", "Coach Feed"), detail: t("что делать сейчас", "what to do now"), icon: "bell.badge.fill")
                InfoText(t("Короткие подсказки по твоему аккаунту: где плюс, кого поставить на паузу, кто близко к рубежу и когда сменятся карты.", "Short account-aware hints: progress, pause picks, close milestones, and map timing."))

                LazyVStack(spacing: 8) {
                    CoachCard(
                        icon: summary.snapshotDelta ?? 0 >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                        title: t("Сегодня", "Today"),
                        message: t("Дельта кубков: \(deltaText(summary.snapshotDelta)). Победы +\(summary.victoryDelta.total), поражения ~\(summary.estimatedLosses).", "Trophy delta: \(deltaText(summary.snapshotDelta)). Wins +\(summary.victoryDelta.total), losses ~\(summary.estimatedLosses)."),
                        tint: deltaColor(summary.snapshotDelta ?? 0)
                    )

                    if let firstClose = closeMilestoneBrawlers.first {
                        CoachCard(
                            icon: "target",
                            title: t("Близко к рубежу", "Close milestone"),
                            message: t("\(firstClose.name) нужно +\(trophiesToNextMilestone(firstClose.trophies)) кубков. Хороший кандидат для короткого пуша.", "\(firstClose.name) needs +\(trophiesToNextMilestone(firstClose.trophies)) trophies. Good short push candidate."),
                            tint: .brawlYellow
                        )
                    }

                    if let dropped = store.recentChanges.first(where: { $0.delta < 0 }) {
                        CoachCard(
                            icon: "pause.circle.fill",
                            title: t("Антислив", "Anti-tilt"),
                            message: t("\(dropped.name) просел на \(abs(dropped.delta)) кубков. Лучше поставить на паузу до следующего sync.", "\(dropped.name) dropped \(abs(dropped.delta)) trophies. Better pause until next sync."),
                            tint: .brawlRed
                        )
                    }

                    if let nextEvent = store.upcomingEvents.first {
                        CoachCard(
                            icon: "map.fill",
                            title: t("Следующая карта", "Next map"),
                            message: t("Скоро: \(nextEvent.localizedTitle(for: store.language).primary), \(nextEvent.localizedModeName(for: store.language)).", "Soon: \(nextEvent.localizedTitle(for: store.language).primary), \(nextEvent.localizedModeName(for: store.language))."),
                            tint: .brawlBlue
                        )
                    }
                }
            }
        }
    }

    private var smartMapAdvisorSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(t("Map Advisor", "Map Advisor"), detail: t("кого пушить на картах", "push picks"), icon: "wand.and.stars")
                InfoText(t("Советник берёт текущие и следующие карты, затем выбирает сильных бравлеров, которые близко к рубежу, в избранном или без просадки.", "Advisor reads current and next maps, then picks strong brawlers that are close to milestones, favorite, or not currently dropped."))

                let events = Array((store.currentEvents + store.upcomingEvents).prefix(4))
                if events.isEmpty || store.topBrawlers.isEmpty {
                    EmptyState(t("Советник появится после загрузки карт и профиля.", "Advisor appears after maps and profile are loaded."))
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(events) { event in
                            AdvisorCard(
                                event: event,
                                picks: advisorPicks(for: event),
                                language: store.language
                            )
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(t("Динамика кубков", "Trophy Trend"), detail: t("последние снимки", "latest snapshots"), icon: "chart.xyaxis.line")
                InfoText(t("Линия показывает общий счёт кубков по последним sync. Ниже отдельно показана дневная дельта: зелёный вверх, красный вниз.", "The line shows total trophies from recent syncs. The strip below shows daily delta: green up, red down."))

                let trendSnapshots = store.chartSnapshots
                if trendSnapshots.count < 2 {
                    EmptyState(t("График появится после второго sync.", "The chart appears after the second sync."))
                } else {
                    let trophyValues = trendSnapshots.map(\.profile.trophies)
                    let firstValue = trophyValues.first ?? 0
                    let currentValue = trophyValues.last ?? 0
                    let highValue = trophyValues.max() ?? currentValue
                    let lowValue = trophyValues.min() ?? currentValue

                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            TrendStat(title: t("Сейчас", "Now"), value: currentValue.formatted(), tint: .brawlYellow)
                            TrendStat(title: t("За период", "Period"), value: deltaText(currentValue - firstValue), tint: deltaColor(currentValue - firstValue))
                            TrendStat(title: t("Диапазон", "Range"), value: "\(lowValue.formatted())-\(highValue.formatted())", tint: .brawlBlue)
                        }

                        TrophyTrendChart(snapshots: trendSnapshots)
                            .frame(height: 190)

                        DailyDeltaStrip(history: store.history, language: store.language)
                    }
                }
            }
        }
    }

    private var progressCalendarSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(t("Календарь", "Calendar"), detail: t("последние дни", "recent days"), icon: "calendar")
                InfoText(t("Каждая клетка - день. Зелёный день в плюс, красный день в минус, серый день без движения.", "Each cell is a day. Green is positive, red is negative, gray is flat."))

                if store.history.isEmpty {
                    EmptyState(t("Календарь появится после нескольких снимков.", "Calendar appears after a few snapshots."))
                } else {
                    ProgressCalendarGrid(history: Array(store.history.suffix(visibleHistoryLimit)), language: store.language)
                    let weekDelta = store.history.suffix(7).reduce(0) { $0 + $1.delta }
                    let monthDelta = store.history.suffix(30).reduce(0) { $0 + $1.delta }
                    let bestDay = store.history.max(by: { $0.delta < $1.delta })?.delta ?? 0
                    HStack(spacing: 8) {
                        TrendStat(title: t("Неделя", "Week"), value: deltaText(weekDelta), tint: deltaColor(weekDelta))
                        TrendStat(title: t("30 дней", "30 days"), value: deltaText(monthDelta), tint: deltaColor(monthDelta))
                        TrendStat(title: t("Лучший день", "Best day"), value: deltaText(bestDay), tint: deltaColor(bestDay))
                    }
                }
            }
        }
    }

    private var personalTierSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(t("Личный тир-лист", "Personal Tier List"), detail: t("по твоему аккаунту", "your account"), icon: "square.stack.3d.up.fill")
                InfoText(t("Это не общий meta-tier. Оценка строится по твоим кубкам, силе, рангу, streak и заполненности loadout.", "This is not a global meta tier. It scores your brawlers by trophies, power, rank, streak, and loadout completion."))

                if store.topBrawlers.isEmpty {
                    EmptyState(t("Тир-лист появится после sync.", "Tier list appears after sync."))
                } else {
                    VStack(spacing: 9) {
                        ForEach(PersonalTier.allCases) { tier in
                            let brawlers = store.topBrawlers.filter { personalTier(for: $0) == tier }.prefix(8)
                            TierRow(tier: tier, brawlers: Array(brawlers), language: store.language)
                        }
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(t("Цель", "Goal"), detail: t("личный план", "personal plan"), icon: "target")
                InfoText(t("Поставь цель по кубкам. Приложение покажет прогресс, остаток и примерный срок по текущему дневному темпу.", "Set a trophy goal. The app shows progress, remaining trophies, and an estimate based on your current daily pace."))

                if let profile = latestProfile {
                    let target = store.trophyGoal ?? suggestedGoalValue
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "flag.checkered")
                                    .font(.caption)
                                    .foregroundStyle(Color.brawlYellow)

                                TextField("\(suggestedGoalValue)", text: $store.trophyGoalText)
                                    .keyboardType(.numberPad)
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.black)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 46)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            )

                            Button {
                                store.setTrophyGoal(suggestedGoalValue)
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16, weight: .black))
                                    .frame(width: 46, height: 46)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.black)
                            .background(Color.brawlYellow, in: RoundedRectangle(cornerRadius: 8))
                        }

                        GoalProgressPanel(
                            current: profile.trophies,
                            target: target,
                            todayDelta: summary.snapshotDelta ?? 0,
                            language: store.language
                        )

                        HStack(spacing: 8) {
                            GoalQuickButton(title: t("След. \(goalStep / 1000)k", "Next \(goalStep / 1000)k"), value: suggestedGoalValue) {
                                store.setTrophyGoal(suggestedGoalValue)
                            }
                            GoalQuickButton(title: "+500", value: profile.trophies + 500) {
                                store.setTrophyGoal(profile.trophies + 500)
                            }
                            GoalQuickButton(title: "+1000", value: profile.trophies + 1_000) {
                                store.setTrophyGoal(profile.trophies + 1_000)
                            }
                        }
                    }
                } else {
                    EmptyState(t("Цель можно поставить после первого sync.", "You can set a goal after the first sync."))
                }
            }
        }
    }

    private var brawlerGoalsSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(t("Цели бравлеров", "Brawler Goals"), detail: t("личные рубежи", "personal targets"), icon: "scope")
                InfoText(t("Закрепи любимых бравлеров и веди цель по каждому. Если цель не задана, приложение предложит ближайший рубеж.", "Pin favorite brawlers and track a target per brawler. If no target is set, the app suggests the next milestone."))

                let targetBrawlers = Array((favoriteBrawlers.isEmpty ? closeMilestoneBrawlers : favoriteBrawlers).prefix(6))
                if targetBrawlers.isEmpty {
                    EmptyState(t("Добавь бравлера в избранное или сделай sync, чтобы появились цели.", "Favorite a brawler or sync to see goals."))
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(targetBrawlers) { brawler in
                            BrawlerGoalRow(
                                brawler: brawler,
                                target: brawlerGoals[brawler.id] ?? nextMilestone(after: brawler.trophies),
                                isFavorite: favoriteBrawlerIds.contains(brawler.id),
                                language: store.language,
                                onToggleFavorite: { toggleFavorite(brawler.id) },
                                onSetGoal: { setBrawlerGoal(id: brawler.id, target: $0) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var pushPlanSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(t("Кого пушить", "Push Queue"), detail: t("умная очередь", "smart queue"), icon: "scope")
                InfoText(t("Подборка бравлеров, которые ближе всего к следующему рубежу или уже показывали положительную динамику.", "Brawlers closest to the next milestone or already showing positive momentum."))

                if store.pushSuggestions.isEmpty {
                    EmptyState(t("Советы появятся после первого sync.", "Suggestions appear after the first sync."))
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(store.pushSuggestions) { suggestion in
                            PushSuggestionRow(suggestion: suggestion, language: store.language)
                        }
                    }
                }
            }
        }
    }

    private var upgradePlannerSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(t("Что докачать", "Upgrade Planner"), detail: "loadout", icon: "hammer.fill")
                InfoText(t("Список показывает бравлеров, где больше всего пользы от докачки: power, gears, пассивки, гаджеты и hypercharge.", "This list shows where upgrades matter most: power, gears, star powers, gadgets, and hypercharge."))

                if upgradeCandidates.isEmpty {
                    EmptyState(t("Критичных докачек не найдено.", "No urgent upgrades found."))
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(upgradeCandidates.prefix(6))) { brawler in
                            UpgradeRow(brawler: brawler, language: store.language)
                        }
                    }
                }
            }
        }
    }

    private var accountQualitySection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(t("Quality Score", "Quality Score"), detail: t("сила аккаунта", "account health"), icon: "gauge.with.dots.needle.67percent")
                InfoText(t("Оценка показывает, насколько аккаунт готов к пушу: power 11, hypercharge, gears, пассивки и общий рост.", "Score reflects push readiness: power 11, hypercharge, gears, star powers, and overall growth."))
                QualityScorePanel(quality: accountQuality, language: store.language)
            }
        }
    }

    private var profileSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(t("Профиль", "Profile"), detail: latestSnapshotText, icon: "person.crop.circle")
                InfoText(t("Параметры ниже приходят из публичного профиля: победы по режимам, ranked points, лучший streak и клуб.", "These stats come from the public profile: wins by mode, ranked points, best streak, and club."))

                if let profile = latestProfile {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ProfileStat("3v3", value: "\(profile.threeVsThreeVictories)", icon: "person.3.fill", tint: .brawlBlue)
                        ProfileStat("Solo", value: "\(profile.soloVictories)", icon: "person.fill", tint: .brawlGreen)
                        ProfileStat("Duo", value: "\(profile.duoVictories)", icon: "person.2.fill", tint: .brawlPink)
                        ProfileStat("Ranked", value: profile.rankedPoints.map { "\($0)" } ?? "\(profile.ranked ?? 0)", icon: "shield.lefthalf.filled", tint: .brawlYellow)
                        ProfileStat("Streak", value: "\(profile.highestWinStreak ?? 0)", icon: "flame.fill", tint: .orange)
                        ProfileStat(t("Клуб", "Club"), value: profile.club?.name ?? "-", icon: "flag.fill", tint: .brawlPurple)
                    }
                } else {
                    EmptyState(t("Сделайте первый снимок профиля.", "Take the first profile snapshot."))
                }
            }
        }
    }

    private var battleLogSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(t("Батл лог", "Battle Log"), detail: t("по снимкам", "by snapshots"), icon: "list.bullet.rectangle")
                InfoText(t("BSInfo без токена не отдаёт реальные матчи. Здесь показаны интервалы между снимками: победы считаются по росту win-счётчиков, поражения оцениваются по потерянным или скрытым кубкам.", "Tokenless BSInfo does not provide real matches. This log shows intervals between snapshots: wins come from win counters, losses are estimated from visible or hidden trophy drops."))

                if store.battleLog.isEmpty {
                    EmptyState(t("Журнал появится после двух sync с изменениями.", "The log appears after two syncs with changes."))
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(store.battleLog.prefix(20))) { entry in
                            BattleLogRow(entry: entry, language: store.language)
                        }
                    }
                }
            }
        }
    }

    private var brawlerChangesSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(t("Последние изменения", "Recent Changes"), detail: t("2 снимка", "2 snapshots"), icon: "waveform.path.ecg")
                InfoText(t("Это список бравлеров, у которых изменились кубки между двумя последними снимками.", "Brawlers whose trophies changed between the last two snapshots."))

                if store.recentChanges.isEmpty {
                    EmptyState(t("Изменения появятся после второго снимка.", "Changes appear after the second snapshot."))
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(store.recentChanges.prefix(20))) { change in
                            BrawlerDeltaRow(change: change, language: store.language)
                        }
                    }
                }
            }
        }
    }

    private var brawlerListSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(t("Бравлеры", "Brawlers"), detail: t("топ 30 по кубкам", "top 30 by trophies"), icon: "star.fill")
                InfoText(t("Карточки показывают кубки, портрет, силу, ранг и прогресс. Ниже видны пассивки, гаджеты, gears, hypercharge и активные усиления.", "Cards show trophies, portrait, power, rank, and progress. Below each brawler you can see star powers, gadgets, gears, hypercharge, and active boosts."))

                brawlerToolbar

                if !store.topBrawlers.isEmpty {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(displayedBrawlers.prefix(40).enumerated()), id: \.element.id) { index, brawler in
                            Button {
                                selectedBrawler = brawler
                            } label: {
                                BrawlerRow(index: index + 1, brawler: brawler, maxTrophies: max(1, store.topBrawlers.first?.trophies ?? 1), language: store.language)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if displayedBrawlers.isEmpty {
                        EmptyState(t("Ничего не найдено по текущим фильтрам.", "Nothing found with current filters."))
                    }
                } else {
                    EmptyState(t("Список заполнится после sync.", "The list fills after sync."))
                }
            }
        }
    }

    private var brawlerToolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))

                TextField(t("Найти бравлера", "Find brawler"), text: $brawlerSearchText)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()

                if !brawlerSearchText.isEmpty {
                    Button {
                        brawlerSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(BrawlerFilter.allCases) { filter in
                        FilterChip(
                            title: filter.title(store.language),
                            isSelected: brawlerFilter == filter,
                            tint: filter.tint
                        ) {
                            brawlerFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            HStack(spacing: 8) {
                Text(t("Сортировка", "Sort"))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.42))

                Picker("", selection: $brawlerSort) {
                    ForEach(BrawlerSort.allCases) { sort in
                        Text(sort.title(store.language)).tag(sort)
                    }
                }
                .pickerStyle(.menu)
                .tint(.brawlYellow)

                Spacer()

                Text("\(displayedBrawlers.count)/\(store.topBrawlers.count)")
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
    }

    private var exportAndSettingsSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(t("Отчёт и настройки", "Report & Settings"), detail: t("экспорт", "export"), icon: "square.and.arrow.up.fill")
                InfoText(t("Можно быстро поделиться дневным отчётом и настроить видимость сложных блоков.", "Share a daily report and tune how much advanced data is shown."))

                ShareLink(item: shareReportText) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text(t("Поделиться отчётом", "Share report"))
                            .fontWeight(.black)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(13)
                    .foregroundStyle(.black)
                    .background(Color.brawlYellow, in: RoundedRectangle(cornerRadius: 8))
                }

                Toggle(isOn: $showAdvancedBlocks) {
                    Text(t("Показывать сложные блоки", "Show advanced blocks"))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                .tint(.brawlYellow)

                Toggle(isOn: $compactUI) {
                    Text(t("Компактный интерфейс", "Compact UI"))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                .tint(.brawlYellow)

                Stepper(value: $visibleHistoryLimit, in: 14...35, step: 7) {
                    Text(t("Дней в календаре: \(visibleHistoryLimit)", "Calendar days: \(visibleHistoryLimit)"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.58))
                }
                .tint(.brawlYellow)
            }
        }
    }

    private var normalizedPreviewTag: String {
        let tag = store.playerTag.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if tag.isEmpty { return "#PLAYER" }
        return tag.hasPrefix("#") ? tag : "#\(tag)"
    }

    private var latestSnapshotText: String {
        guard let latest = store.latest else { return t("нет данных", "no data") }
        return timeFormatter.string(from: latest.capturedAt)
    }

    private var lossMetricSubtitle: String {
        if summary.lossEstimateIsHidden {
            return t("скрытый минус ~\(summary.hiddenLostTrophies)", "hidden loss ~\(summary.hiddenLostTrophies)")
        }
        return t("видимый минус \(summary.visibleLostTrophies)", "visible loss \(summary.visibleLostTrophies)")
    }

    private var goalStep: Int {
        let trophies = latestProfile?.trophies ?? 0
        return trophies < 20_000 ? 1_000 : 5_000
    }

    private var suggestedGoalValue: Int {
        let trophies = latestProfile?.trophies ?? 0
        let step = goalStep
        return ((trophies / step) + 1) * step
    }

    private func deltaText(_ value: Int?) -> String {
        guard let value else { return "-" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private func deltaColor(_ value: Int) -> Color {
        if value > 0 { return .brawlGreen }
        if value < 0 { return .brawlRed }
        return .white.opacity(0.7)
    }

    private func deltaGradient(_ value: Int) -> LinearGradient {
        let color = deltaColor(value)
        return LinearGradient(colors: [color, color.opacity(0.42)], startPoint: .top, endPoint: .bottom)
    }

    private func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM"
        return formatter.string(from: date)
    }

    private func trophiesToNextMilestone(_ trophies: Int) -> Int {
        let step: Int
        if trophies < 500 {
            step = 50
        } else if trophies < 1_000 {
            step = 100
        } else {
            step = 250
        }
        return ((trophies / step) + 1) * step - trophies
    }

    private func nextMilestone(after trophies: Int) -> Int {
        trophies + trophiesToNextMilestone(trophies)
    }

    private func toggleFavorite(_ id: Int) {
        var ids = favoriteBrawlerIds
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        favoriteBrawlersRaw = ids.sorted().map(String.init).joined(separator: ",")
    }

    private func setBrawlerGoal(id: Int, target: Int) {
        var goals = brawlerGoals
        goals[id] = max(0, target)
        let encodable = Dictionary(uniqueKeysWithValues: goals.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(encodable),
           let raw = String(data: data, encoding: .utf8) {
            brawlerGoalsRaw = raw
        }
    }

    private func advisorPicks(for event: CurrentMapEvent) -> [Brawler] {
        let mode = event.modeName.lowercased()
        let preferredNames = preferredBrawlerNames(forMode: mode)
        return store.topBrawlers
            .filter { !droppedBrawlerIds.contains($0.id) }
            .sorted { lhs, rhs in
                advisorScore(lhs, preferredNames: preferredNames) > advisorScore(rhs, preferredNames: preferredNames)
            }
            .prefix(3)
            .map { $0 }
    }

    private func preferredBrawlerNames(forMode mode: String) -> Set<String> {
        if mode.contains("brawl ball") {
            return ["MORTIS", "BIBI", "SURGE", "MAX", "FANG", "KENJI", "STU"]
        }
        if mode.contains("knockout") || mode.contains("bounty") || mode.contains("wipeout") {
            return ["PIPER", "BROCK", "BELLE", "MANDY", "ANGELO", "NANI"]
        }
        if mode.contains("heist") {
            return ["COLT", "COLETTE", "BULL", "CHUCK", "MELODIE", "RICO"]
        }
        if mode.contains("hot zone") || mode.contains("gem grab") {
            return ["SANDY", "GALE", "AMBER", "JESSIE", "PENNY", "NITA"]
        }
        return []
    }

    private func advisorScore(_ brawler: Brawler, preferredNames: Set<String>) -> Int {
        let preferred = preferredNames.contains(brawler.name.uppercased()) ? 60 : 0
        let close = max(0, 30 - trophiesToNextMilestone(brawler.trophies))
        let favorite = favoriteBrawlerIds.contains(brawler.id) ? 35 : 0
        let loadout = min(30, brawler.gears.count * 6 + brawler.gadgets.count * 3 + brawler.starPowers.count * 3 + (brawler.hyperCharges.isEmpty ? 0 : 8))
        return brawler.trophies / 80 + brawler.power * 3 + brawler.rank * 4 + close + favorite + preferred + loadout
    }

    private func missingLoadoutScore(_ brawler: Brawler) -> Int {
        let missingGears = max(0, min(2, 2 - brawler.gears.count))
        let missingGadgets = max(0, min(2, 2 - brawler.gadgets.count))
        let missingStarPowers = max(0, min(2, 2 - brawler.starPowers.count))
        let missingHyper = brawler.hyperCharges.isEmpty ? 1 : 0
        return missingGears * 3 + missingGadgets + missingStarPowers + missingHyper * 2
    }

    private func personalTier(for brawler: Brawler) -> PersonalTier {
        let loadoutScore = min(10, brawler.gears.count * 2 + brawler.gadgets.count + brawler.starPowers.count + (brawler.hyperCharges.isEmpty ? 0 : 2))
        let score = brawler.trophies / 120 + brawler.power * 3 + brawler.rank * 4 + (brawler.winStreak ?? 0) * 2 + loadoutScore
        if score >= 100 { return .s }
        if score >= 78 { return .a }
        if score >= 56 { return .b }
        return .c
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private func t(_ russian: String, _ english: String) -> String {
        store.language.text(russian, english)
    }
}

private enum BrawlerFilter: String, CaseIterable, Identifiable {
    case all
    case hyper
    case missingGears
    case power11
    case nearMilestone
    case dropped

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .all:
            return .brawlYellow
        case .hyper:
            return .brawlPurple
        case .missingGears:
            return .brawlBlue
        case .power11:
            return .brawlGreen
        case .nearMilestone:
            return .orange
        case .dropped:
            return .brawlRed
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .all:
            return language.text("Все", "All")
        case .hyper:
            return language.text("С гипером", "Hyper")
        case .missingGears:
            return language.text("Без gears", "Missing gears")
        case .power11:
            return "Power 11"
        case .nearMilestone:
            return language.text("Близко к рубежу", "Near milestone")
        case .dropped:
            return language.text("Просели", "Dropped")
        }
    }
}

private enum BrawlerSort: String, CaseIterable, Identifiable {
    case trophies
    case power
    case rank
    case loadout
    case name

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .trophies:
            return language.text("Кубки", "Trophies")
        case .power:
            return "Power"
        case .rank:
            return language.text("Ранг", "Rank")
        case .loadout:
            return "Loadout"
        case .name:
            return language.text("Имя", "Name")
        }
    }
}

private enum PersonalTier: String, CaseIterable, Identifiable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .s:
            return .brawlYellow
        case .a:
            return .brawlGreen
        case .b:
            return .brawlBlue
        case .c:
            return .white.opacity(0.62)
        }
    }
}

private struct CompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

private struct AccountQuality {
    let total: Int
    let power11: Int
    let hyper: Int
    let completeGear: Int
    let closeMilestones: Int
    let score: Int

    init(brawlers: [Brawler]) {
        total = max(1, brawlers.count)
        power11 = brawlers.filter { $0.power >= 11 }.count
        hyper = brawlers.filter { !$0.hyperCharges.isEmpty || $0.buffies?.hyperCharge == true }.count
        completeGear = brawlers.filter { $0.gears.count >= 2 }.count
        closeMilestones = brawlers.filter { brawler in
            let step = brawler.trophies < 500 ? 50 : (brawler.trophies < 1_000 ? 100 : 250)
            return ((brawler.trophies / step) + 1) * step - brawler.trophies <= 25
        }.count
        let powerScore = Double(power11) / Double(total) * 35
        let hyperScore = Double(hyper) / Double(total) * 25
        let gearScore = Double(completeGear) / Double(total) * 25
        let milestoneScore = min(15, closeMilestones * 2)
        score = min(100, Int((powerScore + hyperScore + gearScore).rounded()) + milestoneScore)
    }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(hex: 0x070A11), Color(hex: 0x0E1624), Color(hex: 0x111521)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            LinearGradient(
                colors: [.brawlBlue.opacity(0.055), .clear, .brawlYellow.opacity(0.035)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .overlay(
            Color.black.opacity(0.08)
                .ignoresSafeArea()
        )
    }
}

private struct LanguageSwitch: View {
    @Binding var language: AppLanguage

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AppLanguage.allCases) { option in
                Button {
                    language = option
                } label: {
                    Text(option.shortTitle)
                        .font(.caption2)
                        .fontWeight(.black)
                        .foregroundStyle(language == option ? .black : .white.opacity(0.72))
                        .frame(width: 32, height: 26)
                        .background(language == option ? Color.brawlYellow : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.cardBase.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct AccountMark: View {
    @Environment(\.compactLayout) private var compact
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.brawlYellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))

            Text(initials)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.82))
        }
        .frame(width: compact ? 42 : 54, height: compact ? 42 : 54)
        .shadow(color: .brawlYellow.opacity(0.18), radius: 6, y: 3)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let raw = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return raw.isEmpty ? "BS" : raw.uppercased()
    }
}

private struct StatusPill: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

private struct MetricCard: View {
    @Environment(\.compactLayout) private var compact
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 11) {
            HStack {
                Image(systemName: symbol)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(tint)
                    .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: compact ? 22 : 28, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 10 : 14)
        .background(Color.cardBase.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct DashboardCard<Content: View>: View {
    @Environment(\.compactLayout) private var compact
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(compact ? 10 : 16)
            .background(
                LinearGradient(
                    colors: [Color.surfaceRaised.opacity(0.94), Color.cardBase.opacity(0.84)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.075), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: compact ? 4 : 8, y: compact ? 2 : 5)
    }
}

private struct AccountSwitchTile: View {
    @Environment(\.compactLayout) private var compact
    let name: String
    let tag: String
    let trophies: Int?
    let delta: Int?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                AccountMark(name: name)
                    .frame(width: compact ? 34 : 38, height: compact ? 34 : 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.black)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(tag)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Label(trophies?.formatted() ?? "-", systemImage: "trophy.fill")
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundStyle(Color.brawlYellow)

                Text(deltaText)
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundStyle(deltaColor)
            }
        }
        .frame(width: compact ? 154 : 178, alignment: .leading)
        .padding(10)
        .background(
            LinearGradient(
                colors: isSelected ? [.brawlYellow.opacity(0.20), .surfaceRaised.opacity(0.92)] : [.white.opacity(0.08), .surfaceRaised.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.brawlYellow.opacity(0.62) : .white.opacity(0.10), lineWidth: isSelected ? 1.4 : 1)
        )
    }

    private var deltaText: String {
        guard let delta else { return "today -" }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private var deltaColor: Color {
        guard let delta else { return .white.opacity(0.45) }
        if delta > 0 { return .brawlGreen }
        if delta < 0 { return .brawlRed }
        return .white.opacity(0.62)
    }
}

private struct SectionTitle: View {
    @Environment(\.compactLayout) private var compact
    let title: String
    let detail: String
    let icon: String

    init(_ title: String, detail: String, icon: String) {
        self.title = title
        self.detail = detail
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: icon)
                .font(.caption)
                .fontWeight(.black)
                .foregroundStyle(.black)
                .frame(width: compact ? 21 : 24, height: compact ? 21 : 24)
                .background(
                    LinearGradient(colors: [.brawlYellow, .brawlYellow.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .shadow(color: .brawlYellow.opacity(0.18), radius: 8, y: 3)

            Text(title)
                .font(compact ? .subheadline : .headline)
                .fontWeight(.black)
                .foregroundStyle(.white)

            Spacer()

            if !compact {
                Text(detail)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
    }
}

private struct TrendStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2)
                .fontWeight(.black)
                .foregroundStyle(isSelected ? .black.opacity(0.82) : tint)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isSelected ? tint : tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CoachCard: View {
    @Environment(\.compactLayout) private var compact
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 8 : 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .fontWeight(.black)
                .foregroundStyle(tint)
                .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.black)
                    .foregroundStyle(.white)

                Text(message)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 8 : 10)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AdvisorCard: View {
    @Environment(\.compactLayout) private var compact
    let event: CurrentMapEvent
    let picks: [Brawler]
    let language: AppLanguage

    private var accent: Color {
        Color(hexString: event.accentColorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.localizedTitle(for: language).primary)
                        .font(.subheadline)
                        .fontWeight(.black)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(event.localizedModeName(for: language))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(accent)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(picks) { brawler in
                    VStack(spacing: 4) {
                        BrawlerBadge(name: brawler.name, id: brawler.id, tint: accent, size: compact ? 34 : 42)
                        Text(brawler.name)
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .frame(width: 56)
                        Text(brawler.trophies.formatted())
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(Color.brawlYellow)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(compact ? 8 : 10)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum MapEventPhase {
    case active
    case upcoming

    var title: String {
        switch self {
        case .active:
            return "LIVE"
        case .upcoming:
            return "NEXT"
        }
    }

    var tint: Color {
        switch self {
        case .active:
            return .brawlGreen
        case .upcoming:
            return .brawlBlue
        }
    }
}

private struct MapEventLane: View {
    let title: String
    let detail: String
    let emptyText: String
    let events: [CurrentMapEvent]
    let phase: MapEventPhase
    let now: Date
    let language: AppLanguage
    let onSelect: (CurrentMapEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.black)
                    .foregroundStyle(.white)

                Text("\(events.count)")
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundStyle(.black.opacity(0.78))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(phase.tint, in: Capsule())

                Spacer(minLength: 8)

                Text(detail)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.40))
                    .lineLimit(1)
            }

            if events.isEmpty {
                EmptyState(emptyText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(events) { event in
                            Button {
                                onSelect(event)
                            } label: {
                                ActiveMapCard(event: event, now: now, phase: phase, language: language)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }
}

private struct ActiveMapCard: View {
    @Environment(\.compactLayout) private var compact
    let event: CurrentMapEvent
    let now: Date
    let phase: MapEventPhase
    let language: AppLanguage

    private var accent: Color {
        Color(hexString: event.accentColorHex)
    }

    private var localizedTitle: (primary: String, secondary: String?) {
        event.localizedTitle(for: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            ZStack(alignment: .topLeading) {
                MapPreview(event: event, accent: accent)
                    .frame(height: compact ? 82 : 104)

                HStack(spacing: 5) {
                    Text(phase.title)
                    Text("S\(event.slot)")
                }
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.82))
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(phase.tint, in: Capsule())
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)

                    Text(event.localizedModeName(for: language))
                        .font(.caption)
                        .fontWeight(.black)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Text(localizedTitle.primary)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if !compact {
                    Text(localizedTitle.secondary ?? "")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Text(timeText(from: now))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 12)
        }
        .frame(width: compact ? 154 : 184)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x1B263A), accent.opacity(0.18), Color(hex: 0x111827)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.10), radius: 5, y: 3)
    }

    private func timeText(from now: Date) -> String {
        switch phase {
        case .active:
            guard let endDate = event.endDate else { return language.text("время неизвестно", "time unknown") }
            let remaining = max(0, Int(endDate.timeIntervalSince(now)))
            if remaining == 0 { return language.text("смена скоро", "rotation soon") }
            return language.text("смена через \(formattedDuration(remaining))", "rotates in \(formattedDuration(remaining))")
        case .upcoming:
            guard let startDate = event.startDate else { return language.text("старт неизвестен", "start unknown") }
            let remaining = max(0, Int(startDate.timeIntervalSince(now)))
            if remaining == 0 { return language.text("скоро активна", "active soon") }
            return language.text("старт через \(formattedDuration(remaining))", "starts in \(formattedDuration(remaining))")
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let remaining = max(0, seconds)
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return language.text("\(hours)ч \(minutes)м", "\(hours)h \(minutes)m")
        }
        return language.text("\(minutes)м", "\(minutes)m")
    }
}

private struct MapPreview: View {
    let event: CurrentMapEvent
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.22), .white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let imageURL = event.mapImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .overlay(
                                LinearGradient(
                                    colors: [.clear, Color(hex: 0x111827).opacity(0.75)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                            .tint(accent)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        ZStack {
            accent.opacity(0.10)
            Image(systemName: "map")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(accent)
        }
    }
}

private struct MapDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let event: CurrentMapEvent
    let language: AppLanguage

    private var accent: Color {
        Color(hexString: event.accentColorHex)
    }

    private var localizedTitle: (primary: String, secondary: String?) {
        event.localizedTitle(for: language)
    }

    private var isUpcoming: Bool {
        guard let startDate = event.startDate else { return false }
        return startDate > Date()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        largePreview

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 10, height: 10)

                                Text(event.localizedModeName(for: language))
                                    .font(.subheadline)
                                    .fontWeight(.black)
                                    .foregroundStyle(accent)
                            }

                            Text(localizedTitle.primary)
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .minimumScaleFactor(0.72)

                            if let secondaryTitle = localizedTitle.secondary {
                                Text(secondaryTitle)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white.opacity(0.52))
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                MapInfoTile(title: language.text("Слот", "Slot"), value: "S\(event.slot)", icon: "square.grid.2x2.fill", tint: .brawlYellow)
                                MapInfoTile(title: isUpcoming ? language.text("До старта", "Starts in") : language.text("До смены", "Rotates in"), value: timeRemaining(), icon: "clock.fill", tint: accent)
                                MapInfoTile(title: language.text("Старт", "Start"), value: formattedDate(event.startTime), icon: "play.fill", tint: .brawlGreen)
                                MapInfoTile(title: language.text("Конец", "End"), value: formattedDate(event.endTime), icon: "flag.fill", tint: .brawlRed)
                            }

                            if let url = event.mapPageURL {
                                Button {
                                    openURL(url)
                                } label: {
                                    HStack {
                                        Image(systemName: "safari.fill")
                                        Text(language.text("Открыть на Brawlify", "Open on Brawlify"))
                                            .fontWeight(.black)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                    }
                                    .padding(13)
                                    .foregroundStyle(.black)
                                    .background(Color.brawlYellow, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .background(Color.cardBase.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle(language.text("Карта", "Map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.black)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private var largePreview: some View {
        MapPreview(event: event, accent: accent)
            .frame(height: 290)
            .overlay(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.localizedModeName(for: language))
                        .font(.caption)
                        .fontWeight(.black)
                        .foregroundStyle(accent)

                    Text(localizedTitle.primary)
                        .font(.title2)
                        .fontWeight(.black)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(16)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.28), lineWidth: 1)
            )
    }

    private func timeRemaining() -> String {
        let targetDate = isUpcoming ? event.startDate : event.endDate
        guard let targetDate else { return "?" }
        let remaining = max(0, Int(targetDate.timeIntervalSince(Date())))
        if remaining == 0 { return language.text("скоро", "soon") }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        return hours > 0
            ? language.text("\(hours)ч \(minutes)м", "\(hours)h \(minutes)m")
            : language.text("\(minutes)м", "\(minutes)m")
    }

    private func formattedDate(_ value: String) -> String {
        guard let date = CurrentMapEvent.date(from: value) else { return "?" }
        return Self.detailFormatter.string(from: date)
    }

    private static let detailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct MapInfoTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .fontWeight(.black)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))

            Text(value)
                .font(.subheadline)
                .fontWeight(.black)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct GoalProgressPanel: View {
    let current: Int
    let target: Int
    let todayDelta: Int
    let language: AppLanguage

    private var remaining: Int {
        max(0, target - current)
    }

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, Double(current) / Double(target)))
    }

    private var progressPercent: Int {
        Int((progress * 100).rounded())
    }

    private var forecastText: String {
        if remaining == 0 {
            return language.text("цель закрыта", "goal complete")
        }
        guard todayDelta > 0 else {
            return language.text("нужен плюс за день", "need a positive day")
        }
        let days = max(1, Int(ceil(Double(remaining) / Double(todayDelta))))
        if days == 1 {
            return language.text("можно закрыть сегодня", "can finish today")
        }
        return language.text("~\(days) дн. при текущем темпе", "~\(days)d at current pace")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(current.formatted()) / \(target.formatted())")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(forecastText)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                Spacer()

                Text("\(progressPercent)%")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(remaining == 0 ? Color.brawlGreen : Color.brawlYellow)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: remaining == 0 ? [.brawlGreen, .brawlBlue] : [.brawlYellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, proxy.size.width * progress))
                }
            }
            .frame(height: 13)

            HStack(spacing: 8) {
                GoalMiniStat(title: language.text("Осталось", "Left"), value: remaining == 0 ? "0" : remaining.formatted(), tint: remaining == 0 ? .brawlGreen : .brawlYellow)
                GoalMiniStat(title: language.text("Сегодня", "Today"), value: todayDelta > 0 ? "+\(todayDelta)" : "\(todayDelta)", tint: todayDelta >= 0 ? .brawlGreen : .brawlRed)
                GoalMiniStat(title: language.text("Цель", "Goal"), value: target.formatted(), tint: .brawlBlue)
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.08), .brawlYellow.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct GoalMiniStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.black)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct GoalQuickButton: View {
    let title: String
    let value: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(value.formatted())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TrophyTrendChart: View {
    let snapshots: [PlayerSnapshot]

    private var trophies: [Int] {
        snapshots.map(\.profile.trophies)
    }

    private var minValue: Int {
        trophies.min() ?? 0
    }

    private var maxValue: Int {
        trophies.max() ?? 1
    }

    private var range: Int {
        max(1, maxValue - minValue)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let chartRect = CGRect(x: 42, y: 14, width: max(1, size.width - 54), height: max(1, size.height - 42))
            let points = chartPoints(in: chartRect)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.045))

                chartGrid(in: chartRect)

                if points.count > 1 {
                    areaPath(points: points, chartRect: chartRect)
                        .fill(
                            LinearGradient(
                                colors: [.brawlGreen.opacity(0.34), .brawlBlue.opacity(0.10), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(points: points)
                        .stroke(
                            LinearGradient(colors: [.brawlGreen, .brawlBlue], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )

                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        if shouldShowMarker(index: index, count: points.count) {
                            Circle()
                                .fill(Color(hex: 0x101827))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.brawlYellow, lineWidth: 2))
                                .position(point)
                        }
                    }
                }

                chartLabels(in: chartRect)
            }
        }
    }

    @ViewBuilder
    private func chartGrid(in rect: CGRect) -> some View {
        ForEach(0..<4, id: \.self) { index in
            let y = rect.minY + rect.height * CGFloat(index) / 3
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            .stroke(.white.opacity(index == 3 ? 0.12 : 0.07), style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
        }
    }

    @ViewBuilder
    private func chartLabels(in rect: CGRect) -> some View {
        Text(maxValue.formatted())
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white.opacity(0.48))
            .position(x: 20, y: rect.minY + 4)

        Text(minValue.formatted())
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white.opacity(0.48))
            .position(x: 20, y: rect.maxY - 4)

        if let first = snapshots.first, let last = snapshots.last {
            Text(Self.timeFormatter.string(from: first.capturedAt))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.40))
                .position(x: rect.minX + 16, y: rect.maxY + 18)

            Text(Self.timeFormatter.string(from: last.capturedAt))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.40))
                .position(x: rect.maxX - 16, y: rect.maxY + 18)
        }
    }

    private func chartPoints(in rect: CGRect) -> [CGPoint] {
        guard trophies.count > 1 else { return [] }
        return trophies.enumerated().map { index, value in
            let xProgress = CGFloat(index) / CGFloat(max(1, trophies.count - 1))
            let yProgress = CGFloat(value - minValue) / CGFloat(range)
            return CGPoint(
                x: rect.minX + rect.width * xProgress,
                y: rect.maxY - rect.height * yProgress
            )
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(points: [CGPoint], chartRect: CGRect) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: chartRect.maxY))
            path.addLine(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: chartRect.maxY))
            path.closeSubpath()
        }
    }

    private func shouldShowMarker(index: Int, count: Int) -> Bool {
        index == 0 || index == count - 1 || count <= 8 || index.isMultiple(of: max(1, count / 5))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct DailyDeltaStrip: View {
    let history: [(day: Date, delta: Int)]
    let language: AppLanguage

    var body: some View {
        if history.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(language.text("Дневная дельта", "Daily delta"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.62))

                    Spacer()

                    Text(language.text("по дням", "by day"))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.38))
                }

                let maxAbs = max(1, history.map { abs($0.delta) }.max() ?? 1)
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(history, id: \.day) { item in
                        VStack(spacing: 5) {
                            ZStack(alignment: item.delta >= 0 ? .bottom : .top) {
                                Capsule()
                                    .fill(.white.opacity(0.06))
                                    .frame(width: 10, height: 54)

                                Capsule()
                                    .fill(item.delta >= 0 ? Color.brawlGreen : Color.brawlRed)
                                    .frame(width: 10, height: max(6, CGFloat(abs(item.delta)) / CGFloat(maxAbs) * 54))
                            }

                            Text(deltaText(item.delta))
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(item.delta >= 0 ? Color.brawlGreen : Color.brawlRed)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func deltaText(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

private struct ProgressCalendarGrid: View {
    let history: [(day: Date, delta: Int)]
    let language: AppLanguage

    private var maxAbs: Int {
        max(1, history.map { abs($0.delta) }.max() ?? 1)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(history, id: \.day) { item in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color(for: item.delta).opacity(opacity(for: item.delta)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(color(for: item.delta).opacity(0.22), lineWidth: 1)
                        )
                        .frame(height: 32)
                        .overlay {
                            Text(dayFormatter.string(from: item.day))
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(.white.opacity(0.78))
                        }

                    Text(deltaText(item.delta))
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(color(for: item.delta))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(language.text("Календарь прогресса", "Progress calendar"))
    }

    private func color(for value: Int) -> Color {
        if value > 0 { return .brawlGreen }
        if value < 0 { return .brawlRed }
        return .white.opacity(0.55)
    }

    private func opacity(for value: Int) -> Double {
        value == 0 ? 0.12 : max(0.26, min(0.88, Double(abs(value)) / Double(maxAbs)))
    }

    private func deltaText(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd"
        return formatter
    }
}

private struct TierRow: View {
    let tier: PersonalTier
    let brawlers: [Brawler]
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Text(tier.rawValue)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.82))
                .frame(width: 34, height: 34)
                .background(tier.tint, in: RoundedRectangle(cornerRadius: 8))

            if brawlers.isEmpty {
                Text(language.text("пока пусто", "empty for now"))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(brawlers) { brawler in
                            VStack(spacing: 4) {
                                BrawlerBadge(name: brawler.name, id: brawler.id, tint: tier.tint, size: 36)
                                Text(brawler.name)
                                    .font(.system(size: 8, weight: .black, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .lineLimit(1)
                                    .frame(width: 46)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(tier.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HistoryBar: View {
    let item: (day: Date, delta: Int)
    let maxAbs: Int

    var body: some View {
        GeometryReader { proxy in
            let halfHeight = proxy.size.height / 2
            let availableHeight = max(8, halfHeight - 10)
            let barHeight = item.delta == 0 ? 6 : max(8, CGFloat(abs(item.delta)) / CGFloat(maxAbs) * availableHeight)

            Capsule()
                .fill(deltaGradient)
                .frame(width: 18, height: barHeight)
                .position(
                    x: proxy.size.width / 2,
                    y: item.delta >= 0 ? halfHeight - barHeight / 2 : halfHeight + barHeight / 2
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var deltaGradient: LinearGradient {
        let color: Color = item.delta >= 0 ? .brawlGreen : .brawlRed
        return LinearGradient(colors: [color, color.opacity(0.45)], startPoint: .top, endPoint: .bottom)
    }
}

private struct InfoText: View {
    @Environment(\.compactLayout) private var compact
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if !compact {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BattleLogRow: View {
    let entry: BattleLogEntry
    let language: AppLanguage

    private var intervalText: String {
        "\(Self.timeFormatter.string(from: entry.startedAt)) - \(Self.timeFormatter.string(from: entry.endedAt))"
    }

    private var changedPreview: String {
        let names = entry.changedBrawlers.prefix(3).map(\.name)
        guard !names.isEmpty else { return language.text("без изменений по бравлерам", "no brawler changes") }
        return names.joined(separator: ", ")
    }

    private var lossDetail: String {
        entry.lossEstimateIsHidden ? language.text("скр -\(entry.hiddenLostTrophies)", "hidden -\(entry.hiddenLostTrophies)") : "-\(entry.visibleLostTrophies)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: entry.isPositive ? "checkmark.circle.fill" : "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(entry.isPositive ? Color.brawlGreen : Color.brawlRed)
                    .frame(width: 30, height: 30)
                    .background((entry.isPositive ? Color.brawlGreen : Color.brawlRed).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(intervalText)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text(changedPreview)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                DeltaCapsule(value: entry.trophyDelta)
            }

            HStack(spacing: 8) {
                BattleStatPill(title: language.text("Победы", "Wins"), value: "+\(entry.victoryDelta.total)", tint: .brawlGreen)
                BattleStatPill(title: "3v3", value: "\(entry.victoryDelta.threeVsThree)", tint: .brawlBlue)
                BattleStatPill(title: "Solo", value: "\(entry.victoryDelta.solo)", tint: .brawlPink)
                BattleStatPill(title: "Duo", value: "\(entry.victoryDelta.duo)", tint: .brawlPurple)
                BattleStatPill(title: language.text("Пораж.", "Losses"), value: "~\(entry.estimatedLosses)", detail: lossDetail, tint: entry.estimatedLosses > 0 ? .brawlRed : .white.opacity(0.7))
            }
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct BattleStatPill: View {
    let title: String
    let value: String
    var detail: String? = nil
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.black)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let detail {
                Text(detail)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct PushSuggestionRow: View {
    let suggestion: PushSuggestion
    let language: AppLanguage

    private var tint: Color {
        Color(hex: suggestion.tintHex)
    }

    private var progress: Double {
        let previousMilestone = max(0, suggestion.targetTrophies - milestoneSpan)
        let gained = max(0, suggestion.brawler.trophies - previousMilestone)
        return min(1, Double(gained) / Double(milestoneSpan))
    }

    private var milestoneSpan: Int {
        if suggestion.targetTrophies <= 500 { return 50 }
        if suggestion.targetTrophies <= 1_000 { return 100 }
        return 250
    }

    var body: some View {
        HStack(spacing: 12) {
            BrawlerBadge(name: suggestion.brawler.name, id: suggestion.brawler.id, tint: tint)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(suggestion.brawler.name)
                        .font(.subheadline)
                        .fontWeight(.black)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(suggestion.reason)
                        .font(.caption2)
                        .fontWeight(.black)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.13), in: Capsule())

                    Spacer(minLength: 0)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.08))

                        Capsule()
                            .fill(LinearGradient(colors: [tint, tint.opacity(0.48)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, proxy.size.width * progress))
                    }
                }
                .frame(height: 7)
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text("+\(suggestion.neededTrophies)")
                    .font(.subheadline)
                    .fontWeight(.black)
                    .foregroundStyle(tint)

                Text(language.text("до \(suggestion.targetTrophies)", "to \(suggestion.targetTrophies)"))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BrawlerGoalRow: View {
    @Environment(\.compactLayout) private var compact
    let brawler: Brawler
    let target: Int
    let isFavorite: Bool
    let language: AppLanguage
    let onToggleFavorite: () -> Void
    let onSetGoal: (Int) -> Void

    private var remaining: Int {
        max(0, target - brawler.trophies)
    }

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(brawler.trophies) / Double(target))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            HStack(spacing: compact ? 8 : 10) {
                BrawlerBadge(name: brawler.name, id: brawler.id, tint: .brawlYellow, size: compact ? 34 : 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(brawler.name)
                        .font(.subheadline)
                        .fontWeight(.black)
                        .foregroundStyle(.white)
                    Text(language.text("цель \(target.formatted()) · осталось \(remaining.formatted())", "target \(target.formatted()) · left \(remaining.formatted())"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.50))
                }

                Spacer()

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "pin.fill" : "pin")
                        .font(.subheadline)
                        .fontWeight(.black)
                        .foregroundStyle(isFavorite ? Color.brawlYellow : .white.opacity(0.52))
                }
                .buttonStyle(.plain)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.brawlYellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, proxy.size.width * progress))
                }
            }
            .frame(height: compact ? 6 : 8)

            if !compact {
                HStack(spacing: 8) {
                    GoalAdjustButton(title: "-50") { onSetGoal(max(0, target - 50)) }
                    GoalAdjustButton(title: "+50") { onSetGoal(target + 50) }
                    GoalAdjustButton(title: "+100") { onSetGoal(target + 100) }
                }
            }
        }
        .padding(compact ? 8 : 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct GoalAdjustButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2)
                .fontWeight(.black)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct UpgradeRow: View {
    @Environment(\.compactLayout) private var compact
    let brawler: Brawler
    let language: AppLanguage

    private var missing: [String] {
        var values: [String] = []
        if brawler.power < 11 { values.append("P\(brawler.power)->11") }
        if brawler.gears.count < 2 { values.append(language.text("gears \(brawler.gears.count)/2", "gears \(brawler.gears.count)/2")) }
        if brawler.starPowers.count < 2 { values.append(language.text("пассивки \(brawler.starPowers.count)/2", "SP \(brawler.starPowers.count)/2")) }
        if brawler.gadgets.count < 2 { values.append(language.text("гаджеты \(brawler.gadgets.count)/2", "gadgets \(brawler.gadgets.count)/2")) }
        if brawler.hyperCharges.isEmpty { values.append("hyper") }
        return values
    }

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            BrawlerBadge(name: brawler.name, id: brawler.id, tint: .brawlBlue, size: compact ? 34 : 42)
            VStack(alignment: .leading, spacing: 5) {
                Text(brawler.name)
                    .font(.subheadline)
                    .fontWeight(.black)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(missing.joined(separator: " · "))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
            }
            Spacer()
            Text(brawler.trophies.formatted())
                .font(.caption)
                .fontWeight(.black)
                .foregroundStyle(Color.brawlYellow)
        }
        .padding(compact ? 8 : 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct QualityScorePanel: View {
    let quality: AccountQuality
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(quality.score)")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(scoreColor)
                Text("/100")
                    .font(.headline)
                    .fontWeight(.black)
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                Text(language.text(scoreLabelRu, scoreLabelEn))
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundStyle(scoreColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(scoreColor.opacity(0.12), in: Capsule())
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [scoreColor, .brawlBlue], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * CGFloat(quality.score) / 100)
                    }
            }
            .frame(height: 12)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                QualityMiniStat(title: "Power 11", value: "\(quality.power11)/\(quality.total)", tint: .brawlGreen)
                QualityMiniStat(title: "Hyper", value: "\(quality.hyper)/\(quality.total)", tint: .brawlPurple)
                QualityMiniStat(title: "Gears 2", value: "\(quality.completeGear)/\(quality.total)", tint: .brawlBlue)
                QualityMiniStat(title: language.text("Рубежи", "Milestones"), value: "\(quality.closeMilestones)", tint: .brawlYellow)
            }
        }
    }

    private var scoreColor: Color {
        if quality.score >= 80 { return .brawlGreen }
        if quality.score >= 55 { return .brawlYellow }
        return .brawlRed
    }

    private var scoreLabelRu: String {
        if quality.score >= 80 { return "готов к пушу" }
        if quality.score >= 55 { return "нужно докачать" }
        return "много пробелов"
    }

    private var scoreLabelEn: String {
        if quality.score >= 80 { return "push ready" }
        if quality.score >= 55 { return "upgrade needed" }
        return "many gaps"
    }
}

private struct QualityMiniStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.black)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.44))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProfileStat: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    init(_ title: String, value: String, icon: String, tint: Color) {
        self.title = title
        self.value = value
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.black)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BrawlerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let brawler: Brawler
    let snapshots: [PlayerSnapshot]
    let recentChanges: [BrawlerDelta]
    let targetGoal: Int?
    let isFavorite: Bool
    let language: AppLanguage

    private var history: [(date: Date, trophies: Int)] {
        snapshots.compactMap { snapshot in
            guard let match = snapshot.profile.brawlers.first(where: { $0.id == brawler.id }) else { return nil }
            return (snapshot.capturedAt, match.trophies)
        }
    }

    private var latestDelta: Int? {
        recentChanges.first(where: { $0.id == brawler.id })?.delta
    }

    private var activeBoosts: [(String, Color)] {
        guard let buffies = brawler.buffies else { return [] }
        var result: [(String, Color)] = []
        if buffies.starPower { result.append((language.text("пассивка", "star power"), .brawlYellow)) }
        if buffies.gadget { result.append((language.text("гаджет", "gadget"), .brawlGreen)) }
        if buffies.hyperCharge { result.append((language.text("гипер", "hyper"), .brawlPurple)) }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        hero
                        stats
                        chart
                        loadout
                    }
                    .padding(16)
                }
            }
            .navigationTitle(brawler.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.black)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            BrawlerBadge(name: brawler.name, id: brawler.id, tint: .brawlYellow, size: 96)

            VStack(alignment: .leading, spacing: 8) {
                Text(brawler.name)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if let skin = brawler.skin {
                    Text(skin.name.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    BrawlerTinyChip(text: "P\(brawler.power)", tint: .brawlBlue)
                    BrawlerTinyChip(text: language.text("ранг \(brawler.rank)", "rank \(brawler.rank)"), tint: .brawlYellow)
                    if isFavorite {
                        BrawlerTinyChip(text: language.text("избранное", "favorite"), tint: .orange)
                    }
                    if let latestDelta {
                        BrawlerTinyChip(text: latestDelta > 0 ? "+\(latestDelta)" : "\(latestDelta)", tint: latestDelta >= 0 ? .brawlGreen : .brawlRed)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.cardBase.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MapInfoTile(title: language.text("Кубки", "Trophies"), value: brawler.trophies.formatted(), icon: "trophy.fill", tint: .brawlYellow)
            MapInfoTile(title: language.text("Рекорд", "Best"), value: brawler.highestTrophies.formatted(), icon: "crown.fill", tint: .orange)
            MapInfoTile(title: "Win streak", value: "\(brawler.winStreak ?? 0)", icon: "flame.fill", tint: .brawlGreen)
            MapInfoTile(title: targetGoal == nil ? "Mastery" : language.text("До цели", "Goal left"), value: targetGoal.map { max(0, $0 - brawler.trophies).formatted() } ?? "\(brawler.mastery ?? 0)", icon: targetGoal == nil ? "sparkles" : "target", tint: .brawlPurple)
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(language.text("График бравлера", "Brawler Chart"), detail: language.text("по снимкам", "by snapshots"), icon: "chart.xyaxis.line")
            if history.count < 2 {
                EmptyState(language.text("График появится после двух снимков этого бравлера.", "Chart appears after two snapshots for this brawler."))
            } else {
                BrawlerTrophyChart(points: history)
                    .frame(height: 160)
            }
        }
        .padding(16)
        .background(Color.cardBase.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
    }

    private var loadout: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Loadout", detail: language.text("что есть", "owned"), icon: "shippingbox.fill")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                BrawlerLoadoutChip(title: language.text("Пассивки", "Star powers"), value: "\(brawler.starPowers.count)/2", icon: "star.circle.fill", tint: .brawlYellow)
                BrawlerLoadoutChip(title: language.text("Гаджеты", "Gadgets"), value: "\(brawler.gadgets.count)/2", icon: "bolt.circle.fill", tint: .brawlGreen)
                BrawlerLoadoutChip(title: "Gears", value: "\(brawler.gears.count)", icon: "gearshape.fill", tint: .brawlBlue)
                BrawlerLoadoutChip(title: "Hyper", value: "\(brawler.hyperCharges.count)", icon: "flame.circle.fill", tint: .brawlPurple)
            }

            LoadoutList(title: language.text("Пассивки", "Star powers"), items: brawler.starPowers, tint: .brawlYellow, emptyText: language.text("нет пассивок", "no star powers"))
            LoadoutList(title: language.text("Гаджеты", "Gadgets"), items: brawler.gadgets, tint: .brawlGreen, emptyText: language.text("нет гаджетов", "no gadgets"))
            LoadoutList(title: "Gears", items: brawler.gears, tint: .brawlBlue, emptyText: language.text("нет gears", "no gears"))
            LoadoutList(title: "Hyper", items: brawler.hyperCharges, tint: .brawlPurple, emptyText: language.text("нет hypercharge", "no hypercharge"))

            if !activeBoosts.isEmpty {
                HStack(spacing: 6) {
                    Text(language.text("Активно:", "Active:"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.48))
                    ForEach(Array(activeBoosts.enumerated()), id: \.offset) { _, boost in
                        BrawlerTinyChip(text: boost.0, tint: boost.1)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.cardBase.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BrawlerTrophyChart: View {
    let points: [(date: Date, trophies: Int)]

    private var minValue: Int { points.map(\.trophies).min() ?? 0 }
    private var maxValue: Int { points.map(\.trophies).max() ?? 1 }
    private var range: Int { max(1, maxValue - minValue) }

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(x: 12, y: 12, width: proxy.size.width - 24, height: proxy.size.height - 32)
            let chartPoints = points.enumerated().map { index, point in
                let x = rect.minX + rect.width * CGFloat(index) / CGFloat(max(1, points.count - 1))
                let y = rect.maxY - rect.height * CGFloat(point.trophies - minValue) / CGFloat(range)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.04))

                Path { path in
                    guard let first = chartPoints.first else { return }
                    path.move(to: first)
                    chartPoints.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(LinearGradient(colors: [.brawlYellow, .brawlBlue], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                ForEach(Array(chartPoints.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.cardBase)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.brawlYellow, lineWidth: 2))
                        .position(point)
                }

                Text(maxValue.formatted())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.48))
                    .position(x: 32, y: rect.minY + 4)

                Text(minValue.formatted())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.48))
                    .position(x: 32, y: rect.maxY - 4)
            }
        }
    }
}

private struct LoadoutList: View {
    let title: String
    let items: [BrawlerLoadoutItem]
    let tint: Color
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.black)
                .foregroundStyle(tint)

            if items.isEmpty {
                Text(emptyText)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.36))
            } else {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tint)
                            .frame(width: 6, height: 6)
                        Text(item.level.map { "\(item.name) L\($0)" } ?? item.name)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BrawlerDeltaRow: View {
    let change: BrawlerDelta
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            BrawlerBadge(name: change.name, id: change.id, tint: change.delta > 0 ? .brawlGreen : .brawlRed)

            VStack(alignment: .leading, spacing: 4) {
                Text(change.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(language.text("\(change.previousTrophies) -> \(change.currentTrophies) · сила \(change.power)", "\(change.previousTrophies) -> \(change.currentTrophies) · power \(change.power)"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer()

            DeltaCapsule(value: change.delta)
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BrawlerRow: View {
    @Environment(\.compactLayout) private var compact
    let index: Int
    let brawler: Brawler
    let maxTrophies: Int
    let language: AppLanguage

    private var progress: Double {
        min(1, Double(brawler.trophies) / Double(maxTrophies))
    }

    private var activeBoosts: [(String, Color)] {
        guard let buffies = brawler.buffies else { return [] }
        var boosts: [(String, Color)] = []
        if buffies.starPower {
            boosts.append((language.text("пассивка", "star power"), .brawlYellow))
        }
        if buffies.gadget {
            boosts.append((language.text("гаджет", "gadget"), .brawlGreen))
        }
        if buffies.hyperCharge {
            boosts.append((language.text("гипер", "hyper"), .brawlPurple))
        }
        return boosts
    }

    var body: some View {
        if compact {
            compactBody
        } else {
            regularBody
        }
    }

    private var compactBody: some View {
        HStack(spacing: 9) {
            BrawlerBadge(name: brawler.name, id: brawler.id, tint: .brawlYellow, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(brawler.name)
                        .font(.subheadline)
                        .fontWeight(.black)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    BrawlerTinyChip(text: "P\(brawler.power)", tint: .brawlBlue)

                    if favoriteMarker {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.brawlYellow)
                    }
                }

                HStack(spacing: 5) {
                    BrawlerTinyChip(text: language.text("р\(brawler.rank)", "r\(brawler.rank)"), tint: .brawlYellow)
                    BrawlerTinyChip(text: "SP \(brawler.starPowers.count)", tint: .brawlYellow)
                    BrawlerTinyChip(text: "G \(brawler.gears.count)", tint: .brawlBlue)
                    BrawlerTinyChip(text: brawler.hyperCharges.isEmpty ? "H 0" : "H 1", tint: .brawlPurple)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(brawler.trophies.formatted())
                    .font(.subheadline)
                    .fontWeight(.black)
                    .foregroundStyle(Color.brawlYellow)
                if let winStreak = brawler.winStreak, winStreak > 0 {
                    Text("WS \(winStreak)")
                        .font(.caption2)
                        .fontWeight(.black)
                        .foregroundStyle(Color.brawlGreen)
                }
            }
        }
        .padding(8)
        .background(
            LinearGradient(
                colors: [.surfaceRaised.opacity(0.74), .cardBase.opacity(0.48)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var regularBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    BrawlerBadge(name: brawler.name, id: brawler.id, tint: .brawlYellow, size: 58)

                    Text("\(index)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.black.opacity(0.82))
                        .frame(width: 20, height: 20)
                        .background(Color.brawlYellow, in: RoundedRectangle(cornerRadius: 6))
                        .offset(x: -5, y: -5)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(brawler.name)
                            .font(.subheadline)
                            .fontWeight(.black)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        BrawlerTinyChip(text: "P\(brawler.power)", tint: .brawlBlue)

                        if let winStreak = brawler.winStreak, winStreak > 0 {
                            BrawlerTinyChip(text: "WS \(winStreak)", tint: .brawlGreen)
                        }

                        Spacer(minLength: 0)
                    }

                    if let skin = brawler.skin {
                        Text(skin.name.replacingOccurrences(of: "\n", with: " "))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white.opacity(0.40))
                            .lineLimit(1)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.08))

                            Capsule()
                                .fill(LinearGradient(colors: [.brawlBlue, .brawlPurple], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, proxy.size.width * progress))
                        }
                    }
                    .frame(height: 6)
                }

                VStack(alignment: .trailing, spacing: 4) {
                    Text(brawler.trophies.formatted())
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Color.brawlYellow)
                        .lineLimit(1)

                    Text(language.text("кубков", "trophies"))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.46))

                    Text(language.text("ранг \(brawler.rank)", "rank \(brawler.rank)"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(width: 76, alignment: .trailing)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                BrawlerLoadoutChip(title: language.text("Пассивки", "Star powers"), value: "\(brawler.starPowers.count)/2", icon: "star.circle.fill", tint: .brawlYellow)
                BrawlerLoadoutChip(title: language.text("Гаджеты", "Gadgets"), value: "\(brawler.gadgets.count)/2", icon: "bolt.circle.fill", tint: .brawlGreen)
                BrawlerLoadoutChip(title: "Gears", value: "\(brawler.gears.count)", icon: "gearshape.fill", tint: .brawlBlue)
                BrawlerLoadoutChip(title: "Hyper", value: brawler.hyperCharges.isEmpty ? "0" : "\(brawler.hyperCharges.count)", icon: "flame.circle.fill", tint: .brawlPurple)
            }

            if activeBoosts.isEmpty {
                Text(language.text("активные усиления не отмечены", "no active boosts marked"))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    Text(language.text("Активно:", "Active:"))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.42))

                    ForEach(Array(activeBoosts.enumerated()), id: \.offset) { _, boost in
                        BrawlerTinyChip(text: boost.0, tint: boost.1)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(11)
        .background(
            LinearGradient(
                colors: [.surfaceRaised.opacity(0.72), .cardBase.opacity(0.52)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var favoriteMarker: Bool {
        false
    }
}

private struct BrawlerBadge: View {
    let name: String
    let id: Int?
    let tint: Color
    var size: CGFloat = 36

    private var imageURL: URL? {
        guard let id else { return nil }
        return URL(string: "https://cdn.brawlify.com/brawlers/borderless/\(id).png")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.22), .white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(size > 40 ? 2 : 3)
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .tint(tint)
                            .scaleEffect(size > 40 ? 0.8 : 0.55)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.10), radius: 8, y: 3)
    }

    private var fallback: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: max(16, size * 0.42), weight: .black, design: .rounded))
            .foregroundStyle(tint)
    }
}

private struct BrawlerLoadoutChip: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .fontWeight(.black)
                .foregroundStyle(tint)

            Text(value)
                .font(.caption)
                .fontWeight(.black)
                .foregroundStyle(.white)

            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(0.16), lineWidth: 0.8)
        )
    }
}

private struct BrawlerTinyChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.black)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 0.8)
            )
    }
}

private struct DeltaCapsule: View {
    let value: Int

    var body: some View {
        Text(value > 0 ? "+\(value)" : "\(value)")
            .font(.subheadline)
            .fontWeight(.black)
            .foregroundStyle(value >= 0 ? Color.brawlGreen : Color.brawlRed)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((value >= 0 ? Color.brawlGreen : Color.brawlRed).opacity(0.10), in: Capsule())
            .overlay(
                Capsule()
                    .stroke((value >= 0 ? Color.brawlGreen : Color.brawlRed).opacity(0.24), lineWidth: 0.8)
            )
    }
}

private struct EmptyState: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.56))
            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension Color {
    static let cardBase = Color(hex: 0x172033)
    static let surfaceDeep = Color(hex: 0x0B111D)
    static let surfaceRaised = Color(hex: 0x151E2E)
    static let brawlYellow = Color(hex: 0xFFD34D)
    static let brawlBlue = Color(hex: 0x52B6FF)
    static let brawlGreen = Color(hex: 0x48D889)
    static let brawlRed = Color(hex: 0xFF5F72)
    static let brawlPink = Color(hex: 0xFF72AE)
    static let brawlPurple = Color(hex: 0x9B83FF)

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt(cleaned, radix: 16) ?? 0xFFD34D
        self.init(hex: value)
    }
}
