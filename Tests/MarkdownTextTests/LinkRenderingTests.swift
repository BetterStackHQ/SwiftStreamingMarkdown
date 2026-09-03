//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
@testable import SwiftStreamingMarkdown
import XCTest

final class LinkRenderingTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  /// Regression test for a macOS crash: `Link.convert` stored an empty Swift array
  /// as the `.underlineStyle` attribute value, but TextKit expects an `NSNumber`
  /// and AppKit calls `-integerValue` on it, crashing `NSTextView` with
  /// `-[Swift.__EmptyArrayStorage integerValue]` on any rendered link.
  func test_linkUnderlineStyle_bridgesToNSNumber() async {
    let document = await parser.parse(text: "check the [docs](https://example.com) here")
    let renderables = document.convert(with: .default)

    guard case .paragraph(_, let content) = renderables.first else {
      return XCTFail("Expected a single paragraph")
    }

    var foundUnderlineAttribute = false
    var underlineNumber: NSNumber?
    content.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: content.length)) { value, _, _ in
      if value != nil {
        foundUnderlineAttribute = true
        underlineNumber = value as? NSNumber
      }
    }
    XCTAssertTrue(foundUnderlineAttribute, "Expected the link run to carry an underlineStyle attribute")
    XCTAssertNotNil(
      underlineNumber,
      "underlineStyle must bridge to NSNumber — AppKit's TextKit calls -integerValue on it and crashes on any other type"
    )
  }
}

final class LinkSchemeStyleTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  /// A scheme registered in `linkSchemeStyles` renders with its own font/colour/underline
  /// while every other link keeps the shared `linkText*` slots — so a host can style an
  /// inert `mention://` link apart from a real `https` link in the same paragraph.
  func test_linkSchemeStyles_overrideOnlyTheRegisteredScheme() async {
    let base = MarkdownRenderConfig.default.inlineStyle
    let mentionFont = MDFont.boldSystemFont(ofSize: 15)
    let inline = MarkdownRenderConfig.MarkdownInlineTextStyle(
      boldTextColor: base.boldTextColor,
      linkTextFont: base.linkTextFont,
      linkTextColor: .blue,
      linkUnderlineStyle: .single,
      codeTextFont: base.codeTextFont,
      codeTextColor: base.codeTextColor,
      codeBackgroundColor: base.codeBackgroundColor,
      codeUnderlineColor: base.codeUnderlineColor,
      linkSchemeStyles: ["mention": .init(font: mentionFont, color: .red, underlineStyle: [])]
    )
    let config = MarkdownRenderConfig.default.withInlineStyle(value: inline)

    let document = await parser.parse(text: "[@Jane](mention://42) see [docs](https://example.com)")
    let renderables = document.convert(with: config)
    guard case .paragraph(_, let content) = renderables.first else {
      return XCTFail("Expected a single paragraph")
    }
    let text = content.string as NSString

    let mention = content.attributes(at: text.range(of: "@Jane").location, effectiveRange: nil)
    XCTAssertEqual(mention[.font] as? MDFont, mentionFont)
    XCTAssertEqual(mention[.foregroundColor] as? MDColor, MDColor(Color.red))
    XCTAssertEqual((mention[.underlineStyle] as? NSNumber)?.intValue, 0)

    let link = content.attributes(at: text.range(of: "docs").location, effectiveRange: nil)
    XCTAssertEqual(link[.font] as? MDFont, base.linkTextFont)
    XCTAssertEqual(link[.foregroundColor] as? MDColor, MDColor(Color.blue))
    XCTAssertEqual((link[.underlineStyle] as? NSNumber)?.intValue, NSUnderlineStyle.single.rawValue)
  }
}
