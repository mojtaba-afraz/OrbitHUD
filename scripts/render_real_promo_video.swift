import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

let width = 1920
let height = 1080
let fps: Int32 = 30
let durationSeconds = 16
let totalFrames = Int(fps) * durationSeconds

let projectDir = "/Users/mojtaba_afraz/.gemini/antigravity/scratch/AntigravityUsageWidget"
let logoPath = "\(projectDir)/assets/logo.png"
let outScreenshotPath = "\(projectDir)/assets/orbithud-showcase.png"
let outVideoPath = "\(projectDir)/assets/orbithud-demo.mp4"

let logoImage = NSImage(contentsOfFile: logoPath)
let logoCG: CGImage? = {
    guard let img = logoImage,
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.cgImage
}()

func clamp(_ v: CGFloat, _ lo: CGFloat = 0, _ hi: CGFloat = 1) -> CGFloat {
    min(max(v, lo), hi)
}

func easeOutCubic(_ t: CGFloat) -> CGFloat {
    let p = clamp(t) - 1
    return p * p * p + 1
}

func easeInOutCubic(_ t: CGFloat) -> CGFloat {
    let x = clamp(t)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

func drawText(
    _ text: String,
    at point: CGPoint,
    fontSize: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = .white,
    align: NSTextAlignment = .left,
    maxWidth: CGFloat = 1000,
    monospaced: Bool = false
) {
    let baseFont = monospaced
        ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        : (NSFont.systemFont(ofSize: fontSize, weight: weight))
    let para = NSMutableParagraphStyle()
    para.alignment = align

    let attrs: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: color,
        .paragraphStyle: para
    ]
    let attrStr = NSAttributedString(string: text, attributes: attrs)
    let size = attrStr.size()
    let rect: CGRect
    switch align {
    case .center:
        rect = CGRect(x: point.x - maxWidth / 2, y: point.y, width: maxWidth, height: size.height + 4)
    case .right:
        rect = CGRect(x: point.x - maxWidth, y: point.y, width: maxWidth, height: size.height + 4)
    default:
        rect = CGRect(x: point.x, y: point.y, width: maxWidth, height: size.height + 4)
    }
    attrStr.draw(in: rect)
}

func drawRoundedRect(
    _ cg: CGContext,
    rect: CGRect,
    radius: CGFloat,
    fill: NSColor,
    stroke: NSColor? = nil,
    lineWidth: CGFloat = 1.0
) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(path)
    cg.setFillColor(fill.cgColor)
    cg.fillPath()
    if let stroke {
        cg.addPath(path)
        cg.setStrokeColor(stroke.cgColor)
        cg.setLineWidth(lineWidth)
        cg.strokePath()
    }
    cg.restoreGState()
}

func drawOrbitHUDGlyph(_ cg: CGContext, center: CGPoint, size: CGFloat, alpha: CGFloat = 1.0) {
    cg.saveGState()
    let rOuter = size * 0.40
    let rInner = size * 0.26

    // Outer track
    cg.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.20 * alpha).cgColor)
    cg.setLineWidth(size * 0.11)
    cg.addArc(center: center, radius: rOuter, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()

    // Outer active emerald arc
    cg.setStrokeColor(NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: alpha).cgColor)
    cg.setLineCap(.round)
    cg.setLineWidth(size * 0.11)
    cg.addArc(center: center, radius: rOuter, startAngle: .pi * 0.5, endAngle: -.pi * 1.05, clockwise: true)
    cg.strokePath()

    // Inner active sky-cyan arc
    cg.setStrokeColor(NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: alpha).cgColor)
    cg.setLineWidth(size * 0.085)
    cg.addArc(center: center, radius: rInner, startAngle: .pi * 0.25, endAngle: -.pi * 1.1, clockwise: true)
    cg.strokePath()

    // Center 4-point star
    let sr = size * 0.18
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x, y: center.y + sr))
    path.addQuadCurve(to: CGPoint(x: center.x + sr, y: center.y), control: CGPoint(x: center.x + sr * 0.2, y: center.y + sr * 0.2))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - sr), control: CGPoint(x: center.x + sr * 0.2, y: center.y - sr * 0.2))
    path.addQuadCurve(to: CGPoint(x: center.x - sr, y: center.y), control: CGPoint(x: center.x - sr * 0.2, y: center.y - sr * 0.2))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + sr), control: CGPoint(x: center.x - sr * 0.2, y: center.y + sr * 0.2))
    path.closeSubpath()
    cg.addPath(path)
    cg.setFillColor(NSColor(calibratedWhite: 1.0, alpha: alpha).cgColor)
    cg.fillPath()
    cg.restoreGState()
}

func drawCircularGauge(
    _ cg: CGContext,
    center: CGPoint,
    radius: CGFloat,
    lineWidth: CGFloat,
    fraction: CGFloat,
    color: NSColor,
    showText: Bool = true,
    fontSize: CGFloat = 20,
    alpha: CGFloat = 1.0
) {
    cg.saveGState()
    cg.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.12 * alpha).cgColor)
    cg.setLineWidth(lineWidth)
    cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()

    let clamped = max(min(fraction, 1.0), 0.02)
    let startAngle: CGFloat = .pi / 2.0
    let endAngle = startAngle - (.pi * 2.0 * clamped)
    cg.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
    cg.setLineCap(.round)
    cg.setLineWidth(lineWidth)
    cg.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    cg.strokePath()
    cg.restoreGState()

    if showText {
        let pct = Int((fraction * 100.0).rounded())
        drawText(
            "\(pct)%",
            at: CGPoint(x: center.x, y: center.y - fontSize * 0.58),
            fontSize: fontSize,
            weight: .bold,
            color: NSColor(calibratedWhite: 1.0, alpha: alpha),
            align: .center,
            maxWidth: radius * 2.2,
            monospaced: true
        )
    }
}

/// Draws the REAL OrbitHUD Full Bento Glass Widget at a given origin and scale.
func drawFullBentoWidget(
    _ cg: CGContext,
    origin: CGPoint,
    scale: CGFloat = 1.45,
    animProgress: CGFloat = 1.0,
    modeText: String = "Float",
    alpha: CGFloat = 1.0
) {
    let w: CGFloat = 356 * scale
    let h: CGFloat = 280 * scale
    let cardRect = CGRect(x: origin.x, y: origin.y, width: w, height: h)

    // Outer shadow & frosted glass shell
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -18 * scale),
        blur: 42 * scale,
        color: NSColor(calibratedWhite: 0, alpha: 0.55 * alpha).cgColor
    )
    drawRoundedRect(
        cg,
        rect: cardRect,
        radius: 24 * scale,
        fill: NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 0.88 * alpha),
        stroke: NSColor(calibratedWhite: 1.0, alpha: 0.28 * alpha),
        lineWidth: 1.4 * scale
    )
    cg.restoreGState()

    // Header row
    let pad = 14 * scale
    let headerY = cardRect.maxY - 30 * scale
    drawOrbitHUDGlyph(cg, center: CGPoint(x: cardRect.minX + pad + 9 * scale, y: headerY + 9 * scale), size: 17 * scale, alpha: alpha)

    drawText(
        "OrbitHUD",
        at: CGPoint(x: cardRect.minX + pad + 24 * scale, y: headerY),
        fontSize: 13 * scale,
        weight: .bold,
        color: NSColor(calibratedWhite: 0.96, alpha: alpha)
    )

    // Green live status dot
    let dotCenter = CGPoint(x: cardRect.minX + pad + 93 * scale, y: headerY + 9 * scale)
    drawRoundedRect(
        cg,
        rect: CGRect(x: dotCenter.x - 3 * scale, y: dotCenter.y - 3 * scale, width: 6 * scale, height: 6 * scale),
        radius: 3 * scale,
        fill: NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: alpha)
    )

    // Mode capsule badge
    let badgeRect = CGRect(x: cardRect.minX + pad + 106 * scale, y: headerY + 1 * scale, width: 48 * scale, height: 16 * scale)
    drawRoundedRect(
        cg,
        rect: badgeRect,
        radius: 8 * scale,
        fill: NSColor(calibratedWhite: 1.0, alpha: 0.09 * alpha)
    )
    drawText(
        modeText,
        at: CGPoint(x: badgeRect.midX, y: badgeRect.minY + 1.5 * scale),
        fontSize: 9.5 * scale,
        weight: .medium,
        color: NSColor(calibratedWhite: 0.65, alpha: alpha),
        align: .center,
        maxWidth: 48 * scale
    )

    // Action pill on right of header
    let actionRect = CGRect(x: cardRect.maxX - pad - 82 * scale, y: headerY, width: 82 * scale, height: 18 * scale)
    drawRoundedRect(
        cg,
        rect: actionRect,
        radius: 9 * scale,
        fill: NSColor(calibratedWhite: 1.0, alpha: 0.12 * alpha),
        stroke: NSColor(calibratedWhite: 1.0, alpha: 0.22 * alpha),
        lineWidth: 0.8 * scale
    )
    drawText(
        modeText == "Float" ? "Pin Desktop" : "Float Top",
        at: CGPoint(x: actionRect.midX, y: actionRect.minY + 2 * scale),
        fontSize: 9.5 * scale,
        weight: .semibold,
        color: NSColor(calibratedWhite: 0.90, alpha: alpha),
        align: .center,
        maxWidth: 80 * scale
    )

    // Helper for dual-window Bento Card (Gemini Models & Claude/GPT Models)
    func drawDualCard(
        yTop: CGFloat,
        title: String,
        fiveHPct: CGFloat,
        fiveHReset: String,
        weeklyPct: CGFloat,
        weeklyReset: String,
        fiveHColor: NSColor
    ) {
        let ch: CGFloat = 72 * scale
        let rect = CGRect(x: cardRect.minX + pad, y: yTop - ch, width: w - pad * 2, height: ch)
        drawRoundedRect(
            cg,
            rect: rect,
            radius: 15 * scale,
            fill: NSColor(calibratedWhite: 1.0, alpha: 0.065 * alpha),
            stroke: NSColor(calibratedWhite: 1.0, alpha: 0.17 * alpha),
            lineWidth: 1.0 * scale
        )

        let gaugeCenter = CGPoint(x: rect.minX + 34 * scale, y: rect.midY)
        drawCircularGauge(
            cg,
            center: gaugeCenter,
            radius: 21 * scale,
            lineWidth: 4.5 * scale,
            fraction: fiveHPct * animProgress,
            color: fiveHColor,
            showText: true,
            fontSize: 12.5 * scale,
            alpha: alpha
        )

        let textLeft = rect.minX + 68 * scale
        let textRight = rect.maxX - 12 * scale

        drawText(
            title,
            at: CGPoint(x: textLeft, y: rect.maxY - 24 * scale),
            fontSize: 12.5 * scale,
            weight: .semibold,
            color: NSColor(calibratedWhite: 0.98, alpha: alpha)
        )

        let cur5h = Int((fiveHPct * animProgress * 100).rounded())
        drawText(
            cur5h < 100 ? "5h: \(cur5h)% · \(fiveHReset)" : "5h: 100% left",
            at: CGPoint(x: textRight, y: rect.maxY - 23 * scale),
            fontSize: 10.5 * scale,
            weight: .semibold,
            color: fiveHColor.withAlphaComponent(alpha),
            align: .right,
            maxWidth: 160 * scale,
            monospaced: true
        )

        // Weekly limit label & value
        drawText(
            "Weekly limit",
            at: CGPoint(x: textLeft, y: rect.minY + 21 * scale),
            fontSize: 10.5 * scale,
            weight: .medium,
            color: NSColor(calibratedWhite: 0.58, alpha: alpha)
        )

        let curWk = Int((weeklyPct * animProgress * 100).rounded())
        drawText(
            weeklyReset.isEmpty ? "\(curWk)% left" : "\(curWk)% left · \(weeklyReset)",
            at: CGPoint(x: textRight, y: rect.minY + 21 * scale),
            fontSize: 10.5 * scale,
            weight: .semibold,
            color: NSColor(calibratedWhite: 0.86, alpha: alpha),
            align: .right,
            maxWidth: 160 * scale,
            monospaced: true
        )

        // Weekly progress bar
        let barTrack = CGRect(x: textLeft, y: rect.minY + 11 * scale, width: textRight - textLeft, height: 4.5 * scale)
        drawRoundedRect(cg, rect: barTrack, radius: 2.25 * scale, fill: NSColor(calibratedWhite: 1.0, alpha: 0.10 * alpha))
        let barFill = CGRect(
            x: barTrack.minX,
            y: barTrack.minY,
            width: max(barTrack.width * weeklyPct * animProgress, 6 * scale),
            height: barTrack.height
        )
        drawRoundedRect(
            cg,
            rect: barFill,
            radius: 2.25 * scale,
            fill: NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: alpha)
        )
    }

    let emerald = NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: 1.0)
    let amber = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.22, alpha: 1.0)

    // 1. Gemini Models Card
    let card1Top = headerY - 10 * scale
    drawDualCard(
        yTop: card1Top,
        title: "Gemini Models",
        fiveHPct: 0.45,
        fiveHReset: "3h 10m",
        weeklyPct: 0.74,
        weeklyReset: "6d 1h",
        fiveHColor: emerald
    )

    // 2. Claude and GPT models Card
    let card2Top = card1Top - 81 * scale
    drawDualCard(
        yTop: card2Top,
        title: "Claude and GPT models",
        fiveHPct: 1.0,
        fiveHReset: "",
        weeklyPct: 1.0,
        weeklyReset: "",
        fiveHColor: emerald
    )

    // 3. Gemini 4 Argon Card
    let card3Top = card2Top - 81 * scale
    let ch3: CGFloat = 64 * scale
    let rect3 = CGRect(x: cardRect.minX + pad, y: card3Top - ch3, width: w - pad * 2, height: ch3)
    drawRoundedRect(
        cg,
        rect: rect3,
        radius: 15 * scale,
        fill: NSColor(calibratedWhite: 1.0, alpha: 0.065 * alpha),
        stroke: NSColor(calibratedWhite: 1.0, alpha: 0.17 * alpha),
        lineWidth: 1.0 * scale
    )
    drawCircularGauge(
        cg,
        center: CGPoint(x: rect3.minX + 34 * scale, y: rect3.midY),
        radius: 19 * scale,
        lineWidth: 4.2 * scale,
        fraction: 0.93 * animProgress,
        color: emerald,
        showText: true,
        fontSize: 11.5 * scale,
        alpha: alpha
    )
    let tLeft3 = rect3.minX + 68 * scale
    let tRight3 = rect3.maxX - 12 * scale
    drawText(
        "Gemini 4 Argon",
        at: CGPoint(x: tLeft3, y: rect3.maxY - 22 * scale),
        fontSize: 12.5 * scale,
        weight: .semibold,
        color: NSColor(calibratedWhite: 0.98, alpha: alpha)
    )
    let curArgon = Int((0.93 * animProgress * 100).rounded())
    drawText(
        "\(curArgon)% left",
        at: CGPoint(x: tRight3, y: rect3.maxY - 22 * scale),
        fontSize: 11 * scale,
        weight: .bold,
        color: emerald.withAlphaComponent(alpha),
        align: .right,
        maxWidth: 120 * scale,
        monospaced: true
    )
    let barTrack3 = CGRect(x: tLeft3, y: rect3.midY - 2 * scale, width: tRight3 - tLeft3, height: 4 * scale)
    drawRoundedRect(cg, rect: barTrack3, radius: 2 * scale, fill: NSColor(calibratedWhite: 1.0, alpha: 0.10 * alpha))
    drawRoundedRect(
        cg,
        rect: CGRect(x: barTrack3.minX, y: barTrack3.minY, width: max(barTrack3.width * 0.93 * animProgress, 6 * scale), height: barTrack3.height),
        radius: 2 * scale,
        fill: emerald.withAlphaComponent(alpha)
    )
    drawText(
        "Weekly limit · Resets in 6d 22h",
        at: CGPoint(x: tLeft3, y: rect3.minY + 7 * scale),
        fontSize: 10 * scale,
        weight: .medium,
        color: NSColor(calibratedWhite: 0.56, alpha: alpha),
        monospaced: true
    )
    _ = amber
}

/// Draws the REAL OrbitHUD Compact Glass Coding Pill (356x68 scaled).
func drawCompactPillWidget(
    _ cg: CGContext,
    origin: CGPoint,
    scale: CGFloat = 1.45,
    alpha: CGFloat = 1.0
) {
    let w: CGFloat = 356 * scale
    let h: CGFloat = 68 * scale
    let rect = CGRect(x: origin.x, y: origin.y, width: w, height: h)

    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -12 * scale),
        blur: 28 * scale,
        color: NSColor(calibratedWhite: 0, alpha: 0.50 * alpha).cgColor
    )
    drawRoundedRect(
        cg,
        rect: rect,
        radius: 22 * scale,
        fill: NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 0.90 * alpha),
        stroke: NSColor(calibratedWhite: 1.0, alpha: 0.28 * alpha),
        lineWidth: 1.2 * scale
    )
    cg.restoreGState()

    let pillItems: [(String, CGFloat)] = [
        ("Gem 5h", 0.45),
        ("Gem Wk", 0.74),
        ("Cld 5h", 1.00),
        ("Cld Wk", 1.00),
        ("Argon", 0.93)
    ]

    let emerald = NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: 1.0)
    let startX = rect.minX + 16 * scale
    let stepX = (w - 32 * scale) / CGFloat(pillItems.count)

    for (idx, item) in pillItems.enumerated() {
        let ix = startX + CGFloat(idx) * stepX
        let ringCenter = CGPoint(x: ix + 13 * scale, y: rect.midY)
        drawCircularGauge(
            cg,
            center: ringCenter,
            radius: 11.5 * scale,
            lineWidth: 2.8 * scale,
            fraction: item.1,
            color: emerald,
            showText: false,
            alpha: alpha
        )
        let pct = Int((item.1 * 100).rounded())
        drawText(
            "\(pct)%",
            at: CGPoint(x: ix + 29 * scale, y: rect.midY + 1 * scale),
            fontSize: 10.5 * scale,
            weight: .bold,
            color: NSColor(calibratedWhite: 0.98, alpha: alpha),
            monospaced: true
        )
        drawText(
            item.0,
            at: CGPoint(x: ix + 29 * scale, y: rect.midY - 13 * scale),
            fontSize: 8.5 * scale,
            weight: .medium,
            color: NSColor(calibratedWhite: 0.58, alpha: alpha)
        )
    }
}

func renderFrame(frameIndex: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    )!

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let t = CGFloat(frameIndex) / CGFloat(fps) // time in seconds (0.0 .. 16.0)

    // 1. Deep Obsidian & Teal Studio Backdrop
    let bgColors = [
        NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.16, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.06, alpha: 1.0).cgColor
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0.0, 0.55, 1.0])!
    cg.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])

    // Ambient Emerald & Cyan Glow Orbs in background
    let orb1Center = CGPoint(x: CGFloat(width) * 0.72 + sin(t * 0.6) * 30, y: CGFloat(height) * 0.56 + cos(t * 0.5) * 20)
    let orbColors1 = [
        NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: 0.18).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    let orbGrad1 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: orbColors1, locations: [0.0, 1.0])!
    cg.drawRadialGradient(orbGrad1, startCenter: orb1Center, startRadius: 0, endCenter: orb1Center, endRadius: 460, options: [])

    let orb2Center = CGPoint(x: CGFloat(width) * 0.28 - cos(t * 0.5) * 25, y: CGFloat(height) * 0.42)
    let orbColors2 = [
        NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 0.15).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    let orbGrad2 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: orbColors2, locations: [0.0, 1.0])!
    cg.drawRadialGradient(orbGrad2, startCenter: orb2Center, startRadius: 0, endCenter: orb2Center, endRadius: 420, options: [])

    // 2. Top macOS Menu Bar Preview Strip
    let menuBarRect = CGRect(x: 60, y: CGFloat(height) - 62, width: CGFloat(width) - 120, height: 36)
    drawRoundedRect(
        cg,
        rect: menuBarRect,
        radius: 10,
        fill: NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.15, alpha: 0.78),
        stroke: NSColor(calibratedWhite: 1.0, alpha: 0.14),
        lineWidth: 1
    )
    drawText(
        "   Antigravity IDE    File    Edit    Selection    View",
        at: CGPoint(x: menuBarRect.minX + 18, y: menuBarRect.minY + 8),
        fontSize: 14,
        weight: .medium,
        color: NSColor(calibratedWhite: 0.82, alpha: 1.0)
    )
    // Top-right OrbitHUD Menu Bar Extra item
    let mbPillRect = CGRect(x: menuBarRect.maxX - 180, y: menuBarRect.minY + 5, width: 78, height: 26)
    drawRoundedRect(
        cg,
        rect: mbPillRect,
        radius: 7,
        fill: NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: 0.20),
        stroke: NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: 0.45),
        lineWidth: 1
    )
    drawOrbitHUDGlyph(cg, center: CGPoint(x: mbPillRect.minX + 16, y: mbPillRect.midY), size: 15)
    drawText(
        "45%",
        at: CGPoint(x: mbPillRect.minX + 31, y: mbPillRect.minY + 4),
        fontSize: 13.5,
        weight: .bold,
        color: .white,
        monospaced: true
    )
    drawText(
        "Mon 4:45 PM",
        at: CGPoint(x: menuBarRect.maxX - 92, y: menuBarRect.minY + 8),
        fontSize: 13.5,
        weight: .medium,
        color: NSColor(calibratedWhite: 0.78, alpha: 1.0)
    )

    // 3. Left Marketing Typography & Brand Header
    let leftX: CGFloat = 110
    if let logoCG {
        let iconRect = CGRect(x: leftX - 10, y: CGFloat(height) - 255, width: 108, height: 108)
        cg.draw(logoCG, in: iconRect)
    }

    drawText(
        "OrbitHUD",
        at: CGPoint(x: leftX + 108, y: CGFloat(height) - 205),
        fontSize: 44,
        weight: .bold,
        color: .white
    )
    drawText(
        "Zero-Gravity Glassmorphic Usage Widget",
        at: CGPoint(x: leftX + 108, y: CGFloat(height) - 242),
        fontSize: 19,
        weight: .medium,
        color: NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: 1.0)
    )

    // Scene-specific headline on left side
    let headline: String
    let subhead: String
    if t < 5.5 {
        headline = "Real-Time Antigravity Quotas.\nAt a Glance."
        subhead = "Auto-connects to your local Language Server on 127.0.0.1.\nTracks 5-hour & Weekly limits across Gemini, Claude/GPT, and Argon 4."
    } else if t < 11.0 {
        headline = "Bento Glass View +\nCompact Coding Pill."
        subhead = "Switch between the detailed Bento Glass dashboard\nand a sleek 68px floating pill while writing code."
    } else {
        headline = "Float on Top or\nPin to Desktop Wallpaper."
        subhead = "Native SwiftUI engine for macOS (~18 MB RAM)\nplus cross-platform installers for Windows (.exe) & Linux (.AppImage / .deb)."
    }

    let lines = headline.components(separatedBy: "\n")
    for (i, line) in lines.enumerated() {
        drawText(
            line,
            at: CGPoint(x: leftX, y: CGFloat(height) - 355 - CGFloat(i) * 56),
            fontSize: 42,
            weight: .bold,
            color: .white
        )
    }

    let subLines = subhead.components(separatedBy: "\n")
    for (i, line) in subLines.enumerated() {
        drawText(
            line,
            at: CGPoint(x: leftX, y: CGFloat(height) - 485 - CGFloat(i) * 30),
            fontSize: 19,
            weight: .regular,
            color: NSColor(calibratedWhite: 0.72, alpha: 1.0)
        )
    }

    // Feature pills on bottom-left
    let pills = ["macOS Native (SwiftUI)", "Windows (.exe)", "Linux (.AppImage / .deb)", "100% Open Source"]
    var pillX = leftX
    for pill in pills {
        let pw = CGFloat(pill.count) * 9.5 + 28
        let pRect = CGRect(x: pillX, y: 120, width: pw, height: 36)
        drawRoundedRect(
            cg,
            rect: pRect,
            radius: 18,
            fill: NSColor(calibratedWhite: 1.0, alpha: 0.08),
            stroke: NSColor(calibratedWhite: 1.0, alpha: 0.18),
            lineWidth: 1
        )
        drawText(
            pill,
            at: CGPoint(x: pRect.midX, y: pRect.minY + 8),
            fontSize: 14,
            weight: .semibold,
            color: NSColor(calibratedWhite: 0.90, alpha: 1.0),
            align: .center,
            maxWidth: pw
        )
        pillX += pw + 12
    }

    drawText(
        "github.com/mojtaba-afraz/OrbitHUD",
        at: CGPoint(x: leftX, y: 68),
        fontSize: 18,
        weight: .semibold,
        color: NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0),
        monospaced: true
    )

    // 4. Right Side: Live Animated Real OrbitHUD Widgets (Full Bento + Compact Pill)
    let gaugeAnim = easeOutCubic(min(t / 2.2, 1.0))
    let floatOffsetY = sin(t * 1.5) * 6.0
    let modeLabel = t >= 11.0 ? "Desktop" : "Float"

    // Main Full Bento Widget
    let bentoOrigin = CGPoint(x: 1180, y: 390 + floatOffsetY)
    drawFullBentoWidget(
        cg,
        origin: bentoOrigin,
        scale: 1.55,
        animProgress: gaugeAnim,
        modeText: modeLabel,
        alpha: 1.0
    )

    // Below it: Compact Glass Coding Pill (animates in at t = 3.0s)
    let pillAlpha = easeInOutCubic((t - 2.0) / 1.2)
    if pillAlpha > 0.01 {
        let pillOrigin = CGPoint(x: 1180, y: 235 + floatOffsetY * 0.7)
        drawCompactPillWidget(
            cg,
            origin: pillOrigin,
            scale: 1.55,
            alpha: pillAlpha
        )
        drawText(
            "Compact Coding Pill Mode (356 × 68)",
            at: CGPoint(x: 1180 + (356 * 1.55) / 2, y: 198 + floatOffsetY * 0.7),
            fontSize: 14,
            weight: .medium,
            color: NSColor(calibratedWhite: 0.60, alpha: pillAlpha),
            align: .center,
            maxWidth: 500
        )
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// 1. Render 1080p Showcase Screenshot (at t = 6.0s when both Full Bento & Compact Pill are shown)
print("==> Rendering real UI 1080p showcase image to \(outScreenshotPath)...")
let screenshotRep = renderFrame(frameIndex: Int(fps) * 6)
if let pngData = screenshotRep.representation(using: .png, properties: [:]) {
    try pngData.write(to: URL(fileURLWithPath: outScreenshotPath))
    print("  ✓ Saved \(outScreenshotPath)")
}

// 2. Encode 16-second 1080p MP4 Promo Video using AVAssetWriter
print("==> Encoding 16-second 1080p H.264 MP4 promo video to \(outVideoPath)...")
let videoURL = URL(fileURLWithPath: outVideoPath)
try? FileManager.default.removeItem(at: videoURL)

let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 8_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
    ]
]
let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
writerInput.expectsMediaDataInRealTime = false

let attrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height
]
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: attrs)

writer.add(writerInput)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

for frameIdx in 0..<totalFrames {
    while !writerInput.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.005)
    }

    let rep = renderFrame(frameIndex: frameIdx)
    var pixelBufferOut: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary,
        &pixelBufferOut
    )
    guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else { continue }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) {
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let cgCtx = CGContext(
            data: baseAddr,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ), let cgImg = rep.cgImage {
            cgCtx.draw(cgImg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

    let presentationTime = CMTime(value: CMTimeValue(frameIdx), timescale: fps)
    adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
}

writerInput.markAsFinished()
let sema = DispatchSemaphore(value: 0)
writer.finishWriting {
    sema.signal()
}
sema.wait()
print("✅ Saved 1080p MP4 promo video to \(outVideoPath)")
