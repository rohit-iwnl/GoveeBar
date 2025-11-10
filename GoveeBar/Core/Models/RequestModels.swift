//
//  RequestModels.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 11/9/25.
//

import Foundation

struct GoveeCommand<Data: Encodable>: Encodable {
    let msg: Message
    
    struct Message: Encodable {
        let cmd: String
        let data: Data
    }
}

struct ScanData: Encodable {
    let account_topic: String
}

struct TurnData: Encodable {
    let value: Int
}

struct BrightnessData: Encodable {
    let value: Int
}

struct ColorData: Encodable {
    let color: RGB
    let colorTemInKelvin: Int
    
    struct RGB: Encodable {
        let r: Int
        let g: Int
        let b: Int
    }
}

struct EmptyData: Encodable {}
