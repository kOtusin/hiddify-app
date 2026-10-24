//
//  SingBox.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation

class SingBox {
    // iOS 12 rejects utun MTUs above 1500 ("Cannot set MTU, Invalid argument"
    // from nehelper), while the core defaults to 9000. Force a safe value so
    // the core and the NetworkExtension agree on the packet size.
    static let maxMTU: Int = 1500

    // iOS 12 jetsam kills the extension on a small per-process memory limit
    // ("per-process-limit" after ~100 s of browsing). The gVisor stack keeps
    // large buffers per connection and blows through that limit. The system
    // stack forwards packets with a much smaller footprint, so force it.
    static let tunStack: String = "system"

    static func setupConfig(config: String, mtu: Int = maxMTU) -> String? {
        guard
            let config = config.data(using: .utf8),
            var json = try? JSONSerialization
                .jsonObject(
                    with: config,
                    options: [.mutableLeaves, .mutableContainers]
                ) as? [String:Any]
        else {
            return nil
        }
        if let bounds = json["inbounds"] as? [[String: Any]] {
            var fixed: [[String: Any]] = []
            for var inbound in bounds {
                if inbound["type"] as? String == "tun" {
                    let configured = (inbound["mtu"] as? NSNumber)?.intValue ?? 0
                    if configured == 0 || configured > maxMTU {
                        inbound["mtu"] = mtu
                    }
                    // Lighter TUN stack to stay under the iOS 12 extension
                    // memory limit (see tunStack comment above).
                    inbound["stack"] = tunStack
                }
                fixed.append(inbound)
            }
            json["inbounds"] = fixed
        }
        /*json["log"] = [
            "disabled": false,
            "level": "info",
            "output": "log",
            "timestamp": true
        ] as [String:Any]
        json["experimental"] = [
            "clash_api": [
                "external_controller": "127.0.0.1:10864"
            ]
        ]
        json["inbounds"] = [
            [
                "type": "tun",
                "inet4_address": "172.19.0.1/30",
                "auto_route": true,
                "mtu": mtu,
                "sniff": true
            ] as [String:Any]
        ]
        var routing = (json["route"] as? [String:Any]) ?? [
            "rules": [Any](),
            "auto_detect_interface": true,
            "final": (json["inbounds"] as? [[String:Any]])?.first?["tag"] ?? "proxy"
        ]
        routing["geoip"] = [
            "path": FilePath.assetsDirectory.appendingPathComponent("geoip.db"),
        ]
        routing["geosite"] = [
            "path": FilePath.assetsDirectory.appendingPathComponent("geosite.db"),
        ]
        json["route"] = routing*/
        guard let data = try? JSONSerialization.data(withJSONObject: json) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
