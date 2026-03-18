// DiffReviewStoreTests.swift
// CalyxTests
//
// Tests for DiffReviewStore: comment CRUD, submission formatting,
// displayLine interleaving, and input sanitization.

import Testing
@testable import Calyx

// MARK: - Helpers

/// Build a DiffLine for testing without requiring a real parser.
private func makeDiffLine(
    type: DiffLineType,
    text: String,
    oldLineNumber: Int? = nil,
    newLineNumber: Int? = nil
) -> DiffLine {
    DiffLine(type: type, text: text, oldLineNumber: oldLineNumber, newLineNumber: newLineNumber)
}

// MARK: - Store Logic Tests

@MainActor
@Suite("DiffReviewStore CRUD Tests")
struct DiffReviewStoreCRUDTests {

    @Test func test_addComment_increasesCount() {
        let store = DiffReviewStore()
        #expect(store.comments.isEmpty)

        store.addComment(
            lineIndex: 0,
            lineNumber: 42,
            oldLineNumber: nil,
            lineType: .addition,
            text: "looks good"
        )

        #expect(store.comments.count == 1)
    }

    @Test func test_removeComment_decreasesCount() {
        let store = DiffReviewStore()
        store.addComment(
            lineIndex: 0,
            lineNumber: 10,
            oldLineNumber: nil,
            lineType: .addition,
            text: "first"
        )
        store.addComment(
            lineIndex: 1,
            lineNumber: 11,
            oldLineNumber: nil,
            lineType: .addition,
            text: "second"
        )
        #expect(store.comments.count == 2)

        let idToRemove = store.comments[0].id
        store.removeComment(id: idToRemove)

        #expect(store.comments.count == 1)
        #expect(store.comments.first?.text == "second")
    }

    @Test func test_updateComment_changesText() {
        let store = DiffReviewStore()
        store.addComment(
            lineIndex: 0,
            lineNumber: 5,
            oldLineNumber: nil,
            lineType: .addition,
            text: "original"
        )
        let commentID = store.comments[0].id

        store.updateComment(id: commentID, text: "updated")

        #expect(store.comments[0].text == "updated")
    }

    @Test func test_clearAll_emptiesComments() {
        let store = DiffReviewStore()
        store.addComment(
            lineIndex: 0,
            lineNumber: 1,
            oldLineNumber: nil,
            lineType: .addition,
            text: "a"
        )
        store.addComment(
            lineIndex: 1,
            lineNumber: 2,
            oldLineNumber: nil,
            lineType: .context,
            text: "b"
        )
        #expect(store.comments.count == 2)

        store.clearAll()

        #expect(store.comments.isEmpty)
    }

    @Test func test_hasUnsubmittedComments_trueWhenNotEmpty() {
        let store = DiffReviewStore()
        store.addComment(
            lineIndex: 0,
            lineNumber: 1,
            oldLineNumber: nil,
            lineType: .addition,
            text: "note"
        )

        #expect(store.hasUnsubmittedComments == true)
    }

    @Test func test_hasUnsubmittedComments_falseWhenEmpty() {
        let store = DiffReviewStore()

        #expect(store.hasUnsubmittedComments == false)
    }
}

// MARK: - Format Tests

@MainActor
@Suite("DiffReviewStore Format Tests")
struct DiffReviewStoreFormatTests {

    @Test func test_formatForSubmission_singleAdditionComment() {
        let store = DiffReviewStore()
        store.addComment(
            lineIndex: 0,
            lineNumber: 42,
            oldLineNumber: nil,
            lineType: .addition,
            text: "nice change"
        )

        let output = store.formatForSubmission(filePath: "Sources/App.swift")

        #expect(output.contains("[Code Review] Sources/App.swift"))
        #expect(output.contains("L42 (+): nice change"))
    }

    @Test func test_formatForSubmission_deletionUsesOldLineNumber() {
        let store = DiffReviewStore()
        store.addComment(
            lineIndex: 0,
            lineNumber: nil,
            oldLineNumber: 88,
            lineType: .deletion,
            text: "why remove this?"
        )

        let output = store.formatForSubmission(filePath: "file.swift")

        #expect(output.contains("L88(old) (-): why remove this?"))
    }

    @Test func test_formatForSubmission_multipleComments_orderedByLineIndex() {
        let store = DiffReviewStore()
        // Add in reverse order to verify sorting
        store.addComment(
            lineIndex: 10,
            lineNumber: 55,
            oldLineNumber: nil,
            lineType: .context,
            text: "later comment"
        )
        store.addComment(
            lineIndex: 2,
            lineNumber: 20,
            oldLineNumber: nil,
            lineType: .addition,
            text: "earlier comment"
        )

        let output = store.formatForSubmission(filePath: "test.swift")
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        // First non-header line should be the earlier comment (lineIndex 2)
        // Header is "[Code Review] test.swift"
        #expect(lines.count >= 3)
        #expect(lines[0] == "[Code Review] test.swift")
        #expect(lines[1].contains("earlier comment"))
        #expect(lines[2].contains("later comment"))
    }

    @Test func test_formatForSubmission_contextUsesNewLineNumber() {
        let store = DiffReviewStore()
        store.addComment(
            lineIndex: 0,
            lineNumber: 55,
            oldLineNumber: 50,
            lineType: .context,
            text: "context note"
        )

        let output = store.formatForSubmission(filePath: "ctx.swift")

        // Context lines use new-side line number: "L55 ( ): ..."
        #expect(output.contains("L55 ( ): context note"))
        // Must NOT use old-side format
        #expect(!output.contains("L50(old)"))
    }
}

// MARK: - Constraint Tests

@MainActor
@Suite("DiffReviewStore Constraint Tests")
struct DiffReviewStoreConstraintTests {

    @Test func test_commentTextNewlineStripped() {
        let store = DiffReviewStore()
        store.addComment(
            lineIndex: 0,
            lineNumber: 1,
            oldLineNumber: nil,
            lineType: .addition,
            text: "line1\nline2\rline3"
        )

        let comment = store.comments[0]
        #expect(!comment.text.contains("\n"))
        #expect(!comment.text.contains("\r"))
        #expect(comment.text == "line1line2line3")
    }
}

// MARK: - DisplayLine Tests

@MainActor
@Suite("DiffReviewStore DisplayLine Tests")
struct DiffReviewStoreDisplayLineTests {

    @Test func test_displayLines_noComments_matchesDiffLines() {
        let store = DiffReviewStore()
        let diffLines = [
            makeDiffLine(type: .context, text: " unchanged", oldLineNumber: 1, newLineNumber: 1),
            makeDiffLine(type: .addition, text: "+added", oldLineNumber: nil, newLineNumber: 2),
            makeDiffLine(type: .deletion, text: "-removed", oldLineNumber: 2, newLineNumber: nil),
        ]

        let result = store.buildDisplayLines(from: diffLines)

        // Every element should be .diff, matching the input 1:1
        #expect(result.count == 3)
        for (i, displayLine) in result.enumerated() {
            if case .diff(let line) = displayLine {
                #expect(line == diffLines[i])
            } else {
                Issue.record("Expected .diff at index \(i), got .commentBlock")
            }
        }
    }

    @Test func test_displayLines_commentInsertedAfterTargetLine() {
        let store = DiffReviewStore()
        let diffLines = [
            makeDiffLine(type: .context, text: " line A", oldLineNumber: 1, newLineNumber: 1),
            makeDiffLine(type: .addition, text: "+line B", oldLineNumber: nil, newLineNumber: 2),
            makeDiffLine(type: .context, text: " line C", oldLineNumber: 2, newLineNumber: 3),
        ]

        // Add a comment on line index 1 (the addition line)
        store.addComment(
            lineIndex: 1,
            lineNumber: 2,
            oldLineNumber: nil,
            lineType: .addition,
            text: "review note"
        )

        let result = store.buildDisplayLines(from: diffLines)

        // Expected: diff[0], diff[1], commentBlock, diff[2]
        #expect(result.count == 4)

        if case .diff(let d0) = result[0] {
            #expect(d0 == diffLines[0])
        } else {
            Issue.record("Expected .diff at index 0")
        }

        if case .diff(let d1) = result[1] {
            #expect(d1 == diffLines[1])
        } else {
            Issue.record("Expected .diff at index 1")
        }

        if case .commentBlock(let comment) = result[2] {
            #expect(comment.text == "review note")
            #expect(comment.lineIndex == 1)
        } else {
            Issue.record("Expected .commentBlock at index 2")
        }

        if case .diff(let d2) = result[3] {
            #expect(d2 == diffLines[2])
        } else {
            Issue.record("Expected .diff at index 3")
        }
    }

    @Test func test_displayLines_multipleComments_correctOrder() {
        let store = DiffReviewStore()
        let diffLines = [
            makeDiffLine(type: .context, text: " line 1", oldLineNumber: 1, newLineNumber: 1),
            makeDiffLine(type: .addition, text: "+line 2", oldLineNumber: nil, newLineNumber: 2),
            makeDiffLine(type: .addition, text: "+line 3", oldLineNumber: nil, newLineNumber: 3),
            makeDiffLine(type: .context, text: " line 4", oldLineNumber: 2, newLineNumber: 4),
        ]

        // Comment on line index 1 and line index 2 (consecutive additions)
        store.addComment(
            lineIndex: 1,
            lineNumber: 2,
            oldLineNumber: nil,
            lineType: .addition,
            text: "first comment"
        )
        store.addComment(
            lineIndex: 2,
            lineNumber: 3,
            oldLineNumber: nil,
            lineType: .addition,
            text: "second comment"
        )

        let result = store.buildDisplayLines(from: diffLines)

        // Expected: diff[0], diff[1], comment1, diff[2], comment2, diff[3]
        #expect(result.count == 6)

        // Verify comment ordering: first comment after diff[1], second after diff[2]
        if case .commentBlock(let c1) = result[2] {
            #expect(c1.text == "first comment")
        } else {
            Issue.record("Expected .commentBlock (first comment) at index 2")
        }

        if case .commentBlock(let c2) = result[4] {
            #expect(c2.text == "second comment")
        } else {
            Issue.record("Expected .commentBlock (second comment) at index 4")
        }
    }
}
