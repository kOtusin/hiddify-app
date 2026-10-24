//
//  PacketTunnelProvider.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 7/24/1402 AP.
//

import NetworkExtension

class PacketTunnelProvider: ExtensionProvider {
    private var upload: Int64 = 0
    private var download: Int64 = 0

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        super.startTunnel(options: options, completionHandler: completionHandler)
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: (@Sendable (Data?) -> Void)?) {
        let message = String(data: messageData, encoding: .utf8)
        switch message {
        case "stats":
            completionHandler?("\(upload),\(download)".data(using: .utf8))
        default:
            completionHandler?(nil)
        }
    }
}
