// SelectionEditUITests.swift
// CalyxUITests
//
// E2E tests for terminal select+cut (Cmd+X) and select+delete behaviour.
// Verifies clipboard integration and app stability.

import XCTest

final class SelectionEditUITests: CalyxUITestCase {

    func test_cmdXCopiesSelectedTextToClipboard() {
        waitFor(app.windows.firstMatch)
        sleep(2) // wait for shell ready

        // Clear clipboard
        NSPasteboard.general.clearContents()

        // Paste a long string
        let testString = "echo AAAAAA BBBBBB CCCCCC"
        NSPasteboard.general.setString(testString, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        usleep(500_000)

        // Mouse drag to select middle portion
        let window = app.windows.firstMatch
        let startPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.03))
        let endPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.03))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        usleep(300_000)

        // Clear clipboard before cut
        NSPasteboard.general.clearContents()

        // Cmd+X to cut
        app.typeKey("x", modifierFlags: .command)
        usleep(300_000)

        // Clipboard should have content
        let clipboardContent = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertFalse(clipboardContent.isEmpty, "Clipboard should contain selected text after Cmd+X")
    }

    func test_deleteWithSelectionKeepsAppAlive() {
        waitFor(app.windows.firstMatch)
        sleep(2)

        // Paste text
        let testString = "echo XXXXXXXXXX YYYYYYYYYY"
        NSPasteboard.general.setString(testString, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        usleep(500_000)

        // Mouse drag to select portion
        let window = app.windows.firstMatch
        let startPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.03))
        let endPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.03))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        usleep(300_000)

        // Press Delete
        app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        usleep(500_000)

        // App should still be alive
        XCTAssertTrue(app.windows.firstMatch.exists, "App should not crash after delete with selection")
    }

    func test_noSelectionCmdXPassesThrough() {
        waitFor(app.windows.firstMatch)
        sleep(2)

        // Clear clipboard
        NSPasteboard.general.clearContents()

        // Type something (no selection)
        app.typeKey("a", modifierFlags: [])
        usleep(200_000)

        // Cmd+X without selection
        app.typeKey("x", modifierFlags: .command)
        usleep(300_000)

        // Clipboard should still be empty (no selection to cut)
        let clipboardContent = NSPasteboard.general.string(forType: .string)
        XCTAssertNil(clipboardContent, "Clipboard should remain empty when Cmd+X with no selection")
    }
}
