//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
import Foundation
@testable import SwiftStreamingMarkdown
import SwiftUI
import Testing
import UIKit

/// Covers `CitationConfig.citationImage`: the optional per-citation leading icon a host
/// app can composite into the rendered chip. Structural (image geometry), not a snapshot
/// golden — the fork ships no icon assets of its own to snapshot against.
@Suite("InlineCitationAttachment citation-image Tests")
struct InlineCitationAttachmentTests {

  /// Same citation-URL construction `ParagraphViewTests`/`TableViewSnapshotTests` use.
  private func makeCitationData(title: String = "ESPN", destination: String = "http://example.com") -> InlineAttachmentData? {
    let citationURL = "\(destination)?citationMarker=9F742443&citationTitle=\(title)&citationA11yValue=\(title)"
    return CitationCoder.default.decode(linkDestination: citationURL)
  }

  /// A small solid square standing in for a real host-app icon asset.
  private func testIcon(side: CGFloat = 20) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
      UIColor.black.setFill()
      UIBezierPath(rect: CGRect(x: 0, y: 0, width: side, height: side)).fill()
    }
  }

  private func makeConfig(
    citationImage: (@Sendable (String) -> UIImage?)? = nil
  ) -> MarkdownRenderConfig.CitationConfig {
    .init(font: .systemFont(ofSize: 15), textColor: .black, backgroundColor: .gray, citationImage: citationImage)
  }

  @Test("No citationImage closure leaves the attachment's icon nil")
  func noClosureLeavesIconNil() {
    guard let data = makeCitationData(),
          let attachment = InlineCitationAttachment(citationData: data, citationConfig: makeConfig()) else {
      Issue.record("Failed to build a citation attachment")
      return
    }
    #expect(attachment.icon == nil)
  }

  @Test("A citationImage closure returning an icon widens the rendered chip without changing its height")
  func iconWidensTheChip() {
    guard let plainData = makeCitationData(), let iconData = makeCitationData(),
          let plain = InlineCitationAttachment(citationData: plainData, citationConfig: makeConfig()),
          let iconized = InlineCitationAttachment(
            citationData: iconData,
            citationConfig: makeConfig(citationImage: { [icon = testIcon()] _ in icon })
          ),
          let plainImage = plain.image, let iconizedImage = iconized.image
    else {
      Issue.record("Failed to build citation attachments")
      return
    }

    #expect(iconized.icon != nil)
    #expect(iconizedImage.size.width > plainImage.size.width, "icon should widen the chip")
    #expect(iconizedImage.size.height == plainImage.size.height, "icon must fit inside the existing line height")
  }

  /// The icon hugs the capsule: its inset from the chip's leading edge equals its inset
  /// from the top and bottom edges, so a round mark sits concentric with the capsule end.
  @Test("A leading icon is inset from the chip's left edge exactly as far as from its top and bottom")
  func iconHugsTheCapsuleEqually() {
    guard let data = makeCitationData(),
          let iconized = InlineCitationAttachment(
            citationData: data,
            citationConfig: makeConfig(citationImage: { [icon = testIcon()] _ in icon })
          ),
          let image = iconized.image, let cg = image.cgImage
    else {
      Issue.record("Failed to build citation attachment")
      return
    }
    // The test icon is a solid black square on a grey chip: its opaque-black bounds are
    // the icon rect, in pixels.
    let width = cg.width, height = cg.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
      data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { Issue.record("no bitmap context"); return }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, maxX = -1, minY = height, maxY = -1
    for y in 0..<height {
      for x in 0..<width {
        let i = (y * width + x) * 4
        let isBlack = pixels[i] < 30 && pixels[i + 1] < 30 && pixels[i + 2] < 30 && pixels[i + 3] > 200
        if isBlack {
          minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
      }
    }
    #expect(maxX >= 0, "the black test icon was not drawn")
    let left = minX
    let top = minY
    let bottom = height - 1 - maxY
    // Bitmap rows are top-down here (CGContext.draw flips), so top/bottom are symmetric
    // either way; the leading inset must match them within a pixel of rounding.
    #expect(abs(left - top) <= 1, "left inset \(left)px vs top inset \(top)px")
    #expect(abs(left - bottom) <= 1, "left inset \(left)px vs bottom inset \(bottom)px")
  }

  @Test("A citationImage closure that declines a specific citation renders it exactly like no closure at all")
  func closureReturningNilOptsOutPerCitation() {
    guard let plainData = makeCitationData(), let declinedData = makeCitationData(),
          let plain = InlineCitationAttachment(citationData: plainData, citationConfig: makeConfig()),
          let declined = InlineCitationAttachment(
            citationData: declinedData,
            citationConfig: makeConfig(citationImage: { _ in nil })
          ),
          let plainImage = plain.image, let declinedImage = declined.image
    else {
      Issue.record("Failed to build citation attachments")
      return
    }

    #expect(declined.icon == nil)
    #expect(declinedImage.size == plainImage.size)
  }

  @Test("The citationImage closure receives the citation's decoded destination URL")
  func closureReceivesTheDecodedDestination() {
    guard let data = makeCitationData(title: "Runbook", destination: "https://runbooks.test/incident-42") else {
      Issue.record("Failed to build citation data")
      return
    }
    var received: String?
    _ = InlineCitationAttachment(
      citationData: data,
      citationConfig: makeConfig(citationImage: { destination in
        received = destination
        return nil
      })
    )
    #expect(received == data.url.absoluteString)
  }

  // MARK: - citationBaselineAdjustment

  @Test("citationBaselineAdjustment defaults to zero")
  func citationBaselineAdjustmentDefaultsToZero() {
    #expect(makeConfig().citationBaselineAdjustment == 0)
    #expect(MarkdownRenderConfig.CitationConfig.default.citationBaselineAdjustment == 0)
  }

  @Test("citationBaselineAdjustment participates in CitationConfig equality and hashing")
  func citationBaselineAdjustmentParticipatesInEquality() {
    let base = makeConfig()
    let adjusted = MarkdownRenderConfig.CitationConfig(
      font: base.font, textColor: base.textColor, backgroundColor: base.backgroundColor,
      citationBaselineAdjustment: -3
    )
    #expect(base != adjusted)
  }
}
#endif
