//
//  ResponseModels.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 11/9/25.
//

import Foundation

// MARK: - Base Response Structure
struct ResponseModels<Data: Decodable>: Decodable {
    let msg: Message<Data>
    
    struct Message<Data: Decodable>: Decodable {
        let cmd: String
        let data: Data
    }
}

// MARK: - Scan Response
struct ScanResponseData: Decodable {
    let ip: String
    let device: String?
    let deviceName: String?
    let sku: String
    let bleVersionHard: String
    let bleVersionSoft: String
    let wifiVersionHard: String
    let wifiVersionSoft: String
    
    // Computed property to get the best available device name
    var displayName: String {
        device ?? deviceName ?? "Govee Device"
    }
}

// MARK: - Device Status Response
struct DeviceStatusData: Decodable {
    let onOff: Int
    let brightness: Int
    let color: ColorRGB
    let colorTemInKelvin: Int
    
    struct ColorRGB: Decodable {
        let r: Int
        let g: Int
        let b: Int
    }
    
    // Computed properties
    var isOn: Bool {
        onOff == 1
    }
}


