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
    @Published public var isRefreshing: Bool = false
    @Published public var isWidgetHovered: Bool = false
    @Published public var hoveredCardId: String? = nil

    public var onWindowConfigChanged: (() -> Void)?

    private let quotaFetcher = LanguageServerQuotaFetcher()
    private let transcriptAggregator = TranscriptUsageAggregator()
    private var refreshTimer: Timer?

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

    public func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let liveGroupsTask = quotaFetcher.fetchLiveQuotaGroups()
        let aggregator = self.transcriptAggregator
        async let tokenUsageTask = Task.detached(priority: .utility) {
            aggregator.collectUsageSummary()
        }.value

        let liveGroups = await liveGroupsTask
        let tokenUsage = await tokenUsageTask

        if let liveGroups, !liveGroups.isEmpty {
            let newSnapshot = AntigravityUsageSnapshot(
                timestamp: Date(),
                isLanguageServerConnected: true,
                quotaGroups: liveGroups,
                modelQuotas: [],
                tokenUsage: tokenUsage,
                statusMessage: "Live"
            )
            self.snapshot = newSnapshot
            SharedSnapshotStorage.save(newSnapshot)
        } else if !self.snapshot.quotaGroups.isEmpty {
            var cached = self.snapshot
            cached.timestamp = Date()
            cached.isLanguageServerConnected = false
            cached.tokenUsage = tokenUsage
            cached.statusMessage = "Cached"
            self.snapshot = cached
        }
    }
}
