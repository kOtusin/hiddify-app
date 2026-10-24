//
//  ExtensionPlatformInterface.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation
import Libcore
import NetworkExtension

public class ExtensionPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    public func readWIFIState() -> LibboxWIFIState? {
        return nil
    }

    private let tunnel: ExtensionProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?

    init(_ tunnel: ExtensionProvider) {
        self.tunnel = tunnel
    }

    public func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options else {
            throw NSError(domain: "nil options", code: 0)
        }
        guard let ret0_ else {
            throw NSError(domain: "nil return pointer", code: 0)
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "172.19.0.2")
        if options.getAutoRoute() {
            // iOS 12 rejects MTU values above 1500 with EINVAL from nehelper,
            // so clamp to the same maximum the core is forced to use.
            let mtu = min(Int(options.getMTU()), SingBox.maxMTU)
            settings.mtu = NSNumber(value: mtu)

            var error: NSError?
            let dnsServer = options.getDNSServerAddress(&error)
            if let error {
                throw error
            }
            settings.dnsSettings = NEDNSSettings(servers: [dnsServer])
            tunnel.writeMessage("(packet-tunnel) tun settings: mtu=\(mtu) dns=\(dnsServer)")

            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            let ipv4AddressIterator = options.getInet4Address()!
            while ipv4AddressIterator.hasNext() {
                let ipv4Prefix = ipv4AddressIterator.next()!
                ipv4Address.append(ipv4Prefix.address())
                ipv4Mask.append(ipv4Prefix.mask())
            }
            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            var ipv4Routes: [NEIPv4Route] = []
            let inet4RouteAddressIterator = options.getInet4RouteAddress()!
            if inet4RouteAddressIterator.hasNext() {
                while inet4RouteAddressIterator.hasNext() {
                    let ipv4RoutePrefix = inet4RouteAddressIterator.next()!
                    ipv4Routes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address(), subnetMask: ipv4RoutePrefix.mask()))
                }
            } else {
                ipv4Routes.append(NEIPv4Route.default())
            }
            for (index, address) in ipv4Address.enumerated() {
                ipv4Routes.append(NEIPv4Route(destinationAddress: address, subnetMask: ipv4Mask[index]))
            }
            ipv4Settings.includedRoutes = ipv4Routes
            settings.ipv4Settings = ipv4Settings

            var ipv6Address: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            let ipv6AddressIterator = options.getInet6Address()!
            while ipv6AddressIterator.hasNext() {
                let ipv6Prefix = ipv6AddressIterator.next()!
                ipv6Address.append(ipv6Prefix.address())
                ipv6Prefixes.append(NSNumber(value: ipv6Prefix.prefix()))
            }
            // iOS 12 rejects empty network settings blocks, so only assign
            // ipv6Settings when the core actually requested IPv6 addresses.
            if !ipv6Address.isEmpty {
                let ipv6Settings = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
                var ipv6Routes: [NEIPv6Route] = []
                let inet6RouteAddressIterator = options.getInet6RouteAddress()!
                if inet6RouteAddressIterator.hasNext() {
                    while inet6RouteAddressIterator.hasNext() {
                        let ipv6RoutePrefix = inet6RouteAddressIterator.next()!
                        ipv6Routes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.address(), networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix())))
                    }
                } else {
                    ipv6Routes.append(NEIPv6Route.default())
                }
                for (index, address) in ipv6Address.enumerated() {
                    ipv6Routes.append(NEIPv6Route(destinationAddress: address, networkPrefixLength: ipv6Prefixes[index]))
                }
                ipv6Settings.includedRoutes = ipv6Routes
                settings.ipv6Settings = ipv6Settings
            }
        }

        if options.isHTTPProxyEnabled() {
            let proxySettings = NEProxySettings()
            let proxyServer = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxySettings.httpServer = proxyServer
            proxySettings.httpsServer = proxyServer
            settings.proxySettings = proxySettings
        }

        networkSettings = settings
        try applyTunnelSettings(settings)

        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            return
        }

        let tunFdFromLoop = LibboxGetTunnelFileDescriptor()
        if tunFdFromLoop != -1 {
            ret0_.pointee = tunFdFromLoop
        } else {
            throw NSError(domain: "missing file descriptor", code: 0)
        }
    }

    private func applyTunnelSettings(_ settings: NEPacketTunnelNetworkSettings?) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Error?
        tunnel.setTunnelNetworkSettings(settings) { error in
            result = error
            semaphore.signal()
        }
        semaphore.wait()
        if let result {
            throw result
        }
    }

    public func usePlatformAutoDetectControl() -> Bool {
        true
    }

    public func autoDetectControl(_: Int32) throws {}

    public func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32, destinationAddress _: String?, destinationPort _: Int32, ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "not implemented", code: 0)
    }

    public func packageName(byUid _: Int32, error _: NSErrorPointer) -> String {
        ""
    }

    public func uid(byPackageName _: String?, ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "not implemented", code: 0)
    }

    public func useProcFS() -> Bool {
        false
    }

    public func writeLog(_ message: String?) {
        guard let message else {
            return
        }
        tunnel.writeMessage(message)
    }

    public func usePlatformDefaultInterfaceMonitor() -> Bool {
        false
    }

    public func startDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {}

    public func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {}

    public func useGetter() -> Bool {
        false
    }

    public func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        throw NSError(domain: "not implemented", code: 0)
    }

    public func underNetworkExtension() -> Bool {
        true
    }

    public func includeAllNetworks() -> Bool {
        false
    }

    public func clearDNSCache() {
        guard let networkSettings else {
            return
        }
        tunnel.reasserting = true
        tunnel.setTunnelNetworkSettings(nil) { _ in
        }
        tunnel.setTunnelNetworkSettings(networkSettings) { _ in
        }
        tunnel.reasserting = false
    }

    public func serviceReload() throws {
        tunnel.reloadService()
    }

    public func getSystemProxyStatus() -> LibboxSystemProxyStatus? {
        let status = LibboxSystemProxyStatus()
        guard let networkSettings else {
            return status
        }
        guard let proxySettings = networkSettings.proxySettings else {
            return status
        }
        if proxySettings.httpServer == nil {
            return status
        }
        status.available = true
        status.enabled = proxySettings.httpEnabled
        return status
    }

    public func setSystemProxyEnabled(_ isEnabled: Bool) throws {
        guard let networkSettings else {
            return
        }
        guard let proxySettings = networkSettings.proxySettings else {
            return
        }
        if proxySettings.httpServer == nil {
            return
        }
        if proxySettings.httpEnabled == isEnabled {
            return
        }
        proxySettings.httpEnabled = isEnabled
        proxySettings.httpsEnabled = isEnabled
        networkSettings.proxySettings = proxySettings
        try applyTunnelSettings(networkSettings)
    }

    public func postServiceClose() {
        // TODO
    }

    func reset() {
        networkSettings = nil
    }
}
