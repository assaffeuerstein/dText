//
//  Item.swift
//  dText
//
//  Created by Assaf Feuerstein on 20/10/2026.
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
