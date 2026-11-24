import Foundation
import Combine

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published public var snapshot: AntigravityUsageSnapshot
    @Published public var displayMode: WidgetDisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "displayMode_v3")
            onWindowConfigChanged?()
        }
    }
    /// False = Wide 1x4 iOS widget, True = Square 2x2 iOS widget
    @Published public var isCompactMode: Bool {
        didSet {
            UserDefaults.standard.set(isCompactMode, forKey: "isCompactMode_v3")
            onWindowConfigChanged?()
        }
    }
    @Published public var isDesktopPositionLocked: Bool {
        didSet {
            UserDefaults.standard.set(isDesktopPositionLocked, forKey: "isDesktopPositionLocked_v3")
            onWindowConfigChanged?()
        }
    }
    @Published public var windowOpacity: Double {
        didSet {
            UserDefaults.standard.set(windowOpacity, forKey: "windowOpacity")
            onWindowConfigChanged?()
        }
    }
    @Published public var refreshIntervalSeconds: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: "refreshIntervalSeconds")
            restartTimer()
        }
    }
    @Published public var hiddenGroupIds: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenGroupIds), forKey: "hiddenGroupIds_v1")
            onWindowConfigChanged?()
        }
    }
    @Published public var enabledProviders: Set<QuotaProviderID> {
        didSet {
            UserDefaults.standard.set(enabledProviders.map(\.rawValue), forKey: "enabledProviders_v1")
            onWindowConfigChanged?()
        }
    }
    @Published public var activeProviderFilter: String {
        didSet {
            UserDefaults.standard.set(activeProviderFilter, forKey: "activeProviderFilter_v1")
            onWindowConfigChanged?()
        }
    }
    @Published public var providerStatuses: [QuotaProviderID: ProviderStatusInfo] = [:]
    @Published public var isRefreshing: Bool = false
    @Published public var isWidgetHovered: Bool = false
    @Published public var hoveredCardId: String? = nil

    public var orderedEnabledProviders: [QuotaProviderID] {
        QuotaProviderID.allCases.filter { enabledProviders.contains($0) }
    }

    public var visibleQuotaGroups: [QuotaGroup] {
        snapshot.quotaGroups.filter { group in
            guard !hiddenGroupIds.contains(group.id) else { return false }
            guard let pid = QuotaProviderID(rawValue: group.providerId),
                  enabledProviders.contains(pid) else { return false }
            if activeProviderFilter != "all" && group.providerId != activeProviderFilter {
                return false
            }
            return true
        }
    }

    public var visibleStatusCards: [ProviderStatusInfo] {
        orderedEnabledProviders.compactMap { pid in
            if activeProviderFilter != "all" && pid.rawValue != activeProviderFilter {
                return nil
            }
            guard let status = providerStatuses[pid], status.state != .connected else { return nil }
            let hasLiveCards = visibleQuotaGroups.contains { $0.providerId == pid.rawValue }
            if hasLiveCards && status.state != .rateLimited { return nil }
            if status.state == .authRequired || status.state == .rateLimited || activeProviderFilter == pid.rawValue {
                return status
            }
            return nil
        }
    }

    public func isGroupVisible(_ groupId: String) -> Bool {
        groupId.isEmpty || !hiddenGroupIds.contains(groupId)
    }

    public func isRingItemVisible(_ item: QuotaRingItem) -> Bool {
        guard isGroupVisible(item.groupId) else { return false }
        guard let pid = QuotaProviderID(rawValue: item.providerId),
              enabledProviders.contains(pid) else { return false }
        if activeProviderFilter != "all" && item.providerId != activeProviderFilter {
            return false
        }
        return true
    }

    public func toggleProvider(_ provider: QuotaProviderID) {
        if enabledProviders.contains(provider) {
            guard enabledProviders.count > 1 else { return }
            enabledProviders.remove(provider)
            if activeProviderFilter == provider.rawValue {
                activeProviderFilter = "all"
            }
        } else {
            enabledProviders.insert(provider)
        }
        Task { await refreshNow(forceExternal: true) }
    }

    public func setProviderFilter(_ filter: String) {
        activeProviderFilter = filter
    }

    public func toggleGroupVisibility(_ groupId: String) {
        if hiddenGroupIds.contains(groupId) {
            hiddenGroupIds.remove(groupId)
        } else {
            hiddenGroupIds.insert(groupId)
        }
    }

    public func showAllGroups() {
        hiddenGroupIds.removeAll()
    }

    public var onWindowConfigChanged: (() -> Void)?

    private let quotaFetcher = LanguageServerQuotaFetcher()
    private let claudeFetcher = ClaudeCodeQuotaFetcher()
    private let codexFetcher = CodexQuotaFetcher()
    private let transcriptAggregator = TranscriptUsageAggregator()
    private var refreshTimer: Timer?
    private var externalCache: [QuotaProviderID: (groups: [QuotaGroup], status: ProviderStatusInfo, nextAllowedAt: Date)] = [:]

    public init() {
        let savedMode = UserDefaults.standard.string(forKey: "displayMode_v3")
            .flatMap(WidgetDisplayMode.init(rawValue:)) ?? .floatingHUD
        self.displayMode = savedMode
        self.isCompactMode = UserDefaults.standard.bool(forKey: "isCompactMode_v3")
        self.isDesktopPositionLocked = UserDefaults.standard.bool(forKey: "isDesktopPositionLocked_v3")
        let savedOpacity = UserDefaults.standard.double(forKey: "windowOpacity")
        self.windowOpacity = savedOpacity > 0.2 ? savedOpacity : 0.96
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshIntervalSeconds")
        self.refreshIntervalSeconds = savedInterval >= 10 ? savedInterval : 30
        let savedHidden = UserDefaults.standard.stringArray(forKey: "hiddenGroupIds_v1") ?? []
        self.hiddenGroupIds = Set(savedHidden)
        let savedProvidersRaw = UserDefaults.standard.stringArray(forKey: "enabledProviders_v1") ?? [QuotaProviderID.antigravity.rawValue]
        let parsedProviders = Set(savedProvidersRaw.compactMap(QuotaProviderID.init(rawValue:)))
        let initialProviders: Set<QuotaProviderID> = parsedProviders.isEmpty ? [.antigravity] : parsedProviders
        self.enabledProviders = initialProviders
        let savedFilter = UserDefaults.standard.string(forKey: "activeProviderFilter_v1") ?? "all"
        if savedFilter == "all" || (QuotaProviderID(rawValue: savedFilter).map({ initialProviders.contains($0) }) ?? false) {
            self.activeProviderFilter = savedFilter
        } else {
            self.activeProviderFilter = "all"
        }

        if let loaded = SharedSnapshotStorage.load(), !loaded.quotaGroups.isEmpty {
            self.snapshot = loaded
        } else {
            self.snapshot = AntigravityUsageSnapshot(
                quotaGroups: [],
                statusMessage: "Syncing..."
            )
        }

        restartTimer()
        Task {
            await refreshNow()
        }
    }

    public func setSingleMode(_ mode: WidgetDisplayMode) {
        displayMode = mode
    }

    public func restartTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshIntervalSeconds), repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshNow()
            }
        }
    }

    public func refreshNow(forceExternal: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let activeProviders = self.enabledProviders

        let agyTask: Task<[QuotaGroup]?, Never> = Task {
            guard activeProviders.contains(.antigravity) else { return nil }
            return await self.quotaFetcher.fetchLiveQuotaGroups()
        }

        let claudeTask: Task<ExternalProviderFetchResult?, Never> = Task {
            guard activeProviders.contains(.claudeCode) else { return nil }
            if !forceExternal, let cached = await MainActor.run(body: { self.externalCache[.claudeCode] }), now < cached.nextAllowedAt {
                return ExternalProviderFetchResult(groups: cached.groups, status: cached.status)
            }
            return await self.claudeFetcher.fetchLiveQuota()
        }

        let codexTask: Task<ExternalProviderFetchResult?, Never> = Task {
            guard activeProviders.contains(.codex) else { return nil }
            if !forceExternal, let cached = await MainActor.run(body: { self.externalCache[.codex] }), now < cached.nextAllowedAt {
                return ExternalProviderFetchResult(groups: cached.groups, status: cached.status)
            }
            return await self.codexFetcher.fetchLiveQuota()
        }

        let aggregator = self.transcriptAggregator
        let tokenUsageTask = Task.detached(priority: .utility) {
            aggregator.collectUsageSummary()
        }

        let liveAgyGroups = await agyTask.value
        let claudeRes = await claudeTask.value
        let codexRes = await codexTask.value
        let tokenUsage = await tokenUsageTask.value

        var mergedGroups: [QuotaGroup] = []
        var newStatuses: [QuotaProviderID: ProviderStatusInfo] = [:]
        var agyConnected = false

        if activeProviders.contains(.antigravity) {
            if let liveAgyGroups, !liveAgyGroups.isEmpty {
                agyConnected = true
                mergedGroups.append(contentsOf: liveAgyGroups)
                newStatuses[.antigravity] = ProviderStatusInfo(providerId: .antigravity, state: .connected)
            } else {
                let cachedAgy = self.snapshot.quotaGroups.filter { $0.providerId == QuotaProviderID.antigravity.rawValue }
                mergedGroups.append(contentsOf: cachedAgy)
                newStatuses[.antigravity] = ProviderStatusInfo(
                    providerId: .antigravity,
                    state: .disconnected,
                    message: "Waiting for Antigravity live quota..."
                )
            }
        }

        for (pid, res) in [(QuotaProviderID.claudeCode, claudeRes), (QuotaProviderID.codex, codexRes)] {
            guard activeProviders.contains(pid), let res else { continue }
            var groupsToUse = res.groups
            if res.status.state == .rateLimited, groupsToUse.isEmpty, let prev = externalCache[pid], !prev.groups.isEmpty {
                groupsToUse = prev.groups
            }
            let backoff = res.retryAfterSeconds > 0 ? res.retryAfterSeconds : pid.defaultPollInterval
            externalCache[pid] = (groupsToUse, res.status, Date().addingTimeInterval(backoff))
            newStatuses[pid] = res.status
            mergedGroups.append(contentsOf: groupsToUse)
        }

        let prevIds = self.snapshot.quotaGroups.map(\.id)
        let prevStatusCount = self.visibleStatusCards.count
        self.providerStatuses = newStatuses

        let newSnapshot = AntigravityUsageSnapshot(
            timestamp: Date(),
            isLanguageServerConnected: agyConnected || newStatuses.values.contains(where: { $0.state == .connected }),
            quotaGroups: mergedGroups,
            modelQuotas: [],
            tokenUsage: tokenUsage,
            statusMessage: agyConnected ? "Live" : "Synced"
        )
        self.snapshot = newSnapshot
        if !mergedGroups.isEmpty {
            SharedSnapshotStorage.save(newSnapshot)
        }
        if mergedGroups.map(\.id) != prevIds || self.visibleStatusCards.count != prevStatusCount {
            onWindowConfigChanged?()
        }
    }
}
