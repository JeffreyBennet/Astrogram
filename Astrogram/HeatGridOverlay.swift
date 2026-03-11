import MapKit
import UIKit

enum HeatLayerKind {
    case lightPollution
    case cloudCover
}

final class HeatGridOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let kind: HeatLayerKind
    let opacity: CGFloat

    // IMPORTANT: keep a weak reference to the mapView that owns this overlay
    weak var mapView: MKMapView?

    init(mapView: MKMapView, mapRect: MKMapRect, kind: HeatLayerKind, opacity: CGFloat) {
        self.mapView = mapView
        self.boundingMapRect = mapRect
        self.coordinate = MKCoordinateRegion(mapRect).center
        self.kind = kind
        self.opacity = opacity
        super.init()
    }
}

final class HeatGridOverlayRenderer: MKOverlayRenderer {
    private let calculator = VisibilityCalculator()

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? HeatGridOverlay else { return }

        let rect = overlay.boundingMapRect.intersection(mapRect)
        if rect.isNull { return }

        let cells: Int = zoomScale < 0.02 ? 16 : (zoomScale < 0.08 ? 22 : 28)

        let drawRect = self.rect(for: overlay.boundingMapRect)
        let cellW = drawRect.width / CGFloat(cells)
        let cellH = drawRect.height / CGFloat(cells)

        context.saveGState()
        context.setAlpha(overlay.opacity)

        for row in 0..<cells {
            for col in 0..<cells {
                let cellRect = CGRect(
                    x: drawRect.minX + CGFloat(col) * cellW,
                    y: drawRect.minY + CGFloat(row) * cellH,
                    width: cellW,
                    height: cellH
                )

                // convert map point directly to coordinate instead of using mapView.convert
                let mapPoint = MKMapPoint(
                    x: overlay.boundingMapRect.minX + (Double(col) + 0.5) * overlay.boundingMapRect.size.width / Double(cells),
                    y: overlay.boundingMapRect.minY + (Double(row) + 0.5) * overlay.boundingMapRect.size.height / Double(cells)
                )
                let centerCoord = mapPoint.coordinate

                let value: Double
                switch overlay.kind {
                case .lightPollution:
                    value = calculator.lightPollutionIndex(at: centerCoord)
                case .cloudCover:
                    value = calculator.cloudCover(at: centerCoord)
                }

                let hue = CGFloat(0.33 * (1.0 - value))
                let color = UIColor(hue: hue, saturation: 0.9, brightness: 0.95, alpha: 1.0)

                context.setFillColor(color.cgColor)
                context.fill(cellRect.insetBy(dx: 0.5, dy: 0.5))
            }
        }

        context.restoreGState()
    }
}
