import AppKit
import SwiftUI

/// A short message near the bottom of the screen ("Copied 42 words"), gone after a moment. It never
/// takes focus or clicks, so the app you're in keeps both. Used from the main thread only (not marked
/// @MainActor, like AppDelegate, which calls it).
final class Toast {
    private let panel = ShelfPanel()
    private var generation = 0

    init() {
        panel.allowsKey = false
        panel.ignoresMouseEvents = true
    }

    func show(_ text: String, symbol: String) {
        generation += 1
        let shown = generation
        panel.host(ToastView(text: text, symbol: symbol))
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let fitting = panel.contentView?.fittingSize ?? .zero
        let width = min(max(fitting.width, 180), min(560, frame.width - 32))
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY + 72, width: width, height: 40), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.generation == shown else { return }   // a newer message replaced it
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.panel.animator().alphaValue = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.generation == shown else { return }
            self.panel.orderOut(nil)
        }
    }
}

private struct ToastView: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .fixedSize(horizontal: true, vertical: false)
    }
}
