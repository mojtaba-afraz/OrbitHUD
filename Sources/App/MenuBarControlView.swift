import SwiftUI
import AppKit
#if canImport(AntigravityUsageCore)
import AntigravityUsageCore
#endif

/// Menu Bar popover that displays the exact same live Glassmorphism Usage Bento cards
/// at the top, followed by widget display controls.
struct MenuBarControlView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Top Header
            HStack(spacing: 7) {
                OrbitHUDLogoVectorView(size: 16)

                Text("OrbitHUD")
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Circle()
                    .fill(
                        viewModel.snapshot.isLanguageServerConnected
                            ? Color(red: 0.24, green: 0.86, blue: 0.58)
                            : Color.white.opacity(0.35)
                    )
                    .frame(width: 6, height: 6)

                Spacer()

                Button {
                    Task { await viewModel.refreshNow() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Refresh")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                }
                .controlSize(.small)
            }

            // Full Usage Bento Cards (Dynamic models)
            if viewModel.enabledProviders.count > 1 {
                ProviderFilterBarView(viewModel: viewModel)
            }
            QuotaBentoContentListView(viewModel: viewModel, cardNamespace: "menubar")

            Divider().overlay(Color.white.opacity(0.12))

            // Multi-Provider Mode (Opt-in)
            VStack(alignment: .leading, spacing: 6) {
                Text("Providers")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    ForEach(QuotaProviderID.allCases) { provider in
                        Toggle(
                            provider.shortTabName,
                            isOn: Binding(
                                get: { viewModel.enabledProviders.contains(provider) },
                                set: { _ in viewModel.toggleProvider(provider) }
                            )
                        )
                        .font(.system(size: 11, design: .rounded))
                        .disabled(viewModel.enabledProviders.contains(provider) && viewModel.enabledProviders.count <= 1)
                    }
                }
            }

            if !viewModel.snapshot.quotaGroups.isEmpty {
                Divider().overlay(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Visible Models")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        if !viewModel.hiddenGroupIds.isEmpty {
                            Button("Show All") {
                                viewModel.showAllGroups()
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        }
                    }

                    ForEach(viewModel.snapshot.quotaGroups) { group in
                        let prefix = viewModel.enabledProviders.count > 1
                            ? "[\(UsageWidgetLayout.shortBadge(for: group.providerId))] "
                            : ""
                        Toggle(
                            "\(prefix)\(group.displayName)",
                            isOn: Binding(
                                get: { viewModel.isGroupVisible(group.id) },
                                set: { _ in viewModel.toggleGroupVisibility(group.id) }
                            )
                        )
                        .font(.system(size: 11, design: .rounded))
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            // Quick Widget Controls
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Widget Mode")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("Mode", selection: $viewModel.displayMode) {
                        ForEach(WidgetDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 155)
                }

                HStack(spacing: 14) {
                    Toggle("Compact Pill", isOn: $viewModel.isCompactMode)
                        .font(.system(size: 11, design: .rounded))
                    Toggle("Lock Desktop", isOn: $viewModel.isDesktopPositionLocked)
                        .font(.system(size: 11, design: .rounded))
                }

                HStack(spacing: 8) {
                    Text("Opacity")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                    Slider(value: $viewModel.windowOpacity, in: 0.45...1.0, step: 0.05)
                    Text("\(Int(viewModel.windowOpacity * 100))%")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            HStack {
                Text("Today: \(TokenFormatter.format(viewModel.snapshot.tokenUsage.todayTotalTokens)) tokens")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.32, blue: 0.32).opacity(0.85))
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 356)
        .environment(\.colorScheme, .dark)
        .onAppear {
            Task { await viewModel.refreshNow() }
        }
    }
}
