//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

/// The inline citation chip.
///
/// **Threading invariant:** the chip is a rasterized bitmap (UIKit/TextKit drawing), and
/// none of that drawing may happen off the main actor. The attachment is *built* on the
/// parser's background executor during `document.convert(...)`, so `init` stores only value
/// styling and the (`@MainActor`) host icon closure and creates **no** `UIImage`/`UIColor`
/// and does **no** TextKit work. The light/dark preview bitmaps are rendered lazily the
/// first time TextKit asks for the image (`image` getter → `image(forBounds:…)`), which
/// happens on the main thread during layout, and then memoized. This confines every
/// `UIGraphicsImageRenderer` / `NSString.draw` / `UIImage` create-and-release to the main
/// actor and fixes the over-release crash that came from rasterizing on the cooperative
/// pool (ios-app #429). See `renderPreviewsIfNeeded()`.
final class InlineCitationAttachment: NSTextAttachment {
  /// The decoded citation data - available immediately without JSON parsing
  private(set) var citationData: InlineAttachmentData?

  /// Styling resolved from the active `CitationConfig`. Exposed so the live
  /// label provider can mirror the same look as the precomputed preview image.
  let font: MDFont
  let textColor: Color
  let backgroundColor: Color
  /// Host closure that supplies the optional leading icon. `@MainActor` because it reads
  /// main-actor-owned image caches on the host side; only ever invoked from the main-thread
  /// rasterization pass (`renderPreviewsIfNeeded`).
  private let citationImageProvider: (@MainActor @Sendable (_ destination: String) -> MDImage?)?

  /// Untinted leading icon resolved from `CitationConfig.citationImage`, or nil for no icon.
  /// Resolved lazily on the main thread when the previews are rendered, then tinted to match
  /// `textColor` per-appearance inside each preview bitmap.
  private(set) var icon: MDImage?

  // MARK: - Precomputed preview images

  private var lightPreviewImage: MDImage?
  private var darkPreviewImage: MDImage?
  private var assignedImage: MDImage?
  /// Whether `renderPreviewsIfNeeded()` has already run (once per instance).
  private var didRenderPreviews = false

  // MARK: - Shared Layout

  static let textInsets = MDEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
  /// The chip is a capsule: fully round ends, so the radius is half the rendered height.
  static func cornerRadius(for size: CGSize) -> CGFloat { size.height / 2 }
  /// Gap between the leading icon and the title text, when an icon is present.
  static let iconTextSpacing: CGFloat = 3
  /// Icon side as a multiple of the chip font's point size (16pt at a 13.5pt chip).
  static let iconScale: CGFloat = 1.15

  #if canImport(UIKit)
  override var image: UIImage? {
    get {
      renderPreviewsIfNeeded()
      if let assignedImage { return assignedImage }
      let app = AppAppearance.$current.read({ $0 })
      switch app {
      case .dark: return darkPreviewImage
      case .light: return lightPreviewImage
      }
    }
    set { assignedImage = newValue }
  }
  #elseif canImport(AppKit)
  override var image: NSImage? {
    get {
      renderPreviewsIfNeeded()
      if let assignedImage { return assignedImage }
      let app = AppAppearance.$current.read({ $0 })
      switch app {
      case .dark: return darkPreviewImage
      case .light: return lightPreviewImage
      }
    }
    set { assignedImage = newValue }
  }
  #endif

  /// TextKit's per-fragment image lookup. Overridden so both TextKit 1 and TextKit 2 route
  /// through the lazy main-thread rasterization above (the default implementation returns
  /// `self.image`, but we make the dependency explicit).
  override func image(
    forBounds imageBounds: CGRect,
    textContainer: NSTextContainer?,
    characterIndex charIndex: Int
  ) -> MDImage? {
    return image
  }

  /// Called during markdown parsing (background executor). Stores only value styling and the
  /// host icon closure - no UIKit/TextKit object is created here. The preview bitmaps are
  /// rendered lazily on the main thread; see `renderPreviewsIfNeeded()`.
  init(payload: Data, citationConfig: MarkdownRenderConfig.CitationConfig) {
    let decoded = try? JSONDecoder().decode(InlineAttachmentData.self, from: payload)
    let citationData = (decoded?.type == .citation) ? decoded : nil
    self.citationData = citationData

    self.font = citationConfig.font
    self.textColor = citationConfig.textColor
    self.backgroundColor = citationConfig.backgroundColor
    self.citationImageProvider = citationConfig.citationImage

    super.init(data: payload, ofType: UTType.url.identifier)
  }

  /// Create citation attachment directly from data struct
  convenience init?(citationData: InlineAttachmentData, citationConfig: MarkdownRenderConfig.CitationConfig) {
    guard citationData.type == .citation,
          let payload = try? JSONEncoder().encode(citationData) else {
      return nil
    }
    self.init(payload: payload, citationConfig: citationConfig)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  // MARK: - Preview Image Rendering

  /// Render the light/dark preview bitmaps on the main thread, once. Every UIKit/TextKit
  /// object (the host icon, the tinted copy, the `UIGraphicsImageRenderer` output) is created
  /// and released here, on the main actor, so nothing crosses the cooperative pool. The
  /// `dispatchPrecondition` makes the contract enforceable in tests and loud in debug; the
  /// getter that calls this is only ever hit during main-thread TextKit layout.
  private func renderPreviewsIfNeeded() {
    guard !didRenderPreviews else { return }
    dispatchPrecondition(condition: .onQueue(.main))
    didRenderPreviews = true

    guard let title = citationData?.title else { return }

    // We are on the main queue (asserted above); adopt main-actor isolation so the
    // `@MainActor` host closure can be invoked and main-actor caches read safely.
    MainActor.assumeIsolated {
      let resolvedIcon = citationData.flatMap { citationImageProvider?($0.url.absoluteString) }
      self.icon = resolvedIcon

      self.lightPreviewImage = Self.renderCitationImage(
        title: title, font: self.font, icon: resolvedIcon,
        textColor: MDColor(self.textColor), backgroundColor: MDColor(self.backgroundColor),
        appearance: .light
      )
      self.darkPreviewImage = Self.renderCitationImage(
        title: title, font: self.font, icon: resolvedIcon,
        textColor: MDColor(self.textColor), backgroundColor: MDColor(self.backgroundColor),
        appearance: .dark
      )
    }
  }

  @MainActor
  private static func renderCitationImage(
    title: String, font: MDFont, icon: MDImage?,
    textColor: MDColor, backgroundColor: MDColor,
    appearance: AppAppearance
  ) -> MDImage {
    // Resolve colors for the target appearance
    #if canImport(UIKit)
    let traitCollection = UITraitCollection(userInterfaceStyle: appearance.platformType)
    let resolvedTextColor = textColor.resolvedColor(with: traitCollection)
    let resolvedBackgroundColor = backgroundColor.resolvedColor(with: traitCollection)
    #elseif canImport(AppKit)
    var resolvedTextColor = textColor
    var resolvedBackgroundColor = backgroundColor
    appearance.platformType?.performAsCurrentDrawingAppearance {
      resolvedTextColor = textColor.usingColorSpace(.sRGB) ?? textColor
      resolvedBackgroundColor = backgroundColor.usingColorSpace(.sRGB) ?? backgroundColor
    }
    #endif

    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: resolvedTextColor]
    let textSize = (title as NSString).size(withAttributes: attributes)

    // The icon scales with the chip font — a touch over its point size, the way a
    // web chip draws a text-size icon beside its label — and never exceeds the text's
    // own line height, so it stays visually anchored to the title regardless of size.
    // (Cap height read as a glyph half the text's height once the icon's own padding
    // was subtracted.)
    let resolvedIcon = icon?.tinted(resolvedTextColor)
    let iconSide = resolvedIcon != nil ? min(ceil(font.pointSize * Self.iconScale), ceil(textSize.height)) : 0
    // The icon hugs the capsule: its inset from the chip's leading edge equals its inset
    // from the top and bottom, so a round mark sits concentric with the capsule's end
    // instead of floating `textInsets.left` further in (an icon fills the text height,
    // so that inset is `textInsets.top` plus whatever the icon leaves of the line).
    let iconInsetY = textInsets.top + (ceil(textSize.height) - iconSide) / 2
    let iconLeadingInset = resolvedIcon != nil ? iconInsetY : textInsets.left
    let iconLeading = resolvedIcon != nil ? iconSide + iconTextSpacing : 0

    let totalSize = CGSize(
      width: ceil(textSize.width) + iconLeading + iconLeadingInset + textInsets.right,
      height: ceil(textSize.height) + textInsets.top + textInsets.bottom
    )
    let iconRect = CGRect(x: iconLeadingInset, y: iconInsetY, width: iconSide, height: iconSide)
    let textRect = CGRect(x: iconLeadingInset + iconLeading, y: textInsets.top,
                          width: ceil(textSize.width), height: ceil(textSize.height))

    // Render the citation pill image
    #if canImport(UIKit)
    let renderer = UIGraphicsImageRenderer(size: totalSize)
    return renderer.image { _ in
      let rect = CGRect(origin: .zero, size: totalSize)
      let path = UIBezierPath(roundedRect: rect, cornerRadius: Self.cornerRadius(for: rect.size))
      resolvedBackgroundColor.setFill()
      path.fill()

      resolvedIcon?.draw(in: iconRect)
      (title as NSString).draw(in: textRect, withAttributes: attributes)
    }
    #elseif canImport(AppKit)
    return NSImage(size: totalSize, flipped: false) { rect in
      let radius = Self.cornerRadius(for: rect.size)
      let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
      resolvedBackgroundColor.setFill()
      path.fill()

      resolvedIcon?.draw(in: iconRect)
      let textRect = CGRect(x: textRect.minX, y: Self.textInsets.bottom,
                            width: textRect.width, height: textRect.height)
      (title as NSString).draw(in: textRect, withAttributes: attributes)
      return true
    }
    #endif
  }
}
