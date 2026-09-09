//
//  ParagraphAccessibilityRangeTests.swift
//  The accessibility label/actions pass must never index past the string it enumerates.
//  Build 3.0.3 crashed with `NSRangeException` from `generateAccessibilityContent` when a
//  streaming chat handed the paragraph an empty string (attribute(at: 0) on length 0).
//

#if canImport(UIKit)
import Foundation
@testable import SwiftStreamingMarkdown
import SwiftUI
import UIKit
import XCTest

final class ParagraphAccessibilityRangeTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  private let coder = CitationCoder(
    citationMarker: "MARK", citationMarkerQueryParam: "m", citationTextQueryParam: "t",
    citationA11yTextQueryParam: "a", citationInertQueryParam: "inert"
  )

  private var citationConfig: MarkdownRenderConfig.CitationConfig {
    .init(coder: coder, font: MarkdownRenderConfig.CitationConfig.default.font, textColor: .black, backgroundColor: .gray)
  }

  private func makeView() -> ParagraphUIView {
    ParagraphUIView(frame: CGRect(x: 0, y: 0, width: 320, height: 60), textContainer: nil)
  }

  private func paragraph(_ markdown: String) async throws -> NSMutableAttributedString {
    let config = MarkdownRenderConfig.default.withCitationConfig(value: citationConfig)
    let document = await parser.parse(text: markdown)
    guard case .paragraph(_, let content) = document.convert(with: config).first else {
      throw XCTSkip("Expected a paragraph")
    }
    return content
  }

  // The crash: an empty paragraph (a streaming placeholder cleared to "") reaches the
  // accessibility pass, which peeked at index 0 of a zero-length string.
  func test_emptyParagraph_doesNotRaise() {
    let view = makeView()
    view.setParagraphContents(NSMutableAttributedString(string: ""), lineSpacing: nil, animatedByWord: false)
    XCTAssertEqual(view.accessibilityLabel ?? "", "")
    XCTAssertEqual(view.accessibilityCustomActions?.count ?? 0, 0)
  }

  // A paragraph that had content and is then set to "" (a streamed placeholder replaced):
  // the guard against an unchanged string does not apply, so the empty string reaches the
  // accessibility pass. Synchronous on purpose: an ObjC exception unwinding an async test
  // body aborts the runner instead of failing the test.
  func test_contentThenEmpty_animatedByWord_doesNotRaise() {
    let view = makeView()
    view.setParagraphContents(NSMutableAttributedString(string: "Looking at the dashboards…"), lineSpacing: 4, animatedByWord: true)
    view.setParagraphContents(NSMutableAttributedString(string: ""), lineSpacing: 4, animatedByWord: true)
    XCTAssertEqual(view.accessibilityLabel ?? "", "")
    XCTAssertEqual(view.accessibilityCustomActions?.count ?? 0, 0)
  }

  // Multi-scalar text (emoji, combining marks) with a trailing citation attachment, mutated
  // word by word with line spacing applied: every range stays inside the enumerated string.
  func test_emojiAndTrailingAttachment_animatedByWord() async throws {
    let view = makeView()
    let first = try await paragraph("Loading 👩‍🚀 dashboards")
    view.setParagraphContents(first, lineSpacing: 4, animatedByWord: true)
    let second = try await paragraph("Loading 👩‍🚀 dashboards for café 🇨🇿 [MARK](x://a/b?m=MARK&t=Dash&a=Dash%20chip)")
    view.setParagraphContents(second, lineSpacing: 4, animatedByWord: true)

    XCTAssertEqual(view.accessibilityLabel, "Loading 👩‍🚀 dashboards for café 🇨🇿 Dash chip")
    XCTAssertEqual(view.accessibilityCustomActions?.count, 1)
  }

  // Only an inert chip: still labelled by its title, no action, no crash on the lone attachment.
  func test_loneInertAttachment() async throws {
    let view = makeView()
    let lone = try await paragraph("[MARK](x://a/b?m=MARK&t=Dead&a=Dead%20chip&inert=1)")
    view.setParagraphContents(lone, lineSpacing: nil, animatedByWord: true)
    XCTAssertEqual(view.accessibilityLabel, "Dead chip")
    XCTAssertEqual(view.accessibilityCustomActions?.count ?? 0, 0)
  }
}
#endif
