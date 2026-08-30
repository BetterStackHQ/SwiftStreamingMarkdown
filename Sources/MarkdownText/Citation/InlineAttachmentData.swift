//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AttachmentType: String, Codable {
  case citation
}

struct InlineAttachmentData: Codable {
  let type: AttachmentType
  let title: String
  let accessibilityLabel: String
  let url: URL
  /// An inert citation draws the same chip but is not a link (see
  /// `CitationCoder.citationInertQueryParam`). Absent in older payloads: false.
  var isInert: Bool = false

  init(type: AttachmentType, title: String, accessibilityLabel: String, url: URL, isInert: Bool = false) {
    self.type = type
    self.title = title
    self.accessibilityLabel = accessibilityLabel
    self.url = url
    self.isInert = isInert
  }

  private enum CodingKeys: String, CodingKey { case type, title, accessibilityLabel, url, isInert }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decode(AttachmentType.self, forKey: .type)
    title = try container.decode(String.self, forKey: .title)
    accessibilityLabel = try container.decode(String.self, forKey: .accessibilityLabel)
    url = try container.decode(URL.self, forKey: .url)
    isInert = try container.decodeIfPresent(Bool.self, forKey: .isInert) ?? false
  }
}
