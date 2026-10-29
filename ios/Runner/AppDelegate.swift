import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StairNativeUI") {
      StairNativeControls.register(with: registrar)
      StairSymbols.register(with: registrar)
      StairMaps.register(with: registrar)
      StairNavigation.register(with: registrar)
      registrar.register(
        StairTabBarFactory(messenger: registrar.messenger()),
        withId: "giristair/native-tab-bar"
      )
    }
  }
}
