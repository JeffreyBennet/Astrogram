import UIKit
import MapKit
import CoreLocation

final class MapViewController: UIViewController {

    @IBOutlet private weak var mapView: MKMapView!
    @IBOutlet weak var filtersButton: UIBarButtonItem!
    
    private let locationManager = CLLocationManager()
    private let calculator = VisibilityCalculator()

    private var lightOverlay: HeatGridOverlay?
    private var cloudOverlay: HeatGridOverlay?
    private var visibilityOverlay: HeatGridOverlay?
    
    private var didSetInitialRegion = false

    private var overlayRefreshWorkItem: DispatchWorkItem?
    private var lightPollutionTileOverlay: MKTileOverlay?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Astrogram"

        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = true

        configureLocation()
        applyNightModeIfNeeded()
        applyStartupLayer()

        addTapGesture()
        refreshOverlays()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setInitialRegionIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyNightModeIfNeeded()
        refreshOverlays()
    }

    private func configureLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    private func setInitialRegionIfNeeded() {
        guard !didSetInitialRegion else { return }
        didSetInitialRegion = true

        let fallback = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298) // Chicago
        let coord = locationManager.location?.coordinate ?? fallback

        let region = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7)
        )
        mapView.setRegion(region, animated: false)
    }

    private func addTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        tap.numberOfTapsRequired = 1
        mapView.addGestureRecognizer(tap)
    }

    @objc private func mapTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: mapView)
        let coord = mapView.convert(point, toCoordinateFrom: mapView)

        let summary = calculator.summary(at: coord)

        let message = """
        Overall: \(summary.overallScore)/100 (\(summary.label))

        Light pollution: \(Int((summary.lightPollutionIndex * 100).rounded()))/100
        Cloud cover: \(Int((summary.cloudCover * 100).rounded()))/100

        Lat: \(String(format: "%.4f", coord.latitude))
        Lon: \(String(format: "%.4f", coord.longitude))
        """

        let alert = UIAlertController(title: "Visibility Summary", message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Drop Pin", style: .default, handler: { [weak self] _ in
            self?.dropPin(at: coord, title: "Score \(summary.overallScore)", subtitle: summary.label)
        }))
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))

        if let pop = alert.popoverPresentationController {
            pop.sourceView = mapView
            pop.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        }

        present(alert, animated: true)
    }

    private func dropPin(at coord: CLLocationCoordinate2D, title: String, subtitle: String) {
        let ann = MKPointAnnotation()
        ann.coordinate = coord
        ann.title = title
        ann.subtitle = subtitle
        mapView.addAnnotation(ann)
    }

    private func applyStartupLayer() {
        let s = AppSettings.shared
        switch s.startupLayer {
        case .none:
            break
        case .light:
            s.showLightLayer = true
            s.showCloudLayer = false
            s.showVisibility = false
        case .clouds:
            s.showLightLayer = false
            s.showCloudLayer = true
            s.showVisibility = false
        case .visibility:
            s.showLightLayer = false
            s.showCloudLayer = false
            s.showVisibility = true
        }
    }

    private func applyNightModeIfNeeded() {
        if AppSettings.shared.nightMode {
            overrideUserInterfaceStyle = .dark
            mapView.overrideUserInterfaceStyle = .dark
            mapView.mapType = .mutedStandard
        } else {
            overrideUserInterfaceStyle = .unspecified
            mapView.overrideUserInterfaceStyle = .unspecified
            mapView.mapType = .standard
        }
    }

    private func refreshOverlays() {
        if let lo = lightOverlay { mapView.removeOverlay(lo) }
        if let vo = visibilityOverlay { mapView.removeOverlay(vo) }

        lightOverlay = nil
        visibilityOverlay = nil

        let visible = mapView.visibleMapRect
        let padded = visible.insetBy(dx: -visible.size.width * 0.2,
                                     dy: -visible.size.height * 0.2)

        let s = AppSettings.shared

        // Tile overlay: only add/remove when toggle state changes,
        // not on every region change — MKTileOverlay handles its own tiling.
        if s.showLightLayer && lightPollutionTileOverlay == nil {
            let overlay = LightPollutionTileOverlay(urlTemplate: nil)
            overlay.canReplaceMapContent = false
            overlay.tileSize = CGSize(width: 256, height: 256)

            lightPollutionTileOverlay = overlay
            mapView.addOverlay(overlay, level: .aboveLabels)
        } else if !s.showLightLayer, let tile = lightPollutionTileOverlay {
            mapView.removeOverlay(tile)
            lightPollutionTileOverlay = nil
        }

        if s.showVisibility {
            let o = HeatGridOverlay(mapView: mapView, mapRect: padded, kind: .visibility, opacity: 0.35)
            visibilityOverlay = o
            mapView.addOverlay(o)
        }
    }

    @IBAction private func recenterTapped(_ sender: Any) {
        if let coord = locationManager.location?.coordinate {
            let region = MKCoordinateRegion(center: coord,
                                            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35))
            mapView.setRegion(region, animated: true)
        }
    }

    @IBAction func filtersTapped(_ sender: Any) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let vc = sb.instantiateViewController(withIdentifier: "MapFiltersViewController") as? MapFiltersViewController else {
            return
        }

        vc.delegate = self
        vc.modalPresentationStyle = .pageSheet

        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 18
            sheet.largestUndimmedDetentIdentifier = .medium
        }

        present(vc, animated: true)
    }
}

// MARK: - Filters Delegate
extension MapViewController: MapFiltersDelegate {
    func filtersDidChange(showLight: Bool, showClouds: Bool, nightMode: Bool, showVisibility: Bool) {
        let s = AppSettings.shared
        s.showLightLayer = showLight
        s.showCloudLayer = showClouds
        s.nightMode = nightMode
        s.showVisibility = showVisibility

        applyNightModeIfNeeded()
        refreshOverlays()
    }
}

// MARK: - MKMapViewDelegate
extension MapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let tileOverlay = overlay as? MKTileOverlay {
            let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
            renderer.alpha = 0.55
            return renderer
        }
        if overlay is HeatGridOverlay {
            return HeatGridOverlayRenderer(overlay: overlay)
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    //
    //    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
    //        overlayRefreshWorkItem?.cancel()
    //
    //        let work = DispatchWorkItem { [weak self] in
    //            self?.refreshOverlays()
    //        }
    //        overlayRefreshWorkItem = work
    //        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    //    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        refreshOverlays()
        //        fetchWeatherForVisibleRegion()
    }
    
    //    private func fetchWeatherForVisibleRegion() {
    //        let region = mapView.region
    //        print("Fetching weather for region: \(region.center)")
    //        Task {
    //            await WeatherService.shared.fetchGrid(for: region, steps: 14)
    //            print("Weather fetch complete")
    //            await MainActor.run {
    //                self.refreshOverlays()  // redraw with real data once fetched
    //            }
    //        }
    //    }
    //}
    
}
// MARK: - CLLocationManagerDelegate
extension MapViewController: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !didSetInitialRegion else { return }
        guard let loc = locations.last else { return }

        didSetInitialRegion = true

        let region = MKCoordinateRegion(
            center: loc.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
        mapView.setRegion(region, animated: true)
    }
}
