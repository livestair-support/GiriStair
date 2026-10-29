import Flutter
import MapKit
import UIKit

/// Venue lookup is initiated by a search button, never by device location.
final class StairMaps: NSObject, FlutterPlugin {
  private weak var presenter: UIViewController?
  private weak var activePicker: StairMapSearchController?

  private init(presenter: UIViewController?) {
    self.presenter = presenter
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "giristair/native-maps", binaryMessenger: registrar.messenger())
    let plugin = StairMaps(presenter: registrar.viewController)
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.register(
      StairMapPreviewFactory(messenger: registrar.messenger()),
      withId: "giristair/native-map")
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      result(["available": true])
    case "pickPlace":
      guard activePicker == nil else {
        result(FlutterError(code: "busy", message: "地図の検索画面はすでに開いています。", details: nil))
        return
      }
      guard let presenter = topPresenter() else {
        result(FlutterError(code: "unavailable", message: "地図の検索画面を開けませんでした。", details: nil))
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      let query = String((arguments["initialQuery"] as? String ?? "").prefix(512))
      presenter.view.endEditing(true)
      let picker = StairMapSearchController(initialQuery: query) { [weak self] value in
        self?.activePicker = nil
        result(value)
      }
      activePicker = picker
      let navigation = UINavigationController(rootViewController: picker)
      if let dark = arguments["dark"] as? Bool {
        navigation.overrideUserInterfaceStyle = dark ? .dark : .light
      }
      navigation.modalPresentationStyle = .pageSheet
      navigation.presentationController?.delegate = picker
      presenter.present(navigation, animated: true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func topPresenter() -> UIViewController? {
    var controller = presenter
    if controller?.viewIfLoaded?.window == nil {
      let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
        .flatMap { $0.windows }
      controller = windows.first { $0.isKeyWindow }?.rootViewController ?? controller
    }
    while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
      controller = presented
    }
    return controller
  }
}

private final class StairMapSearchController: UITableViewController,
  UISearchBarDelegate, UIAdaptivePresentationControllerDelegate {
  private let searchController = UISearchController(searchResultsController: nil)
  private let initialQuery: String
  private var completion: ((Any?) -> Void)?
  private var activeSearch: MKLocalSearch?
  private var searchToken: UUID?
  private var items: [MKMapItem] = []
  private var isSearching = false
  private var isFinishing = false

  init(initialQuery: String, completion: @escaping (Any?) -> Void) {
    self.initialQuery = initialQuery
    self.completion = completion
    super.init(style: .insetGrouped)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  deinit { activeSearch?.cancel() }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "地図情報を紐付け"
    view.tintColor = .systemPink
    tableView.backgroundColor = .systemGroupedBackground
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 64
    tableView.keyboardDismissMode = .interactive
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "閉じる", style: .plain, target: self, action: #selector(close))
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "検索", style: .plain, target: self, action: #selector(search))
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "会場名で検索"
    searchController.searchBar.text = initialQuery
    searchController.searchBar.delegate = self
    searchController.searchBar.returnKeyType = .search
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
    definesPresentationContext = true
    showMessage("会場名を入力して検索してください。")
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { search() }

  @objc private func search() {
    let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty, !isFinishing else { return }
    activeSearch?.cancel()
    searchController.searchBar.resignFirstResponder()
    let token = UUID()
    searchToken = token
    isSearching = true
    items = []
    navigationItem.rightBarButtonItem?.isEnabled = false
    let progress = UIActivityIndicatorView(style: .medium)
    progress.startAnimating()
    tableView.backgroundView = progress
    tableView.reloadData()
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = String(query.prefix(512))
    request.resultTypes = [.address, .pointOfInterest]
    let search = MKLocalSearch(request: request)
    activeSearch = search
    search.start { [weak self] response, error in
      DispatchQueue.main.async {
        guard let self, self.searchToken == token, !self.isFinishing else { return }
        self.activeSearch = nil
        self.isSearching = false
        self.navigationItem.rightBarButtonItem?.isEnabled = true
        self.items = error == nil ? (response?.mapItems ?? []) : []
        if error != nil {
          self.showMessage("検索に失敗しました。もう一度お試しください。")
        } else if self.items.isEmpty {
          self.showMessage("会場が見つかりませんでした。検索する名前を変えてお試しください。")
        } else {
          self.tableView.backgroundView = nil
        }
        self.tableView.reloadData()
      }
    }
  }

  private func showMessage(_ text: String) {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    tableView.backgroundView = label
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    items.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "place") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "place")
    let item = items[indexPath.row]
    cell.textLabel?.text = item.name ?? "名称未設定"
    cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    cell.textLabel?.textColor = .label
    cell.detailTextLabel?.text = item.placemark.title ?? ""
    cell.detailTextLabel?.font = .systemFont(ofSize: 13)
    cell.detailTextLabel?.textColor = .secondaryLabel
    cell.detailTextLabel?.numberOfLines = 2
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    guard !isSearching, items.indices.contains(indexPath.row) else { return }
    let item = items[indexPath.row]
    let coordinate = item.placemark.coordinate
    guard CLLocationCoordinate2DIsValid(coordinate) else { return }
    finish([
      "name": item.name ?? "名称未設定",
      "address": item.placemark.title ?? "",
      "latitude": coordinate.latitude,
      "longitude": coordinate.longitude,
    ])
  }

  @objc private func close() { finish(nil) }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    resolve(nil)
  }

  private func finish(_ value: Any?) {
    guard !isFinishing else { return }
    isFinishing = true
    activeSearch?.cancel()
    dismiss(animated: true) { self.resolve(value) }
  }

  private func resolve(_ value: Any?) {
    activeSearch?.cancel()
    searchToken = nil
    let result = completion
    completion = nil
    result?(value)
  }
}

private final class StairMapPreviewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    StairMapPreviewView(frame: frame, viewId: viewId, arguments: args as? [String: Any] ?? [:], messenger: messenger)
  }
}

private final class StairMapPreviewView: NSObject, FlutterPlatformView {
  private let map = MKMapView()
  private let channel: FlutterMethodChannel
  private var lastCoordinate: CLLocationCoordinate2D?
  private var lastName: String?

  init(frame: CGRect, viewId: Int64, arguments: [String: Any], messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "giristair/native-map/\(viewId)", binaryMessenger: messenger)
    super.init()
    map.frame = frame
    map.isScrollEnabled = false
    map.isZoomEnabled = false
    map.isRotateEnabled = false
    map.isPitchEnabled = false
    map.isUserInteractionEnabled = false
    map.showsUserLocation = false
    map.layer.cornerRadius = 16
    map.layer.cornerCurve = .continuous
    map.layer.masksToBounds = true
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "configure", let values = call.arguments as? [String: Any] {
        self?.configure(values)
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
    configure(arguments)
  }

  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { map }

  private func configure(_ arguments: [String: Any]) {
    if let dark = arguments["dark"] as? Bool {
      map.overrideUserInterfaceStyle = dark ? .dark : .light
    }
    guard let latitude = (arguments["latitude"] as? NSNumber)?.doubleValue,
      let longitude = (arguments["longitude"] as? NSNumber)?.doubleValue,
      latitude.isFinite, longitude.isFinite else { return }
    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    guard CLLocationCoordinate2DIsValid(coordinate) else { return }
    let name = arguments["name"] as? String ?? ""
    if let old = lastCoordinate, old.latitude == latitude, old.longitude == longitude, lastName == name { return }
    lastCoordinate = coordinate
    lastName = name
    map.removeAnnotations(map.annotations)
    let pin = MKPointAnnotation()
    pin.coordinate = coordinate
    pin.title = name
    map.addAnnotation(pin)
    map.setRegion(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)), animated: false)
  }
}
