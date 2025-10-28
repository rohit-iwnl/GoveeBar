//
//  APIKeySetupView.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 10/28/25.
//

import SwiftUI

struct APIKeySetupView: View {
    @State private var apiKey: String = ""
    @State private var isLoading: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showSuccess: Bool = false
    
    let onAPIKeySaved: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Setup Govee API Key")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter your Govee API key to control your lights")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                
                SecureField("Enter your Govee API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                
                Text("You can find your API key in the Govee Home app under Settings > About Us > Apply for API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if showError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .transition(.move(edge: .top).combined(with: .blurReplace))

            }
            
            if showSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("API key saved successfully!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .animation(.smooth, value: showSuccess)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .transition(.move(edge: .top).combined(with: .blurReplace))
            }
            
            Button(action: saveAPIKey) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text(isLoading ? "Saving..." : "Save API Key")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            
            VStack(spacing: 4) {
                Text("Need help getting your API key?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Open Govee Developer Guide") {
                    if let url = URL(string: "https://developer.govee.com/reference/apply-you-govee-api-key") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
    
    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic validation
        guard !trimmedKey.isEmpty else {
            showErrorMessage("Please enter an API key")
            return
        }
        
        // Govee API keys are typically 32 characters long
        guard trimmedKey.count >= 20 else {
            showErrorMessage("API key appears to be too short")
            return
        }
        
        isLoading = true
        showError = false
        showSuccess = false
        
        // Simulate a brief delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let success = KeychainHelper.save(trimmedKey, for: "govee-api-key")
            
            isLoading = false
            
            if success {
                withAnimation(.easeIn(duration: 0.25)){
                    showSuccess = true
                }
                // Clear the text field for security
                apiKey = ""
                
                // Call the completion handler after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.25)){
                        showSuccess = false
                    }
                    onAPIKeySaved()
                }
            } else {
                showErrorMessage("Failed to save API key to keychain")
            }
        }
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        withAnimation(.easeIn(duration: 0.25)){
            showError = true
            showSuccess = false

        }
        
        // Auto-hide error after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.25)) {
                showError = false
            }
        }
    }
}

#Preview {
    APIKeySetupView {
        print("API Key saved!")
    }
}
