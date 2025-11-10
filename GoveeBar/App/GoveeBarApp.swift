//
//  GoveeBarApp.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 11/9/25.
//

import SwiftUI

@main
struct GoveeBarApp: App {
    var body: some Scene {
        MenuBarExtra("GoveeBar", systemImage: "lightbulb.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
