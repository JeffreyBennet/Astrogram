import UIKit
import MapKit

protocol MapPickerDelegate: AnyObject {
    func mapPickerDidSelect(coordinate: CLLocationCoordinate2D, placeName: String)
}

final class MapPickerViewController: UIViewController {
    weak var delegate: MapPickerDelegate?

    private let mapView = MKMapView()
    private let completer = MKLocalSearchCompleter()
    private let resultsController = MapSearchResultsViewController()

    var initialCoordinate: CLLocationCoordinate2D?
    var initialPlaceName: String?

    private var droppedAnnotation: MKPointAnnotation?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pick Location"
        view.backgroundColor = .systemBackground

        configureMap()
        configureSearch()
        configureNavigationItems()

        if let initialCoordinate {
            dropPin(at: initialCoordinate)
            let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            mapView.setRegion(MKCoordinateRegion(center: initialCoordinate, span: span), animated: false)
        }
    }

    private func configureMap() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        view.addSubview(mapView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)
    }

    private func configureSearch() {
        completer.delegate = self
        resultsController.onSelection = { [weak self] completion in
            self?.search(with: completion)
        }

        let searchController = UISearchController(searchResultsController: resultsController)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = true
        searchController.searchBar.placeholder = "Search for a place"
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    private func configureNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Use",
            style: .plain,
            target: self,
            action: #selector(useTapped)
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    private func search(with completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        MKLocalSearch(request: request).start { [weak self] response, _ in
            guard let self, let coordinate = response?.mapItems.first?.location.coordinate else { return }
            self.dropPin(at: coordinate)
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            self.mapView.setRegion(region, animated: true)
            self.navigationItem.searchController?.isActive = false
        }
    }

    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        if let droppedAnnotation {
            mapView.removeAnnotation(droppedAnnotation)
        }

        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = initialPlaceName
        droppedAnnotation = annotation
        mapView.addAnnotation(annotation)
        mapView.selectAnnotation(annotation, animated: true)
        navigationItem.rightBarButtonItem?.isEnabled = true
    }

    private func resolvePlaceName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String) -> Void) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            completion(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
            return
        }

        Task {
            let mapItems = try? await request.mapItems
            let mapItem = mapItems?.first
            let addressRepresentations = mapItem?.addressRepresentations
            let city = addressRepresentations?.cityName
            let cityWithContext = addressRepresentations?.cityWithContext
            let shortAddress = mapItem?.address?.shortAddress
            let name = mapItem?.name

            if let cityWithContext, !cityWithContext.isEmpty {
                completion(cityWithContext)
                return
            }
            if let city {
                completion(city)
                return
            }
            if let shortAddress, !shortAddress.isEmpty {
                completion(shortAddress)
                return
            }
            if let name, !name.isEmpty {
                completion(name)
                return
            }
            completion(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        dropPin(at: coordinate)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func useTapped() {
        guard let coordinate = droppedAnnotation?.coordinate else { return }
        resolvePlaceName(for: coordinate) { [weak self] placeName in
            guard let self else { return }
            DispatchQueue.main.async {
                self.delegate?.mapPickerDidSelect(coordinate: coordinate, placeName: placeName)
                self.dismiss(animated: true)
            }
        }
    }
}

extension MapPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        completer.queryFragment = searchController.searchBar.text ?? ""
    }
}

extension MapPickerViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        resultsController.results = completer.results
    }
}

private final class MapSearchResultsViewController: UITableViewController {
    var results: [MKLocalSearchCompletion] = [] {
        didSet { tableView.reloadData() }
    }

    var onSelection: ((MKLocalSearchCompletion) -> Void)?

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SearchResultCell")
        let result = results[indexPath.row]
        cell.textLabel?.text = result.title
        cell.detailTextLabel?.text = result.subtitle
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelection?(results[indexPath.row])
    }
}
