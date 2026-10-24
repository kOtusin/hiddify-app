import Foundation
import Flutter
import Libcore

public class GroupsEventHandler: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let name = "\(Bundle.main.serviceIdentifier)/groups"

    private var commandClient: CommandClient?
    private var channel: FlutterEventChannel?
    private var events: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = GroupsEventHandler()
        instance.channel = FlutterEventChannel(name: Self.name,
                                               binaryMessenger: registrar.messenger())
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
        self.events = events
        let client = CommandClient(.groups)
        client.onGroups = { [weak self] groups in
            self?.writeGroups(groups)
        }
        commandClient = client
        client.connect()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        commandClient?.onGroups = nil
        commandClient?.disconnect()
        commandClient = nil
        events = nil
        return nil
    }

    func writeGroups(_ sbGroups: [SBGroup]?) {
        guard let sbGroups else { return }
        guard
            let groups = try? JSONEncoder().encode(sbGroups),
            let groups = String(data: groups, encoding: .utf8)
        else { return }
        events?(groups)
    }
}
