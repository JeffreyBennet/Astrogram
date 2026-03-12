import UIKit
import MapKit
import CoreLocation

final class MapViewController: UIViewController {

    @IBOutlet private weak var mapView: MKMapView!
    @IBOutlet weak var filtersButton: UIBarButtonItem!
    
    private let locationManager = CLLocationManager()

    private var cloudTileOverlay: MKTileOverlay?
    private var rainTileOverlay: MKTileOverlay?
    
    private var didSetInitialRegion = false
    private var overlayRefreshWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Astrogram"

        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = true

        configureLocation()
        applyNightModeIfNeeded()

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

        let fallback = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)

        let coord = locationManager.location?.coordinate ?? fallback

        let region = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7)
        )

        mapView.setRegion(region, animated: false)
    }

    private func applyNightModeIfNeeded() {
        overrideUserInterfaceStyle = .dark
        mapView.overrideUserInterfaceStyle = .dark
        mapView.mapType = .mutedStandard
    }

    private func refreshOverlays() {
        // Clear overlays
        mapView.removeOverlays(mapView.overlays)
        cloudTileOverlay = nil
        rainTileOverlay = nil

        // Show cloud overlay when toggle is on
        if AppSettings.shared.showCloudLayer {
            let tileOverlay = VisibilityService.shared.weatherLayer(type: .clouds)
            cloudTileOverlay = tileOverlay
            mapView.addOverlay(tileOverlay, level: .aboveLabels)
        }
        
        // Show rain overlay when toggle is on
        if AppSettings.shared.showRainLayer {
            let tileOverlay = VisibilityService.shared.weatherLayer(type: .precipitation)
            rainTileOverlay = tileOverlay
            mapView.addOverlay(tileOverlay, level: .aboveLabels)
        }
    }

    @IBAction private func recenterTapped(_ sender: Any) {
        if let coord = locationManager.location?.coordinate {

            let region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
            )

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

    func filtersDidChange(showLight: Bool, showClouds: Bool, showRain: Bool, nightMode: Bool) {

        let s = AppSettings.shared
        s.showCloudLayer = showClouds
        s.showRainLayer = showRain
        s.nightMode = nightMode

        applyNightModeIfNeeded()
        refreshOverlays()
    }
}

// MARK: - MKMapViewDelegate
extension MapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {

        if let tileOverlay = overlay as? MKTileOverlay {
            let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
            renderer.alpha = 0.75
            return renderer
        }

        return MKOverlayRenderer(overlay: overlay)
    }
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
