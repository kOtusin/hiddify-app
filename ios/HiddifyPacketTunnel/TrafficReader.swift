//
//  TrafficReader.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation

struct TrafficReaderUpdate: Codable {
    let up: Int64
    let down: Int64
}

// The original traffic reader used URLSessionWebSocketTask (iOS 13+) and
// Swift concurrency. It was already disabled in PacketTunnelProvider; this
// stub keeps the file compiling for iOS 12.
class TrafficReader {
    init(onUpdate: @escaping (TrafficReaderUpdate) -> ()) {
        _ = onUpdate
    }
}
