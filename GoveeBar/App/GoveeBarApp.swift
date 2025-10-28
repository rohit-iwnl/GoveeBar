//
//  GoveeBarApp.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 10/27/25.
//

import SwiftUI

@main
struct GoveeBarApp: App {
    var body: some Scene {
        MenuBarExtra("GoveeBar", systemImage: "lightbulb.led") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
