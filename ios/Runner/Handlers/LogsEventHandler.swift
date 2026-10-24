import Foundation
import Flutter
import Libcore

class LogsEventHandler: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let name = "\(Bundle.main.serviceIdentifier)/service.logs"

    private var commandClient: CommandClient?
    private var events: FlutterEventSink?
    private var channel: FlutterEventChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = LogsEventHandler()
        instance.channel = FlutterEventChannel(name: Self.name,
                                               binaryMessenger: registrar.messenger())
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
        self.events = events
        let client = CommandClient(.log)
        client.onLogs = { [weak self] logs in
            self?.events?(logs)
        }
        commandClient = client
        client.connect()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        commandClient?.onLogs = nil
        commandClient?.disconnect()
        commandClient = nil
        events = nil
        return nil
    }
}
