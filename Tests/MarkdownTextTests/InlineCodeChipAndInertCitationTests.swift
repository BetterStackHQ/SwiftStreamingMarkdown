//
//  InlineCodeChipAndInertCitationTests.swift
//  Inline code drawn as a rounded, bordered chip; citations that are chips but not links.
//

#if canImport(UIKit)
import Foundation
@testable import SwiftStreamingMarkdown
import SwiftUI
import UIKit
import XCTest

final class InlineCodeChipAndInertCitationTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  private func chipStyle(radius: CGFloat = 3, border: Color = .gray) -> MarkdownRenderConfig.MarkdownInlineTextStyle {
    let defaults = MarkdownRenderConfig.defaultInlineStyle
    return .init(
      boldTextColor: defaults.boldTextColor, linkTextFont: defaults.linkTextFont, linkTextColor: defaults.linkTextColor,
      linkUnderlineStyle: [], codeTextFont: defaults.codeTextFont, codeTextColor: defaults.codeTextColor,
      codeBackgroundColor: .yellow, codeUnderlineColor: .clear, codeBorderColor: border, codeCornerRadius: radius
    )
  }

  private func paragraph(_ markdown: String, config: MarkdownRenderConfig) async throws -> NSMutableAttributedString {
    let document = await parser.parse(text: markdown)
    guard case .paragraph(_, let content) = document.convert(with: config).first else {
      throw XCTSkip("Expected a paragraph")
    }
    return content
  }

  // MARK: - Inline code chip

  func test_defaultStyle_keepsTheSquareRunBackground() async throws {
    let content = try await paragraph("run `ls -la` now", config: .default)
    let range = (content.string as NSString).range(of: "ls -la")
    XCTAssertNotNil(content.attribute(.backgroundColor, at: range.location, effectiveRange: nil))
    XCTAssertNil(content.attribute(.inlineCodeChip, at: range.location, effectiveRange: nil))
  }

  func test_chipStyle_marksTheRunAndDropsTheSquareBackground() async throws {
    let config = MarkdownRenderConfig.default.withInlineStyle(value: chipStyle())
    let content = try await paragraph("run `ls -la` now", config: config)
    let range = (content.string as NSString).range(of: "ls -la")
    let chip = content.attribute(.inlineCodeChip, at: range.location, effectiveRange: nil) as? InlineCodeChipAttribute
    XCTAssertEqual(chip?.cornerRadius, 3)
    XCTAssertEqual(chip?.fillColor, UIColor(Color.yellow))
    XCTAssertNil(content.attribute(.backgroundColor, at: range.location, effectiveRange: nil),
                 "the square TextKit fill would show at the chip's corners")
    // Prose around the code carries no chip.
    XCTAssertNil(content.attribute(.inlineCodeChip, at: 0, effectiveRange: nil))
  }

  func test_paragraphView_drawsOneShapePerChipRunUnderTheText() async throws {
    let config = MarkdownRenderConfig.default.withInlineStyle(value: chipStyle())
    let content = try await paragraph("first `alpha` then `beta`", config: config)
    let view = ParagraphUIView(frame: CGRect(x: 0, y: 0, width: 320, height: 60), textContainer: nil)
    view.setParagraphContents(content, lineSpacing: nil, animatedByWord: false)
    view.layoutIfNeeded()

    let shapes = view.inlineCodeChipShapes
    XCTAssertEqual(shapes.count, 2)
    let first = try XCTUnwrap(shapes.first?.path?.boundingBox)
    let second = try XCTUnwrap(shapes.last?.path?.boundingBox)
    XCTAssertGreaterThan(first.width, 0)
    XCTAssertLessThan(first.maxX, second.minX, "chips follow their runs in text order")
    XCTAssertEqual(shapes.first?.strokeColor, UIColor(Color.gray).resolvedColor(with: view.traitCollection).cgColor)
    XCTAssertTrue(view.layer.sublayers?.first === shapes.first?.superlayer, "the chip host sits beneath the text canvas")
  }

  func test_segmentsOnOneLineMergeIntoOneChip() {
    let merged = ParagraphUIView.mergingRectsPerLine([
      CGRect(x: 0, y: 0, width: 10, height: 20), CGRect(x: 10, y: 0, width: 5, height: 20),
      CGRect(x: 0, y: 20, width: 8, height: 20),
    ])
    XCTAssertEqual(merged, [CGRect(x: 0, y: 0, width: 15, height: 20), CGRect(x: 0, y: 20, width: 8, height: 20)])
  }

  func test_paragraphView_drawsNothingWithoutChips() async throws {
    let content = try await paragraph("plain `code`", config: .default)
    let view = ParagraphUIView(frame: CGRect(x: 0, y: 0, width: 320, height: 60), textContainer: nil)
    view.setParagraphContents(content, lineSpacing: nil, animatedByWord: false)
    view.layoutIfNeeded()
    XCTAssertTrue(view.inlineCodeChipShapes.isEmpty)
  }

  // MARK: - Inert citations

  private let coder = CitationCoder(
    citationMarker: "MARK", citationMarkerQueryParam: "m", citationTextQueryParam: "t",
    citationA11yTextQueryParam: "a", citationInertQueryParam: "inert"
  )

  private var citationConfig: MarkdownRenderConfig.CitationConfig {
    .init(coder: coder, font: MarkdownRenderConfig.CitationConfig.default.font, textColor: .black, backgroundColor: .gray)
  }

  func test_coder_decodesTheInertFlag() {
    XCTAssertEqual(coder.decode(linkDestination: "x://a/b?m=MARK&t=Name&a=Name&inert=1")?.isInert, true)
    XCTAssertEqual(coder.decode(linkDestination: "x://a/b?m=MARK&t=Name&a=Name")?.isInert, false)
    // A coder without the param never marks anything inert, whatever the URL says.
    XCTAssertEqual(CitationCoder.default.decode(
      linkDestination: "http://e.com?citationMarker=9F742443&citationTitle=T&citationA11yValue=T&inert=1"
    )?.isInert, false)
  }

  func test_inertCitation_isAChipButNotALink() async throws {
    let config = MarkdownRenderConfig.default.withCitationConfig(value: citationConfig)
    let live = try await paragraph("see [MARK](x://a/b?m=MARK&t=Live&a=Live)", config: config)
    let inert = try await paragraph("see [MARK](x://a/b?m=MARK&t=Dead&a=Dead&inert=1)", config: config)

    func attachmentIndex(_ s: NSAttributedString) -> Int { (s.string as NSString).range(of: "\u{FFFC}").location }
    XCTAssertNotNil(live.attribute(.attachment, at: attachmentIndex(live), effectiveRange: nil))
    XCTAssertNotNil(live.attribute(.link, at: attachmentIndex(live), effectiveRange: nil))
    XCTAssertNotNil(inert.attribute(.attachment, at: attachmentIndex(inert), effectiveRange: nil), "still a chip")
    XCTAssertNil(inert.attribute(.link, at: attachmentIndex(inert), effectiveRange: nil), "not a link")
  }

  func test_inertCitation_offersNoAccessibilityActionAndKeepsItsLabel() async throws {
    let config = MarkdownRenderConfig.default.withCitationConfig(value: citationConfig)
    let inert = try await paragraph("see [MARK](x://a/b?m=MARK&t=Dead&a=Dead%20chip&inert=1)", config: config)
    let view = ParagraphUIView(frame: CGRect(x: 0, y: 0, width: 320, height: 60), textContainer: nil)
    view.setParagraphContents(inert, lineSpacing: nil, animatedByWord: false)

    XCTAssertEqual(view.accessibilityCustomActions?.count ?? 0, 0)
    XCTAssertEqual(view.accessibilityLabel, "see Dead chip")

    let live = try await paragraph("see [MARK](x://a/b?m=MARK&t=Live&a=Live%20chip)", config: config)
    view.setParagraphContents(live, lineSpacing: nil, animatedByWord: false)
    XCTAssertEqual(view.accessibilityCustomActions?.count, 1)
  }

  func test_inertCitation_tapIsNotForwarded() async throws {
    let config = MarkdownRenderConfig.default.withCitationConfig(value: citationConfig)
    let inert = try await paragraph("[MARK](x://a/b?m=MARK&t=Dead&a=Dead&inert=1)", config: config)
    let view = ParagraphUIView(frame: CGRect(x: 0, y: 0, width: 320, height: 60), textContainer: nil)
    var tapped: URL?
    view.onUrlTap = { tapped = $0 }
    view.setParagraphContents(inert, lineSpacing: nil, animatedByWord: false)
    let attachment = try XCTUnwrap(inert.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)

    _ = view.textView(view, shouldInteractWith: attachment, in: NSRange(location: 0, length: 1))

    XCTAssertNil(tapped)
  }
}
#endif
