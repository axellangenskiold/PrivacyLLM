//
//  Item.swift
//  PrivacyLLM
//
//  Created by Axel Langenskiöld on 2026-06-10.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
