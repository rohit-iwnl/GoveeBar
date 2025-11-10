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
    
    
    private func sendRequest<T : Encodable>(jsonPayload payload: T){
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
}
