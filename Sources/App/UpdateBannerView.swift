import SwiftUI
import AppKit
#if canImport(AntigravityUsageCore)
import AntigravityUsageCore
#endif

/// Compact, dismissible glassmorphic update banner rendered in both the Floating/Desktop widget
/// and the Menu Bar popover when a macOS release update is available, downloading, or failed.
struct UpdateBannerView: View {
    @ObservedObject var viewModel: UsageViewModel

    private let accentEmerald = Color(red: 0.24, green: 0.86, blue: 0.58)
    private let accentCyan = Color(red: 0.13, green: 0.83, blue: 0.93)
    private let accentAmber = Color(red: 0.98, green: 0.72, blue: 0.22)

    var body: some View {
        if viewModel.isUpdateBannerVisible {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(0.16),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.38), lineWidth: 0.8)
                    }
                )
        }
    }

    private var accentColor: Color {
        if case .error = viewModel.updateState {
            return accentAmber
        }
        return accentEmerald
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.updateState {
        case .available(let info):
            HStack(spacing: 8) {
                Circle()
                    .fill(accentEmerald)
                    .frame(width: 6, height: 6)

                Text("Update v\(info.latestVersion) available")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Button {
                    Task { await viewModel.installAvailableUpdate() }
                } label: {
                    Text("Update")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.black.opacity(0.92))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accentEmerald, accentCyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)

                dismissButton
            }

        case .downloading(let version, let progress):
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Downloading v\(version)...")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("\(min(max(progress, 0), 100))%")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(accentEmerald)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 4)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accentEmerald, accentCyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: max(geo.size.width * CGFloat(min(max(progress, 0), 100)) / 100.0, 4),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
            }

        case .verifying(let version):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text("Verifying SHA256 for v\(version)...")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Spacer()
            }

        case .installing(let version):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text("Installing v\(version) & relaunching...")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Spacer()
            }

        case .error(let message, let releaseURL):
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundColor(accentAmber)

                Text(message)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if let releaseURL {
                    Button("Release") {
                        NSWorkspace.shared.open(releaseURL)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                }

                dismissButton
            }

        case .idle, .checking, .upToDate:
            EmptyView()
        }
    }

    private var dismissButton: some View {
        Button {
            viewModel.dismissUpdateBanner()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }
}
