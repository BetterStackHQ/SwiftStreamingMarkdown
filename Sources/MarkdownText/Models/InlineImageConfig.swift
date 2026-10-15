import Foundation
import SwiftUI

extension MarkdownRenderConfig {

  /// Controls whether inline images (`![alt](source)` inside a paragraph, a link's label
  /// included) render, and how. With no `image` provider (the default) an inline image
  /// renders as nothing, as it always has.
  ///
  /// The host draws the image: the provider gets the image's source and the appearance to
  /// draw it for, and returns the finished bitmap (already clipped to its shape). It is
  /// drawn as is, untinted, at `size`, followed by `spacing` points of blank before the
  /// text that follows. An image inside a link is part of the link: it carries the link's
  /// `.link` attribute, so a tap on it opens the link.
  public struct InlineImageConfig: Hashable, Sendable {
    /// Width and height the image is drawn at, in points.
    public let size: CGSize
    /// Blank points drawn after the image, before the text that follows it.
    public let spacing: CGFloat
    /// Points added to the image's baseline offset. At `0` the image's bottom sits on the
    /// text baseline; a negative value lowers it (e.g. to center it on the line).
    public let baselineAdjustment: CGFloat
    /// Resolves an image's source to the bitmap drawn for one appearance, or nil to draw
    /// nothing for it (the image's place stays blank). Called lazily on the main thread when
    /// the text is laid out, once per appearance per image, so a host may read main-actor
    /// image caches here.
    public let image: (@MainActor @Sendable (_ source: String, _ colorScheme: ColorScheme) -> MDImage?)?

    public init(
      size: CGSize,
      spacing: CGFloat = 0,
      baselineAdjustment: CGFloat = 0,
      image: (@MainActor @Sendable (_ source: String, _ colorScheme: ColorScheme) -> MDImage?)? = nil
    ) {
      self.size = size
      self.spacing = spacing
      self.baselineAdjustment = baselineAdjustment
      self.image = image
    }

    /// No provider: inline images render as nothing.
    public static let `default` = InlineImageConfig(size: .zero)

    /// Equality compares every field except `image` (a function value can't be compared),
    /// matching `CitationConfig.citationImage`.
    public static func == (lhs: InlineImageConfig, rhs: InlineImageConfig) -> Bool {
      lhs.size == rhs.size &&
        lhs.spacing == rhs.spacing &&
        lhs.baselineAdjustment == rhs.baselineAdjustment &&
        (lhs.image == nil) == (rhs.image == nil)
    }

    /// Hash mirrors `==`.
    public func hash(into hasher: inout Hasher) {
      hasher.combine(size.width)
      hasher.combine(size.height)
      hasher.combine(spacing)
      hasher.combine(baselineAdjustment)
      hasher.combine(image == nil)
    }
  }
}
