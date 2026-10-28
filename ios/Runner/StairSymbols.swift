import Flutter
import UIKit

/// Render the same system symbols/weights as SwiftUI's Image(systemName:).
/// Only UI artwork is returned; no participation records cross this channel.
final class StairSymbols: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "giristair/native-symbols", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(StairSymbols(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "rasterize" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
      let names = arguments["symbols"] as? [String], names.count <= 128
    else {
      result(FlutterError(code: "invalid", message: "Invalid symbol request", details: nil))
      return
    }
    let requestedScale = (arguments["scale"] as? NSNumber)?.doubleValue ?? Double(UIScreen.main.scale)
    let displayScale = CGFloat(requestedScale.isFinite ? min(4, max(1, requestedScale)) : 2)
    let variants: [(CGFloat, UIImage.SymbolWeight, Int)] = [
      (14, .semibold, 600), (19, .bold, 700),
    ]
    var images: [String: [String: Any]] = [:]
    for name in Set(names) {
      for (pointSize, weight, numericWeight) in variants {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration),
          symbol.size.width > 0, symbol.size.height > 0
        else { continue }
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        format.preferredRange = .standard
        let raster = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
          symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(
            in: CGRect(origin: .zero, size: symbol.size))
        }
        guard let data = raster.pngData() else { continue }
        images["\(name)/\(Int(pointSize))/\(numericWeight)"] = [
          "bytes": FlutterStandardTypedData(bytes: data),
          "width": Double(symbol.size.width),
          "height": Double(symbol.size.height),
        ]
      }
    }
    result(images)
  }
}
