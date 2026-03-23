import SwiftUI

@MainActor final class GitDiffPanelState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var persistedWidth: CGFloat = 380

    static let minimumWidth: CGFloat = 280
    static let maximumWidth: CGFloat = 700

    func toggle() { isVisible.toggle() }
}
