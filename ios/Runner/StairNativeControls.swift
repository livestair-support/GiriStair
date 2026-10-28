import CoreText
import Flutter
import UIKit

/// Small native controls shared by the Flutter screens. No records are stored here.
final class StairNativeControls: NSObject, FlutterPlugin {
  private weak var presenter: UIViewController?

  private init(presenter: UIViewController?) {
    self.presenter = presenter
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "giristair/native-controls", binaryMessenger: registrar.messenger())
    let plugin = StairNativeControls(presenter: registrar.viewController())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.register(
      StairNativeMenuFactory(messenger: registrar.messenger()),
      withId: "giristair/native-menu")
    registrar.register(
      StairNativeTimeFactory(messenger: registrar.messenger()),
      withId: "giristair/native-time")
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      result(["available": true, "fonts": Self.fonts()])
    case "pickDate":
      guard let arguments = call.arguments as? [String: Any],
        let components = arguments["components"] as? [Int], components.count == 5,
        let presenter = topPresenter()
      else {
        result(FlutterError(code: "unavailable", message: "Picker presenter unavailable", details: nil))
        return
      }
      presenter.view.endEditing(true)
      let picker = StairNativeDateController(arguments: arguments, components: components, result: result)
      let navigation = UINavigationController(rootViewController: picker)
      navigation.overrideUserInterfaceStyle = (arguments["dark"] as? Bool == true) ? .dark : .light
      navigation.modalPresentationStyle = .pageSheet
      navigation.presentationController?.delegate = picker
      if let sheet = navigation.sheetPresentationController {
        sheet.detents = [.medium()]
        sheet.prefersGrabberVisible = false
      }
      presenter.present(navigation, animated: true)
    case "saveFeedback":
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func topPresenter() -> UIViewController? {
    var controller = presenter
    if controller?.viewIfLoaded?.window == nil {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let window = scenes
        .filter { $0.activationState == .foregroundActive }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }
      controller = window?.rootViewController ?? controller
    }
    while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
      controller = presented
    }
    return controller
  }

  /// Resolve the actual Japanese fallback from the system font cascade on this
  /// device, including the rounded descriptor used by LiveStair's card titles.
  private static func fonts() -> [String: [String: Any]] {
    let roles: [(String, CGFloat, UIFont.Weight, Bool)] = [
      ("pageTitle", 34, .bold, false), ("sectionTitle", 18, .bold, true),
      ("formLabel", 15, .medium, false), ("input", 17, .regular, false),
      ("value", 17, .regular, false), ("dateValue", 17, .semibold, false),
      ("button", 17, .regular, false), ("tabLabel", 10, .medium, false),
      ("saveButton", 17, .bold, false), ("caption", 12, .regular, false),
      ("footnote", 13, .regular, false),
      ("dialogTitle", 17, .semibold, false), ("dialogBody", 13, .regular, false),
      ("menuItem", 17, .regular, false),
    ]
    var output: [String: [String: Any]] = [:]
    for (name, size, weight, rounded) in roles {
      var font = UIFont.systemFont(ofSize: size, weight: weight)
      if rounded, let descriptor = font.fontDescriptor.withDesign(.rounded) {
        font = UIFont(descriptor: descriptor, size: size)
      }
      let base = CTFontCreateWithName(font.fontName as CFString, size, nil)
      let text = "あいうえお漢字" as CFString
      let japanese = CTFontCreateForString(base, text, CFRange(location: 0, length: CFStringGetLength(text)))
      output[name] = [
        "latinPostscriptName": font.fontName,
        "japanesePostscriptName": CTFontCopyPostScriptName(japanese) as String,
        "latinFamilyName": font.familyName,
        "japaneseFamilyName": CTFontCopyFamilyName(japanese) as String,
        "fontSize": font.pointSize, "lineHeight": font.lineHeight,
        "ascender": font.ascender, "descender": font.descender,
      ]
    }
    return output
  }
}

private final class StairNativeTimeFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    StairNativeTime(frame: frame, id: viewId, arguments: args as? [String: Any] ?? [:], messenger: messenger)
  }
}

private final class StairNativeTime: NSObject, FlutterPlatformView {
  private let container = StairNativeTimeContainer()
  private let channel: FlutterMethodChannel

  init(frame: CGRect, id: Int64, arguments: [String: Any], messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "giristair/native-time/\(id)", binaryMessenger: messenger)
    super.init()
    container.frame = frame
    container.picker.addTarget(self, action: #selector(changed), for: .valueChanged)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let values = call.arguments as? [String: Any] {
        self?.update(values)
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
    update(arguments)
  }

  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { container }

  private func update(_ arguments: [String: Any]) {
    let components = arguments["components"] as? [Int] ?? []
    if components.count == 5,
      let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: components[0], month: components[1], day: components[2], hour: components[3], minute: components[4])) {
      container.picker.setDate(date, animated: false)
    }
    container.overrideUserInterfaceStyle = (arguments["dark"] as? Bool == true) ? .dark : .light
    container.picker.isEnabled = arguments["enabled"] as? Bool ?? true
    container.picker.accessibilityLabel = arguments["label"] as? String
    container.placeholder.isHidden = arguments["hasValue"] as? Bool == true
    container.placeholder.alpha = container.picker.isEnabled ? 1 : 0.4
    container.picker.accessibilityValue = container.placeholder.isHidden ? nil : "未定"
  }

  @objc private func changed() {
    container.placeholder.isHidden = true
    let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: container.picker.date)
    guard let year = parts.year, let month = parts.month, let day = parts.day,
      let hour = parts.hour, let minute = parts.minute else { return }
    channel.invokeMethod("changed", arguments: [year, month, day, hour, minute])
  }
}

private final class StairNativeTimeContainer: UIView {
  let picker = UIDatePicker()
  let placeholder = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    picker.locale = Locale(identifier: "ja_JP")
    picker.datePickerMode = .time
    picker.calendar = Calendar(identifier: .gregorian)
    picker.preferredDatePickerStyle = .compact
    picker.tintColor = .systemPink
    addSubview(picker)
    placeholder.text = "--:--"
    placeholder.textAlignment = .center
    placeholder.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    placeholder.textColor = .label
    placeholder.backgroundColor = .systemGray5
    placeholder.layer.cornerRadius = 16
    placeholder.layer.masksToBounds = true
    placeholder.isUserInteractionEnabled = false
    placeholder.isAccessibilityElement = false
    addSubview(placeholder)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func layoutSubviews() {
    super.layoutSubviews()
    picker.transform = .identity
    picker.frame = bounds
    picker.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
    placeholder.frame = bounds
  }
}

private final class StairNativeMenuFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    StairNativeMenu(frame: frame, id: viewId, arguments: args as? [String: Any] ?? [:], messenger: messenger)
  }
}

private final class StairNativeMenu: NSObject, FlutterPlatformView {
  private let button = UIButton(type: .system)
  private let channel: FlutterMethodChannel
  private var arguments: [String: Any]

  init(frame: CGRect, id: Int64, arguments: [String: Any], messenger: FlutterBinaryMessenger) {
    self.arguments = arguments
    channel = FlutterMethodChannel(name: "giristair/native-menu/\(id)", binaryMessenger: messenger)
    super.init()
    button.frame = frame
    button.backgroundColor = .clear
    button.contentHorizontalAlignment = .trailing
    button.showsMenuAsPrimaryAction = true
    button.addTarget(self, action: #selector(willOpen), for: .menuActionTriggered)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let values = call.arguments as? [String: Any] {
        self?.arguments = values
        self?.update()
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
    update()
  }

  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { button }

  @objc private func willOpen() {
    button.window?.endEditing(true)
    channel.invokeMethod("opened", arguments: nil)
  }

  private func update() {
    let labels = arguments["labels"] as? [String] ?? []
    let selected = arguments["selectedIndex"] as? Int ?? -1
    button.overrideUserInterfaceStyle = (arguments["dark"] as? Bool == true) ? .dark : .light
    button.isEnabled = arguments["enabled"] as? Bool ?? true
    let title = labels.indices.contains(selected) ? labels[selected] : ""
    let scale = CGFloat((arguments["textScale"] as? Double) ?? 1)
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration:
      UIImage.SymbolConfiguration(pointSize: 12 * scale, weight: .regular))
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 5
    configuration.contentInsets = .zero
    configuration.baseForegroundColor = .label
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = UIFont.systemFont(ofSize: 17 * scale, weight: .regular)
      return attributes
    }
    button.configuration = configuration
    button.accessibilityLabel = arguments["label"] as? String
    button.accessibilityValue = title
    button.menu = UIMenu(children: labels.enumerated().map { index, label in
      UIAction(title: label, state: index == selected ? .on : .off) { [weak self] _ in
        guard let self else { return }
        self.arguments["selectedIndex"] = index
        self.update()
        self.channel.invokeMethod("selected", arguments: index)
      }
    })
  }
}

/// Draft changes live in this controller until Done. Swipe-to-dismiss and Cancel
/// always return a cancellation, and clearing is distinct from cancellation.
private final class StairNativeDateController: UIViewController, UIAdaptivePresentationControllerDelegate {
  private let picker = UIDatePicker()
  private var completion: FlutterResult?
  private let arguments: [String: Any]
  private let components: [Int]

  init(arguments: [String: Any], components: [Int], result: @escaping FlutterResult) {
    self.arguments = arguments
    self.components = components
    completion = result
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    view.tintColor = .systemPink
    title = arguments["label"] as? String
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: "キャンセル", style: .plain, target: self, action: #selector(cancel))
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完了", style: .done, target: self, action: #selector(done))
    picker.locale = Locale(identifier: "ja_JP")
    picker.calendar = Calendar(identifier: .gregorian)
    picker.datePickerMode = (arguments["mode"] as? String == "time") ? .time : .dateAndTime
    picker.preferredDatePickerStyle = .wheels
    picker.date = Calendar(identifier: .gregorian).date(from: DateComponents(year: components[0], month: components[1], day: components[2], hour: components[3], minute: components[4])) ?? Date()
    picker.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(picker)
    let clear = UIButton(type: .system)
    clear.setTitle("未定に戻す", for: .normal)
    clear.titleLabel?.font = .systemFont(ofSize: 17)
    clear.addTarget(self, action: #selector(clearDate), for: .touchUpInside)
    clear.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(clear)
    NSLayoutConstraint.activate([
      picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
      clear.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 4),
      clear.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      clear.heightAnchor.constraint(equalToConstant: 44),
      clear.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
    ])
  }

  @objc private func cancel() { finish(["committed": false]) }
  @objc private func clearDate() { finish(["committed": true]) }
  @objc private func done() {
    let date = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: picker.date)
    finish(["committed": true, "components": [date.year ?? components[0], date.month ?? components[1], date.day ?? components[2], date.hour ?? components[3], date.minute ?? components[4]]])
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { resolve(["committed": false]) }
  private func finish(_ value: [String: Any]) {
    dismiss(animated: true) { self.resolve(value) }
  }
  private func resolve(_ value: [String: Any]) {
    let result = completion
    completion = nil
    result?(value)
  }
}
