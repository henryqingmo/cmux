import SwiftUI
import AppKit

struct GitDiffResizeHandle: View {
    @ObservedObject var panelState: GitDiffPanelState
    @State private var isHovered = false
    @State private var dragStartWidth: CGFloat? = nil

    var body: some View {
        Rectangle()
            .fill(isHovered ? Color(NSColor.separatorColor).opacity(0.5) : Color(NSColor.separatorColor).opacity(0.2))
            .frame(width: 4)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = panelState.persistedWidth
                            TerminalWindowPortalRegistry.beginInteractiveGeometryResize()
                        }
                        let newWidth = (dragStartWidth ?? panelState.persistedWidth) - value.translation.width
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            panelState.persistedWidth = max(
                                GitDiffPanelState.minimumWidth,
                                min(GitDiffPanelState.maximumWidth, newWidth)
                            )
                        }
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        TerminalWindowPortalRegistry.endInteractiveGeometryResize()
                    }
            )
    }
}
