// DiffReviewStore.swift
// Calyx
//
// Model and store for inline diff review comments.

import Foundation

struct ReviewComment: Identifiable, Sendable {
    let id: UUID
    let lineIndex: Int           // FileDiff.lines[] index (snapshot-fixed)
    let displayLineNumber: String // For submission ("L42", "L42(old)")
    let lineType: DiffLineType   // addition/deletion/context only
    var text: String             // single-line only (no newlines)
}

enum DisplayLine: Sendable {
    case diff(DiffLine)
    case commentBlock(ReviewComment)
}

enum ReviewSendResult {
    case sent
    case cancelled
    case failed
}

@MainActor @Observable
class DiffReviewStore {
    var comments: [ReviewComment] = []
    var hasUnsubmittedComments: Bool { !comments.isEmpty }
    var onCommentsChanged: (() -> Void)?

    func addComment(lineIndex: Int, lineNumber: Int?, oldLineNumber: Int?, lineType: DiffLineType, text: String) {
        // Strip newlines for single-line constraint
        let sanitized = Self.sanitizeForTerminal(text)

        // Determine displayLineNumber
        let displayLineNumber: String
        switch lineType {
        case .deletion:
            displayLineNumber = "L\(oldLineNumber ?? 0)(old)"
        case .addition, .context:
            displayLineNumber = "L\(lineNumber ?? 0)"
        default:
            displayLineNumber = "L?"
        }
        
        let comment = ReviewComment(
            id: UUID(),
            lineIndex: lineIndex,
            displayLineNumber: displayLineNumber,
            lineType: lineType,
            text: sanitized
        )
        comments.append(comment)
        onCommentsChanged?()
    }

    func removeComment(id: UUID) {
        comments.removeAll { $0.id == id }
        onCommentsChanged?()
    }

    func updateComment(id: UUID, text: String) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        let sanitized = Self.sanitizeForTerminal(text)
        comments[index].text = sanitized
        onCommentsChanged?()
    }

    func clearAll() {
        comments.removeAll()
        onCommentsChanged?()
    }

    func formatForSubmission(filePath: String) -> String {
        let sorted = comments.sorted { $0.lineIndex < $1.lineIndex }
        var lines: [String] = ["[Code Review] \(filePath)", ""]
        for comment in sorted {
            let typeChar: String
            switch comment.lineType {
            case .addition: typeChar = "+"
            case .deletion: typeChar = "-"
            case .context: typeChar = " "
            default: typeChar = "?"
            }
            lines.append("\(comment.displayLineNumber) (\(typeChar)): \(comment.text)")
        }
        return lines.joined(separator: "\n")
    }
    
    /// Formats comments from multiple file stores into a single submission string.
    static func formatAllForSubmission(_ entries: [(source: DiffSource, store: DiffReviewStore)]) -> String {
        // Filter out empty stores
        let nonEmpty = entries.filter { $0.store.hasUnsubmittedComments }
        guard !nonEmpty.isEmpty else { return "" }

        // Sort by filePath first, then source kind (staged < unstaged < commit < untracked)
        let sorted = nonEmpty.sorted { a, b in
            let pathA = Self.filePath(from: a.source)
            let pathB = Self.filePath(from: b.source)
            if pathA != pathB { return pathA < pathB }
            return Self.sourceOrder(a.source) < Self.sourceOrder(b.source)
        }

        let fileCount = sorted.count
        let header = "[Code Review] \(fileCount) file\(fileCount == 1 ? "" : "s")"
        var lines: [String] = [header]

        for entry in sorted {
            let path = Self.filePath(from: entry.source)
            let label = Self.sourceLabel(entry.source)
            lines.append("")
            lines.append("--- \(path) (\(label)) ---")

            let sortedComments = entry.store.comments.sorted { $0.lineIndex < $1.lineIndex }
            for comment in sortedComments {
                let typeChar: String
                switch comment.lineType {
                case .addition: typeChar = "+"
                case .deletion: typeChar = "-"
                case .context: typeChar = " "
                default: typeChar = "?"
                }
                lines.append("\(comment.displayLineNumber) (\(typeChar)): \(comment.text)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func filePath(from source: DiffSource) -> String {
        switch source {
        case .unstaged(let p, _), .staged(let p, _), .commit(_, let p, _), .untracked(let p, _):
            return p
        }
    }

    private static func sourceLabel(_ source: DiffSource) -> String {
        switch source {
        case .staged: return "staged"
        case .unstaged: return "unstaged"
        case .commit(let hash, _, _): return String(hash.prefix(7))
        case .untracked: return "untracked"
        }
    }

    private static func sourceOrder(_ source: DiffSource) -> Int {
        switch source {
        case .staged: return 0
        case .unstaged: return 1
        case .commit: return 2
        case .untracked: return 3
        }
    }

    private static func sanitizeForTerminal(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            if scalar.value == 0x09 { return " " }
            // Strip C0 (0x00-0x1F), DEL (0x7F), and C1 (0x80-0x9F) control characters
            if scalar.value < 0x20 || scalar.value == 0x7F || (scalar.value >= 0x80 && scalar.value <= 0x9F) { return "" }
            return String(scalar)
        }.joined()
    }

    func buildDisplayLines(from diffLines: [DiffLine]) -> [DisplayLine] {
        // Build lookup: lineIndex -> [ReviewComment]
        var commentsByLine: [Int: [ReviewComment]] = [:]
        for comment in comments {
            commentsByLine[comment.lineIndex, default: []].append(comment)
        }
        
        var result: [DisplayLine] = []
        for (index, line) in diffLines.enumerated() {
            result.append(.diff(line))
            if let lineComments = commentsByLine[index] {
                for comment in lineComments {
                    result.append(.commentBlock(comment))
                }
            }
        }
        return result
    }
}
