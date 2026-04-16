import UIKit
import MapKit
import CoreLocation

final class MapViewController: UIViewController {

    @IBOutlet private weak var mapView: MKMapView!
    @IBOutlet weak var filtersButton: UIBarButtonItem!
    @IBOutlet weak var nightmodeButton: UIBarButtonItem!
    
    private let locationManager = CLLocationManager()
    private let calculator = VisibilityCalculator()

    private var visibilityOverlay: HeatGridOverlay?
    private var cloudTileOverlay: MKTileOverlay?
    private var rainTileOverlay: MKTileOverlay?

    private var didSetInitialRegion = false
    private var overlayRefreshWorkItem: DispatchWorkItem?
    private var lightPollutionTileOverlay: MKTileOverlay?
    private var postAnnotationsById: [String: PostAnnotation] = [:]
    private var postsById: [String: AstroPost] = [:]
    private let postImageCache = NSCache<NSString, UIImage>()
    private var visibilityTapAnnotation: MKPointAnnotation?
    private var pendingPostSelectionId: String?
    private var pendingPostSelectionCoordinate: CLLocationCoordinate2D?

    override func viewDidLoad() {
        super.viewDidLoad()

        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = true

        configureLocation()
        applyStartupLayer()
        applyNightModeIfNeeded()
        updateNightModeButtonIcon()
        addTapGesture()
        NotificationCenter.default.addObserver(self, selector: #selector(showPostOnMap(_:)), name: .showPostOnMap, object: nil)

        refreshOverlays()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        overlayRefreshWorkItem?.cancel()
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

    private func applyStartupLayer() {
        let s = AppSettings.shared
        switch s.startupLayer {
        case .none:
            break
        case .light:
            s.showLightLayer = true
        case .clouds:
            s.showCloudLayer = true
        case .visibility:
            s.showVisibility = true
        }
    }

    private func applyNightModeIfNeeded() {
        if AppSettings.shared.nightMode {
            overrideUserInterfaceStyle = .dark
            mapView.overrideUserInterfaceStyle = .dark
            mapView.mapType = .mutedStandard
        } else {
            overrideUserInterfaceStyle = .light
            mapView.overrideUserInterfaceStyle = .light
            mapView.mapType = .standard
        }
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

        refreshPostsAnnotations()
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

    private func addTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        mapView.addGestureRecognizer(tap)
    }

    @objc private func mapTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: mapView)
        let coord = mapView.convert(point, toCoordinateFrom: mapView)

        Task {
            let summary = await calculator.summary(at: coord)
            await MainActor.run {
                let title = "Visibility: \(summary.label) (\(summary.overallScore)/100)"
                var parts: [String] = []
                parts.append(String(format: "Cloud cover: %.0f%%", summary.cloudCover * 100))
                parts.append(String(format: "Visibility: %.0f%%", summary.visibility * 100))
                parts.append(String(format: "Humidity: %.0f%%", summary.humidity * 100))
                let subtitle = parts.joined(separator: " · ")
                self.dropPin(at: coord, title: title, subtitle: subtitle)
            }
        }
    }

    private func dropPin(at coord: CLLocationCoordinate2D, title: String, subtitle: String) {
        if let visibilityTapAnnotation {
            mapView.removeAnnotation(visibilityTapAnnotation)
        }
        let pin = MKPointAnnotation()
        pin.coordinate = coord
        pin.title = title
        pin.subtitle = subtitle
        visibilityTapAnnotation = pin
        mapView.addAnnotation(pin)
        mapView.selectAnnotation(pin, animated: true)
    }

    @objc private func showPostOnMap(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let lat = userInfo["lat"] as? Double,
              let lon = userInfo["lon"] as? Double else { return }

        pendingPostSelectionId = userInfo["postId"] as? String
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        pendingPostSelectionCoordinate = coordinate
        AppSettings.shared.showPostsLayer = true

        // Clean up any fallback pin from previous builds/runs.
        let stalePins = mapView.annotations.compactMap { $0 as? MKPointAnnotation }.filter { $0.title == "Selected post" }
        if !stalePins.isEmpty {
            mapView.removeAnnotations(stalePins)
        }

        refreshOverlays()

        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
        mapView.setRegion(region, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.attemptPendingPostSelection()
        }
    }

    private func refreshPostsAnnotations() {
        guard AppSettings.shared.showPostsLayer else {
            let existing = mapView.annotations.compactMap { $0 as? PostAnnotation }
            mapView.removeAnnotations(existing)
            postAnnotationsById.removeAll()
            postsById.removeAll()
            return
        }

        FirebasePostService.shared.fetchRecentPosts(limit: 200) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard case let .success(posts) = result else { return }
                let inRegionPosts = self.filterPostsToVisibleRegion(posts)
                var nextById: [String: PostAnnotation] = [:]
                var nextPostsById: [String: AstroPost] = [:]
                var toAdd: [PostAnnotation] = []

                for post in inRegionPosts {
                    guard let id = post.id, let lat = post.latitude, let lon = post.longitude else { continue }
                    nextPostsById[id] = post
                    if let existing = self.postAnnotationsById[id] {
                        nextById[id] = existing
                    } else {
                        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        let annotation = PostAnnotation(post: post, coordinate: coordinate)
                        nextById[id] = annotation
                        toAdd.append(annotation)
                    }
                }

                let removed = self.postAnnotationsById.keys
                    .filter { nextById[$0] == nil }
                    .compactMap { self.postAnnotationsById[$0] }

                if !removed.isEmpty {
                    self.mapView.removeAnnotations(removed)
                }
                if !toAdd.isEmpty {
                    self.mapView.addAnnotations(toAdd)
                }

                self.postAnnotationsById = nextById
                self.postsById = nextPostsById
                self.attemptPendingPostSelection()
            }
        }
    }

    private func filterPostsToVisibleRegion(_ posts: [AstroPost]) -> [AstroPost] {
        let region = mapView.region
        let minLat = region.center.latitude - (region.span.latitudeDelta / 2)
        let maxLat = region.center.latitude + (region.span.latitudeDelta / 2)
        let minLon = region.center.longitude - (region.span.longitudeDelta / 2)
        let maxLon = region.center.longitude + (region.span.longitudeDelta / 2)

        return posts.filter { post in
            guard let lat = post.latitude, let lon = post.longitude else { return false }
            return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
        }
    }

    private func refreshVisibleRegionData() {
        if visibilityOverlay != nil {
            preloadWeatherData()
            WeatherService.shared.startCrawling(from: mapView.region.center)
        }
        refreshPostsAnnotations()
    }

    private func presentPostDetail(for post: AstroPost) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let detailVC = storyboard.instantiateViewController(withIdentifier: "PostDetailViewController") as? PostDetailViewController else {
            return
        }
        detailVC.post = post
        detailVC.cachedImage = postImageCache.object(forKey: NSString(string: post.imageURL))
        detailVC.modalPresentationStyle = .fullScreen
        present(detailVC, animated: true)
    }

    @objc private func postAnnotationTapped(_ recognizer: UITapGestureRecognizer) {
        guard let view = recognizer.view as? MKAnnotationView,
              let postAnnotation = view.annotation as? PostAnnotation else { return }

        if mapView.selectedAnnotations.contains(where: { ($0 as? PostAnnotation)?.postId == postAnnotation.postId }) {
            presentPostDetail(for: postAnnotation.post)
        } else {
            mapView.selectAnnotation(postAnnotation, animated: true)
        }
    }

    private func makePreviewImageView(image: UIImage?) -> UIImageView {
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 6
        imageView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.image = image
        return imageView
    }

    private func attemptPendingPostSelection() {
        guard let postId = pendingPostSelectionId else { return }

        if let annotation = postAnnotationsById[postId] {
            mapView.selectAnnotation(annotation, animated: true)
            pendingPostSelectionId = nil
            pendingPostSelectionCoordinate = nil
            return
        }

        guard let coordinate = pendingPostSelectionCoordinate else { return }
        let candidate = postAnnotationsById.values.min { lhs, rhs in
            let leftDistance = hypot(lhs.coordinate.latitude - coordinate.latitude, lhs.coordinate.longitude - coordinate.longitude)
            let rightDistance = hypot(rhs.coordinate.latitude - coordinate.latitude, rhs.coordinate.longitude - coordinate.longitude)
            return leftDistance < rightDistance
        }

        if let candidate {
            let distance = hypot(candidate.coordinate.latitude - coordinate.latitude, candidate.coordinate.longitude - coordinate.longitude)
            if distance < 0.01 {
                mapView.selectAnnotation(candidate, animated: true)
                pendingPostSelectionId = nil
                pendingPostSelectionCoordinate = nil
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
    
    // Night mode button pressed
    @IBAction func nightModeButtonTapped(_ sender: Any) {
        let settings = AppSettings.shared
        settings.nightMode.toggle()
        applyNightModeIfNeeded()
        updateNightModeButtonIcon()
    }
    
    private func updateNightModeButtonIcon() {
        if AppSettings.shared.nightMode {
            nightmodeButton.image = UIImage(systemName: "sun.max.fill")
        } else {
            nightmodeButton.image = UIImage(systemName: "moon.stars.fill")
        }
    }
}

// MARK: - Filters Delegate
extension MapViewController: MapFiltersDelegate {

    func filtersDidChange(showLight: Bool, showClouds: Bool, showRain: Bool, showVisibility: Bool, showPosts: Bool) {
        let s = AppSettings.shared
        s.showLightLayer = showLight
        s.showCloudLayer = showClouds
        s.showRainLayer = showRain
        s.showVisibility = showVisibility
        s.showPostsLayer = showPosts

        refreshOverlays()
    }
}

// MARK: - MKMapViewDelegate
extension MapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let tileOverlay = overlay as? MKTileOverlay {
            let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
            renderer.alpha = 0.85
            return renderer
        }

        if overlay is HeatGridOverlay {
            return HeatGridOverlayRenderer(overlay: overlay)
        }

        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }

        if let cluster = annotation as? MKClusterAnnotation {
            let identifier = "PostClusterAnnotationView"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: identifier)
            view.annotation = cluster
            view.markerTintColor = .systemIndigo
            view.glyphText = "\(cluster.memberAnnotations.count)"
            return view
        }

        if let postAnnotation = annotation as? PostAnnotation {
            let identifier = "PostAnnotationView"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: postAnnotation, reuseIdentifier: identifier)
            view.annotation = postAnnotation
            view.canShowCallout = true
            view.clusteringIdentifier = "posts"
            view.markerTintColor = .systemIndigo
            view.leftCalloutAccessoryView = nil
            view.detailCalloutAccessoryView = nil
            view.rightCalloutAccessoryView = nil
            if view.gestureRecognizers?.contains(where: { $0.name == "postAnnotationTap" }) != true {
                let tap = UITapGestureRecognizer(target: self, action: #selector(postAnnotationTapped(_:)))
                tap.name = "postAnnotationTap"
                view.addGestureRecognizer(tap)
            }

            let cacheKey = NSString(string: postAnnotation.post.imageURL)
            if let cached = postImageCache.object(forKey: cacheKey) {
                view.leftCalloutAccessoryView = makePreviewImageView(image: cached)
            } else {
                view.leftCalloutAccessoryView = makePreviewImageView(image: nil)
                if let url = URL(string: postAnnotation.post.imageURL) {
                    URLSession.shared.dataTask(with: url) { [weak self, weak view] data, _, _ in
                        guard let self, let data, let image = UIImage(data: data) else { return }
                        self.postImageCache.setObject(image, forKey: cacheKey)
                        DispatchQueue.main.async {
                            if let view, (view.annotation as? PostAnnotation)?.postId == postAnnotation.postId {
                                view.leftCalloutAccessoryView = self.makePreviewImageView(image: image)
                            }
                        }
                    }.resume()
                }
            }
            return view
        }

        return nil
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let postAnnotation = view.annotation as? PostAnnotation else { return }
        presentPostDetail(for: postAnnotation.post)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        overlayRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshVisibleRegionData()
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
