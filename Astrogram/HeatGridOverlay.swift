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
        
        var missingCoords: [CLLocationCoordinate2D] = []
        
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
                
                let mapPoint = MKMapPoint(
                    x: overlay.boundingMapRect.minX + (Double(col) + 0.5) * overlay.boundingMapRect.size.width / Double(cells),
                    y: overlay.boundingMapRect.minY + (Double(row) + 0.5) * overlay.boundingMapRect.size.height / Double(cells)
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
                    //placeholder
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

                if hasRealData {
                    let hue = CGFloat(0.33 * (1.0 - value))
                    let color = UIColor(hue: hue, saturation: 0.9, brightness: 0.95, alpha: 1.0)
                    context.setFillColor(color.cgColor)
                    
                //not real data case
                } else {
                    // loading state - draw neutral gray
                    context.setFillColor(UIColor.gray.withAlphaComponent(0.3).cgColor)
                }

                context.fill(cellRect.insetBy(dx: 0.5, dy: 0.5))
            }
        }
        
        context.restoreGState()
        
        //fetch missing then redraw
        if !missingCoords.isEmpty {
            Task {
                await WeatherService.shared.fetchCoordinates(missingCoords)
                await MainActor.run {
                    self.setNeedsDisplay(overlay.boundingMapRect)
                }
            }
        }
    }
}
