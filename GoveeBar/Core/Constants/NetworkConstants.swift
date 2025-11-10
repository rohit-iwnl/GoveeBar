//
//  NetworkConstants.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 11/9/25.
//

import Foundation


/// Refer to govee lan api docs
/// https://app-h5.govee.com/user-manual/wlan-guide

struct NetworkConstants {
    let multicastAddress = "239.255.255.250"
    let multicastPort = 4001
    let listenPort = 4002   
}
