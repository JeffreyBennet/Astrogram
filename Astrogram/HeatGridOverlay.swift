import MapKit
import UIKit

enum HeatLayerKind {
    case lightPollution
    case cloudCover
    case visibility
}

final class HeatGridOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let kind: HeatLayerKind
    let opacity: CGFloat

    init(kind: HeatLayerKind, opacity: CGFloat) {
        self.boundingMapRect = MKMapRect.world
        self.coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        self.kind = kind
        self.opacity = opacity
        super.init()
    }
}

final class HeatGridOverlayRenderer: MKOverlayRenderer {
    private let calculator = VisibilityCalculator()
    private let sampleCount = 8

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? HeatGridOverlay else { return }

        let n = sampleCount
        var missingCoords: [CLLocationCoordinate2D] = []
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        var hasAnyData = false

        for row in 0..<n {
            for col in 0..<n {
                let mapPoint = MKMapPoint(
                    x: mapRect.minX + (Double(col) + 0.5) * mapRect.size.width / Double(n),
                    y: mapRect.minY + (Double(row) + 0.5) * mapRect.size.height / Double(n)
                )
                let centerCoord = mapPoint.coordinate

                if WeatherService.shared.cachedData(near: centerCoord) == nil {
                    missingCoords.append(centerCoord)
                }

                let value: Double
                let hasRealData: Bool

                switch overlay.kind {
                case .lightPollution:
                    value = calculator.lightPollutionIndex(at: centerCoord)
                    hasRealData = true
                case .cloudCover:
                    let weather = WeatherService.shared.cachedData(near: centerCoord)
                    hasRealData = weather != nil
                    value = weather?.cloudCoverFraction ?? 0.5
                case .visibility:
                    let summary = calculator.summary(at: centerCoord)
                    hasRealData = summary.isRealData
                    value = Double(summary.overallScore) / 100.0
                }

                let idx = (row * n + col) * 4
                if hasRealData {
                    hasAnyData = true
                    let hue = CGFloat(0.33 * (1.0 - value))
                    let color = UIColor(hue: hue, saturation: 0.9, brightness: 0.95, alpha: 1.0)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    color.getRed(&r, green: &g, blue: &b, alpha: &a)
                    pixels[idx]     = UInt8(r * 255)
                    pixels[idx + 1] = UInt8(g * 255)
                    pixels[idx + 2] = UInt8(b * 255)
                    pixels[idx + 3] = 255
                }
                // else: stays at 0,0,0,0 (fully transparent)
            }
        }

        if hasAnyData {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let image = CGImage(
                    width: n, height: n,
                    bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: n * 4,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider,
                    decode: nil, shouldInterpolate: true,
                    intent: .defaultIntent
                  ) else { return }

            let drawRect = self.rect(for: mapRect)

            context.saveGState()
            context.interpolationQuality = .high

            UIGraphicsPushContext(context)
            UIImage(cgImage: image).draw(in: drawRect, blendMode: .normal, alpha: overlay.opacity)
            UIGraphicsPopContext()

            context.restoreGState()
        }

        //fetch missing then redraw this tile
        if !missingCoords.isEmpty {
            Task {
                await WeatherService.shared.fetchCoordinates(missingCoords)
                await MainActor.run {
                    self.setNeedsDisplay(mapRect)
                }
            }
        }
    }
}
