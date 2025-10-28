//
//  ContentView.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 10/27/25.
//

//
//  ContentView.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 10/27/25.
//

import SwiftUI

struct ContentView: View {
    @State private var hasAPIKey: Bool = KeychainHelper.get("govee-api-key") != nil

    var body: some View {
        VStack(spacing: 20) {

            if hasAPIKey {
                // Placeholder until device controls are added
                VStack(spacing: 12) {
                    Text("GoveeBar")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Devices & controls will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider().padding(.vertical, 4)

                    Button("Quit App") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 8)
                }
                .padding(12)
                .frame(width: 250)

            } else {
                APIKeySetupView {
                    withAnimation(.smooth) {
                        hasAPIKey = true
                    }
                }
            }
        }
        .padding(16)
    }
}

#Preview {
    ContentView()
}
