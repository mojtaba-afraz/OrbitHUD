import SwiftUI
import AppKit
#if canImport(AntigravityUsageCore)
import AntigravityUsageCore
#endif

/// Native macOS translucent glass backdrop (true behind-window wallpaper blur).
struct GlassVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = 24

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.layer?.cornerRadius = cornerRadius
    }
}

/// Reusable inner frosted glass card (Bento tile) with top-left specular border and hover highlight.
struct GlassBentoCard<Content: View>: View {
    let cardId: String
    @ObservedObject var viewModel: UsageViewModel
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 12
    @ViewBuilder let content: () -> Content

    private var isHovered: Bool {
        viewModel.hoveredCardId == cardId
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.10 : 0.06))

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.30 : 0.20),
                                    Color.white.opacity(0.06),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    if hovering {
                        viewModel.hoveredCardId = cardId
                    } else if viewModel.hoveredCardId == cardId {
                        viewModel.hoveredCardId = nil
                    }
                }
            }
    }
}

/// Precision circular progress ring using tabular numerals and semantic status colors.
struct GlassCircularGauge: View {
    let fraction: Double
    var size: CGFloat = 46
    var lineWidth: CGFloat = 4.5
    var showPercentageText: Bool = true
    var fontSize: CGFloat = 13

    private var clamped: Double {
        min(max(fraction, 0.0), 1.0)
    }

    private var percentage: Int {
        Int((clamped * 100.0).rounded())
    }

    static func semanticColor(for fraction: Double) -> Color {
        if fraction <= 0.15 {
            return Color(red: 1.0, green: 0.32, blue: 0.32)
        } else if fraction <= 0.40 {
            return Color(red: 0.98, green: 0.72, blue: 0.22)
        } else {
            return Color(red: 0.24, green: 0.86, blue: 0.58)
        }
    }

    var body: some View {
        let color = Self.semanticColor(for: clamped)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(max(clamped, 0.02)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if showPercentageText {
                HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                    Text("\(percentage)")
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    Text("%")
                        .font(.system(size: fontSize * 0.65, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.60))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Linear glass progress bar with subtle track and crisp fill.
struct GlassProgressBar: View {
    let fraction: Double
    var height: CGFloat = 4.5

    private var clamped: Double {
        min(max(fraction, 0.0), 1.0)
    }

    var body: some View {
        let color = GlassCircularGauge.semanticColor(for: clamped)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: height)

                Capsule()
                    .fill(color)
                    .frame(width: max(geo.size.width * CGFloat(clamped), height), height: height)
            }
        }
        .frame(height: height)
    }
}

/// Shared dynamic layout dimensions and provider colors for UsageWidgetView and WidgetWindowManager.
enum UsageWidgetLayout {
    static func accentColor(for providerId: String) -> Color {
        switch providerId {
        case QuotaProviderID.claudeCode.rawValue:
            return Color(red: 0.91, green: 0.57, blue: 0.42)
        case QuotaProviderID.codex.rawValue:
            return Color(red: 0.22, green: 0.74, blue: 0.97)
        default:
            return Color(red: 0.24, green: 0.86, blue: 0.58)
        }
    }

    static func shortBadge(for providerId: String) -> String {
        QuotaProviderID(rawValue: providerId)?.shortBadge ?? String(providerId.prefix(3)).uppercased()
    }

    @MainActor
    static func targetSize(for viewModel: UsageViewModel) -> CGSize {
        if viewModel.isCompactMode {
            let visibleItems = viewModel.snapshot
                .iosRingItems(relativeTo: viewModel.snapshot.timestamp)
                .filter { viewModel.isRingItemVisible($0) }
            let width: CGFloat
            switch visibleItems.count {
            case 0: width = 264
            case 1...2: width = 252
            case 3: width = 308
            case 4...5: width = 356
            default: width = 416
            }
            return CGSize(width: width, height: 52)
        }

        let tabsExtra: CGFloat = viewModel.enabledProviders.count > 1 ? 32 : 0
        let visibleGroups = viewModel.visibleQuotaGroups
        let statusCards = viewModel.visibleStatusCards

        if visibleGroups.isEmpty && statusCards.isEmpty {
            return CGSize(width: 356, height: 112 + tabsExtra)
        }

        // Outer vertical padding (26) + header (22) + spacing (9)
        var height: CGFloat = 57 + tabsExtra
        for (idx, group) in visibleGroups.enumerated() {
            height += group.buckets.count >= 2 ? 78 : 70
            if idx > 0 { height += 9 }
        }
        for idx in 0..<statusCards.count {
            if !visibleGroups.isEmpty || idx > 0 { height += 9 }
            height += 40
        }
        return CGSize(width: 356, height: min(max(height, 112), 620))
    }
}

/// Segmented glass filter bar shown when 2+ providers are enabled.
struct ProviderFilterBarView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 4) {
            filterTab(id: "all", title: "All", dotColor: nil)
            ForEach(viewModel.orderedEnabledProviders) { provider in
                let st = viewModel.providerStatuses[provider]?.state
                let dotColor: Color = {
                    if st == .authRequired || st == .rateLimited {
                        return Color(red: 0.98, green: 0.72, blue: 0.22)
                    } else if st == .disconnected {
                        return Color.white.opacity(0.32)
                    }
                    return UsageWidgetLayout.accentColor(for: provider.rawValue)
                }()
                filterTab(id: provider.rawValue, title: provider.shortTabName, dotColor: dotColor)
            }
        }
        .padding(2.5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                )
        )
    }

    private func filterTab(id: String, title: String, dotColor: Color?) -> some View {
        let isActive = viewModel.activeProviderFilter == id
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                viewModel.setProviderFilter(id)
            }
        } label: {
            HStack(spacing: 4) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 5, height: 5)
                }
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(isActive ? .white : Color.white.opacity(0.70))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .background(
                Capsule()
                    .fill(isActive ? Color.white.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Shared Glassmorphic Bento Cards View used inside BOTH the Desktop/Floating Widget AND the Menu Bar Popover.
struct QuotaBentoContentListView: View {
    @ObservedObject var viewModel: UsageViewModel
    let cardNamespace: String

    private var showProviderBadge: Bool {
        viewModel.enabledProviders.count > 1 && viewModel.activeProviderFilter == "all"
    }

    var body: some View {
        let now = viewModel.snapshot.timestamp
        let allGroups = viewModel.snapshot.quotaGroups
        let visibleGroups = viewModel.visibleQuotaGroups
        let statusCards = viewModel.visibleStatusCards

        VStack(alignment: .leading, spacing: 9) {
            if allGroups.isEmpty && statusCards.isEmpty {
                emptyStateBento
            } else if visibleGroups.isEmpty && statusCards.isEmpty && !allGroups.isEmpty {
                allHiddenStateBento
            } else {
                ForEach(visibleGroups) { group in
                    if group.buckets.count >= 2 {
                        dualWindowBentoCard(
                            cardId: "\(cardNamespace)-\(group.id)",
                            group: group,
                            now: now
                        )
                    } else {
                        singleWindowBentoCard(
                            cardId: "\(cardNamespace)-\(group.id)",
                            group: group,
                            now: now
                        )
                    }
                }

                ForEach(statusCards, id: \.providerId) { status in
                    providerStatusBentoCard(status: status)
                }
            }
        }
    }

    @ViewBuilder
    private func providerMicroBadge(_ providerId: String) -> some View {
        if showProviderBadge {
            let accent = UsageWidgetLayout.accentColor(for: providerId)
            Text(UsageWidgetLayout.shortBadge(for: providerId))
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundColor(accent)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(accent.opacity(0.14))
                        .overlay(Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 0.6))
                )
        }
    }

    private func providerStatusBentoCard(status: ProviderStatusInfo) -> some View {
        let accent = UsageWidgetLayout.accentColor(for: status.providerId.rawValue)
        let dotColor: Color = (status.state == .authRequired || status.state == .rateLimited)
            ? Color(red: 0.98, green: 0.72, blue: 0.22)
            : Color.white.opacity(0.35)

        return GlassBentoCard(cardId: "\(cardNamespace)-status-\(status.providerId.rawValue)", viewModel: viewModel, cornerRadius: 14, padding: 9) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 5.5, height: 5.5)

                Text(status.providerId.shortBadge)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(accent.opacity(0.14))
                            .overlay(Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 0.6))
                    )

                Text(status.message ?? "\(status.providerId.displayName) unavailable")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.76))
                    .lineLimit(1)

                Spacer()
            }
        }
    }

    /// Bento card for groups with multiple windows (e.g. 5h + Weekly).
    private func dualWindowBentoCard(cardId: String, group: QuotaGroup, now: Date) -> some View {
        let primaryBucket = group.buckets.first(where: { $0.window.lowercased() == "5h" })
            ?? group.buckets.first(where: { $0.window.lowercased() == "daily" })
            ?? group.buckets.first
        let secondaryBucket = group.buckets.first(where: { $0.id != primaryBucket?.id && $0.window.lowercased() == "weekly" })
            ?? group.buckets.first(where: { $0.id != primaryBucket?.id })

        let primaryPrefix: String = {
            let w = (primaryBucket?.window ?? "").lowercased()
            if w == "5h" || w == "5hr" || w == "five_hour" { return "5h" }
            if w == "weekly" { return "Wk" }
            if w == "daily" { return "1d" }
            return primaryBucket?.window ?? ""
        }()

        return GlassBentoCard(cardId: cardId, viewModel: viewModel, cornerRadius: 15, padding: 11) {
            HStack(spacing: 12) {
                if let primary = primaryBucket {
                    GlassCircularGauge(
                        fraction: primary.remainingFraction,
                        size: 46,
                        lineWidth: 4.5,
                        fontSize: 13
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    // Header + primary limit row
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        providerMicroBadge(group.providerId)

                        Text(group.displayName)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        if let primary = primaryBucket {
                            let prefix = primaryPrefix.isEmpty ? "" : "\(primaryPrefix): "
                            Text(
                                primary.remainingPercentage < 100
                                    ? "\(prefix)\(primary.remainingPercentage)% · \(primary.formattedResetDuration(relativeTo: now) ?? "soon")"
                                    : "\(prefix)100% left"
                            )
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(GlassCircularGauge.semanticColor(for: primary.remainingFraction))
                        }
                    }

                    // Secondary limit row + progress bar
                    if let secondary = secondaryBucket {
                        VStack(alignment: .leading, spacing: 3.5) {
                            HStack {
                                Text(secondary.windowLabel)
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.white.opacity(0.55))

                                Spacer()

                                Text(
                                    secondary.remainingPercentage < 100
                                        ? "\(secondary.remainingPercentage)% left · \(secondary.formattedResetDuration(relativeTo: now) ?? "")"
                                        : "100% left"
                                )
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(Color.white.opacity(0.85))
                            }

                            GlassProgressBar(fraction: secondary.remainingFraction, height: 4)
                        }
                    }
                }
            }
        }
    }

    private var allHiddenStateBento: some View {
        GlassBentoCard(cardId: "\(cardNamespace)-hidden", viewModel: viewModel, cornerRadius: 15, padding: 12) {
            HStack(spacing: 10) {
                Text("All models are hidden")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.72))
                Spacer()
                Button("Show All") {
                    viewModel.showAllGroups()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// Compact Bento card for single-bucket groups (Gemini 4 Argon Weekly limit).
    private func singleWindowBentoCard(cardId: String, group: QuotaGroup, now: Date) -> some View {
        let bucket = group.buckets.first
        let fraction = bucket?.remainingFraction ?? 1.0
        let pct = bucket?.remainingPercentage ?? 100
        let resetText: String = {
            guard let b = bucket else { return "Weekly limit" }
            if b.remainingPercentage < 100, let dur = b.formattedResetDuration(relativeTo: now) {
                return "\(b.windowLabel) · Resets in \(dur)"
            }
            return "\(b.windowLabel) · Full"
        }()

        return GlassBentoCard(cardId: cardId, viewModel: viewModel, cornerRadius: 15, padding: 11) {
            HStack(spacing: 12) {
                GlassCircularGauge(
                    fraction: fraction,
                    size: 42,
                    lineWidth: 4.2,
                    fontSize: 12
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        providerMicroBadge(group.providerId)

                        Text(group.displayName)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Text("\(pct)% left")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(GlassCircularGauge.semanticColor(for: fraction))
                    }

                    GlassProgressBar(fraction: fraction, height: 4)

                    Text(resetText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Color.white.opacity(0.55))
                }
            }
        }
    }

    private var emptyStateBento: some View {
        GlassBentoCard(cardId: "\(cardNamespace)-empty", viewModel: viewModel, cornerRadius: 15, padding: 14) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connecting to Antigravity...")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Keep Antigravity open to stream live usage.")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.55))
                }
                Spacer()
            }
        }
    }
}

struct UsageWidgetView: View {
    @ObservedObject var viewModel: UsageViewModel
    let windowRole: WidgetDisplayMode

    private var isFloatingWindow: Bool {
        windowRole == .floatingHUD
    }

    private var isWidgetHovered: Bool {
        viewModel.isWidgetHovered
    }

    var body: some View {
        ZStack {
            GlassVisualEffectView(
                material: .hudWindow,
                cornerRadius: viewModel.isCompactMode ? 22 : 24
            )

            RoundedRectangle(cornerRadius: viewModel.isCompactMode ? 22 : 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: viewModel.isCompactMode ? 22 : 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.38),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            if viewModel.isCompactMode {
                compactGlassPillView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    headerBar
                    if viewModel.enabledProviders.count > 1 {
                        ProviderFilterBarView(viewModel: viewModel)
                    }
                    QuotaBentoContentListView(viewModel: viewModel, cardNamespace: windowRole.rawValue)
                }
                .padding(13)
            }
        }
        .frame(
            width: UsageWidgetLayout.targetSize(for: viewModel).width,
            height: UsageWidgetLayout.targetSize(for: viewModel).height
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                viewModel.isWidgetHovered = hovering
            }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                OrbitHUDLogoVectorView(size: 15)

                Text("OrbitHUD")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.95))

                Circle()
                    .fill(
                        viewModel.snapshot.isLanguageServerConnected
                            ? Color(red: 0.24, green: 0.86, blue: 0.58)
                            : Color.white.opacity(0.35)
                    )
                    .frame(width: 5.5, height: 5.5)

                Text(isFloatingWindow ? "Float" : "Desktop")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.50))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
            }

            Spacer()

            HStack(spacing: 5) {
                if !isFloatingWindow {
                    glassIconButton(
                        systemName: viewModel.isDesktopPositionLocked ? "lock.fill" : "lock.open",
                        isActive: viewModel.isDesktopPositionLocked,
                        help: viewModel.isDesktopPositionLocked ? "Unlock Position" : "Lock Desktop Position"
                    ) {
                        viewModel.isDesktopPositionLocked.toggle()
                    }
                }

                glassPillButton(
                    title: isFloatingWindow ? "Pin Desktop" : "Float Top",
                    systemName: isFloatingWindow ? "macwindow" : "pip.fill"
                ) {
                    viewModel.setSingleMode(isFloatingWindow ? .desktopPinned : .floatingHUD)
                }

                glassIconButton(
                    systemName: "rectangle.compress.vertical",
                    help: "Minimize to Compact Glass Pill"
                ) {
                    viewModel.isCompactMode = true
                }

                glassIconButton(
                    systemName: "arrow.clockwise",
                    help: "Refresh Now"
                ) {
                    Task { await viewModel.refreshNow() }
                }
            }
            .opacity(isWidgetHovered ? 1.0 : 0.0)
            .allowsHitTesting(isWidgetHovered)
        }
        .frame(height: 22)
    }

    // MARK: - Compact Floating Glass Pill Layout (Dynamic visible metrics)
    private var compactGlassPillView: some View {
        let items = viewModel.snapshot
            .iosRingItems(relativeTo: viewModel.snapshot.timestamp)
            .filter { viewModel.isRingItemVisible($0) }
        let multiProvider = viewModel.enabledProviders.count > 1

        return HStack(spacing: 6) {
            if items.isEmpty && !viewModel.snapshot.quotaGroups.isEmpty {
                Text("Models hidden")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.70))
                Spacer()
                glassPillButton(title: "Show All", systemName: "eye") {
                    viewModel.showAllGroups()
                }
            } else {
                ForEach(items.prefix(6)) { item in
                    HStack(spacing: 4.5) {
                        GlassCircularGauge(
                            fraction: item.remainingFraction,
                            size: 24,
                            lineWidth: 2.8,
                            showPercentageText: false
                        )

                        VStack(alignment: .leading, spacing: 0.5) {
                            Text("\(item.remainingPercentage)%")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)

                            HStack(spacing: 3) {
                                if multiProvider {
                                    Circle()
                                        .fill(UsageWidgetLayout.accentColor(for: item.providerId))
                                        .frame(width: 4, height: 4)
                                }
                                Text(shortPillLabel(item.title))
                                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            glassIconButton(
                systemName: "rectangle.expand.vertical",
                help: "Expand to Bento Glass View"
            ) {
                viewModel.isCompactMode = false
            }
        }
    }

    private func glassIconButton(
        systemName: String,
        isActive: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isActive ? Color(red: 0.98, green: 0.72, blue: 0.22) : Color.white.opacity(0.78))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isActive ? 0.18 : 0.10))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func glassPillButton(
        title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(Color.white.opacity(0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func shortPillLabel(_ raw: String) -> String {
        switch raw {
        case "Gemini 5h": return "Gem 5h"
        case "Gemini Wk": return "Gem Wk"
        case "Claude 5h": return "Cld 5h"
        case "Claude Wk": return "Cld Wk"
        case "Argon 4": return "Argon"
        default: return raw
        }
    }
}
