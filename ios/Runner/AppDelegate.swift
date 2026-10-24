import UIKit
import Flutter
import Libcore

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var flutterEngine: FlutterEngine?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        setupFileManager()

        // The upstream project created the Flutter view controller through
        // Main.storyboard; it also relied on that storyboard so that the plugin
        // registrars existed before AppDelegate.registerHandlers ran. Xcode 26's
        // ibtool cannot compile storyboards in this environment, so create the
        // engine and root view controller explicitly, BEFORE registering any
        // FlutterPlugin. self.registrar(forPlugin:) returns nil until an engine
        // is attached, which crashed with EXC_BREAKPOINT on launch.
        window = UIWindow(frame: UIScreen.main.bounds)

        let engine = FlutterEngine(name: "com.kotu.hiddify.main")
        engine.run(withEntrypoint: nil)
        flutterEngine = engine

        window.rootViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        window.makeKeyAndVisible()

        registerHandlers(engine: engine)
        GeneratedPluginRegistrant.register(with: engine)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func setupFileManager() {
        try? FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
    }

    func registerHandlers(engine: FlutterEngine) {
        MethodHandler.register(with: engine.registrar(forPlugin: MethodHandler.name)!)
        PlatformMethodHandler.register(with: engine.registrar(forPlugin: PlatformMethodHandler.name)!)
        FileMethodHandler.register(with: engine.registrar(forPlugin: FileMethodHandler.name)!)
        StatusEventHandler.register(with: engine.registrar(forPlugin: StatusEventHandler.name)!)
        AlertsEventHandler.register(with: engine.registrar(forPlugin: AlertsEventHandler.name)!)
        LogsEventHandler.register(with: engine.registrar(forPlugin: LogsEventHandler.name)!)
        GroupsEventHandler.register(with: engine.registrar(forPlugin: GroupsEventHandler.name)!)
        ActiveGroupsEventHandler.register(with: engine.registrar(forPlugin: ActiveGroupsEventHandler.name)!)
        StatsEventHandler.register(with: engine.registrar(forPlugin: StatsEventHandler.name)!)
    }
}

