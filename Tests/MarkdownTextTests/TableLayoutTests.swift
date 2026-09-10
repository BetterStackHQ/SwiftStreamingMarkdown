//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

@testable import SwiftStreamingMarkdown
import CoreGraphics
import XCTest

/// Pure layout math for `TableLayout.filledColumnWidths` — kept out of the UIKit-gated
/// `TableViewTests` so it runs on every platform.
final class TableLayoutTests: XCTestCase {

  /// A narrow key/value table grows its last (value) column to fill the viewport, so the
  /// right half of a phone sheet isn't left empty (Juraj, C2).
  func testFilledColumnWidthsGrowsLastColumnToFillViewport() {
    let filled = TableLayout.filledColumnWidths([80, 100], fillWidth: 390)
    XCTAssertEqual(filled, [80, 310])
    XCTAssertEqual(filled.reduce(0, +), 390)
  }

  /// A table already at least as wide as the viewport is left untouched, so a wide table
  /// still scrolls horizontally instead of being squeezed.
  func testFilledColumnWidthsLeavesWideTableUnchanged() {
    XCTAssertEqual(TableLayout.filledColumnWidths([200, 250], fillWidth: 390), [200, 250])
  }

  /// A `fillWidth` of 0 (viewport not measured yet) disables filling entirely.
  func testFilledColumnWidthsDisabledWhenFillWidthIsZero() {
    XCTAssertEqual(TableLayout.filledColumnWidths([80, 100], fillWidth: 0), [80, 100])
  }

  /// An empty table (no columns) is returned unchanged rather than crashing.
  func testFilledColumnWidthsHandlesNoColumns() {
    XCTAssertEqual(TableLayout.filledColumnWidths([], fillWidth: 390), [])
  }
}
