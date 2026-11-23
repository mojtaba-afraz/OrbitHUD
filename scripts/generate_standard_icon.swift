import AppKit
import CoreGraphics

let sourcePath = "/Users/mojtaba_afraz/.gemini/antigravity/brain/33ca9917-c653-40c0-93fa-6d1f7df81e1a/antigravity_app_icon_logo_1795436192063.jpg"
let outPngPath = "/Users/mojtaba_afraz/.gemini/antigravity/scratch/AntigravityUsageWidget/assets/logo.png"

guard let srcImage = NSImage(contentsOfFile: sourcePath),
      let srcTiff = srcImage.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: srcTiff),
      let srcCG = srcRep.cgImage else {
    fputs("Failed to load source image\n", stderr)
    exit(1)
}

// Crop center 650x650 of the 1024x1024 image so the outer white background & outer frame are 100% excluded
let cropSize: CGFloat = 650
let cropOrigin = (CGFloat(srcCG.width) - cropSize) / 2.0
let cropRect = CGRect(x: cropOrigin, y: cropOrigin, width: cropSize, height: cropSize)
guard let croppedCG = srcCG.cropping(to: cropRect) else {
    fputs("Failed to crop source image\n", stderr)
    exit(1)
}

func renderStandardMacIcon(canvasSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasSize,
        pixelsHigh: canvasSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let s = CGFloat(canvasSize)
    cg.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Apple macOS Big Sur / Sonoma / Sequoia HIG icon grid:
    // 824x824 squircle on a 1024x1024 canvas (100px transparent margin on all 4 sides = 9.765625%)
    let margin = s * (100.0 / 1024.0)
    let bodySize = s - (margin * 2.0)
    let bodyRect = CGRect(x: margin, y: margin, width: bodySize, height: bodySize)
    let cornerRadius = bodySize * 0.225 // Standard macOS squircle radius (~185.4px at 1024)

    let squirclePath = CGPath(
        roundedRect: bodyRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    // 1. Standard macOS icon drop shadow in the transparent margin
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -s * 0.010),
        blur: s * 0.024,
        color: NSColor(calibratedWhite: 0.0, alpha: 0.45).cgColor
    )
    cg.addPath(squirclePath)
    cg.setFillColor(NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.08, alpha: 1.0).cgColor)
    cg.fillPath()
    cg.restoreGState()

    // 2. Clip to squircle and draw the cropped 3D Glassmorphic orbital artwork filling the squircle
    cg.saveGState()
    cg.addPath(squirclePath)
    cg.clip()

    cg.setFillColor(NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.08, alpha: 1.0).cgColor)
    cg.fill(bodyRect)

    cg.interpolationQuality = .high
    cg.draw(croppedCG, in: bodyRect)

    // Subtle dark vignette near squircle edges so corners blend seamlessly
    let colors = [
        NSColor.clear.cgColor,
        NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.07, alpha: 0.55).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.68, 1.0]) {
        let center = CGPoint(x: s / 2.0, y: s / 2.0)
        cg.drawRadialGradient(
            grad,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: bodySize * 0.72,
            options: [.drawsAfterEndLocation]
        )
    }
    cg.restoreGState()

    // 3. Subtle inner glass rim highlight along the squircle edge
    cg.saveGState()
    let insetRect = bodyRect.insetBy(dx: s * 0.002, dy: s * 0.002)
    let borderPath = CGPath(
        roundedRect: insetRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    cg.addPath(borderPath)
    cg.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.22).cgColor)
    cg.setLineWidth(max(s * 0.003, 1.0))
    cg.strokePath()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

guard let png1024 = renderStandardMacIcon(canvasSize: 1024) else {
    fputs("Failed to render 1024 PNG\n", stderr)
    exit(1)
}
try png1024.write(to: URL(fileURLWithPath: outPngPath))
print("Wrote standard HIG transparent 1024x1024 PNG to \(outPngPath)")

// Pack ICNS with ic07 (128), ic08 (256), ic09 (512), ic10 (1024)
let tagsAndSizes: [(String, Int)] = [
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024)
]

var icnsBody = Data()
for (tag, sz) in tagsAndSizes {
    if let pngData = renderStandardMacIcon(canvasSize: sz) {
        var chunkHeader = Data(tag.utf8)
        var chunkLen = UInt32(8 + pngData.count).bigEndian
        chunkHeader.append(Data(bytes: &chunkLen, count: 4))
        icnsBody.append(chunkHeader)
        icnsBody.append(pngData)
    }
}

var icnsData = Data("icns".utf8)
var totalLen = UInt32(8 + icnsBody.count).bigEndian
icnsData.append(Data(bytes: &totalLen, count: 4))
icnsData.append(icnsBody)

let icnsPath = "/Users/mojtaba_afraz/.gemini/antigravity/scratch/AntigravityUsageWidget/assets/AppIcon.icns"
try icnsData.write(to: URL(fileURLWithPath: icnsPath))
print("Wrote standard HIG AppIcon.icns (\(icnsData.count) bytes)")
