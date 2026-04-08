import UIKit

protocol FeedFilterDelegate: AnyObject {
    func filtersDidApply(_ filter: FeedFilter)
}

final class FeedFilterViewController: UIViewController {

    weak var delegate: FeedFilterDelegate?
    var currentFilter = FeedFilter()

    // MARK: - IBOutlets

    @IBOutlet weak var searchField: UITextField!
    @IBOutlet weak var sortSegment: UISegmentedControl!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        loadCurrentFilter()
    }

    private func loadCurrentFilter() {
        sortSegment.selectedSegmentIndex = currentFilter.sortBy.rawValue
        searchField.text = currentFilter.searchText
    }

    // MARK: - IBActions

    @IBAction func resetTapped(_ sender: Any) {
        delegate?.filtersDidApply(FeedFilter())
        dismiss(animated: true)
    }

    @IBAction func applyTapped(_ sender: Any) {
        var filter = FeedFilter()
        filter.sortBy = FeedFilter.SortOrder(rawValue: sortSegment.selectedSegmentIndex) ?? .newest
        filter.searchText = searchField.text

        delegate?.filtersDidApply(filter)
        dismiss(animated: true)
    }
}
