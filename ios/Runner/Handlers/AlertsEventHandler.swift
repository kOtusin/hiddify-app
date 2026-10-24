//
//  AlertEventHandler.swift
//  Runner
//
//  Created by GFWFighter on 10/24/23.
//

import Foundation
import Flutter

public class AlertsEventHandler: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let name = "\(Bundle.main.serviceIdentifier)/service.alerts"

    private var channel: FlutterEventChannel?
    private var observer: UUID?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AlertsEventHandler()
        instance.channel = FlutterEventChannel(name: Self.name, binaryMessenger: registrar.messenger(), codec: FlutterJSONMethodCodec())
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        observer = VPNManager.shared.observeAlert { alert in
            var data: [String: Any] = [
                "status": "Stopped",
            ]
            if let value = alert.alert?.rawValue {
                data["alert"] = value
            }
            if let value = alert.message {
                data["message"] = value
            }
            if Thread.isMainThread {
                events(data)
            } else {
                DispatchQueue.main.async {
                    events(data)
                }
            }
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if let observer {
            VPNManager.shared.removeAlertObserver(observer)
            self.observer = nil
        }
        return nil
    }
}
