import Foundation
import SwiftUI

// MARK: - Data structs

struct GitStatLine: Identifiable {
    let id = UUID()
    let filename: String
    let insertions: Int
    let deletions: Int
}

enum GitDiffLineKind {
    case context, added, removed, hunkHeader, fileHeader
}

struct GitDiffLine: Identifiable {
    let id = UUID()
    let text: String
    let kind: GitDiffLineKind
}

// MARK: - ViewModel

@MainActor final class GitDiffViewModel: ObservableObject {
    @Published var statLines: [GitStatLine] = []
    @Published var diffLines: [GitDiffLine] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var repoRoot: String? = nil
    @Published var currentBranch: String? = nil

    var workingDirectory: String? {
        didSet {
            guard workingDirectory != oldValue else { return }
            resolveRepoRootAndRestart()
        }
    }

    private let queue = DispatchQueue(label: "com.cmux.git-diff", qos: .utility)

    // nonisolated(unsafe) because deinit is not guaranteed to run on the
    // main actor, but DispatchSource.cancel() is thread-safe.
    private nonisolated(unsafe) var indexWatchSource: DispatchSourceFileSystemObject?
    private nonisolated(unsafe) var headWatchSource: DispatchSourceFileSystemObject?
    private var indexFd: Int32 = -1
    private var headFd: Int32 = -1

    private var debounceWorkItem: DispatchWorkItem?

    private static let diffLineCap = 5000

    // MARK: - Working directory / repo root

    private func resolveRepoRootAndRestart() {
        guard let dir = workingDirectory else {
            stopWatcher()
            repoRoot = nil
            currentBranch = nil
            statLines = []
            diffLines = []
            errorMessage = nil
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
                DispatchQueue.main.async {
                    self.errorMessage = String(localized: "gitdiff.noRepo.message", defaultValue: "No git repository found")
                }
                return
            }
            let root = self.runGit(["rev-parse", "--show-toplevel"], in: dir)?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard let root, !root.isEmpty else {
                    self.stopWatcher()
                    self.repoRoot = nil
                    self.currentBranch = nil
                    self.statLines = []
                    self.diffLines = []
                    self.errorMessage = String(localized: "gitdiff.noRepo.message", defaultValue: "No git repository found")
                    return
                }
                self.repoRoot = root
                self.errorMessage = nil
                self.stopWatcher()
                self.startWatcher(repoRoot: root)
                self.scheduleRefresh()
            }
        }
    }

    // MARK: - File watcher

    private func startWatcher(repoRoot: String) {
        let gitDir = (repoRoot as NSString).appendingPathComponent(".git")
        let indexPath = (gitDir as NSString).appendingPathComponent("index")
        let headPath = (gitDir as NSString).appendingPathComponent("HEAD")

        let idxFd = open(indexPath, O_EVTONLY)
        if idxFd >= 0 {
            indexFd = idxFd
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: idxFd,
                eventMask: [.write, .extend],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduledDebounce()
            }
            source.setCancelHandler {
                Darwin.close(idxFd)
            }
            source.resume()
            indexWatchSource = source
        }

        let hFd = open(headPath, O_EVTONLY)
        if hFd >= 0 {
            headFd = hFd
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: hFd,
                eventMask: [.write, .extend],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduledDebounce()
            }
            source.setCancelHandler {
                Darwin.close(hFd)
            }
            source.resume()
            headWatchSource = source
        }
    }

    private func stopWatcher() {
        indexWatchSource?.cancel()
        indexWatchSource = nil
        headWatchSource?.cancel()
        headWatchSource = nil
        indexFd = -1
        headFd = -1
    }

    // MARK: - Debounce

    private nonisolated func scheduledDebounce() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.debounceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.refresh()
                }
            }
            self.debounceWorkItem = item
            self.queue.asyncAfter(deadline: .now() + 0.25, execute: item)
        }
    }

    private func scheduleRefresh() {
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        guard let root = repoRoot else { return }
        isLoading = true

        queue.async { [weak self] in
            guard let self else { return }
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = String(localized: "gitdiff.noRepo.message", defaultValue: "No git repository found")
                }
                return
            }

            let branch = self.runGit(["branch", "--show-current"], in: root)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let statOutput = self.runGit(["diff", "--stat", "--color=never"], in: root) ?? ""
            let diffOutput = self.runGit(["diff", "--color=never"], in: root) ?? ""

            let parsedStats = Self.parseStatLines(statOutput)
            let parsedDiff = Self.parseDiffLines(diffOutput)

            DispatchQueue.main.async {
                self.isLoading = false
                self.currentBranch = (branch?.isEmpty == false) ? branch : nil
                self.statLines = parsedStats
                self.diffLines = parsedDiff
            }
        }
    }

    // MARK: - Git process

    private nonisolated func runGit(_ args: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Parsing

    private static func parseStatLines(_ output: String) -> [GitStatLine] {
        var result: [GitStatLine] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            // Skip summary line ("X files changed, ...")
            if line.contains("file") && (line.contains("changed") || line.contains("insertion") || line.contains("deletion")) {
                continue
            }
            // Parse lines like " src/foo.swift | 5 ++---"
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let pipeRange = trimmed.range(of: "|") else { continue }
            let filename = trimmed[trimmed.startIndex..<pipeRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let afterPipe = trimmed[pipeRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            // afterPipe: "5 ++---" or "Bin 0 -> 1234 bytes"
            var insertions = 0
            var deletions = 0
            for ch in afterPipe {
                if ch == "+" { insertions += 1 }
                else if ch == "-" { deletions += 1 }
            }
            guard !filename.isEmpty else { continue }
            result.append(GitStatLine(filename: filename, insertions: insertions, deletions: deletions))
        }
        return result
    }

    private static func parseDiffLines(_ output: String) -> [GitDiffLine] {
        var result: [GitDiffLine] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if result.count >= diffLineCap { break }
            let kind: GitDiffLineKind
            if line.hasPrefix("+++") || line.hasPrefix("---") {
                kind = .fileHeader
            } else if line.hasPrefix("@@") {
                kind = .hunkHeader
            } else if line.hasPrefix("+") {
                kind = .added
            } else if line.hasPrefix("-") {
                kind = .removed
            } else {
                kind = .context
            }
            result.append(GitDiffLine(text: line, kind: kind))
        }
        return result
    }

    deinit {
        indexWatchSource?.cancel()
        headWatchSource?.cancel()
    }
}
