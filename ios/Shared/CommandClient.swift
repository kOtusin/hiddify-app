import Foundation
import Libcore

public class CommandClient {
    public enum ConnectionType {
        case status
        case groups
        case log
        case groupsInfoOnly
    }

    private let connectionType: ConnectionType
    private let logMaxLines: Int
    private var commandClient: LibboxCommandClient?
    private var handler: clientHandler?
    private var generation: Int = 0
    private let lock = NSLock()

    private(set) var isConnected: Bool = false
    private(set) var status: LibboxStatusMessage?
    private(set) var groups: [SBGroup]?
    private(set) var logList: [String] = []

    public var onConnected: (() -> Void)?
    public var onDisconnected: ((String?) -> Void)?
    public var onStatus: ((LibboxStatusMessage?) -> Void)?
    public var onGroups: (([SBGroup]?) -> Void)?
    public var onLogs: (([String]) -> Void)?

    public init(_ connectionType: ConnectionType, logMaxLines: Int = 300) {
        self.connectionType = connectionType
        self.logMaxLines = logMaxLines
    }

    public func connect() {
        if isConnected {
            return
        }

        lock.lock()
        generation += 1
        let currentGeneration = generation
        lock.unlock()

        let clientOptions = LibboxCommandClientOptions()
        switch connectionType {
        case .status:
            clientOptions.command = LibboxCommandStatus
        case .groups:
            clientOptions.command = LibboxCommandGroup
        case .log:
            clientOptions.command = LibboxCommandLog
        case .groupsInfoOnly:
            clientOptions.command = LibboxCommandGroupInfoOnly
        }
        clientOptions.statusInterval = Int64(2 * NSEC_PER_SEC)

        let clientHandler = clientHandler(self)
        guard let client = LibboxNewCommandClient(clientHandler, clientOptions) else {
            return
        }
        self.handler = clientHandler

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for i in 0 ..< 10 {
                guard let self else {
                    try? client.disconnect()
                    return
                }
                self.lock.lock()
                let cancelled = self.generation != currentGeneration
                self.lock.unlock()
                if cancelled {
                    try? client.disconnect()
                    return
                }

                Thread.sleep(forTimeInterval: 0.1 + (Double(i) * 0.05))

                self.lock.lock()
                let cancelledAfterSleep = self.generation != currentGeneration
                self.lock.unlock()
                if cancelledAfterSleep {
                    try? client.disconnect()
                    return
                }

                do {
                    try client.connect()
                    self.lock.lock()
                    let stillCurrent = self.generation == currentGeneration
                    self.lock.unlock()
                    if !stillCurrent {
                        try? client.disconnect()
                        return
                    }
                    DispatchQueue.main.async {
                        self.commandClient = client
                    }
                    return
                } catch {
                    // retry
                }
            }
            try? client.disconnect()
        }
    }

    public func disconnect() {
        lock.lock()
        generation += 1
        let client = commandClient
        commandClient = nil
        lock.unlock()

        if let client {
            try? client.disconnect()
        }
        isConnected = false
        handler = nil
    }

    private class clientHandler: NSObject, LibboxCommandClientHandlerProtocol {
        private weak var commandClient: CommandClient?

        init(_ commandClient: CommandClient) {
            self.commandClient = commandClient
        }

        func connected() {
            DispatchQueue.main.async { [weak self] in
                guard let commandClient = self?.commandClient else { return }
                if commandClient.connectionType == .log {
                    commandClient.logList = []
                    commandClient.onLogs?(commandClient.logList)
                }
                commandClient.isConnected = true
                commandClient.onConnected?()
            }
        }

        func disconnected(_ message: String?) {
            DispatchQueue.main.async { [weak self] in
                guard let commandClient = self?.commandClient else { return }
                commandClient.isConnected = false
                commandClient.onDisconnected?(message)
            }
        }

        func clearLog() {
            DispatchQueue.main.async { [weak self] in
                guard let commandClient = self?.commandClient else { return }
                commandClient.logList.removeAll()
                commandClient.onLogs?(commandClient.logList)
            }
        }

        func writeLog(_ message: String?) {
            guard let message else { return }
            DispatchQueue.main.async { [weak self] in
                guard let commandClient = self?.commandClient else { return }
                if commandClient.logList.count >= commandClient.logMaxLines {
                    commandClient.logList.removeFirst()
                }
                commandClient.logList.append(message)
                commandClient.onLogs?(commandClient.logList)
            }
        }

        func writeStatus(_ message: LibboxStatusMessage?) {
            DispatchQueue.main.async { [weak self] in
                guard let commandClient = self?.commandClient else { return }
                commandClient.status = message
                commandClient.onStatus?(message)
            }
        }

        func writeGroups(_ groups: LibboxOutboundGroupIteratorProtocol?) {
            guard let groups else { return }
            var sbGroups = [SBGroup]()
            while groups.hasNext() {
                guard let group = groups.next() else { continue }
                var items = [SBItem]()
                if let groupItems = group.getItems() {
                    while groupItems.hasNext() {
                        guard let item = groupItems.next() else { continue }
                        items.append(SBItem(tag: item.tag,
                                            type: item.type,
                                            urlTestDelay: Int(item.urlTestDelay)))
                    }
                }
                sbGroups.append(.init(tag: group.tag,
                                      type: group.type,
                                      selected: group.selected,
                                      items: items))
            }
            DispatchQueue.main.async { [weak self] in
                guard let commandClient = self?.commandClient else { return }
                commandClient.groups = sbGroups
                commandClient.onGroups?(sbGroups)
            }
        }

        func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {
        }

        func updateClashMode(_ newMode: String?) {
        }
    }
}
