import Foundation
import Markdown
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// An inline image drawn in the text (`InlineImageConfig`), e.g. a person's avatar before
/// their name. Public so a host can find its images in the rendered text (tests, a11y).
///
/// Same threading invariant as `InlineCitationAttachment`: the attachment is built on the
/// parser's background executor, so `init` stores only values and the (`@MainActor`) host
/// closure. The light/dark bitmaps are drawn lazily the first time TextKit asks for the
/// image, on the main thread during layout, and then memoized.
public final class InlineImageAttachment: NSTextAttachment {
  /// The image's markdown source, handed to the host provider.
  public let source: String
  /// The image's alt text: what a screen reader reads for it (nothing when empty).
  public let altText: String

  private let size: CGSize
  private let spacing: CGFloat
  private let provider: (@MainActor @Sendable (_ source: String, _ colorScheme: ColorScheme) -> MDImage?)?

  private var lightImage: MDImage?
  private var darkImage: MDImage?
  private var assignedImage: MDImage?
  private var didRender = false

  init(source: String, altText: String, config: MarkdownRenderConfig.InlineImageConfig) {
    self.source = source
    self.altText = altText
    self.size = config.size
    self.spacing = config.spacing
    self.provider = config.image
    super.init(data: nil, ofType: nil)
    bounds = CGRect(x: 0, y: config.baselineAdjustment, width: config.size.width + config.spacing, height: config.size.height)
  }

  public required init?(coder: NSCoder) {
    return nil
  }

  #if canImport(UIKit)
  public override var image: UIImage? {
    get { currentImage() }
    set { assignedImage = newValue }
  }
  #elseif canImport(AppKit)
  public override var image: NSImage? {
    get { currentImage() }
    set { assignedImage = newValue }
  }
  #endif

  public override func image(
    forBounds imageBounds: CGRect,
    textContainer: NSTextContainer?,
    characterIndex charIndex: Int
  ) -> MDImage? {
    return image
  }

  private func currentImage() -> MDImage? {
    renderIfNeeded()
    if let assignedImage { return assignedImage }
    switch AppAppearance.$current.read({ $0 }) {
    case .dark: return darkImage
    case .light: return lightImage
    }
  }

  private func renderIfNeeded() {
    guard !didRender else { return }
    dispatchPrecondition(condition: .onQueue(.main))
    didRender = true
    guard let provider else { return }
    MainActor.assumeIsolated {
      self.lightImage = provider(source, .light).map(self.padded)
      self.darkImage = provider(source, .dark).map(self.padded)
    }
  }

  /// The host's bitmap at `size`, followed by `spacing` blank points, so the gap before
  /// the next word belongs to the image and can't be broken or collapsed.
  @MainActor
  private func padded(_ image: MDImage) -> MDImage {
    let canvas = CGSize(width: size.width + spacing, height: size.height)
    let imageRect = CGRect(origin: .zero, size: size)
    #if canImport(UIKit)
    let format = UIGraphicsImageRendererFormat.preferred()
    format.opaque = false
    return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
      image.draw(in: imageRect)
    }
    #elseif canImport(AppKit)
    return NSImage(size: canvas, flipped: false) { _ in
      image.draw(in: imageRect)
      return true
    }
    #endif
  }
}

extension Markdown.Image: InlineConvertible {

  /// With an `InlineImageConfig.image` provider, an inline image attachment carrying the
  /// surrounding run's attributes (a link's `.link` included); without one, nothing, as
  /// before images had a conversion.
  func convert(attributeContainer: NSAttributeContainer, config: MarkdownRenderConfig) -> NSMutableAttributedString {
    let imageConfig = config.inlineImageConfig
    guard imageConfig.image != nil, let source, !source.isEmpty else { return NSMutableAttributedString() }
    let attachment = InlineImageAttachment(source: source, altText: plainText, config: imageConfig)
    return NSMutableAttributedString(attachment: attachment).mergingAttributes(attributeContainer)
  }
}
