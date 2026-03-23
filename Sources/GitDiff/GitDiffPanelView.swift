import SwiftUI

struct GitDiffPanelView: View {
    @ObservedObject var viewModel: GitDiffViewModel

    var body: some View {
        VStack(spacing: 0) {
            GitDiffHeaderView(viewModel: viewModel)
            Divider()
            if viewModel.isLoading {
                Spacer()
                Text(String(localized: "gitdiff.loading.message", defaultValue: "Loading diff…"))
                    .foregroundStyle(.secondary)
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else if viewModel.statLines.isEmpty && viewModel.diffLines.isEmpty {
                Spacer()
                Text(String(localized: "gitdiff.noChanges.message", defaultValue: "No unstaged changes"))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                GitDiffStatView(statLines: viewModel.statLines)
                Divider()
                GitDiffContentView(diffLines: viewModel.diffLines)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct GitDiffHeaderView: View {
    @ObservedObject var viewModel: GitDiffViewModel
    @EnvironmentObject var gitDiffPanelState: GitDiffPanelState

    var body: some View {
        HStack {
            Image(systemName: "arrow.left.arrow.right")
            Text(String(localized: "gitdiff.panel.title", defaultValue: "Code Review"))
                .fontWeight(.semibold)
            if let branch = viewModel.currentBranch {
                Text(branch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            Button(action: { gitDiffPanelState.toggle() }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct GitDiffStatView: View {
    let statLines: [GitStatLine]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(statLines) { line in
                    HStack(spacing: 4) {
                        Text(line.filename)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        if line.insertions > 0 {
                            Text("+\(line.insertions)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(red: 0.3, green: 0.75, blue: 0.3))
                        }
                        if line.deletions > 0 {
                            Text("-\(line.deletions)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(red: 0.85, green: 0.35, blue: 0.35))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 120)
    }
}

struct GitDiffContentView: View {
    let diffLines: [GitDiffLine]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(diffLines) { line in
                    GitDiffLineView(line: line)
                }
            }
        }
    }
}

struct GitDiffLineView: View {
    let line: GitDiffLine

    var body: some View {
        Text(line.text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(foregroundColor)
            .italic(line.kind == .hunkHeader)
            .fontWeight(line.kind == .fileHeader ? .bold : .regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 0.5)
            .background(backgroundColor)
            .allowsHitTesting(false)
    }

    private var foregroundColor: Color {
        switch line.kind {
        case .added: return Color(red: 0.3, green: 0.75, blue: 0.3)
        case .removed: return Color(red: 0.85, green: 0.35, blue: 0.35)
        case .hunkHeader: return .secondary
        case .fileHeader: return .primary
        case .context: return .primary
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .added: return Color(red: 0.3, green: 0.75, blue: 0.3).opacity(0.08)
        case .removed: return Color(red: 0.85, green: 0.35, blue: 0.35).opacity(0.08)
        default: return .clear
        }
    }
}
