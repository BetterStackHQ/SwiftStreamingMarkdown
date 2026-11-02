@testable import SwiftStreamingMarkdown
import XCTest

/// An ordered list is numbered from its source's first number, as CommonMark has it: a host
/// that renders the rest of a list on its own ("2. Gather logs" after the first step) keeps
/// the step's number instead of restarting at 1.
final class OrderedListStartTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  func test_listStartingLater_keepsItsFirstNumber() async {
    let renderables = await parser.parse(text: "3. Restart\n4. Verify").convert(with: .default)

    guard case .orderedList(_, let items, let start) = renderables.first else {
      return XCTFail("Expected the parsed document to start with an ordered list")
    }
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(start, 3)
  }

  func test_listStartingAtOne_startsAtOne() async {
    let renderables = await parser.parse(text: "1. First\n2. Second").convert(with: .default)

    guard case .orderedList(_, _, let start) = renderables.first else {
      return XCTFail("Expected the parsed document to start with an ordered list")
    }
    XCTAssertEqual(start, 1)
  }
}
