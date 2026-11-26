import SwiftUI
import AppKit
#if canImport(AntigravityUsageCore)
import AntigravityUsageCore
#endif

/// Renders the project's official OrbitHUD SVG logo (`assets/logo.svg`: dual orbital rings + 4-point sparkle core)
/// for the macOS Menu Bar and widget headers.
enum OrbitHUDOfficialLogo {
    /// Menu bar glyph SVG (matches `assets/logo.svg` dual orbital rings + center 4-point sparkle core).
    static let menuBarGlyphSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="64 64 384 384" width="16" height="16">
      <circle cx="256" cy="256" r="144" fill="none" stroke="black" stroke-opacity="0.28" stroke-width="32" />
      <circle
        cx="256"
        cy="256"
        r="144"
        fill="none"
        stroke="black"
        stroke-width="32"
        stroke-linecap="round"
        stroke-dasharray="700 905"
        transform="rotate(-90 256 256)"
      />
      <circle
        cx="256"
        cy="256"
        r="96"
        fill="none"
        stroke="black"
        stroke-width="26"
        stroke-linecap="round"
        stroke-dasharray="420 603"
        transform="rotate(-45 256 256)"
      />
      <path
        d="M256 190 C262 232, 280 250, 322 256 C280 262, 262 280, 256 322 C250 280, 232 262, 190 256 C232 250, 250 232, 256 190 Z"
        fill="black"
      />
    </svg>
    """

    static let menuBarImage: NSImage = {
        if let data = menuBarGlyphSVG.data(using: .utf8),
           let svgImg = NSImage(data: data) {
            svgImg.size = NSSize(width: 16, height: 16)
            svgImg.isTemplate = true
            return svgImg
        }
        if let url = Bundle.main.url(forResource: "logo", withExtension: "svg"),
           let svgImg = NSImage(contentsOf: url) {
            svgImg.size = NSSize(width: 16, height: 16)
            return svgImg
        }
        return NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "OrbitHUD") ?? NSImage()
    }()
}

/// SwiftUI vector view of the project's official `assets/logo.svg` (emerald-cyan outer orbital arc,
/// indigo-sky inner orbital arc, and luminous 4-point center core).
struct OrbitHUDLogoVectorView: View {
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            // Outer orbital track
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: size * 0.11)

            // Outer active orbital arc (Emerald -> Cyan)
            Circle()
                .trim(from: 0, to: 0.78)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.24, green: 0.86, blue: 0.58),
                            Color(red: 0.13, green: 0.83, blue: 0.93)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Inner active orbital arc (Sky -> Indigo)
            Circle()
                .trim(from: 0, to: 0.68)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.74, blue: 0.97),
                            Color(red: 0.51, green: 0.55, blue: 0.97)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round)
                )
                .frame(width: size * 0.66, height: size * 0.66)
                .rotationEffect(.degrees(-45))

            // Center 4-point sparkle core
            OrbitHUDSparkleCoreShape()
                .fill(Color.white)
                .frame(width: size * 0.42, height: size * 0.42)
        }
        .frame(width: size, height: size)
    }
}

struct OrbitHUDSparkleCoreShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2.0
        let c = r * 0.18

        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - r))
        path.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + c, y: cy - c))
        path.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx + c, y: cy + c))
        path.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx - c, y: cy + c))
        path.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx - c, y: cy - c))
        path.closeSubpath()
        return path
    }
}

/// Dedicated observed view for the MenuBarExtra label using OrbitHUD's own SVG logo.
struct MenuBarLiveLabelView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: OrbitHUDOfficialLogo.menuBarImage)
            if let pct = viewModel.snapshot.primaryQuotaPercentage {
                Text("\(pct)%")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("--%")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = UsageViewModel()
    var windowManager: WidgetWindowManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let logoURL = Bundle.main.url(forResource: "logo", withExtension: "png"),
           let appIcon = NSImage(contentsOf: logoURL) {
            NSApp.applicationIconImage = appIcon
            NSWorkspace.shared.setIcon(appIcon, forFile: Bundle.main.bundlePath, options: [])
        }
        viewModel.onRequestAppTerminate = {
            NSApplication.shared.terminate(nil)
        }
        windowManager = WidgetWindowManager(viewModel: viewModel)
    }
}

@main
struct AntigravityUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarControlView(viewModel: appDelegate.viewModel)
        } label: {
            MenuBarLiveLabelView(viewModel: appDelegate.viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
