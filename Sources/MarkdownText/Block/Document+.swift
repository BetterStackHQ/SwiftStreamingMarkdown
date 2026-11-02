//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI

extension Markdown.Document {

  func convert(with config: MarkdownRenderConfig) -> [MarkdownRenderable] {
    var renderables = self
      .blockConvertibleChildren
      .map { $0.convert(attributeContainer: NSAttributeContainer(), config: config) }
    let firstListNumber = config.orderedListStyle.firstListNumber
    if firstListNumber != 1,
       let first = renderables.firstIndex(where: { if case .orderedList = $0 { return true } else { return false } }),
       case .orderedList(let id, let items, _) = renderables[first] {
      renderables[first] = .orderedList(id: id, items: items, start: firstListNumber)
    }
    return renderables
  }
}
