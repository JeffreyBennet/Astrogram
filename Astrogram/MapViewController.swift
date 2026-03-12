import UIKit
import MapKit
import CoreLocation

final class MapViewController: UIViewController {

    @IBOutlet private weak var mapView: MKMapView!
    @IBOutlet weak var filtersButton: UIBarButtonItem!

    private let locationManager = CLLocationManager()

    private var visibilityOverlay: HeatGridOverlay?
    private var cloudTileOverlay: MKTileOverlay?
    private var rainTileOverlay: MKTileOverlay?

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
        // Remove cloud/rain overlays (recreated each time since they're cheap tile URLs)
        if let ct = cloudTileOverlay { mapView.removeOverlay(ct) }
        if let rt = rainTileOverlay { mapView.removeOverlay(rt) }
        cloudTileOverlay = nil
        rainTileOverlay = nil

        let s = AppSettings.shared

        // Light pollution: persistent, only add/remove on toggle
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

        // Cloud layer
        if s.showCloudLayer {
            let tileOverlay = VisibilityService.shared.weatherLayer(type: .clouds)
            cloudTileOverlay = tileOverlay
            mapView.addOverlay(tileOverlay, level: .aboveLabels)
        }

        // Rain layer
        if s.showRainLayer {
            let tileOverlay = VisibilityService.shared.weatherLayer(type: .precipitation)
            rainTileOverlay = tileOverlay
            mapView.addOverlay(tileOverlay, level: .aboveLabels)
        }

        // Visibility overlay: persistent (world-bounded), only add/remove on toggle
        if s.showVisibility && visibilityOverlay == nil {
            let o = HeatGridOverlay(kind: .visibility, opacity: 0.35)
            visibilityOverlay = o
            mapView.addOverlay(o)
            preloadWeatherData()
            WeatherService.shared.startCrawling(from: mapView.region.center)
        } else if !s.showVisibility, let o = visibilityOverlay {
            mapView.removeOverlay(o)
            visibilityOverlay = nil
        }
    }

    /// Preload weather data for the visible area + surrounding region so
    /// tiles render with real data instead of being empty.
    private func preloadWeatherData() {
        let region = mapView.region
        let latPad = region.span.latitudeDelta * 0.6
        let lonPad = region.span.longitudeDelta * 0.6
        let step = 0.25

        var coords: [CLLocationCoordinate2D] = []
        var lat = region.center.latitude - latPad
        while lat <= region.center.latitude + latPad {
            var lon = region.center.longitude - lonPad
            while lon <= region.center.longitude + lonPad {
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                lon += step
            }
            lat += step
        }

        Task {
            await WeatherService.shared.fetchCoordinates(coords)
            await MainActor.run {
                if let overlay = self.visibilityOverlay {
                    self.mapView.renderer(for: overlay)?.setNeedsDisplay(self.mapView.visibleMapRect)
                }
            }
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

    func filtersDidChange(showLight: Bool, showClouds: Bool, showRain: Bool, nightMode: Bool, showVisibility: Bool) {
        let s = AppSettings.shared
        s.showLightLayer = showLight
        s.showCloudLayer = showClouds
        s.showRainLayer = showRain
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
            renderer.alpha = 0.75
            return renderer
        }

        if overlay is HeatGridOverlay {
            return HeatGridOverlayRenderer(overlay: overlay)
        }

        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard visibilityOverlay != nil else { return }
        overlayRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.preloadWeatherData()
            if let center = self?.mapView.region.center {
                WeatherService.shared.startCrawling(from: center)
            }
        }
        overlayRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
