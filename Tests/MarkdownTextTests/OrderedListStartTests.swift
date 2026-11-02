@testable import SwiftStreamingMarkdown
import SwiftUI
import XCTest

/// Ordered lists number from 1 whatever the source says, as most HTML renderers draw them
/// (no `start` attribute). A host that renders the later items of a list on their own
/// ("2. Gather logs" after the first step and its checklist) sets `firstListNumber`, which
/// numbers the document's first top-level ordered list from there and nothing else.
final class OrderedListStartTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  private func starts(_ text: String, config: MarkdownRenderConfig = .default) async -> [Int] {
    await parser.parse(text: text).convert(with: config).compactMap {
      if case .orderedList(_, _, let start) = $0 { return start }
      return nil
    }
  }

  func test_aListNumberedFromThreeStillStartsAtOne() async {
    let starts = await starts("3. Restart\n4. Verify")
    XCTAssertEqual(starts, [1])
  }

  func test_firstListNumber_startsOnlyTheFirstList() async {
    let config = MarkdownRenderConfig.default.withOrderedListStyle(value: .init(
      textFonts: MarkdownRenderConfig.defaultOrderedListStyle.textFonts,
      textColor: .primary,
      firstListNumber: 2
    ))
    let starts = await starts("2. Gather logs\n\nThen:\n\n1. Other list", config: config)
    XCTAssertEqual(starts, [2, 1])
  }
}
