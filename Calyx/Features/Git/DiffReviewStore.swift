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

@MainActor @Observable
class DiffReviewStore {
    var comments: [ReviewComment] = []
    var hasUnsubmittedComments: Bool { !comments.isEmpty }

    func addComment(lineIndex: Int, lineNumber: Int?, oldLineNumber: Int?, lineType: DiffLineType, text: String) {
        // Strip newlines for single-line constraint
        let sanitized = text.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        
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
    }

    func removeComment(id: UUID) {
        comments.removeAll { $0.id == id }
    }

    func updateComment(id: UUID, text: String) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        let sanitized = text.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        comments[index].text = sanitized
    }

    func clearAll() {
        comments.removeAll()
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
