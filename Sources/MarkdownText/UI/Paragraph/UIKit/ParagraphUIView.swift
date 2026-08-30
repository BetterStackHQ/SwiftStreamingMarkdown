//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
import iosMath
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AccessibilityContent {
  let label: String?
  let actions: [UIAccessibilityCustomAction]
}

private struct CachedParagraphUIViewSize {
  let size: CGSize
  let targetWidth: CGFloat
}

class ParagraphUIView: UITextView {
  private static let jsonEncoder = JSONEncoder()
  static let animationDuration: CFTimeInterval = ParagraphAnimationConstants.fadeInDuration

  private(set) var paragraphContents: NSMutableAttributedString = NSMutableAttributedString()
  private(set) var lineSpacing: CGFloat?
  private var activeAnimations: [FadeAnimationData] = []
  private var fadeAnimationDisplayLink: CADisplayLink?
  private var cachedSize: CachedParagraphUIViewSize?

  var textContextMenu: TextContextMenu?
  var markdownController: MarkdownController?

  // To override the behaviour of this property, do so on ParagraphView's SwiftUI wrapper.
  var onUrlTap: (URL) -> Void = { UIApplication.shared.open($0) }

  override init(frame: CGRect, textContainer: NSTextContainer?) {
    super.init(frame: frame, textContainer: textContainer)
    delegate = self
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    delegate = self
    setupView()
  }

  deinit {
    tearDownDisplayLink()
    activeAnimations.removeAll()
  }

  override func willMove(toWindow newWindow: UIWindow?) {
    super.willMove(toWindow: newWindow)
    // Fix for crash: "UIPreviewTarget requires that the container view is in a window". When the view is removed from the window (e.g. scrolled out in LazyVStack), we should clear the selection to prevent any pending menu or drag interactions from trying to reference the detached view.
    if newWindow == nil {
      selectedTextRange = nil
    }
  }

  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if result {
      selectedTextRange = nil
    }
    return result
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
      AppAppearance.update(style: traitCollection.userInterfaceStyle)
      // Chip colours are resolved into CGColors at draw time; re-resolve for the new appearance.
      updateInlineCodeChips()
    }
  }

  override var intrinsicContentSize: CGSize {
    if let cachedSize {
      return cachedSize.size
    }
    var targetWidth = bounds.width
    if targetWidth <= 0 || targetWidth.isInfinite {
      // When bounds.width is not valid, we have to give a best guess, otherwise Chat becomes blank in some cases sometimes. It may be related to LazyVStack.
      targetWidth = UIScreen.main.bounds.width
    }
    let targetSize = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
    let contentSize = sizeThatFits(targetSize)
    let roundedUpSize = CGSize(width: contentSize.width.rounded(.up), height: contentSize.height.rounded(.up))
    cachedSize = CachedParagraphUIViewSize(size: roundedUpSize, targetWidth: targetWidth)
    return roundedUpSize
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.width != cachedSize?.targetWidth {
      invalidateCachedSize()
    }
    invalidateIntrinsicContentSize()
    updateInlineCodeChips()
  }

  // MARK: - Inline code chips

  /// Hosts one shape layer per inline code chip (`.inlineCodeChip` runs), beneath the text
  /// so the run's glyphs paint over the chip's fill and border. TextKit's own run background
  /// is square and borderless; the chip is drawn from the run's laid-out segment frames instead.
  private let inlineCodeChipLayer = CALayer()

  /// The chip shapes currently drawn, in text order (tests read these back).
  var inlineCodeChipShapes: [CAShapeLayer] {
    (inlineCodeChipLayer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
  }

  private func updateInlineCodeChips() {
    inlineCodeChipLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    let text: NSAttributedString = attributedText
    guard text.length > 0 else { return }
    var chips: [(NSRange, InlineCodeChipAttribute)] = []
    text.enumerateAttribute(.inlineCodeChip, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      if let style = value as? InlineCodeChipAttribute { chips.append((range, style)) }
    }
    guard !chips.isEmpty else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    inlineCodeChipLayer.frame = bounds
    for (range, style) in chips {
      for rect in segmentRects(for: range) {
        // Web `px-0.5`: the chip reaches a little past the glyphs on each side; a hair
        // inside the line box vertically so neighbouring lines' chips never touch.
        let chipRect = rect
          .insetBy(dx: -InlineCodeChipAttribute.horizontalPadding, dy: 0.5)
          .offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
        let shape = CAShapeLayer()
        shape.path = UIBezierPath(roundedRect: chipRect, cornerRadius: style.cornerRadius).cgPath
        shape.fillColor = style.fillColor.resolvedColor(with: traitCollection).cgColor
        shape.strokeColor = style.borderColor.resolvedColor(with: traitCollection).cgColor
        shape.lineWidth = 1
        inlineCodeChipLayer.addSublayer(shape)
      }
    }
    CATransaction.commit()
  }

  /// The laid-out rectangles a character range occupies (one per line it spans), in text
  /// container coordinates. TextKit 2 when the view has it; TextKit 1 otherwise. TextKit 2
  /// may report a single line's run as several segments, so segments on one line are merged.
  private func segmentRects(for range: NSRange) -> [CGRect] {
    Self.mergingRectsPerLine(rawSegmentRects(for: range))
  }

  /// Unions rects that share a line (same vertical extent) into one, keeping line order.
  static func mergingRectsPerLine(_ rects: [CGRect]) -> [CGRect] {
    var merged: [CGRect] = []
    for rect in rects {
      if let last = merged.last, abs(last.midY - rect.midY) < 0.5 {
        merged[merged.count - 1] = last.union(rect)
      } else {
        merged.append(rect)
      }
    }
    return merged
  }

  private func rawSegmentRects(for range: NSRange) -> [CGRect] {
    var rects: [CGRect] = []
    if let layoutManager = textLayoutManager, let contentManager = layoutManager.textContentManager,
       let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
       let end = contentManager.location(start, offsetBy: range.length),
       let textRange = NSTextRange(location: start, end: end) {
      layoutManager.ensureLayout(for: textRange)
      layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
        rects.append(frame)
        return true
      }
      return rects
    }
    let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    layoutManager.enumerateEnclosingRects(
      forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer
    ) { rect, _ in rects.append(rect) }
    return rects
  }

  func setParagraphContents(_ newContents: NSMutableAttributedString, lineSpacing: CGFloat? = nil, animatedByWord: Bool) {
    // Keep the cached interface style up to date for citation preview rendering.
    // This runs on the main thread so it's safe to read traitCollection here.
    AppAppearance.update(style: traitCollection.userInterfaceStyle)

    guard paragraphContents != newContents || self.lineSpacing != lineSpacing else {
      return
    }
    self.paragraphContents = newContents
    self.lineSpacing = lineSpacing

    let oldAttributedString: NSAttributedString = attributedText
    let finalString: NSMutableAttributedString
    if lineSpacing != nil {
      finalString = applyLineSpacing(to: newContents, lineSpacing: lineSpacing)
    } else {
      finalString = newContents
    }

    guard finalString != oldAttributedString else {
      return
    }

    // Stop display link update before updating the attributed string
    tearDownDisplayLink()
    invalidateCachedSize()
    attributedText = finalString

    configureAccessibility(for: finalString)

    invalidateIntrinsicContentSize()
    setNeedsLayout()

    let newContentLength = attributedText.length - oldAttributedString.length

    if animatedByWord,
       newContentLength > 0 {
      // Animate word by word
      let newContentRange = NSRange(location: oldAttributedString.length, length: newContentLength)
      let wordRanges = attributedText.splitIntoWords(withIn: newContentRange)
      let wordCount = wordRanges.count
      let delayBetweenWords: Double = ParagraphAnimationConstants.delayBetweenWordsRatio / Double(wordCount)
      let baseStartTime = CACurrentMediaTime()
      for (index, wordRange) in wordRanges.enumerated() {
        let animationData = FadeAnimationData(
          startTime: baseStartTime + Double(index) * delayBetweenWords,
          duration: Self.animationDuration,
          range: wordRange
        )
        activeAnimations.append(animationData)
      }

      updateTextViewWithCurrentAnimations()

      if fadeAnimationDisplayLink == nil {
        setUpDisplayLink()
      }
    } else {
      // If no animation needed anymore, clean up all existings animations if any.
      activeAnimations.removeAll()
    }
  }

  private func applyLineSpacing(to attributedString: NSMutableAttributedString, lineSpacing: CGFloat?) -> NSMutableAttributedString {
    let result = NSMutableAttributedString(attributedString: attributedString)
    if let lineSpacing {
      result.setLineSpacing(lineSpacing)
    }
    return result
  }

  private func setupView() {
    // Only register if not already registered to prevent conflicts
    if NSTextAttachment.textAttachmentViewProviderClass(forFileType: UTType.data.identifier) == nil {
      NSTextAttachment.registerViewProviderClass(LatexViewProvider.self, forFileType: UTType.data.identifier)
    }

    isEditable = false
    isSelectable = true
    isScrollEnabled = false
    textAlignment = .left
    backgroundColor = .clear
    if #available(iOS 18.0, *) {
      writingToolsBehavior = .none
    }

    setContentHuggingPriority(.defaultHigh, for: .vertical)
    setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
    setContentHuggingPriority(.defaultLow, for: .horizontal)
    setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    textContainerInset = .zero
    textContainer.lineFragmentPadding = 0
    textContainer.widthTracksTextView = true
    textContainer.heightTracksTextView = true
    textContainer.maximumNumberOfLines = 0
    textContainer.lineBreakMode = .byWordWrapping

    // When this is empty, UITextView will not override the styles set by attributes
    self.linkTextAttributes = [:]

    // Beneath every subview's layer (the text canvas included), so chips sit under the glyphs.
    layer.insertSublayer(inlineCodeChipLayer, at: 0)

    // Disable drag interaction to prevent crashes related to dragging from a view that might disappear
    textDragInteraction?.isEnabled = false
  }

  /// Creates a custom accessibility action that forwards activation to `onUrlTap`.
  private func makeAccessibilityAction(name: String, url: URL) -> UIAccessibilityCustomAction {
    return UIAccessibilityCustomAction(name: name) { [weak self] _ in
      guard let self else { return false }
      self.onUrlTap(url)
      return true
    }
  }

  /// Generate accessibility label and actions in a single pass (optimized)
  private func generateAccessibilityContent(from attributedString: NSAttributedString) -> AccessibilityContent? {
    var labelComponents: [String] = []
    var actions: [UIAccessibilityCustomAction] = []
    let fullRange = NSRange(location: 0, length: attributedString.length)

    attributedString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
      // Handle citation attachments
      if let attachment = attrs[.attachment] as? InlineCitationAttachment,
         let citationData = attachment.citationData {
        // Add to accessibility label
        labelComponents.append(citationData.accessibilityLabel)

        // Create accessibility action for citations; an inert chip offers none.
        if !citationData.isInert {
          let actionName = String.openCitation(citationLabel: citationData.accessibilityLabel)
          let action = makeAccessibilityAction(name: actionName, url: citationData.url)
          actions.append(action)
        }
      } else {
        // Add the regular text for this range
        let substring = attributedString.attributedSubstring(from: range)
        let text = substring.string
        if !text.isEmpty {
          labelComponents.append(text)
        }
      }
    }

    let accessibilityLabel = labelComponents.isEmpty ? nil : labelComponents.joined()

    // Nothing but plain text: let the caller fall back to the string itself. A citation
    // (even an inert one, which offers no action) needs the composed label so the chip
    // reads as its title rather than the attachment placeholder character.
    let hasCitation = attributedString.attribute(.attachment, at: 0, longestEffectiveRange: nil, in: fullRange) != nil
      || labelComponents.joined() != attributedString.string
    guard !actions.isEmpty || hasCitation else { return nil }

    return AccessibilityContent(label: accessibilityLabel, actions: actions)
  }

  /// Configure accessibility properties for the text view
  private func configureAccessibility(for attributedString: NSAttributedString) {
    // Generate the full accessibility content directly
    if let accessibilityContent = generateAccessibilityContent(from: attributedString) {
      // We have citations, use the generated content
      accessibilityLabel = accessibilityContent.label
      accessibilityCustomActions = accessibilityContent.actions
    } else {
      // No citations found, just use the plain text
      accessibilityLabel = attributedString.string
      accessibilityCustomActions = nil
    }
  }

  @objc private func updateFadeAnimation() {
    let currentTime = CACurrentMediaTime()
    var completedAnimations: [UUID] = []

    updateTextViewWithCurrentAnimations()

    // Remove completed animations
    for animation in activeAnimations {
      let elapsed = currentTime - animation.startTime
      let progress = elapsed / animation.duration

      if progress >= 1.0 {
        completedAnimations.append(animation.id)
      }
    }
    activeAnimations.removeAll { completedAnimations.contains($0.id) }

    if activeAnimations.isEmpty {
      tearDownDisplayLink()
    }
  }

  private func updateTextViewWithCurrentAnimations() {
    let currentTime = CACurrentMediaTime()

    textStorage.beginEditing()
    defer { textStorage.endEditing() }

    for animation in activeAnimations {
      guard animation.range.location + animation.range.length <= textStorage.length else {
        continue
      }
      let elapsed = currentTime - animation.startTime
      let animatedAlpha: CGFloat

      if elapsed < 0 {
        animatedAlpha = 0.0
      } else {
        let progress = min(max(elapsed / animation.duration, 0.0), 1.0)
        let easedProgress = paragraphEaseOut(progress)
        animatedAlpha = easedProgress
      }

      // Apply alpha to this animation's range, preserving each span's
      // existing foreground color. Spans with no foreground color get a
      // sensible default so they still fade in instead of disappearing.
      let defaultColor = UIColor(Color.Theme.Foreground.Primary.Primary750)
      textStorage.enumerateAttribute(.foregroundColor, in: animation.range, options: []) { value, range, _ in
        let baseColor = (value as? UIColor) ?? defaultColor
        textStorage.addAttribute(.foregroundColor, value: baseColor.withAlphaComponent(animatedAlpha), range: range)
      }
    }
  }

  private func setUpDisplayLink() {
    fadeAnimationDisplayLink = CADisplayLink(target: self, selector: #selector(updateFadeAnimation))
    fadeAnimationDisplayLink?.preferredFramesPerSecond = 60
    fadeAnimationDisplayLink?.add(to: .main, forMode: .common)
  }

  private func tearDownDisplayLink() {
    fadeAnimationDisplayLink?.remove(from: .main, forMode: .common)
    fadeAnimationDisplayLink = nil
  }

  private func invalidateCachedSize() {
    cachedSize = nil
  }

  func setTextContextMenu(_ menu: TextContextMenu?) {
    textContextMenu = menu
  }

  func setMarkdownController(_ controller: MarkdownController?) {
    markdownController = controller
  }
}

// MARK: - UITextViewDelegate
extension ParagraphUIView: UITextViewDelegate {
  func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
    self.onUrlTap(URL)
    return false
  }

  func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange) -> Bool {
    // Check if this is our custom citation attachment with pre-decoded data
    if let citationAttachment = textAttachment as? InlineCitationAttachment,
       let citationData = citationAttachment.citationData, !citationData.isInert {
      self.onUrlTap(citationData.url)
      return false
    }

    return false
  }

  func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
    return textContextMenu?.buildUIMenu(
      textView: textView,
      selectedRange: range,
      suggestedActions: suggestedActions,
      markdownController: markdownController
    )
  }

  func textView(_ textView: UITextView, willPresentEditMenuWith animator: any UIEditMenuInteractionAnimating) {
    guard let textContextMenu, let markdownController else { return }
    let clampedRange = NSIntersectionRange(textView.selectedRange, NSRange(location: 0, length: textView.attributedText.length))
    let selectedText = textView.attributedText.attributedSubstring(from: clampedRange).string
    for group in textContextMenu.menuGroups {
      for item in group.items {
        markdownController.onContextMenuAppear(id: item.id, selectedContent: selectedText)
      }
    }
  }
}

fileprivate extension NSMutableAttributedString {
  func setLineSpacing(_ lineSpacing: CGFloat) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.alignment = .left
    addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: length))
  }
}
#endif
