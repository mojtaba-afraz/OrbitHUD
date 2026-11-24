import AppKit
import CoreGraphics
import Foundation

let width = 1920
let height = 960
let projectDir = "/Users/mojtaba_afraz/.gemini/antigravity/scratch/AntigravityUsageWidget"
let logoPath = "\(projectDir)/assets/logo.png"
let outPath = "\(projectDir)/assets/orbithud-showcase.png"

let logoCG: CGImage? = {
    guard let img = NSImage(contentsOfFile: logoPath),
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.cgImage
}()

// Semantic & Provider Colors
let cEmerald = NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: 1.0) // #3DDB94 Antigravity
let cCoral   = NSColor(calibratedRed: 0.91, green: 0.57, blue: 0.42, alpha: 1.0) // #E8926B Claude Code
let cSky     = NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0) // #38BDF8 Codex
let cAmber   = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.22, alpha: 1.0) // #FAB838 Warning

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

func drawText(
    _ text: String,
    at point: CGPoint,
    fontSize: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = .white,
    align: NSTextAlignment = .left,
    maxWidth: CGFloat = 1100,
    monospaced: Bool = false
) {
    let font = monospaced
        ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        : NSFont.systemFont(ofSize: fontSize, weight: weight)
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineSpacing = 6
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: para
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let size = str.size()
    let rect: CGRect
    switch align {
    case .center:
        rect = CGRect(x: point.x - maxWidth / 2, y: point.y, width: maxWidth, height: size.height + 10)
    case .right:
        rect = CGRect(x: point.x - maxWidth, y: point.y, width: maxWidth, height: size.height + 10)
    default:
        rect = CGRect(x: point.x, y: point.y, width: maxWidth, height: size.height + 10)
    }
    str.draw(in: rect)
}

func drawOrbitGlyph(_ cg: CGContext, center: CGPoint, size: CGFloat) {
    cg.saveGState()
    let rOuter = size * 0.40
    let rInner = size * 0.25
    cg.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.22).cgColor)
    cg.setLineWidth(size * 0.11)
    cg.addArc(center: center, radius: rOuter, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()

    cg.setStrokeColor(cEmerald.cgColor)
    cg.setLineCap(.round)
    cg.setLineWidth(size * 0.11)
    cg.addArc(center: center, radius: rOuter, startAngle: -.pi * 0.5, endAngle: .pi * 1.05, clockwise: false)
    cg.strokePath()

    cg.setStrokeColor(cSky.cgColor)
    cg.setLineWidth(size * 0.085)
    cg.addArc(center: center, radius: rInner, startAngle: -.pi * 0.25, endAngle: .pi * 1.1, clockwise: false)
    cg.strokePath()

    cg.setFillColor(NSColor.white.cgColor)
    cg.fillEllipse(in: CGRect(x: center.x - size * 0.09, y: center.y - size * 0.09, width: size * 0.18, height: size * 0.18))
    cg.restoreGState()
}

func drawGauge(
    _ cg: CGContext,
    center: CGPoint,
    radius: CGFloat,
    lineWidth: CGFloat,
    fraction: CGFloat,
    color: NSColor,
    showText: Bool,
    fontSize: CGFloat = 25
) {
    cg.saveGState()
    cg.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.16).cgColor)
    cg.setLineWidth(lineWidth)
    cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()

    let start: CGFloat = -.pi / 2
    let end = start + .pi * 2 * max(fraction, 0.03)
    cg.setStrokeColor(color.cgColor)
    cg.setLineCap(.round)
    cg.setLineWidth(lineWidth)
    cg.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
    cg.strokePath()
    cg.restoreGState()

    if showText {
        let pct = "\(Int((fraction * 100).rounded()))%"
        drawText(
            pct,
            at: CGPoint(x: center.x, y: center.y - fontSize * 0.63),
            fontSize: fontSize,
            weight: .bold,
            color: .white,
            align: .center,
            maxWidth: radius * 2.3,
            monospaced: true
        )
    }
}

func drawBadge(
    _ cg: CGContext,
    text: String,
    origin: CGPoint,
    accent: NSColor,
    fontSize: CGFloat = 16,
    height: CGFloat = 28
) -> CGFloat {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let w = (text as NSString).size(withAttributes: [.font: font]).width + 20
    drawRoundedRect(
        cg,
        rect: CGRect(x: origin.x, y: origin.y, width: w, height: height),
        radius: height / 2,
        fill: accent.withAlphaComponent(0.18),
        stroke: accent.withAlphaComponent(0.48),
        lineWidth: 1.2
    )
    drawText(
        text,
        at: CGPoint(x: origin.x + w / 2, y: origin.y + (height - fontSize * 1.25) / 2),
        fontSize: fontSize,
        weight: .bold,
        color: accent,
        align: .center,
        maxWidth: w
    )
    return w
}

func drawBentoCard(
    _ cg: CGContext,
    rect: CGRect,
    badgeText: String,
    badgeColor: NSColor,
    title: String,
    fiveHFraction: CGFloat,
    fiveHMeta: String,
    fiveHColor: NSColor,
    weeklyFraction: CGFloat,
    weeklyMeta: String,
    weeklyColor: NSColor
) {
    drawRoundedRect(
        cg,
        rect: rect,
        radius: 28,
        fill: NSColor(calibratedWhite: 1.0, alpha: 0.065),
        stroke: NSColor(calibratedWhite: 1.0, alpha: 0.18),
        lineWidth: 1.4
    )

    let gaugeCenter = CGPoint(x: rect.minX + 66, y: rect.midY)
    drawGauge(cg, center: gaugeCenter, radius: 42, lineWidth: 8.0, fraction: fiveHFraction, color: fiveHColor, showText: true, fontSize: 24)

    let contentX = rect.minX + 132
    let contentRight = rect.maxX - 26
    let contentW = contentRight - contentX

    // Top row: provider badge + title + 5h meta
    let badgeW = drawBadge(cg, text: badgeText, origin: CGPoint(x: contentX, y: rect.minY + 21), accent: badgeColor, fontSize: 15, height: 28)
    drawText(
        title,
        at: CGPoint(x: contentX + badgeW + 10, y: rect.minY + 19),
        fontSize: 26,
        weight: .bold,
        color: .white
    )
    drawText(
        fiveHMeta,
        at: CGPoint(x: contentRight, y: rect.minY + 22),
        fontSize: 21,
        weight: .bold,
        color: fiveHColor,
        align: .right,
        maxWidth: 320,
        monospaced: true
    )

    // Weekly label + value
    drawText(
        "Weekly limit",
        at: CGPoint(x: contentX, y: rect.minY + 67),
        fontSize: 19,
        weight: .medium,
        color: NSColor(calibratedWhite: 0.88, alpha: 0.78)
    )
    drawText(
        weeklyMeta,
        at: CGPoint(x: contentRight, y: rect.minY + 67),
        fontSize: 19,
        weight: .semibold,
        color: NSColor(calibratedWhite: 1.0, alpha: 0.94),
        align: .right,
        maxWidth: 320,
        monospaced: true
    )

    // Progress bar
    let barRect = CGRect(x: contentX, y: rect.minY + 102, width: contentW, height: 10)
    drawRoundedRect(cg, rect: barRect, radius: 5, fill: NSColor(calibratedWhite: 1.0, alpha: 0.13))
    let fillRect = CGRect(x: barRect.minX, y: barRect.minY, width: max(barRect.width * weeklyFraction, 14), height: barRect.height)
    drawRoundedRect(cg, rect: fillRect, radius: 5, fill: weeklyColor)
}

// MARK: - Create Flipped Canvas (Top-Left Origin)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
let baseCtx = NSGraphicsContext(bitmapImageRep: rep)!
let cg = baseCtx.cgContext
cg.translateBy(x: 0, y: CGFloat(height))
cg.scaleBy(x: 1, y: -1)
let nsCtx = NSGraphicsContext(cgContext: cg, flipped: true)
nsCtx.imageInterpolation = .high
NSGraphicsContext.current = nsCtx

// 1. Deep Obsidian Space Gradient Background
let bgColors = [
    NSColor(calibratedRed: 0.045, green: 0.065, blue: 0.108, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.075, green: 0.118, blue: 0.172, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.035, green: 0.048, blue: 0.080, alpha: 1.0).cgColor
] as CFArray
let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0.0, 0.5, 1.0])!
cg.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: CGFloat(width), y: CGFloat(height)), options: [])

func drawGlow(_ center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    let gColors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gColors, locations: [0.0, 1.0])!
    cg.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}
drawGlow(CGPoint(x: 420, y: 520), radius: 560, color: cSky, alpha: 0.14)
drawGlow(CGPoint(x: 1460, y: 310), radius: 520, color: cEmerald, alpha: 0.12)
drawGlow(CGPoint(x: 1520, y: 740), radius: 440, color: cCoral, alpha: 0.09)

// 2. Left Hero Column (Big, Bold, Thumbnail-Readable!)
let leftX: CGFloat = 92
if let logoCG {
    cg.saveGState()
    let logoRect = CGRect(x: leftX, y: 84, width: 108, height: 108)
    let clipPath = CGPath(roundedRect: logoRect, cornerWidth: 26, cornerHeight: 26, transform: nil)
    cg.addPath(clipPath)
    cg.clip()
    cg.translateBy(x: logoRect.minX, y: logoRect.maxY)
    cg.scaleBy(x: 1, y: -1)
    cg.draw(logoCG, in: CGRect(x: 0, y: 0, width: logoRect.width, height: logoRect.height))
    cg.restoreGState()
}

drawText("OrbitHUD", at: CGPoint(x: leftX + 132, y: 82), fontSize: 64, weight: .heavy, color: .white)
_ = drawBadge(cg, text: "v1.2.0", origin: CGPoint(x: leftX + 448, y: 104), accent: cSky, fontSize: 20, height: 34)
drawText("Zero-Gravity Multi-Provider AI HUD", at: CGPoint(x: leftX + 134, y: 158), fontSize: 26, weight: .semibold, color: cEmerald)

drawText("One Glass HUD.\nAll Your AI Quotas.", at: CGPoint(x: leftX, y: 256), fontSize: 78, weight: .heavy, color: .white, maxWidth: 880)

drawText(
    "Live 5h & Weekly limits for Google Antigravity,\nplus opt-in Claude Code & OpenAI Codex CLI.",
    at: CGPoint(x: leftX, y: 472),
    fontSize: 30,
    weight: .medium,
    color: NSColor(calibratedWhite: 0.90, alpha: 0.86),
    maxWidth: 880
)

// Provider Legend Pills (Large & Bold)
let provLabels: [(String, NSColor)] = [
    ("Antigravity", cEmerald),
    ("Claude Code", cCoral),
    ("Codex CLI", cSky)
]
var px = leftX
for (label, col) in provLabels {
    let font = NSFont.systemFont(ofSize: 22, weight: .bold)
    let w = (label as NSString).size(withAttributes: [.font: font]).width + 52
    let pill = CGRect(x: px, y: 604, width: w, height: 48)
    drawRoundedRect(cg, rect: pill, radius: 24, fill: col.withAlphaComponent(0.14), stroke: col.withAlphaComponent(0.45), lineWidth: 1.4)
    cg.setFillColor(col.cgColor)
    cg.fillEllipse(in: CGRect(x: pill.minX + 18, y: pill.midY - 6, width: 12, height: 12))
    drawText(label, at: CGPoint(x: pill.minX + 38, y: pill.minY + 10), fontSize: 22, weight: .bold, color: .white)
    px += w + 16
}

// Package Manager Chips (Large & Clear)
let chips = [
    "Homebrew",
    "WinGet",
    "AUR",
    "macOS · Win · Linux"
]
var cx = leftX
for chip in chips {
    let font = NSFont.systemFont(ofSize: 20, weight: .semibold)
    let w = (chip as NSString).size(withAttributes: [.font: font]).width + 42
    let r = CGRect(x: cx, y: 744, width: w, height: 46)
    drawRoundedRect(
        cg,
        rect: r,
        radius: 23,
        fill: NSColor(calibratedWhite: 1.0, alpha: 0.08),
        stroke: NSColor(calibratedWhite: 1.0, alpha: 0.20),
        lineWidth: 1.2
    )
    drawText(chip, at: CGPoint(x: r.midX, y: r.minY + 10), fontSize: 20, weight: .semibold, color: NSColor(calibratedWhite: 0.95, alpha: 0.95), align: .center, maxWidth: w)
    cx += w + 14
}

drawText("github.com/mojtaba-afraz/OrbitHUD", at: CGPoint(x: leftX, y: 834), fontSize: 26, weight: .bold, color: cSky)

// 3. Right Showcase Column — Large Crisp Bento Glass HUD + 52px Compact Pill
let hudX: CGFloat = 1044
let hudW: CGFloat = 784
let hudY: CGFloat = 68
let hudH: CGFloat = 636
let hudRect = CGRect(x: hudX, y: hudY, width: hudW, height: hudH)

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: 20), blur: 44, color: NSColor.black.withAlphaComponent(0.55).cgColor)
drawRoundedRect(
    cg,
    rect: hudRect,
    radius: 40,
    fill: NSColor(calibratedRed: 0.075, green: 0.088, blue: 0.125, alpha: 0.95),
    stroke: NSColor(calibratedWhite: 1.0, alpha: 0.24),
    lineWidth: 1.8
)
cg.restoreGState()

// Header Row inside Bento HUD
drawOrbitGlyph(cg, center: CGPoint(x: hudX + 46, y: hudY + 46), size: 34)
drawText("OrbitHUD", at: CGPoint(x: hudX + 72, y: hudY + 29), fontSize: 28, weight: .bold, color: .white)
cg.setFillColor(cEmerald.cgColor)
cg.fillEllipse(in: CGRect(x: hudX + 208, y: hudY + 40, width: 11, height: 11))
let floatPill = CGRect(x: hudX + 232, y: hudY + 29, width: 82, height: 32)
drawRoundedRect(cg, rect: floatPill, radius: 16, fill: NSColor(calibratedWhite: 1.0, alpha: 0.11))
drawText("Float", at: CGPoint(x: floatPill.midX, y: floatPill.minY + 5), fontSize: 18, weight: .semibold, color: NSColor(calibratedWhite: 0.90, alpha: 0.90), align: .center, maxWidth: 82)

let pinBtn = CGRect(x: hudX + hudW - 266, y: hudY + 26, width: 138, height: 38)
drawRoundedRect(cg, rect: pinBtn, radius: 19, fill: NSColor(calibratedWhite: 1.0, alpha: 0.12), stroke: NSColor(calibratedWhite: 1.0, alpha: 0.24), lineWidth: 1.2)
drawText("Pin Desktop", at: CGPoint(x: pinBtn.midX, y: pinBtn.minY + 8), fontSize: 17.5, weight: .semibold, color: .white, align: .center, maxWidth: 138)
for (idx, icon) in ["⤡", "↻", "⚙"].enumerated() {
    let bx = hudX + hudW - 116 + CGFloat(idx) * 34
    let br = CGRect(x: bx, y: hudY + 30, width: 30, height: 30)
    drawRoundedRect(cg, rect: br, radius: 15, fill: NSColor(calibratedWhite: 1.0, alpha: 0.11), stroke: NSColor(calibratedWhite: 1.0, alpha: 0.22), lineWidth: 1.0)
    drawText(icon, at: CGPoint(x: br.midX, y: br.minY + 4), fontSize: 16, weight: .semibold, color: .white, align: .center, maxWidth: 30)
}

// Segmented Glass Provider Filter Bar
let tabBarRect = CGRect(x: hudX + 26, y: hudY + 86, width: hudW - 52, height: 48)
drawRoundedRect(
    cg,
    rect: tabBarRect,
    radius: 24,
    fill: NSColor(calibratedWhite: 1.0, alpha: 0.065),
    stroke: NSColor(calibratedWhite: 1.0, alpha: 0.15),
    lineWidth: 1.2
)
let tabs: [(String, NSColor?, Bool)] = [
    ("All", nil, true),
    ("Antigravity", cEmerald, false),
    ("Claude", cCoral, false),
    ("Codex", cSky, false)
]
let tabW = (tabBarRect.width - 12) / CGFloat(tabs.count)
for (idx, tab) in tabs.enumerated() {
    let tx = tabBarRect.minX + 6 + CGFloat(idx) * tabW
    let tr = CGRect(x: tx, y: tabBarRect.minY + 5, width: tabW, height: tabBarRect.height - 10)
    if tab.2 {
        drawRoundedRect(cg, rect: tr, radius: 19, fill: NSColor(calibratedWhite: 1.0, alpha: 0.18), stroke: NSColor(calibratedWhite: 1.0, alpha: 0.22), lineWidth: 1.0)
    }
    if let dotColor = tab.1 {
        let labelW = (tab.0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 19, weight: .semibold)]).width
        let startX = tr.midX - (labelW + 17) / 2
        cg.setFillColor(dotColor.cgColor)
        cg.fillEllipse(in: CGRect(x: startX, y: tr.midY - 5, width: 10, height: 10))
        drawText(tab.0, at: CGPoint(x: startX + 16, y: tr.minY + 7), fontSize: 19, weight: .semibold, color: tab.2 ? .white : NSColor(calibratedWhite: 0.90, alpha: 0.84))
    } else {
        drawText(tab.0, at: CGPoint(x: tr.midX, y: tr.minY + 7), fontSize: 19, weight: .bold, color: .white, align: .center, maxWidth: tr.width)
    }
}

// 3 Multi-Provider Bento Cards
let cardW = hudW - 52
let cardH: CGFloat = 138
let cardGap: CGFloat = 18
let firstCardY = hudY + 154

drawBentoCard(
    cg,
    rect: CGRect(x: hudX + 26, y: firstCardY, width: cardW, height: cardH),
    badgeText: "AGY",
    badgeColor: cEmerald,
    title: "Gemini Models",
    fiveHFraction: 0.68,
    fiveHMeta: "5h: 68% · 2h 40m",
    fiveHColor: cEmerald,
    weeklyFraction: 0.82,
    weeklyMeta: "82% left · 5d 4h",
    weeklyColor: cEmerald
)

drawBentoCard(
    cg,
    rect: CGRect(x: hudX + 26, y: firstCardY + cardH + cardGap, width: cardW, height: cardH),
    badgeText: "CC",
    badgeColor: cCoral,
    title: "Claude Code",
    fiveHFraction: 0.34,
    fiveHMeta: "5h: 34% · 1h 15m",
    fiveHColor: cAmber,
    weeklyFraction: 0.78,
    weeklyMeta: "78% left · 6d 2h",
    weeklyColor: cEmerald
)

drawBentoCard(
    cg,
    rect: CGRect(x: hudX + 26, y: firstCardY + (cardH + cardGap) * 2, width: cardW, height: cardH),
    badgeText: "CDX",
    badgeColor: cSky,
    title: "Codex CLI (Plus)",
    fiveHFraction: 0.86,
    fiveHMeta: "5h: 86% · 4h 12m",
    fiveHColor: cEmerald,
    weeklyFraction: 0.91,
    weeklyMeta: "91% left · 5d 18h",
    weeklyColor: cEmerald
)

// 4. Sleek 52px Compact Coding Pill (Large & Razor-Sharp)
let pillRect = CGRect(x: hudX, y: 742, width: hudW, height: 108)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: 16), blur: 36, color: NSColor.black.withAlphaComponent(0.52).cgColor)
drawRoundedRect(
    cg,
    rect: pillRect,
    radius: 54,
    fill: NSColor(calibratedRed: 0.075, green: 0.088, blue: 0.125, alpha: 0.95),
    stroke: NSColor(calibratedWhite: 1.0, alpha: 0.24),
    lineWidth: 1.6
)
cg.restoreGState()

let pillMetrics: [(CGFloat, String, NSColor, NSColor)] = [
    (0.68, "Gem 5h", cEmerald, cEmerald),
    (0.82, "Gem Wk", cEmerald, cEmerald),
    (0.34, "CC 5h",  cAmber,   cCoral),
    (0.86, "CDX 5h", cEmerald, cSky)
]
let slotW: CGFloat = 162
let startPillX = pillRect.minX + 28
for (idx, item) in pillMetrics.enumerated() {
    let sx = startPillX + CGFloat(idx) * slotW
    let gCenter = CGPoint(x: sx + 26, y: pillRect.midY)
    drawGauge(cg, center: gCenter, radius: 24, lineWidth: 5.2, fraction: item.0, color: item.2, showText: false)
    drawText("\(Int((item.0 * 100).rounded()))%", at: CGPoint(x: sx + 58, y: pillRect.midY - 27), fontSize: 24, weight: .bold, color: .white, monospaced: true)
    cg.setFillColor(item.3.cgColor)
    cg.fillEllipse(in: CGRect(x: sx + 59, y: pillRect.midY + 10, width: 9, height: 9))
    drawText(item.1, at: CGPoint(x: sx + 73, y: pillRect.midY + 3), fontSize: 17.5, weight: .semibold, color: NSColor(calibratedWhite: 0.88, alpha: 0.84))
}

for (idx, sym) in ["⤢", "⚙"].enumerated() {
    let bx = pillRect.maxX - 102 + CGFloat(idx) * 44
    let br = CGRect(x: bx, y: pillRect.midY - 19, width: 38, height: 38)
    drawRoundedRect(cg, rect: br, radius: 19, fill: NSColor(calibratedWhite: 1.0, alpha: 0.11), stroke: NSColor(calibratedWhite: 1.0, alpha: 0.22), lineWidth: 1.1)
    drawText(sym, at: CGPoint(x: br.midX, y: br.minY + 6), fontSize: 19, weight: .semibold, color: .white, align: .center, maxWidth: 38)
}

drawText(
    "Compact Coding Pill (52px)  ·  Dynamic Models & Hide/Show",
    at: CGPoint(x: pillRect.midX, y: pillRect.maxY + 20),
    fontSize: 21,
    weight: .semibold,
    color: NSColor(calibratedWhite: 0.84, alpha: 0.78),
    align: .center,
    maxWidth: 780
)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
try pngData.write(to: URL(fileURLWithPath: outPath))
print("✅ Rendered bold v1.2.0 showcase banner (\(width)x\(height)) to \(outPath)")
