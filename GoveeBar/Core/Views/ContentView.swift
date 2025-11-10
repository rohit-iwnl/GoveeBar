//
//  ContentView.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 11/9/25.
//

import SwiftUI
import AppKit


struct ContentView: View {
    @State private var deviceManager = DeviceManager()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("GoveeBar")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    deviceManager.scanForDevices()
                } label: {
                    if deviceManager.isScanning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.callout)
                    }
                }
                .buttonStyle(.plain)
                .disabled(deviceManager.isScanning)
                
                // Refresh all devices status
                Button {
                    deviceManager.refreshAllDevices()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .disabled(deviceManager.devices.isEmpty)
            
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            
            Divider()
            
            // Device List
            if deviceManager.devices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "lightbulb.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No devices")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Tap refresh to scan")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        // Debug: Show device count
                        Text("\(deviceManager.devices.count) device(s)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ForEach(deviceManager.devices) { device in
                            DeviceRow(device: device, deviceManager: deviceManager)
                        }
                    }
                    .padding(8)
                }
            }
            
            // Status footer
            if !deviceManager.statusMessage.isEmpty {
                Divider()
                HStack {
                    Text(deviceManager.statusMessage)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.05))
            }
        }
        .frame(width: 300, height: 300)
        .onAppear {
            // Automatically scan for devices when the view appears
            deviceManager.scanForDevices()
        }
    }
}

struct DeviceRow: View {
    let device: GoveeDevice
    let deviceManager: DeviceManager
    
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var isExpanded = false
    @State private var customColor: Color = .white
    @State private var lastPickedColor: (r: Int, g: Int, b: Int)?
    @State private var savedColors: [[String: Int]] = []
    @State private var showSavedFeedback = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Device Controls (shown when expanded)
            VStack(spacing: 8) {
                // Screen Sync Toggle
                HStack {
                    Image(systemName: device.isScreenSyncEnabled ? "display.trianglebadge.exclamationmark" : "display")
                        .font(.system(size: 10))
                        .foregroundColor(device.isScreenSyncEnabled ? .green : .white)
                    
                    Text(device.isScreenSyncEnabled ? "Screen Sync Active" : "Screen Sync")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { device.isScreenSyncEnabled },
                        set: { newValue in
                            deviceManager.toggleScreenSync(for: device, enabled: newValue)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(device.isScreenSyncEnabled ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
                .cornerRadius(6)
                
                // Brightness Control
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "sun.max")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                        Text("Brightness: \(device.brightness)%")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(device.brightness) },
                            set: { newValue in
                                deviceManager.setBrightness(device, brightness: Float(newValue))
                            }
                        ),
                        in: 0...100
                    )
                    .disabled(device.isScreenSyncEnabled)
                }
                
                // Quick Color Buttons (disabled when screen sync is on)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ColorButton(color: .red, r: 255, g: 0, b: 0, device: device, deviceManager: deviceManager)
                            .disabled(device.isScreenSyncEnabled)
                        ColorButton(color: .green, r: 0, g: 255, b: 0, device: device, deviceManager: deviceManager)
                            .disabled(device.isScreenSyncEnabled)
                        ColorButton(color: .blue, r: 0, g: 0, b: 255, device: device, deviceManager: deviceManager)
                            .disabled(device.isScreenSyncEnabled)
                        ColorButton(color: .purple, r: 128, g: 0, b: 128, device: device, deviceManager: deviceManager)
                            .disabled(device.isScreenSyncEnabled)
                        ColorButton(color: .white, r: 255, g: 255, b: 255, device: device, deviceManager: deviceManager)
                            .disabled(device.isScreenSyncEnabled)
                    }
                    .opacity(device.isScreenSyncEnabled ? 0.3 : 1.0)
                    
                    // Saved/Favorite Colors
                    if !savedColors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Saved Colors")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("Double-tap to delete")
                                    .font(.system(size: 8))
                                    .foregroundColor(.accentColor)
                                    .italic()
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(savedColors.indices, id: \.self) { index in
                                        if let r = savedColors[index]["r"],
                                           let g = savedColors[index]["g"],
                                           let b = savedColors[index]["b"] {
                                            SavedColorButton(
                                                r: r, g: g, b: b,
                                                device: device,
                                                deviceManager: deviceManager,
                                                onDelete: {
                                                    removeSavedColor(r: r, g: g, b: b)
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Custom Color Picker with Save Button
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                            
                            Text("Pick & Save Color")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            // Save picked color button
                            Button {
                                savePickedColor()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                    if showSavedFeedback {
                                        Text("Saved!")
                                            .font(.system(size: 9))
                                            .foregroundColor(.green)
                                    }
                                }
                                .foregroundColor(lastPickedColor != nil && !device.isScreenSyncEnabled ? .green : .gray)
                            }
                            .buttonStyle(.plain)
                            .disabled(lastPickedColor == nil || device.isScreenSyncEnabled)
                            .help(device.isScreenSyncEnabled ? "Disabled during screen sync" : (lastPickedColor != nil ? "Save this color to favorites" : "Pick a color first"))
                            
                            ColorPicker("", selection: $customColor, supportsOpacity: false)
                                .labelsHidden()
                                .scaleEffect(0.8)
                                .disabled(device.isScreenSyncEnabled)
                                .onChange(of: customColor) { oldValue, newValue in
                                    applyAndTrackCustomColor(newValue)
                                }
                        }
                        .padding(8)
                        
                        // Hint text
                        if device.isScreenSyncEnabled {
                            Text("🖥️ Color picker disabled during screen sync")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 8)
                        } else if lastPickedColor != nil && !showSavedFeedback {
                            Text("👆 Tap + to save this color")
                                .font(.system(size: 8))
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 8)
                        }
                    }
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(6)
                    .opacity(device.isScreenSyncEnabled ? 0.5 : 1.0)
                }
            }
            .padding()
            .onAppear {
                loadSavedColors()
            }
        } label: {
            // Device Header
            HStack(spacing: 8) {
                // Color indicator
                Circle()
                    .fill(Color(
                        red: Double(device.color.r) / 255.0,
                        green: Double(device.color.g) / 255.0,
                        blue: Double(device.color.b) / 255.0
                    ))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .opacity(device.isOn ? 1.0 : 0.3)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if isEditingName {
                            // Editing mode - show text field
                            TextField("Device name", text: $editedName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .focused($isTextFieldFocused)
                                .onSubmit {
                                    saveNewName()
                                }
                        } else {
                            // Normal mode - show device name
                            Text(device.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        
                        if device.isOn {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                    
                    if device.isOn {
                        Text("\(device.brightness)%")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 8)
                
                // Rename button (pencil/checkmark icon)
                Button {
                    if isEditingName {
                        // Save the name
                        saveNewName()
                    } else {
                        // Start editing
                        editedName = device.displayName
                        isEditingName = true
                        isTextFieldFocused = true
                    }
                } label: {
                    Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(isEditingName ? .green : .secondary)
                }
                .buttonStyle(.plain)
                
                Toggle("", isOn: Binding(
                    get: { device.isOn },
                    set: { newValue in
                        deviceManager.toggleDevice(device, on: newValue)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(8)
            .contentShape(Rectangle())
            .onTapGesture {
                // Don't toggle when editing name or clicking buttons
                if !isEditingName {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(
                    red: Double(device.color.r) / 255.0,
                    green: Double(device.color.g) / 255.0,
                    blue: Double(device.color.b) / 255.0
                ).opacity(0.5), lineWidth: 0.5)
        )
    }
    
    private func saveNewName() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            deviceManager.setCustomName(trimmedName, for: device)
        }
        isEditingName = false
    }
    
    private func applyAndTrackCustomColor(_ color: Color) {
        // Convert SwiftUI Color to RGB values
        let nsColor = NSColor(color)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else { return }
        
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        
        // Apply to device
        deviceManager.setColor(device, r: r, g: g, b: b)
        
        // Track this color for potential saving
        lastPickedColor = (r, g, b)
        showSavedFeedback = false
    }
    
    private func loadSavedColors() {
        savedColors = deviceManager.loadSavedColors(for: device)
    }
    
    private func savePickedColor() {
        guard let picked = lastPickedColor else { return }
        
        deviceManager.saveFavoriteColor(
            r: picked.r,
            g: picked.g,
            b: picked.b,
            for: device
        )
        loadSavedColors()
        
        // Show feedback
        showSavedFeedback = true
        
        // Hide feedback after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSavedFeedback = false
            lastPickedColor = nil
        }
    }
    
    private func removeSavedColor(r: Int, g: Int, b: Int) {
        deviceManager.removeFavoriteColor(r: r, g: g, b: b, for: device)
        loadSavedColors()
    }
}

struct SavedColorButton: View {
    let r: Int
    let g: Int
    let b: Int
    let device: GoveeDevice
    let deviceManager: DeviceManager
    let onDelete: () -> Void
    
    @State private var tapCount = 0
    @State private var tapTimer: DispatchWorkItem?
    
    var body: some View {
        Circle()
            .fill(Color(
                red: Double(r) / 255.0,
                green: Double(g) / 255.0,
                blue: Double(b) / 255.0
            ))
            .frame(width: 24, height: 24)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .overlay(
                Circle()
                    .stroke(Color.red, lineWidth: tapCount == 1 ? 2 : 0)
                    .animation(.easeInOut(duration: 0.2), value: tapCount)
            )
            .onTapGesture {
                handleTap()
            }
            .help("Tap to apply • Double-tap to delete")
    }
    
    private func handleTap() {
        tapCount += 1
        
        // Cancel previous timer
        tapTimer?.cancel()
        
        if tapCount == 1 {
            // First tap - apply color after delay (if no second tap)
            let workItem = DispatchWorkItem { [self] in
                deviceManager.setColor(device, r: r, g: g, b: b)
                tapCount = 0
            }
            tapTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        } else if tapCount == 2 {
            // Second tap - delete
            tapTimer?.cancel()
            onDelete()
            tapCount = 0
        }
    }
}

struct ColorButton: View {
    let color: Color
    let r: Int
    let g: Int
    let b: Int
    let device: GoveeDevice
    let deviceManager: DeviceManager
    
    var body: some View {
        Button {
            deviceManager.setColor(device, r: r, g: g, b: b)
        } label: {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Main View") {
    ContentView()
}

#Preview("Device Row") {
    let sampleDevice = GoveeDevice(
        ip: "192.168.1.100",
        device: "Govee LED Strip",
        sku: "H6199",
        bleVersionHard: "1.0",
        bleVersionSoft: "2.1",
        wifiVersionHard: "1.0",
        wifiVersionSoft: "3.2",
        isOn: true,
        brightness: 75,
        color: DeviceColor(r: 255, g: 100, b: 50),
        colorTemInKelvin: 3000
    )
    
    let manager = DeviceManager()
    
    return VStack(spacing: 8) {
        DeviceRow(device: sampleDevice, deviceManager: manager)
        
        // Show a second one in off state
        DeviceRow(
            device: GoveeDevice(
                ip: "192.168.1.101",
                device: "Govee Light Bar",
                sku: "H6076",
                bleVersionHard: "1.0",
                bleVersionSoft: "2.0",
                wifiVersionHard: "1.0",
                wifiVersionSoft: "3.0",
                isOn: false,
                brightness: 50,
                color: DeviceColor(r: 0, g: 255, b: 0),
                colorTemInKelvin: 4000
            ),
            deviceManager: manager
        )
    }
    .padding()
    .frame(width: 300)
}
