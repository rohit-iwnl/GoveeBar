//
//  ContentView.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 11/9/25.
//

import SwiftUI


struct ContentView: View {
    var body: some View {
        VStack() {
            HStack {
                Text("GoveeBar")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                
                Spacer()
            
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                }
                .tint(.red)
            }
            
            Divider()
            
            
            
        

            Spacer()
            
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

#Preview {
    ContentView()
}
