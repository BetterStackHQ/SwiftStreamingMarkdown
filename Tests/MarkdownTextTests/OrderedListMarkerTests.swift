//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
@testable import SwiftStreamingMarkdown
import SwiftUI
import XCTest

/// The ordered list's marker option: plain keeps the original "1." layout, a badge sets
/// the item gaps and indents nested blocks to the item text, and every builder keeps it.
final class OrderedListMarkerTests: XCTestCase {

  private let fonts = TextFonts(normal: .systemFont(ofSize: 14), italic: nil, bold: .boldSystemFont(ofSize: 14), boldItalic: nil, preferredLetterSpacing: nil, preferredLineHeight: nil)

  private let badge = MarkdownRenderConfig.OrderedListBadgeStyle(
    size: 26,
    cornerRadius: 4,
    font: .systemFont(ofSize: 12, weight: .medium),
    textColor: .primary,
    fillColor: .gray,
    borderColor: .black,
    contentSpacing: 10,
    itemSpacing: 20
  )

  func testPlainIsTheDefault() {
    let style = MarkdownRenderConfig.MarkdownTextStyle(textFonts: fonts, textColor: .primary)
    XCTAssertEqual(style.orderedListMarker, .plain)
    XCTAssertEqual(style.orderedListMarker.itemSpacing, 8)
    XCTAssertEqual(style.orderedListMarker.contentSpacing, 11)
    XCTAssertEqual(style.orderedListMarker.nestedIndent, 0)
  }

  func testBadgeSpacingAndNestedIndent() {
    let marker = MarkdownRenderConfig.OrderedListMarker.badge(badge)
    XCTAssertEqual(marker.itemSpacing, 20)
    XCTAssertEqual(marker.contentSpacing, 10)
    XCTAssertEqual(marker.nestedIndent, 36)
  }

  func testLaterBuildersKeepTheBadge() {
    let config = MarkdownRenderConfig.default
      .withOrderedListStyle(value: .init(textFonts: fonts, textColor: .primary, orderedListMarker: .badge(badge)))
      .withParagraphStyle(value: .init(textFonts: fonts, textColor: .primary))
      .withBlockSpacing(value: 12)
    XCTAssertEqual(config.orderedListStyle.orderedListMarker, .badge(badge))
  }

  @MainActor
  func testBadgeListRenders() async {
    let parser = MarkdownParserImpl()
    let doc = await parser.parse(text: "1. First\n2. Second\n   - nested")
    let config = MarkdownRenderConfig.default
      .withOrderedListStyle(value: .init(textFonts: fonts, textColor: .primary, orderedListMarker: .badge(badge)))
    let renderables = doc.convert(with: config)
    let host = UIHostingController(rootView: BlockView(renderables: renderables).environment(\.markdownConfig, config))
    host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
    host.view.layoutIfNeeded()
    XCTAssertGreaterThan(host.view.intrinsicContentSize.height, 0)
  }
}
#endif
