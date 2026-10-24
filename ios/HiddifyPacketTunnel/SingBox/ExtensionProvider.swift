//
//  ExtensionProvider.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation
import Libcore
import NetworkExtension

open class ExtensionProvider: NEPacketTunnelProvider {
    public static let errorFile = FilePath.workingDirectory.appendingPathComponent("network_extension_error")

    private var commandServer: LibboxCommandServer!
    private var boxService: LibboxBoxService!
    private var systemProxyAvailable = false
    private var systemProxyEnabled = false
    private var platformInterface: ExtensionPlatformInterface!
    private var config: String!

    override open func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        try? FileManager.default.removeItem(at: ExtensionProvider.errorFile)
        try? FileManager.default.removeItem(at: FilePath.workingDirectory.appendingPathComponent("TestLog"))

        let disableMemoryLimit = (options?["DisableMemoryLimit"] as? NSString as? String ?? "NO") == "YES"

        guard let config = options?["Config"] as? NSString as? String else {
            completionHandler(makeFatalError("(packet-tunnel) error: config not provided"))
            return
        }
        guard let config = SingBox.setupConfig(config: config) else {
            completionHandler(makeFatalError("(packet-tunnel) error: config is invalid"))
            return
        }
        self.config = config

        do {
            try FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        } catch {
            completionHandler(makeFatalError("(packet-tunnel) error: create working directory: \(error.localizedDescription)"))
            return
        }

        // iOS 12 delivers the setTunnelNetworkSettings reply on the same serial
        // NetworkExtension queue that executes startTunnel. Blocking this queue
        // inside LibboxNewService().start() (which waits for openTun, which
        // waits for the reply) deadlocks the tunnel forever, so the blocking
        // service setup must run off the provider queue. It is legal to call
        // the start completion handler later, from any thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                let message = "(packet-tunnel) error: provider released"
                NSLog(message)
                completionHandler(NSError(domain: message, code: 0))
                return
            }
            self.startServiceAsync(config: config, disableMemoryLimit: disableMemoryLimit, completionHandler: completionHandler)
        }
    }

    private func startServiceAsync(config _: String, disableMemoryLimit: Bool, completionHandler: @escaping (Error?) -> Void) {
        LibboxSetup(
            FilePath.sharedDirectory.relativePath,
            FilePath.workingDirectory.relativePath,
            FilePath.cacheDirectory.relativePath,
            false
        )

        var error: NSError?
        LibboxRedirectStderr(FilePath.cacheDirectory.appendingPathComponent("stderr.log").relativePath, &error)
        if let error {
            writeError("(packet-tunnel) redirect stderr error: \(error.localizedDescription)")
        }

        LibboxSetMemoryLimit(!disableMemoryLimit)

        // The start completion handler is called exactly once below, on the
        // single exit paths of this function.
        if platformInterface == nil {
            platformInterface = ExtensionPlatformInterface(self)
        }
        commandServer = LibboxNewCommandServer(platformInterface, Int32(30))
        do {
            try commandServer.start()
        } catch {
            completionHandler(makeFatalError("(packet-tunnel) error: log server start: \(error.localizedDescription)"))
            return
        }
        writeMessage("(packet-tunnel) log server started")

        if let error = startService() {
            completionHandler(makeFatalError("(packet-tunnel) error: start service: \(error.localizedDescription)"))
            return
        }
        completionHandler(nil)
    }

    func writeMessage(_ message: String) {
        NSLog(message)
        if let commandServer {
            commandServer.writeMessage(message)
        }
    }

    func writeError(_ message: String) {
        writeMessage(message)
        try? message.write(to: ExtensionProvider.errorFile, atomically: true, encoding: .utf8)
    }

    private func makeFatalError(_ message: String) -> NSError {
        NSLog(message)
        writeError(message)
        return NSError(domain: message, code: 0)
    }

    public func writeFatalError(_ message: String) {
        let error = makeFatalError(message)
        cancelTunnelWithError(error)
    }

    private func startService() -> Error? {
        var error: NSError?
        guard let service = LibboxNewService(config, platformInterface, &error) else {
            if let error {
                writeError("(packet-tunnel) error: create service: \(error.localizedDescription)")
                return error
            }
            return NSError(domain: "(packet-tunnel) error: create service: empty result", code: 0)
        }
        do {
            try service.start()
        } catch {
            writeError("(packet-tunnel) error: start service: \(error.localizedDescription)")
            return error
        }
        boxService = service
        commandServer.setService(service)
        return nil
    }

    private func stopService() {
        if let service = boxService {
            do {
                try service.close()
            } catch {
                writeError("(packet-tunnel) error: stop service: \(error.localizedDescription)")
            }
            boxService = nil
            commandServer.setService(nil)
        }
        if let platformInterface {
            platformInterface.reset()
        }
    }

    func reloadService() {
        writeMessage("(packet-tunnel) reloading service")
        reasserting = true
        stopService()
        if let error = startService() {
            writeError("(packet-tunnel) error: reload service: \(error.localizedDescription)")
        }
        reasserting = false
    }

    override open func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        writeMessage("(packet-tunnel) stopping, reason: \(reason)")
        stopService()
        if let server = commandServer {
            commandServer = nil
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
                try? server.close()
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

    override open func handleAppMessage(_ messageData: Data, completionHandler: (@Sendable (Data?) -> Void)?) {
        completionHandler?(messageData)
    }

    override open func sleep(completionHandler: @escaping () -> Void) {
        if let boxService {
            boxService.pause()
        }
        completionHandler()
    }

    override open func wake() {
        if let boxService {
            boxService.wake()
        }
    }
}
