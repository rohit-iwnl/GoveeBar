//
//  NetworkController.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 11/9/25.
//

import Foundation
import Network

class NetworkController {
    /// Utility class to control the network requests
    
    private var sender : NWConnection?
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    
    
    init(_host: String, _port: UInt16){
        self.host = NWEndpoint.Host(_host)
        self.port = NWEndpoint.Port(rawValue : _port) ?? 0
    }
    
    
    private func sendRequest<T : Encodable>(_ payload: T){
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        guard let data = try? encoder.encode(payload) else {
            NSLog("Serialization error")
            return
        }
        
        let connection = NWConnection(host: host, port: port, using: .udp)
        
        self.sender = connection
        
        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                connection
                    .send(
                        content: data,
                        completion: .contentProcessed(
                            { error in
                                if let err = error {
                                    NSLog(
                                        "Unexpected error occured while sending: \(err) "
                                    )
                                } else {
                                    NSLog("Successfully sent data")
                                }
                            })
                    )
                
                
            default: break
                
                
            }
        }
        
        
        connection.start(queue: .global())
    }
    
    
    
    func sendScanCommand() {
        let payload = RequestModels(
            msg: .init(
                cmd: "scan",
                data: ScanData(account_topic: "reserve")
            )
        )
        sendRequest( payload)
    }

    func sendTurnCommand(on: Bool) {
        let payload = RequestModels(
            msg: .init(
                cmd: "turn",
                data: TurnData(value: on ? 1 : 0)
            )
        )
        sendRequest(payload)
    }
    
    func sendBrightness(brightness: Float) {
        let payload = RequestModels(
            msg: .init(
                cmd: "brightness",
                data: BrightnessData(value: Int(brightness))
            )
        )
        sendRequest(payload)
    }

    func sendDevStatus() {
        let payload = RequestModels(
            msg: .init(
                cmd: "devStatus",
                data: EmptyData()
            )
        )
        sendRequest(payload)
    }

    func sendColor(r: Int, g: Int, b: Int) {
        let payload = RequestModels(
            msg: .init(
                cmd: "colorwc",
                data: ColorData(
                    color: .init(r: r, g: g, b: b),
                    colorTemInKelvin: 0
                )
            )
        )
        sendRequest(payload)
    }
}
