import Flutter
import UIKit

/// SwiftUI TabView in LiveStair delegates the tab's fonts, SF Symbols, glass,
/// selection shape and transitions to iOS. Do the same instead of drawing
/// another Flutter approximation of whichever iOS version is installed.
final class StairTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    StairTabBarView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      configuration: args as? [String: Any] ?? [:]
    )
  }
}

private final class StairTabContainerView: UIView {
  var onWindowChanged: (() -> Void)?
  var onLayout: (() -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    onWindowChanged?()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

private final class StairSystemTabController: UITabBarController {
  var onLayout: (() -> Void)?

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onLayout?()
  }
}

private final class StairTabBarView: NSObject,
  FlutterPlatformView, UITabBarControllerDelegate {
  private let container: StairTabContainerView
  private let controller = StairSystemTabController()
  private let channel: FlutterMethodChannel
  private var reportedHeight: CGFloat = 0

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    configuration: [String: Any]
  ) {
    container = StairTabContainerView(frame: frame)
    channel = FlutterMethodChannel(
      name: "giristair/native-tab-bar/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    container.backgroundColor = .clear
    container.isOpaque = false
    controller.view.backgroundColor = .clear
    controller.view.isOpaque = false
    controller.delegate = self
    controller.tabBar.isTranslucent = true
    controller.tabBar.unselectedItemTintColor = .label

    let items = [
      ("登録", "plus.circle.fill"),
      ("一覧", "clock.fill"),
      ("戦績", "trophy.fill"),
      ("思考", "checklist"),
      ("設定", "gearshape")
    ]
    controller.viewControllers = items.enumerated().map { index, item in
      let child = UIViewController()
      child.view.backgroundColor = .clear
      child.view.isOpaque = false
      child.tabBarItem = UITabBarItem(
        title: item.0,
        image: UIImage(systemName: item.1),
        tag: index
      )
      return child
    }

    container.onWindowChanged = { [weak self] in self?.attachController() }
    container.onLayout = { [weak self] in
      guard let self else { return }
      self.controller.view.frame = self.container.bounds
    }
    controller.onLayout = { [weak self] in self?.reportHeight() }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "configure" {
        self.configure(call.arguments as? [String: Any] ?? [:])
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    configure(configuration)
  }

  deinit {
    channel.setMethodCallHandler(nil)
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
  }

  func view() -> UIView { container }

  private func attachController() {
    guard container.window != nil else { return }
    if controller.parent == nil {
      var responder: UIResponder? = container.next
      while let current = responder {
        if let parent = current as? UIViewController {
          parent.addChild(controller)
          controller.view.frame = container.bounds
          container.addSubview(controller.view)
          controller.didMove(toParent: parent)
          break
        }
        responder = current.next
      }
    }
    controller.view.setNeedsLayout()
  }

  private func configure(_ values: [String: Any]) {
    if let dark = values["dark"] as? Bool {
      controller.overrideUserInterfaceStyle = dark ? .dark : .light
    }
    if let tint = values["tintColor"] as? NSNumber {
      let argb = tint.uint32Value
      controller.tabBar.tintColor = UIColor(
        red: CGFloat((argb >> 16) & 255) / 255,
        green: CGFloat((argb >> 8) & 255) / 255,
        blue: CGFloat(argb & 255) / 255,
        alpha: CGFloat((argb >> 24) & 255) / 255
      )
    }
    if let index = values["selectedIndex"] as? Int,
       (0..<5).contains(index), controller.selectedIndex != index {
      controller.selectedIndex = index
    }
    // The first layout can happen before Dart installs its callback handler.
    reportedHeight = 0
    controller.view.setNeedsLayout()
  }

  private func reportHeight() {
    guard container.window != nil,
          controller.view.bounds.height > 0,
          controller.tabBar.bounds.height > 0 else { return }
    let height = ceil(
      controller.view.bounds.maxY - controller.tabBar.frame.minY
    )
    guard height >= 44, height <= 180,
          abs(height - reportedHeight) > 0.5 else { return }
    reportedHeight = height
    channel.invokeMethod("heightChanged", arguments: Double(height))
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
  ) {
    // LiveStair adds no extra haptic to the standard control's own feedback.
    channel.invokeMethod("select", arguments: tabBarController.selectedIndex)
  }
}
