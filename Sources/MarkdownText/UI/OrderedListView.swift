//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

struct OrderedListView: View {

  let items: [MarkdownListItem]
  @Environment(\.markdownConfig) var config: MarkdownRenderConfig

  var body: some View {
    let marker = config.orderedListStyle.orderedListMarker
    VStack(alignment: .leading, spacing: marker.itemSpacing, content: {
      ForEach(0..<items.count, id: \.self) { idx in
        HStack(alignment: .centerOfFirstLine, spacing: marker.contentSpacing) {
          markerView(marker, number: idx + 1)
            .transition(.opacity)
          if let firstChild = items[idx].children.first {
            if case .paragraph(_, let contents) = firstChild {
              // Wrap the SingleBlockView to provide proper baseline alignment. This is to fix the mis-alignment when the view is rendered off-screen, e.g. snapshot.
              ListItemContentWrapper(paragraphContents: contents) {
                SingleBlockView(renderable: firstChild)
              }
              .accessibilityLabel(Text(markdownListAccessibilityLabel(for: contents.string, at: idx, length: items.count)))
            } else {
              SingleBlockView(renderable: firstChild)
            }
          }
          Spacer()
        }
        if items[idx].children.count > 1 {
          BlockView(renderables: Array(items[idx].children.dropFirst()))
            .padding([.leading], marker.nestedIndent)
        }
      }
    })
  }

  @ViewBuilder
  private func markerView(_ marker: MarkdownRenderConfig.OrderedListMarker, number: Int) -> some View {
    switch marker {
    case .plain:
      Text(verbatim: "\(number).")
        .font(config.orderedListStyle.textFonts, bold: true)
        .foregroundStyle(config.orderedListStyle.textColor)
    case .badge(let badge):
      let shape = RoundedRectangle(cornerRadius: badge.cornerRadius, style: .continuous)
      Text(verbatim: "\(number)")
        .font(Font(badge.font))
        .foregroundStyle(badge.textColor)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: badge.size, height: badge.size)
        .background(shape.fill(badge.fillColor))
        .overlay(shape.strokeBorder(badge.borderColor, lineWidth: badge.borderWidth))
    }
  }
}

extension MarkdownRenderConfig.OrderedListMarker {
  var itemSpacing: CGFloat {
    switch self {
    case .plain: 8
    case .badge(let badge): badge.itemSpacing
    }
  }

  var contentSpacing: CGFloat {
    switch self {
    case .plain: 11
    case .badge(let badge): badge.contentSpacing
    }
  }

  /// Nested blocks line up with the item text under a badge; plain lists keep them flush.
  var nestedIndent: CGFloat {
    switch self {
    case .plain: 0
    case .badge(let badge): badge.size + badge.contentSpacing
    }
  }
}

// Wrapper to provide proper baseline alignment for UIViewRepresentable content
struct ListItemContentWrapper<Content: View>: View {
  let paragraphContents: NSMutableAttributedString
  let content: () -> Content

  init(paragraphContents: NSMutableAttributedString, @ViewBuilder content: @escaping () -> Content) {
    self.paragraphContents = paragraphContents
    self.content = content
  }

  var body: some View {
    content()
      .alignmentGuide(.centerOfFirstLine) { _ in
        let font = extractFirstFont()
        return font.lineHeight / 2.0
      }
  }

  private func extractFirstFont() -> MDFont {
    // First check if the first character is a citation attachment - use its
    // own font so the alignment guide matches the actual rendered glyph,
    // not a stale default.
    if let citation = firstCharacterCitationAttachment(in: paragraphContents) {
      return citation.font
    }
    // Otherwise, look for regular font attributes
    if let font = firstFont(in: paragraphContents) {
      return font
    }
    return Typography.base.mdFont
  }

  private func firstCharacterCitationAttachment(in attributedString: NSAttributedString) -> InlineCitationAttachment? {
    guard attributedString.length > 0 else { return nil }
    return attributedString.attribute(.attachment, at: 0, effectiveRange: nil) as? InlineCitationAttachment
  }

  private func firstFont(in attributedString: NSAttributedString) -> MDFont? {
    guard attributedString.length > 0 else { return nil }

    // Fast path: attribute at location 0
    if let font = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? MDFont {
      return font
    }

    var found: MDFont?
    attributedString.enumerateAttribute(.font, in: NSRange(location: 0, length: attributedString.length)) { value, _, stop in
      if let font = value as? MDFont {
        found = font
        stop.pointee = true
      }
    }
    return found
  }
}

func markdownListAccessibilityLabel(for item: String, at index: Int, length: Int) -> String {
  "\(String.markdownList(length: String(length))), item \(index + 1): \(item)"
}

#Preview(body: {
  let items: [MarkdownListItem] = (0..<40).map { i in
    MarkdownListItem(children: [.paragraph(id: "\(i)", content: NSMutableAttributedString(string: "item \(i + 1)"))], startsWithBold: false)
  }
  return ScrollView {
    OrderedListView(items: items)
  }
})
