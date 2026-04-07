import UIKit

protocol FeedFilterDelegate: AnyObject {
    func filtersDidApply(_ filter: FeedFilter)
}

final class FeedFilterViewController: UIViewController {

    weak var delegate: FeedFilterDelegate?
    var currentFilter = FeedFilter()

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let myPostsSwitch = UISwitch()
    private let sortSegment = UISegmentedControl(items: ["Newest", "Oldest"])
    private let cameraPicker = UIPickerView()
    private let cameraField = UITextField()
    private let searchField = UITextField()
    private let startDatePicker = UIDatePicker()
    private let endDatePicker = UIDatePicker()
    private let startDateSwitch = UISwitch()
    private let endDateSwitch = UISwitch()

    private var cameraOptions: [String] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        loadCurrentFilter()
        fetchCameraOptions()
    }

    // MARK: - Setup

    private func setupUI() {
        // Button row pinned to bottom
        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = UIButton(type: .system)
        var resetConfig = UIButton.Configuration.tinted()
        resetConfig.title = "Reset"
        resetConfig.baseBackgroundColor = .systemGray
        resetButton.configuration = resetConfig
        resetButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        let applyButton = UIButton(type: .system)
        var applyConfig = UIButton.Configuration.filled()
        applyConfig.title = "Apply Filters"
        applyConfig.baseBackgroundColor = .systemIndigo
        applyButton.configuration = applyConfig
        applyButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        applyButton.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)

        buttonRow.addArrangedSubview(resetButton)
        buttonRow.addArrangedSubview(applyButton)
        view.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            buttonRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        // Scroll view above the buttons
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -8)
        ])

        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Filters"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(titleLabel)

        // Search
        searchField.placeholder = "Search title, description, or location..."
        searchField.borderStyle = .roundedRect
        searchField.font = .systemFont(ofSize: 16)
        searchField.backgroundColor = .secondarySystemBackground
        searchField.clearButtonMode = .whileEditing
        searchField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(searchField)

        // My posts only
        stack.addArrangedSubview(makeSwitchRow("My Posts Only", toggle: myPostsSwitch))

        // Sort
        let sortLabel = UILabel()
        sortLabel.text = "Sort By"
        sortLabel.font = .systemFont(ofSize: 16, weight: .medium)
        stack.addArrangedSubview(sortLabel)

        sortSegment.selectedSegmentIndex = 0
        stack.addArrangedSubview(sortSegment)

        // Camera filter
        let cameraLabel = UILabel()
        cameraLabel.text = "Camera"
        cameraLabel.font = .systemFont(ofSize: 16, weight: .medium)
        stack.addArrangedSubview(cameraLabel)

        cameraField.placeholder = "All cameras"
        cameraField.borderStyle = .roundedRect
        cameraField.font = .systemFont(ofSize: 16)
        cameraField.backgroundColor = .secondarySystemBackground
        cameraField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        cameraField.inputView = cameraPicker
        cameraPicker.delegate = self
        cameraPicker.dataSource = self

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let doneBtn = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(cameraPickerDone))
        let clearBtn = UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(cameraPickerClear))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.items = [clearBtn, flex, doneBtn]
        cameraField.inputAccessoryView = toolbar

        stack.addArrangedSubview(cameraField)

        // Date range
        let dateLabel = UILabel()
        dateLabel.text = "Date Range"
        dateLabel.font = .systemFont(ofSize: 16, weight: .medium)
        stack.addArrangedSubview(dateLabel)

        // Start date
        let startRow = UIStackView()
        startRow.axis = .horizontal
        startRow.spacing = 8
        startRow.alignment = .center
        let startLabel = UILabel()
        startLabel.text = "From"
        startLabel.font = .systemFont(ofSize: 15)
        startLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        startDateSwitch.isOn = false
        startDateSwitch.addTarget(self, action: #selector(startDateToggled), for: .valueChanged)
        startDatePicker.datePickerMode = .date
        startDatePicker.preferredDatePickerStyle = .compact
        startDatePicker.isEnabled = false
        startDatePicker.alpha = 0.4
        startRow.addArrangedSubview(startLabel)
        startRow.addArrangedSubview(startDateSwitch)
        startRow.addArrangedSubview(startDatePicker)
        stack.addArrangedSubview(startRow)

        // End date
        let endRow = UIStackView()
        endRow.axis = .horizontal
        endRow.spacing = 8
        endRow.alignment = .center
        let endLabel = UILabel()
        endLabel.text = "To"
        endLabel.font = .systemFont(ofSize: 15)
        endLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        endDateSwitch.isOn = false
        endDateSwitch.addTarget(self, action: #selector(endDateToggled), for: .valueChanged)
        endDatePicker.datePickerMode = .date
        endDatePicker.preferredDatePickerStyle = .compact
        endDatePicker.isEnabled = false
        endDatePicker.alpha = 0.4
        endRow.addArrangedSubview(endLabel)
        endRow.addArrangedSubview(endDateSwitch)
        endRow.addArrangedSubview(endDatePicker)
        stack.addArrangedSubview(endRow)

    }

    private func makeSwitchRow(_ text: String, toggle: UISwitch) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16)
        row.addArrangedSubview(label)
        row.addArrangedSubview(toggle)
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return row
    }

    // MARK: - Load Current Filter State

    private func loadCurrentFilter() {
        myPostsSwitch.isOn = currentFilter.myPostsOnly
        sortSegment.selectedSegmentIndex = currentFilter.sortBy.rawValue
        searchField.text = currentFilter.searchText
        cameraField.text = currentFilter.camera

        if let start = currentFilter.startDate {
            startDateSwitch.isOn = true
            startDatePicker.date = start
            startDatePicker.isEnabled = true
            startDatePicker.alpha = 1
        }
        if let end = currentFilter.endDate {
            endDateSwitch.isOn = true
            endDatePicker.date = end
            endDatePicker.isEnabled = true
            endDatePicker.alpha = 1
        }
    }

    private func fetchCameraOptions() {
        FirebasePostService.shared.fetchCameraOptions { [weak self] cameras in
            DispatchQueue.main.async {
                self?.cameraOptions = cameras
                self?.cameraPicker.reloadAllComponents()
            }
        }
    }

    // MARK: - Actions

    @objc private func startDateToggled(_ sender: UISwitch) {
        startDatePicker.isEnabled = sender.isOn
        startDatePicker.alpha = sender.isOn ? 1 : 0.4
    }

    @objc private func endDateToggled(_ sender: UISwitch) {
        endDatePicker.isEnabled = sender.isOn
        endDatePicker.alpha = sender.isOn ? 1 : 0.4
    }

    @objc private func cameraPickerDone() {
        cameraField.resignFirstResponder()
    }

    @objc private func cameraPickerClear() {
        cameraField.text = nil
        cameraField.resignFirstResponder()
    }

    @objc private func resetTapped() {
        delegate?.filtersDidApply(FeedFilter())
        dismiss(animated: true)
    }

    @objc private func applyTapped() {
        var filter = FeedFilter()
        filter.myPostsOnly = myPostsSwitch.isOn
        filter.sortBy = FeedFilter.SortOrder(rawValue: sortSegment.selectedSegmentIndex) ?? .newest
        filter.camera = cameraField.text
        filter.searchText = searchField.text
        filter.startDate = startDateSwitch.isOn ? startDatePicker.date : nil
        filter.endDate = endDateSwitch.isOn ? endDatePicker.date : nil

        delegate?.filtersDidApply(filter)
        dismiss(animated: true)
    }
}

// MARK: - UIPickerView

extension FeedFilterViewController: UIPickerViewDelegate, UIPickerViewDataSource {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        cameraOptions.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        cameraOptions[row]
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        guard row < cameraOptions.count else { return }
        cameraField.text = cameraOptions[row]
    }
}
