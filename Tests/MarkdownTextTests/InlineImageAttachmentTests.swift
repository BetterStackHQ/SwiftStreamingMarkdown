//
//  InlineImageAttachmentTests.swift
//  Inline images drawn in the text by a host provider (an avatar before a name).
//

#if canImport(UIKit)
import Foundation
@testable import SwiftStreamingMarkdown
import SwiftUI
import UIKit
import XCTest

/// `@MainActor`: reading `attachment.image` draws the host's bitmap, which is confined to the
/// main thread (`InlineImageAttachment.renderIfNeeded`).
@MainActor
final class InlineImageAttachmentTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  private func paragraph(_ markdown: String, config: MarkdownRenderConfig) async throws -> NSMutableAttributedString {
    let document = await parser.parse(text: markdown)
    guard case .paragraph(_, let content) = document.convert(with: config).first else {
      throw XCTSkip("Expected a paragraph")
    }
    return content
  }

  private func dot(_ color: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
      color.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
  }

  private func imageConfig(spacing: CGFloat = 4) -> MarkdownRenderConfig {
    MarkdownRenderConfig.default.withInlineImageConfig(value: .init(
      size: CGSize(width: 16, height: 16),
      spacing: spacing,
      baselineAdjustment: -3,
      image: { [dot] source, scheme in
        source == "avatar://missing" ? nil : dot(scheme == .dark ? .white : .black)
      }
    ))
  }

  private func attachments(in content: NSAttributedString) -> [(InlineImageAttachment, NSRange)] {
    var found: [(InlineImageAttachment, NSRange)] = []
    content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, range, _ in
      if let attachment = value as? InlineImageAttachment { found.append((attachment, range)) }
    }
    return found
  }

  func test_withoutAProvider_anInlineImageRendersNothing() async throws {
    let content = try await paragraph("Calling ![](avatar://simon)Simon now", config: .default)
    XCTAssertEqual(content.string, "Calling Simon now")
    XCTAssertTrue(attachments(in: content).isEmpty)
  }

  func test_withAProvider_theImageSitsInTheTextAtItsSizePlusSpacing() async throws {
    let content = try await paragraph("Calling ![](avatar://simon)Simon now", config: imageConfig())
    let found = attachments(in: content)
    XCTAssertEqual(found.count, 1)
    let (attachment, range) = try XCTUnwrap(found.first)
    XCTAssertEqual(range.location, ("Calling " as NSString).length)
    XCTAssertEqual(attachment.source, "avatar://simon")
    XCTAssertEqual(attachment.bounds, CGRect(x: 0, y: -3, width: 20, height: 16))
    XCTAssertEqual(attachment.image?.size, CGSize(width: 20, height: 16), "the spacing is drawn into the image")
  }

  func test_theProviderDrawsEachAppearance() async throws {
    let content = try await paragraph("![](avatar://simon)Simon", config: imageConfig(spacing: 0))
    let attachment = try XCTUnwrap(attachments(in: content).first?.0)
    AppAppearance.update(style: .light)
    let light = try XCTUnwrap(attachment.image?.cgImage)
    AppAppearance.update(style: .dark)
    let dark = try XCTUnwrap(attachment.image?.cgImage)
    XCTAssertFalse(light === dark)
  }

  func test_aMissingImageLeavesItsPlaceBlank() async throws {
    let content = try await paragraph("![](avatar://missing)Simon", config: imageConfig())
    let attachment = try XCTUnwrap(attachments(in: content).first?.0)
    XCTAssertNil(attachment.image)
    XCTAssertEqual(attachment.bounds.width, 20, "the layout doesn't jump when the image is missing")
  }

  func test_anImageInsideALinkIsPartOfTheLink() async throws {
    let content = try await paragraph("Calling [![](avatar://simon)Simon](https://example.com/simon) now", config: imageConfig())
    let (_, range) = try XCTUnwrap(attachments(in: content).first)
    let link = content.attribute(.link, at: range.location, effectiveRange: nil) as? URL
    XCTAssertEqual(link, URL(string: "https://example.com/simon"))
    let nameLink = content.attribute(.link, at: range.location + 1, effectiveRange: nil) as? URL
    XCTAssertEqual(nameLink, link)
  }

  func test_accessibilityReadsTheAltTextNotTheAttachmentGlyph() async throws {
    let content = try await paragraph("Calling ![](avatar://simon)Simon and ![Face of Juraj](avatar://juraj)Juraj", config: imageConfig())
    let view = ParagraphUIView(frame: CGRect(x: 0, y: 0, width: 320, height: 60), textContainer: nil)
    view.setParagraphContents(content, lineSpacing: nil, animatedByWord: false)
    XCTAssertEqual(view.accessibilityLabel, "Calling Simon and Face of JurajJuraj")
    XCTAssertFalse(view.accessibilityLabel?.contains("\u{FFFC}") ?? true)
  }
}
#endif
