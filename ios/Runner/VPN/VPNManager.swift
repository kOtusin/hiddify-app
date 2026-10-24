//
//  VPNManager.swift
//  Runner
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation
import NetworkExtension
import CFNetwork

enum VPNManagerAlertType: String {
    case RequestVPNPermission
    case RequestNotificationPermission
    case EmptyConfiguration
    case StartCommandServer
    case CreateService
    case StartService
}

struct VPNManagerAlert {
    let alert: VPNManagerAlertType?
    let message: String?
}

class VPNManager {
    private var observer: NSObjectProtocol?
    private var manager = NEVPNManager.shared()
    private var loaded: Bool = false
    private var timer: Timer?

    private let observerLock = NSLock()
    private var stateObservers: [UUID: (NEVPNStatus) -> Void] = [:]
    private var alertObservers: [UUID: (VPNManagerAlert) -> Void] = [:]

    static let shared: VPNManager = VPNManager()

    private(set) var state: NEVPNStatus = .invalid {
        didSet {
            if oldValue != state {
                notifyState()
            }
        }
    }

    private(set) var alert: VPNManagerAlert = .init(alert: nil, message: nil) {
        didSet {
            notifyAlert()
        }
    }

    private(set) var upload: Int64 = 0
    private(set) var download: Int64 = 0
    private(set) var elapsedTime: TimeInterval = 0

    private var _connectTime: Date?
    private var connectTime: Date? {
        set {
            UserDefaults(suiteName: FilePath.groupName)?.set(newValue?.timeIntervalSince1970, forKey: "SingBoxConnectTime")
            _connectTime = newValue
        }
        get {
            if let _connectTime {
                return _connectTime
            }
            guard let interval = UserDefaults(suiteName: FilePath.groupName)?.value(forKey: "SingBoxConnectTime") as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }
    }
    private var readingWS: Bool = false
    private var statsIPCAttempted: Bool = false

    var isConnectedToAnyVPN: Bool = false

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            self?.state = connection.status
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            updateStats()
            elapsedTime = -1 * (connectTime?.timeIntervalSinceNow ?? 0)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        timer?.invalidate()
    }

    // MARK: - Observers

    @discardableResult
    func observeState(_ handler: @escaping (NEVPNStatus) -> Void) -> UUID {
        let id = UUID()
        observerLock.lock()
        stateObservers[id] = handler
        observerLock.unlock()
        handler(state)
        return id
    }

    func removeStateObserver(_ id: UUID) {
        observerLock.lock()
        stateObservers.removeValue(forKey: id)
        observerLock.unlock()
    }

    @discardableResult
    func observeAlert(_ handler: @escaping (VPNManagerAlert) -> Void) -> UUID {
        let id = UUID()
        observerLock.lock()
        alertObservers[id] = handler
        observerLock.unlock()
        handler(alert)
        return id
    }

    func removeAlertObserver(_ id: UUID) {
        observerLock.lock()
        alertObservers.removeValue(forKey: id)
        observerLock.unlock()
    }

    private func notifyState() {
        let value = state
        observerLock.lock()
        let handlers = Array(stateObservers.values)
        observerLock.unlock()
        let call = { handlers.forEach { $0(value) } }
        if Thread.isMainThread {
            call()
        } else {
            DispatchQueue.main.async(execute: call)
        }
    }

    private func notifyAlert() {
        let value = alert
        observerLock.lock()
        let handlers = Array(alertObservers.values)
        observerLock.unlock()
        let call = { handlers.forEach { $0(value) } }
        if Thread.isMainThread {
            call()
        } else {
            DispatchQueue.main.async(execute: call)
        }
    }

    // MARK: - VPN lifecycle

    func setup(completion: @escaping (Error?) -> Void) {
        loaded = true
        loadVPNPreference(completion: completion)
    }

    private func loadVPNPreference(completion: @escaping (Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self else {
                completion(error)
                return
            }
            if let error {
                completion(error)
                return
            }
            if let manager = managers?.first {
                DispatchQueue.main.async {
                    self.manager = manager
                }
                completion(nil)
                return
            }

            let newManager = NETunnelProviderManager()
            let providerProtocol = NETunnelProviderProtocol()
            providerProtocol.providerBundleIdentifier = Bundle.main.baseBundleIdentifier + ".PacketTunnel"
            providerProtocol.serverAddress = "localhost"
            newManager.protocolConfiguration = providerProtocol
            newManager.localizedDescription = "Hiddify"

            newManager.saveToPreferences { error in
                if let error {
                    completion(error)
                    return
                }
                newManager.loadFromPreferences { error in
                    if error == nil {
                        DispatchQueue.main.async {
                            self.manager = newManager
                        }
                    }
                    completion(error)
                }
            }
        }
    }

    private func enableVPNManager(completion: @escaping (Error?) -> Void) {
        manager.isEnabled = true
        manager.saveToPreferences { [weak self] error in
            guard let self else {
                completion(error)
                return
            }
            if let error {
                completion(error)
                return
            }
            self.manager.loadFromPreferences { error in
                completion(error)
            }
        }
    }

    func connect(with config: String, disableMemoryLimit: Bool = false, completion: @escaping (Error?) -> Void) {
        set(upload: 0, download: 0)
        statsIPCAttempted = false
        guard state == .disconnected || state == .invalid else {
            completion(nil)
            return
        }
        enableVPNManager { [weak self] error in
            guard let self else {
                completion(error)
                return
            }
            if let error {
                completion(error)
                return
            }
            do {
                try self.manager.connection.startVPNTunnel(options: [
                    "Config": config as NSString,
                    "DisableMemoryLimit": (disableMemoryLimit ? "YES" : "NO") as NSString,
                ])
                self.connectTime = Date()
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func disconnect() {
        guard state == .connected else { return }
        manager.connection.stopVPNTunnel()
    }

    func waitForDisconnect(completion: @escaping () -> Void) {
        if state == .disconnected || state == .invalid {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: completion)
            return
        }

        var token: UUID?
        var completed = false
        token = observeState { [weak self] status in
            guard status == .disconnected || status == .invalid else { return }
            guard !completed else { return }
            completed = true
            if let token {
                self?.removeStateObserver(token)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: completion)
        }
    }

    func reset() {
        loaded = false
        if state != .disconnected && state != .invalid {
            disconnect()
        }
        waitForDisconnect { [weak self] in
            guard let self else { return }
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                let group = DispatchGroup()
                for manager in managers ?? [] {
                    group.enter()
                    manager.removeFromPreferences { _ in
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    self.loadVPNPreference { _ in }
                }
            }
        }
    }

    private func updateStats() {
        let isAnyVPNConnected = self.isAnyVPNConnected
        if isConnectedToAnyVPN != isAnyVPNConnected {
            isConnectedToAnyVPN = isAnyVPNConnected
        }
        guard state == .connected else { return }
        // On iOS 12 nesessionmanager rejects the app's request to establish
        // IPC with the tunnel plugin ("not entitled"), producing an error log
        // every second, and libbox stats are already delivered to the UI
        // through the command socket in the shared app group
        // (StatsEventHandler). So do not hammer sendProviderMessage.
        if statsIPCAttempted { return }
        statsIPCAttempted = true
        guard let connection = manager.connection as? NETunnelProviderSession else { return }
        do {
            try connection.sendProviderMessage("stats".data(using: .utf8)!) { [weak self] response in
                guard
                    let response,
                    let response = String(data: response, encoding: .utf8)
                else { return }
                let responseComponents = response.components(separatedBy: ",")
                guard
                    responseComponents.count == 2,
                    let upload = Int64(responseComponents[0]),
                    let download = Int64(responseComponents[1])
                else { return }
                self?.set(upload: upload, download: download)
            }
        } catch {
            print(error.localizedDescription)
        }
    }

    private func set(upload: Int64, download: Int64) {
        let update = {
            self.upload = upload
            self.download = download
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    var isAnyVPNConnected: Bool {
        guard let cfDict = CFNetworkCopySystemProxySettings() else { return false }
        let nsDict = cfDict.takeRetainedValue() as NSDictionary
        guard let keys = nsDict["__SCOPED__"] as? NSDictionary else {
            return false
        }
        for key: String in keys.allKeys as! [String] {
            if key == "tap" || key == "tun" || key == "ppp" || key == "ipsec" || key == "ipsec0" {
                return true
            } else if key.starts(with: "utun") {
                return true
            }
        }
        return false
    }
}
