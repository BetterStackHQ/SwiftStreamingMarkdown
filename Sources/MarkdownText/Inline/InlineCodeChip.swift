//
//  InlineCodeChip.swift
//  The attribute an inline code run carries when the inline style asks for a rounded or
//  bordered chip. TextKit's own `.backgroundColor` is a square per-glyph fill with no
//  border and no corners, so the chip is painted separately (`ParagraphUIView`) from the
//  run's rendered geometry; the attribute only says what to paint.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension NSAttributedString.Key {
  /// Value: `InlineCodeChipAttribute`. Present on an inline code run drawn as a chip.
  public static let inlineCodeChip = NSAttributedString.Key("SwiftStreamingMarkdown.inlineCodeChip")
}

/// What an inline code chip looks like: fill, border, and corner radius. A class so it
/// can travel as an attributed string attribute value.
final class InlineCodeChipAttribute: NSObject {
  let fillColor: MDColor
  let borderColor: MDColor
  let cornerRadius: CGFloat

  init(fillColor: MDColor, borderColor: MDColor, cornerRadius: CGFloat) {
    self.fillColor = fillColor
    self.borderColor = borderColor
    self.cornerRadius = cornerRadius
  }

  /// Horizontal breathing room the chip adds past the glyph run on each side (web `px-0.5`).
  static let horizontalPadding: CGFloat = 2

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? InlineCodeChipAttribute else { return false }
    return fillColor == other.fillColor && borderColor == other.borderColor && cornerRadius == other.cornerRadius
  }

  override var hash: Int {
    var hasher = Hasher()
    hasher.combine(fillColor)
    hasher.combine(borderColor)
    hasher.combine(cornerRadius)
    return hasher.finalize()
  }
}
