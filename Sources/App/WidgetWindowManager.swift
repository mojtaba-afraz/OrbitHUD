import AppKit
import SwiftUI
#if canImport(AntigravityUsageCore)
import AntigravityUsageCore
#endif

/// Custom NSPanel that intercepts mouse drag events at the window level so the user can drag the widget
/// from anywhere on its surface, while still allowing normal clicks on buttons.
final class WidgetPanel: NSPanel {
    var isDraggingEnabled: Bool = true
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var isCurrentlyDragging: Bool = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard isDraggingEnabled else {
            super.sendEvent(event)
            return
        }

        switch event.type {
        case .leftMouseDown:
            dragStartMouseLocation = NSEvent.mouseLocation
            dragStartWindowOrigin = frame.origin
            isCurrentlyDragging = false
            super.sendEvent(event)

        case .leftMouseDragged:
            guard let startMouse = dragStartMouseLocation,
                  let startOrigin = dragStartWindowOrigin else {
                super.sendEvent(event)
                return
            }
            let currentMouse = NSEvent.mouseLocation
            let dx = currentMouse.x - startMouse.x
            let dy = currentMouse.y - startMouse.y

            if isCurrentlyDragging || hypot(dx, dy) > 3.0 {
                isCurrentlyDragging = true
                setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
            } else {
                super.sendEvent(event)
            }

        case .leftMouseUp:
            let wasDragging = isCurrentlyDragging
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
            isCurrentlyDragging = false

            if wasDragging {
                saveFrame(usingName: frameAutosaveName)
            }
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class WidgetWindowManager {
    private var desktopPanel: WidgetPanel?
    private var floatingPanel: WidgetPanel?
    private let viewModel: UsageViewModel

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        setupWindows()
        viewModel.onWindowConfigChanged = { [weak self] in
            self?.applyConfiguration()
        }
        applyConfiguration()
    }

    private func setupWindows() {
        desktopPanel = createPanel(
            role: .desktopPinned,
            autosaveName: "AntigravityIOSDesktopWidgetFrame",
            defaultOriginOffset: CGPoint(x: 28, y: 120)
        )
        floatingPanel = createPanel(
            role: .floatingHUD,
            autosaveName: "AntigravityIOSFloatingWidgetFrame",
            defaultOriginOffset: CGPoint(x: 28, y: 40)
        )
    }

    private func createPanel(
        role: WidgetDisplayMode,
        autosaveName: String,
        defaultOriginOffset: CGPoint
    ) -> WidgetPanel {
        let initialSize = viewModel.isCompactMode
            ? CGSize(width: 356, height: 68)
            : CGSize(width: 356, height: 280)
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: screenRect.maxX - initialSize.width - defaultOriginOffset.x,
            y: screenRect.maxY - initialSize.height - defaultOriginOffset.y
        )

        let panel = WidgetPanel(
            contentRect: NSRect(origin: origin, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName(autosaveName)

        let rootView = UsageWidgetView(
            viewModel: viewModel,
            windowRole: role
        )
        let hostingView = FirstMouseHostingView(rootView: rootView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView

        return panel
    }

    func applyConfiguration() {
        let targetSize = viewModel.isCompactMode
            ? CGSize(width: 356, height: 68)
            : CGSize(width: 356, height: 280)

        // 1. Desktop Pinned Widget Window (just below normal app windows so it stays on desktop & accepts mouse drags)
        if let desktopPanel {
            let belowNormalLevel = Int(CGWindowLevelForKey(.normalWindow)) - 1
            desktopPanel.level = NSWindow.Level(rawValue: belowNormalLevel)
            desktopPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            desktopPanel.alphaValue = viewModel.windowOpacity
            desktopPanel.isDraggingEnabled = !viewModel.isDesktopPositionLocked
            resizePanelIfNeeded(desktopPanel, to: targetSize)

            if viewModel.displayMode == .desktopPinned || viewModel.displayMode == .both {
                desktopPanel.orderFrontRegardless()
            } else {
                desktopPanel.orderOut(nil)
            }
        }

        // 2. Floating Always-on-Top Widget Window
        if let floatingPanel {
            floatingPanel.level = .floating
            floatingPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            floatingPanel.alphaValue = viewModel.windowOpacity
            floatingPanel.isDraggingEnabled = true
            resizePanelIfNeeded(floatingPanel, to: targetSize)

            if viewModel.displayMode == .floatingHUD || viewModel.displayMode == .both {
                floatingPanel.orderFrontRegardless()
            } else {
                floatingPanel.orderOut(nil)
            }
        }
    }

    private func resizePanelIfNeeded(_ panel: NSPanel, to newSize: CGSize) {
        var frame = panel.frame
        guard abs(frame.width - newSize.width) > 1 || abs(frame.height - newSize.height) > 1 else {
            return
        }
        // Keep top-right corner anchored
        let maxX = frame.maxX
        let maxY = frame.maxY
        frame.size = newSize
        frame.origin.x = maxX - newSize.width
        frame.origin.y = maxY - newSize.height
        panel.setFrame(frame, display: true, animate: true)
    }
}
