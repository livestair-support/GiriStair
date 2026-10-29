import Flutter
import UIKit

/// Render the same system back item as SwiftUI NavigationStack. UIKit owns
/// the chevron, its iOS 26 glass, touch target and accessibility treatment.
final class StairNavigation {
  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(StairBackFactory(messenger: registrar.messenger()), withId: "giristair/native-back")
  }
}

private final class StairBackFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    StairBackView(frame: frame, id: viewId, messenger: messenger, values: args as? [String: Any] ?? [:])
  }
}

private final class StairBackView: NSObject, FlutterPlatformView, UINavigationBarDelegate {
  private let bar: UINavigationBar
  private let channel: FlutterMethodChannel
  init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger, values: [String: Any]) {
    bar = UINavigationBar(frame: frame)
    channel = FlutterMethodChannel(name: "giristair/native-back/\(id)", binaryMessenger: messenger)
    super.init()
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    bar.standardAppearance = appearance
    bar.compactAppearance = appearance
    bar.scrollEdgeAppearance = appearance
    bar.tintColor = .label
    bar.backgroundColor = .clear
    let previous = UINavigationItem(title: "")
    previous.backButtonDisplayMode = .minimal
    let current = UINavigationItem(title: "")
    bar.setItems([previous, current], animated: false)
    bar.delegate = self
    update(values)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "configure" {
        self?.update(call.arguments as? [String: Any] ?? [:])
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
  }
  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { bar }
  private func update(_ values: [String: Any]) {
    bar.overrideUserInterfaceStyle = values["dark"] as? Bool == true ? .dark : .light
    let enabled = values["enabled"] as? Bool ?? true
    bar.isUserInteractionEnabled = enabled
    bar.alpha = enabled ? 1 : 0.4
  }
  func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool {
    channel.invokeMethod("back", arguments: nil)
    return false // Flutter owns the route stack and the edge-swipe gesture.
  }
}
