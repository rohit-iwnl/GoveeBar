//
//  DeviceManager.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 11/10/25.
//

import Foundation
import SwiftUI
import Network

// MARK: - Device Model
struct GoveeDevice: Identifiable {
    let id = UUID()
    var ip: String
    var device: String  // This is typically the MAC address
    var sku: String
    var bleVersionHard: String
    var bleVersionSoft: String
    var wifiVersionHard: String
    var wifiVersionSoft: String
    
    // Custom name (persisted in UserDefaults)
    var customName: String?
    
    // Device state
    var isOn: Bool = false
    var brightness: Int = 0
    var color: DeviceColor = DeviceColor(r: 0, g: 0, b: 0)
    var colorTemInKelvin: Int = 0
    var lastSeen: Date = Date()
    
    // Screen sync state
    var isScreenSyncEnabled: Bool = false
    
    // Computed property for display name
    var displayName: String {
        if let customName = customName, !customName.isEmpty {
            return customName
        }
        // Fallback to generic name since device field is often MAC address
        return "Govee Light"
    }
    
    // MAC address identifier (using device field)
    var macAddress: String {
        return device
    }
}

struct DeviceColor {
    var r: Int
    var g: Int
    var b: Int
}

// MARK: - Device Storage (Names & Colors)
class DeviceStorage {
    private let userDefaults = UserDefaults.standard
    private let namesKey = "govee_device_custom_names"
    private let colorsKey = "govee_device_saved_colors"
    
    // MARK: - Name Storage
    func saveCustomName(_ name: String, forMacAddress mac: String) {
        var names = loadAllNames()
        names[mac] = name
        userDefaults.set(names, forKey: namesKey)
        
    }
    
    func loadCustomName(forMacAddress mac: String) -> String? {
        let names = loadAllNames()
        return names[mac]
    }
    
    private func loadAllNames() -> [String: String] {
        return userDefaults.dictionary(forKey: namesKey) as? [String: String] ?? [:]
    }
    
    func removeCustomName(forMacAddress mac: String) {
        var names = loadAllNames()
        names.removeValue(forKey: mac)
        userDefaults.set(names, forKey: namesKey)
    }
    
    // MARK: - Color Storage
    func saveFavoriteColor(r: Int, g: Int, b: Int, forMacAddress mac: String) {
        var allColors = loadAllSavedColors()
        var deviceColors = allColors[mac] ?? []
        
        // Check if color already exists
        let colorDict = ["r": r, "g": g, "b": b]
        if !deviceColors.contains(where: { 
            $0["r"] == r && $0["g"] == g && $0["b"] == b 
        }) {
            deviceColors.append(colorDict)
            allColors[mac] = deviceColors
            userDefaults.set(allColors, forKey: colorsKey)
            
        }
    }
    
    func loadSavedColors(forMacAddress mac: String) -> [[String: Int]] {
        let allColors = loadAllSavedColors()
        return allColors[mac] ?? []
    }
    
    private func loadAllSavedColors() -> [String: [[String: Int]]] {
        return userDefaults.dictionary(forKey: colorsKey) as? [String: [[String: Int]]] ?? [:]
    }
    
    func removeSavedColor(r: Int, g: Int, b: Int, forMacAddress mac: String) {
        var allColors = loadAllSavedColors()
        guard var deviceColors = allColors[mac] else { return }
        
        deviceColors.removeAll { color in
            color["r"] == r && color["g"] == g && color["b"] == b
        }
        
        if deviceColors.isEmpty {
            allColors.removeValue(forKey: mac)
        } else {
            allColors[mac] = deviceColors
        }
        
        userDefaults.set(allColors, forKey: colorsKey)
    }
}

// MARK: - Device Manager
@Observable
class DeviceManager {
    var devices: [GoveeDevice] = []
    var isScanning: Bool = false
    var statusMessage: String = "Ready"
    
    private var listener: NWListener?
    private let multicastAddress = "239.255.255.250"
    private let multicastPort: UInt16 = 4001
    private let listenPort: UInt16 = 4002
    
    private var controller: NetworkController?
    private let storage = DeviceStorage()
    
    // Screen sync
    private var screenCaptureSyncs: [UUID: ScreenCaptureSync] = [:]
    
    init() {
        setupListener()
    }
    
    // MARK: - Custom Name Management
    func setCustomName(_ name: String, for device: GoveeDevice) {
        storage.saveCustomName(name, forMacAddress: device.macAddress)
        
        // Update the device in the array
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].customName = name
            
        }
    }
    
    // MARK: - Favorite Color Management
    func saveFavoriteColor(r: Int, g: Int, b: Int, for device: GoveeDevice) {
        storage.saveFavoriteColor(r: r, g: g, b: b, forMacAddress: device.macAddress)
    }
    
    func loadSavedColors(for device: GoveeDevice) -> [[String: Int]] {
        return storage.loadSavedColors(forMacAddress: device.macAddress)
    }
    
    func removeFavoriteColor(r: Int, g: Int, b: Int, for device: GoveeDevice) {
        storage.removeSavedColor(r: r, g: g, b: b, forMacAddress: device.macAddress)
    }
    
    // MARK: - UDP Listener Setup
    private func setupListener() {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: listenPort)!)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("Listener ready on port \(self?.listenPort ?? 0)")
                case .failed(let error):
                    print("Listener failed: \(error)")
                    self?.statusMessage = "Listener failed: \(error.localizedDescription)"
                default:
                    break
                }
            }
            
            listener?.start(queue: .global())
        } catch {
            print("Failed to create listener: \(error)")
            statusMessage = "Failed to create listener"
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        receiveMessage(on: connection)
    }
    
    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Received: \(jsonString)")
                    self?.parseResponse(jsonString)
                }
            }
            
            if error == nil {
                self?.receiveMessage(on: connection)
            }
        }
    }
    
    // MARK: - Device Discovery
    func addTestDevice() {
        let testDevice = GoveeDevice(
            ip: "192.168.1.\(Int.random(in: 100...200))",
            device: "Test Govee Device",
            sku: "H6199",
            bleVersionHard: "1.0",
            bleVersionSoft: "2.0",
            wifiVersionHard: "1.0",
            wifiVersionSoft: "3.0",
            isOn: true,
            brightness: 50
        )
        devices.append(testDevice)
        statusMessage = "Added test device"
        print("Added test device: \(testDevice.device)")
    }
    
    func scanForDevices() {
        isScanning = true
        statusMessage = "Scanning for devices..."
        
        // Clear old devices (optional - you might want to keep them)
        // devices.removeAll()
        
        // Initialize controller with multicast address
        controller = NetworkController(_host: multicastAddress, _port: multicastPort)
        
        // Send scan command
        controller?.sendScanCommand()
        
        // Stop scanning after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.isScanning = false
            if let count = self?.devices.count {
                self?.statusMessage = count > 0 ? "Found \(count) device(s)" : "No devices found"
            }
        }
    }
    
    func refreshAllDevices() {
        statusMessage = "Refreshing device status..."
        for device in devices {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.refreshDeviceStatus(device)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.statusMessage = "Status refreshed"
        }
    }
    
    // MARK: - Parse Responses
    private func parseResponse(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        
        // First, decode just to get the command type
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["msg"] as? [String: Any],
               let cmd = msg["cmd"] as? String {
                
                switch cmd {
                case "scan":
                    parseScanResponse(data: data)
                case "devStatus":
                    parseDeviceStatus(data: data)
                default:
                    print(" Received command: \(cmd)")
                }
            }
        } catch {
            print(" JSON parse error: \(error)")
        }
    }
    
    private func parseScanResponse(data: Data) {
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(ResponseModels<ScanResponseData>.self, from: data)
            let scanData = response.msg.data
            
            // Use the displayName from scan response as the MAC address
            let macAddress = scanData.displayName
            
            
            // Load saved custom name if exists
            let savedName = storage.loadCustomName(forMacAddress: macAddress)
            
            var newDevice = GoveeDevice(
                ip: scanData.ip,
                device: macAddress,  // Store MAC address in device field
                sku: scanData.sku,
                bleVersionHard: scanData.bleVersionHard,
                bleVersionSoft: scanData.bleVersionSoft,
                wifiVersionHard: scanData.wifiVersionHard,
                wifiVersionSoft: scanData.wifiVersionSoft
            )
            
            // Apply saved custom name if it exists
            newDevice.customName = savedName
        
            DispatchQueue.main.async { [weak self] in
                // Check if device already exists (by MAC address, not IP)
                if let index = self?.devices.firstIndex(where: { $0.macAddress == macAddress }) {
                    // Update existing device info but keep custom name
                    let existingCustomName = self?.devices[index].customName
                    self?.devices[index].ip = scanData.ip
                    self?.devices[index].sku = scanData.sku
                    self?.devices[index].lastSeen = Date()
                    self?.devices[index].customName = existingCustomName ?? savedName
                    
                } else {
                    self?.devices.append(newDevice)
                    
                    
                    // Automatically request device status after discovery
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.refreshDeviceStatus(newDevice)
                    }
                }
            }
        } catch {
            print(" Failed to decode scan response: \(error)")
           
        }
    }
    
    private func parseDeviceStatus(data: Data) {
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(ResponseModels<DeviceStatusData>.self, from: data)
            let statusData = response.msg.data
        
            // Update device state in UI
            updateDeviceStatus(
                isOn: statusData.isOn,
                brightness: statusData.brightness,
                color: DeviceColor(
                    r: statusData.color.r,
                    g: statusData.color.g,
                    b: statusData.color.b
                ),
                colorTemp: statusData.colorTemInKelvin
            )
        } catch {
            print(" Failed to decode device status: \(error)")
        }
    }
    
    private var lastQueriedDeviceIP: String?
    
    private func updateDeviceStatus(isOn: Bool, brightness: Int, color: DeviceColor, colorTemp: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // If we have a recently queried device, update it
            if let ip = self.lastQueriedDeviceIP,
               let index = self.devices.firstIndex(where: { $0.ip == ip }) {
                self.devices[index].isOn = isOn
                self.devices[index].brightness = brightness
                self.devices[index].color = color
                self.devices[index].colorTemInKelvin = colorTemp
                
            } else if let lastDevice = self.devices.last {
                // Fallback: update the most recently added device
                if let index = self.devices.firstIndex(where: { $0.id == lastDevice.id }) {
                    self.devices[index].isOn = isOn
                    self.devices[index].brightness = brightness
                    self.devices[index].color = color
                    self.devices[index].colorTemInKelvin = colorTemp
                    
                }
            }
        }
    }
    
    // MARK: - Device Control
    func toggleDevice(_ device: GoveeDevice, on: Bool) {
        let controller = NetworkController(_host: device.ip, _port: 4003)
        controller.sendTurnCommand(on: on)
        
        // Immediately update UI for responsiveness
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            DispatchQueue.main.async {
                self.devices[index].isOn = on
            }
        }
        
        // Refresh actual status after a delay to confirm
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshDeviceStatus(device)
        }
    }
    
    func setBrightness(_ device: GoveeDevice, brightness: Float) {
        let controller = NetworkController(_host: device.ip, _port: 4003)
        controller.sendBrightness(brightness: brightness)
        
        // Immediately update UI for responsiveness
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            DispatchQueue.main.async {
                self.devices[index].brightness = Int(brightness)
            }
        }
    }
    
    func setColor(_ device: GoveeDevice, r: Int, g: Int, b: Int) {
        let controller = NetworkController(_host: device.ip, _port: 4003)
        controller.sendColor(r: r, g: g, b: b)
        
        // Immediately update UI for responsiveness
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            DispatchQueue.main.async {
                self.devices[index].color = DeviceColor(r: r, g: g, b: b)
            }
        }
        
        // Refresh actual status after a delay to confirm
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshDeviceStatus(device)
        }
    }
    
    func refreshDeviceStatus(_ device: GoveeDevice) {
        lastQueriedDeviceIP = device.ip
        let controller = NetworkController(_host: device.ip, _port: 4003)
        controller.sendDevStatus()
        
    }
    
    // MARK: - Screen Sync Management
    func toggleScreenSync(for device: GoveeDevice, enabled: Bool) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].isScreenSyncEnabled = enabled
            
            if enabled {
                startScreenSync(for: devices[index])
            } else {
                stopScreenSync(for: device)
            }
        }
    }
    
    private func startScreenSync(for device: GoveeDevice) {
        // Stop existing sync if any
        stopScreenSync(for: device)
        
        if #available(macOS 12.3, *) {
            let controller = NetworkController(_host: device.ip, _port: 4003)
            let screenSync = ScreenCaptureSync(goveeController: controller)
            screenCaptureSyncs[device.id] = screenSync
            
            // Start capturing with default settings
            screenSync.start(pollInterval: 0.1, downscaleWidth: 320, downscaleHeight: 180)
            
            
            statusMessage = "Screen sync started for \(device.displayName)"
        } else {
            
            statusMessage = "Screen sync requires macOS 12.3+"
        }
    }
    
    private func stopScreenSync(for device: GoveeDevice) {
        if let screenSync = screenCaptureSyncs[device.id] {
            if #available(macOS 12.3, *) {
                screenSync.stop()
            }
            screenCaptureSyncs.removeValue(forKey: device.id)
            
            statusMessage = "Screen sync stopped for \(device.displayName)"
        }
    }
    
    func stopAllScreenSyncs() {
        for device in devices where device.isScreenSyncEnabled {
            stopScreenSync(for: device)
        }
    }
    
    deinit {
        stopAllScreenSyncs()
    }
}

