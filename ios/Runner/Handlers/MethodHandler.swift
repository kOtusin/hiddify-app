//
//  MethodHandler.swift
//  Runner
//
//  Created by GFWFighter on 10/23/23.
//

import Flutter
import Libcore

public class MethodHandler: NSObject, FlutterPlugin {
    public static let name = "\(Bundle.main.serviceIdentifier)/method"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: Self.name, binaryMessenger: registrar.messenger())
        let instance = MethodHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.channel = channel
    }

    private var channel: FlutterMethodChannel?

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        func mainResult(_ res: Any?) {
            DispatchQueue.main.async {
                result(res)
            }
        }

        switch call.method {
        case "parse_config":
            guard
                let args = call.arguments as? [String: Any?],
                let path = args["path"] as? String,
                let tempPath = args["tempPath"] as? String,
                let debug = (args["debug"] as? NSNumber)?.boolValue
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            var error: NSError?
            MobileParse(path, tempPath, debug, &error)
            if let error {
                result(FlutterError(code: String(error.code), message: error.description, details: nil))
                return
            }
            result("")
        case "change_config_options", "change_hiddify_options":
            // Dart (PlatformSingboxService.changeOptions) sends
            // "change_hiddify_options" on this channel; the Android plugin
            // historically named the same method "change_config_options".
            // Accept both so a method-name drift can never surface as
            // MissingPluginException again.
            guard let options = call.arguments as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            VPNConfig.shared.configOptions = options
            result(true)
        case "clear_logs":
            // Logs arrive through the service.logs event channel straight from
            // the core; there is no native-side buffer to clear. Acknowledge so
            // Dart's log clear button does not hit MissingPluginException.
            result(true)
        case "setup":
            VPNManager.shared.setup { error in
                if let error {
                    mainResult(FlutterError(code: "SETUP", message: error.localizedDescription, details: nil))
                } else {
                    mainResult(true)
                }
            }
        case "start":
            guard
                let args = call.arguments as? [String: Any?],
                let path = args["path"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            VPNConfig.shared.activeConfigPath = path
            var error: NSError?
            let config = MobileBuildConfig(path, VPNConfig.shared.configOptions, &error)
            if let error {
                result(FlutterError(code: String(error.code), message: error.description, details: nil))
                return
            }
            VPNManager.shared.setup { error in
                if let error {
                    mainResult(FlutterError(code: "SETUP_CONNECTION", message: error.localizedDescription, details: nil))
                    return
                }
                VPNManager.shared.connect(with: config, disableMemoryLimit: VPNConfig.shared.disableMemoryLimit) { error in
                    if let error {
                        mainResult(FlutterError(code: "SETUP_CONNECTION", message: error.localizedDescription, details: nil))
                    } else {
                        mainResult(true)
                    }
                }
            }
        case "restart":
            guard
                let args = call.arguments as? [String: Any?],
                let path = args["path"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            VPNConfig.shared.activeConfigPath = path
            VPNManager.shared.disconnect()
            VPNManager.shared.waitForDisconnect {
                var error: NSError?
                let config = MobileBuildConfig(path, VPNConfig.shared.configOptions, &error)
                if let error {
                    mainResult(FlutterError(code: "BUILD_CONFIG", message: error.localizedDescription, details: nil))
                    return
                }
                VPNManager.shared.setup { error in
                    if let error {
                        mainResult(FlutterError(code: "SETUP_CONNECTION", message: error.localizedDescription, details: nil))
                        return
                    }
                    VPNManager.shared.connect(with: config, disableMemoryLimit: VPNConfig.shared.disableMemoryLimit) { error in
                        if let error {
                            mainResult(FlutterError(code: "SETUP_CONNECTION", message: error.localizedDescription, details: nil))
                        } else {
                            mainResult(true)
                        }
                    }
                }
            }
        case "stop":
            VPNManager.shared.disconnect()
            result(true)
        case "reset":
            VPNManager.shared.reset()
            result(true)
        case "url_test":
            guard let args = call.arguments as? [String: Any?] else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            let group = args["groupTag"] as? String
            FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
            do {
                try LibboxNewStandaloneCommandClient()?.urlTest(group)
            } catch {
                result(FlutterError(code: "URL_TEST", message: error.localizedDescription, details: nil))
                return
            }
            result(true)
        case "select_outbound":
            guard
                let args = call.arguments as? [String: Any?],
                let group = args["groupTag"] as? String,
                let outbound = args["outboundTag"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
            do {
                try LibboxNewStandaloneCommandClient()?.selectOutbound(group, outboundTag: outbound)
            } catch {
                result(FlutterError(code: "SELECT_OUTBOUND", message: error.localizedDescription, details: nil))
                return
            }
            result(true)
        case "generate_config":
            guard
                let args = call.arguments as? [String: Any?],
                let path = args["path"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            var error: NSError?
            let config = MobileBuildConfig(path, VPNConfig.shared.configOptions, &error)
            if let error {
                result(FlutterError(code: "BUILD_CONFIG", message: error.localizedDescription, details: nil))
                return
            }
            result(config)
        case "generate_warp_config":
            guard
                let args = call.arguments as? [String: Any],
                let licenseKey = args["license-key"] as? String,
                let accountId = args["previous-account-id"] as? String,
                let accessToken = args["previous-access-token"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            let warpConfig = MobileGenerateWarpConfig(licenseKey, accountId, accessToken, nil)
            result(warpConfig)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
