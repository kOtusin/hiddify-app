//
//  StatusEventHandler.swift
//  Runner
//
//  Created by GFWFighter on 10/24/23.
//

import Foundation
import Flutter

public class StatusEventHandler: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let name = "\(Bundle.main.serviceIdentifier)/service.status"

    private var channel: FlutterEventChannel?
    private var observer: UUID?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = StatusEventHandler()
        instance.channel = FlutterEventChannel(name: Self.name, binaryMessenger: registrar.messenger(), codec: FlutterJSONMethodCodec())
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        observer = VPNManager.shared.observeState { status in
            let value: String
            switch status {
            case .reasserting, .connecting:
                value = "Starting"
            case .connected:
                value = "Started"
            case .disconnecting:
                value = "Stopping"
            case .disconnected, .invalid:
                value = "Stopped"
            @unknown default:
                value = "Stopped"
            }
            if Thread.isMainThread {
                events(["status": value])
            } else {
                DispatchQueue.main.async {
                    events(["status": value])
                }
            }
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if let observer {
            VPNManager.shared.removeStateObserver(observer)
            self.observer = nil
        }
        return nil
    }
}
