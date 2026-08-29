//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
@testable import SwiftStreamingMarkdown
import SwiftUI
import XCTest

/// The table chrome options: defaults keep the original grid, and the header bolding
/// helper swaps every run to the style's bold face.
final class TableStyleTests: XCTestCase {

  private func style(boldsHeader: Bool = false) -> MarkdownRenderConfig.MarkdownTableTextStyle {
    MarkdownRenderConfig.MarkdownTableTextStyle(
      textFonts: TextFonts(normal: .systemFont(ofSize: 13), italic: nil, bold: .boldSystemFont(ofSize: 13), boldItalic: nil, preferredLetterSpacing: nil, preferredLineHeight: nil),
      headerTextColor: .primary,
      regularTextColor: .primary,
      headerBackgroundColor: .clear,
      borderColor: .gray,
      actionButtonColor: .blue,
      boldsHeader: boldsHeader
    )
  }

  func testDefaultsKeepTheGridLook() {
    let style = style()
    XCTAssertTrue(style.showsColumnDividers)
    XCTAssertTrue(style.showsOuterBorder)
    XCTAssertFalse(style.boldsHeader)
  }

  func testEmboldenedHeadingUsesTheBoldFace() {
    let heading = AttributedString(NSAttributedString(string: "Name", attributes: [.font: UIFont.systemFont(ofSize: 13)]))
    let bolded = TableView.emboldened(heading, with: style(boldsHeader: true).textFonts)
    let font = NSAttributedString(bolded).attribute(.font, at: 0, effectiveRange: nil) as? UIFont
    XCTAssertEqual(font, .boldSystemFont(ofSize: 13))
    XCTAssertEqual(String(bolded.characters), "Name")
  }

  func testEmboldenedHeadingWithoutABoldFaceIsUnchanged() {
    let fonts = TextFonts(normal: .systemFont(ofSize: 13), italic: nil, bold: nil, boldItalic: nil, preferredLetterSpacing: nil, preferredLineHeight: nil)
    let heading = AttributedString("Name")
    XCTAssertEqual(TableView.emboldened(heading, with: fonts), heading)
  }
}
#endif
