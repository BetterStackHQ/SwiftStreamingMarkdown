//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
import UIKit
/// Cross-platform image type. Resolves to `UIImage` on UIKit platforms and `NSImage` on AppKit platforms.
public typealias MDImage = UIImage
#elseif canImport(AppKit)
import AppKit
/// Cross-platform image type. Resolves to `UIImage` on UIKit platforms and `NSImage` on AppKit platforms.
public typealias MDImage = NSImage
#endif

extension MDImage {
  /// Creates a cross-platform image from an SF Symbol name.
  public convenience init?(sfSymbol name: String) {
    #if canImport(UIKit)
    self.init(systemName: name)
    #elseif canImport(AppKit)
    self.init(systemSymbolName: name, accessibilityDescription: nil)
    #endif
  }

  /// Recolors every opaque pixel to `color`, preserving alpha — used to tint a citation
  /// chip's leading icon to the same resolved color as its text.
  func tinted(_ color: MDColor) -> MDImage {
    #if canImport(UIKit)
    return withTintColor(color, renderingMode: .alwaysTemplate)
    #elseif canImport(AppKit)
    return NSImage(size: size, flipped: false) { rect in
      color.setFill()
      rect.fill()
      self.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
      return true
    }
    #endif
  }
}
