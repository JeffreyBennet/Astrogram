import UIKit
import FirebaseAuth
import MapKit

final class PostDetailViewController: UIViewController {

    var post: AstroPost!
    var cachedImage: UIImage?
    var onPostUpdated: (() -> Void)?
    var allowsEditing: Bool = false

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let contentStack = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let starButton = UIButton(type: .system)
    private let starCountLabel = UILabel()
    private let starRow = UIStackView()
    private let starRowContainer = UIView()
    private var isStarred = false
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private var isOwner: Bool {
        Auth.auth().currentUser?.uid == post.userId
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        populateData()
        checkStarStatus()
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Setup

    private func setupUI() {
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .systemBackground
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Content stack
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        // Image
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .secondarySystemBackground
        imageView.clipsToBounds = true
        contentStack.addArrangedSubview(imageView)

        // Constrain image height after it's in the view hierarchy
        let imageHeight = imageView.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 1.0)
        imageHeight.priority = .defaultHigh
        imageHeight.isActive = true

        // Metadata container with padding
        let metaContainer = UIView()
        metaContainer.backgroundColor = .clear
        let metaStack = UIStackView()
        metaStack.axis = .vertical
        metaStack.spacing = 12
        metaStack.alignment = .fill
        metaStack.translatesAutoresizingMaskIntoConstraints = false
        metaContainer.addSubview(metaStack)
        NSLayoutConstraint.activate([
            metaStack.topAnchor.constraint(equalTo: metaContainer.topAnchor),
            metaStack.leadingAnchor.constraint(equalTo: metaContainer.leadingAnchor, constant: 16),
            metaStack.trailingAnchor.constraint(equalTo: metaContainer.trailingAnchor, constant: -16),
            metaStack.bottomAnchor.constraint(equalTo: metaContainer.bottomAnchor)
        ])
        metaStack.tag = 100
        contentStack.addArrangedSubview(metaContainer)

        // Close button (overlay on top)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        // Edit/Delete button - only when allowsEditing is true (Profile tab)
        if allowsEditing && isOwner {
            let editButton = UIButton(type: .system)
            editButton.translatesAutoresizingMaskIntoConstraints = false
            let editConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            editButton.setImage(UIImage(systemName: "ellipsis.circle.fill", withConfiguration: editConfig), for: .normal)
            editButton.tintColor = .label
            editButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
            editButton.layer.cornerRadius = 18
            editButton.addTarget(self, action: #selector(editMenuTapped), for: .touchUpInside)
            view.addSubview(editButton)

            NSLayoutConstraint.activate([
                editButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                editButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
                editButton.widthAnchor.constraint(equalToConstant: 36),
                editButton.heightAnchor.constraint(equalToConstant: 36)
            ])
        }

        // Star row (in content, under image)
        starButton.addTarget(self, action: #selector(starTapped), for: .touchUpInside)
        starCountLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        starCountLabel.textColor = .label
        starRow.axis = .horizontal
        starRow.spacing = 4
        starRow.alignment = .center
        starRow.translatesAutoresizingMaskIntoConstraints = false
        starRow.addArrangedSubview(starButton)
        starRow.addArrangedSubview(starCountLabel)
        starRowContainer.addSubview(starRow)
        NSLayoutConstraint.activate([
            starRow.topAnchor.constraint(equalTo: starRowContainer.topAnchor),
            starRow.leadingAnchor.constraint(equalTo: starRowContainer.leadingAnchor),
            starRow.bottomAnchor.constraint(equalTo: starRowContainer.bottomAnchor),
            starRow.trailingAnchor.constraint(lessThanOrEqualTo: starRowContainer.trailingAnchor)
        ])

        updateStarAppearance()

        // Activity indicator
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .label
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
        ])
    }

    // MARK: - Populate

    private func populateData() {
        // Load image
        if let cached = cachedImage {
            imageView.image = cached
        } else {
            activityIndicator.startAnimating()
            if let url = URL(string: post.imageURL) {
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        self?.activityIndicator.stopAnimating()
                        self?.imageView.image = image
                    }
                }.resume()
            }
        }

        // Fill metadata
        guard let metaStack = contentStack.viewWithTag(100) as? UIStackView else { return }
        populateMetaStack(metaStack)
    }

    private func populateMetaStack(_ metaStack: UIStackView) {
        metaStack.addArrangedSubview(starRowContainer)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = post.title
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        metaStack.addArrangedSubview(titleLabel)

        // Author & date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let authorLabel = UILabel()
        authorLabel.text = "by \(post.userEmail)  •  \(dateFormatter.string(from: post.timestamp))"
        authorLabel.font = .systemFont(ofSize: 13)
        authorLabel.textColor = .secondaryLabel
        authorLabel.numberOfLines = 0
        metaStack.addArrangedSubview(authorLabel)

        // Description
        if !post.description.isEmpty {
            let descLabel = UILabel()
            descLabel.text = post.description
            descLabel.font = .systemFont(ofSize: 16)
            descLabel.textColor = .label
            descLabel.numberOfLines = 0
            metaStack.addArrangedSubview(descLabel)
        }

        // Divider
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        metaStack.addArrangedSubview(divider)

        // Camera settings section
        let hasSettings = !post.camera.isEmpty || !post.iso.isEmpty || !post.exposure.isEmpty || !post.focalLength.isEmpty
        if hasSettings {
            let settingsTitle = UILabel()
            settingsTitle.text = "Camera Settings"
            settingsTitle.font = .systemFont(ofSize: 16, weight: .semibold)
            settingsTitle.textColor = .label
            metaStack.addArrangedSubview(settingsTitle)

            let grid = UIStackView()
            grid.axis = .vertical
            grid.spacing = 6

            if !post.camera.isEmpty {
                grid.addArrangedSubview(makeMetaRow(icon: "camera", label: "Camera", value: post.camera))
            }
            if !post.iso.isEmpty {
                grid.addArrangedSubview(makeMetaRow(icon: "dial.low", label: "ISO", value: post.iso))
            }
            if !post.exposure.isEmpty {
                grid.addArrangedSubview(makeMetaRow(icon: "timer", label: "Exposure", value: post.exposure))
            }
            if !post.focalLength.isEmpty {
                grid.addArrangedSubview(makeMetaRow(icon: "scope", label: "Focal Length", value: post.focalLength))
            }

            metaStack.addArrangedSubview(grid)
        }

        // Location
        if !post.locationName.isEmpty {
            let locDivider = UIView()
            locDivider.backgroundColor = .separator
            locDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
            metaStack.addArrangedSubview(locDivider)

            let locationRow = makeMetaRow(icon: "mappin.and.ellipse", label: "Location", value: post.locationName)
            if post.latitude != nil, post.longitude != nil {
                locationRow.isUserInteractionEnabled = true
                locationRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openOnMapTapped)))
            }
            metaStack.addArrangedSubview(locationRow)
        }
    }

    private func makeMetaRow(icon: String, label: String, value: String) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .systemIndigo
        iconView.contentMode = .scaleAspectFit
        iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let labelText = UILabel()
        labelText.text = "\(label):"
        labelText.font = .systemFont(ofSize: 14, weight: .medium)
        labelText.textColor = .secondaryLabel
        labelText.setContentHuggingPriority(.required, for: .horizontal)

        let valueText = UILabel()
        valueText.text = value
        valueText.font = .systemFont(ofSize: 14)
        valueText.textColor = .label
        valueText.numberOfLines = 0

        row.addArrangedSubview(iconView)
        row.addArrangedSubview(labelText)
        row.addArrangedSubview(valueText)

        return row
    }

    // MARK: - Star

    private func checkStarStatus() {
        guard let postId = post.id, let uid = Auth.auth().currentUser?.uid else { return }
        FirebasePostService.shared.isStarred(postId: postId, userId: uid) { [weak self] starred in
            DispatchQueue.main.async {
                self?.isStarred = starred
                self?.updateStarAppearance()
            }
        }
    }

    private func updateStarAppearance() {
        let iconName = isStarred ? "star.fill" : "star"
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        starButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        starButton.tintColor = isStarred ? .systemYellow : .label
        starCountLabel.text = post.starCount > 0 ? "\(post.starCount)" : ""
    }

    @objc private func starTapped() {
        guard let postId = post.id, let uid = Auth.auth().currentUser?.uid else { return }
        starButton.isEnabled = false

        FirebasePostService.shared.toggleStar(postId: postId, userId: uid) { [weak self] result in
            DispatchQueue.main.async {
                self?.starButton.isEnabled = true
                switch result {
                case .success(let nowStarred):
                    self?.isStarred = nowStarred
                    self?.post.starCount += nowStarred ? 1 : -1
                    self?.updateStarAppearance()
                    self?.onPostUpdated?()
                case .failure:
                    break
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func openOnMapTapped() {
        guard let lat = post.latitude, let lon = post.longitude else { return }
        guard let tabBarController = resolveTabBarController() else { return }
        let mapIndex = resolveMapTabIndex(in: tabBarController)
        let payload: [String: Any] = [
            "postId": post.id ?? "",
            "lat": lat,
            "lon": lon,
            "imageURL": post.imageURL
        ]

        tabBarController.selectedIndex = mapIndex
        tabBarController.dismiss(animated: true) {
            NotificationCenter.default.post(name: .showPostOnMap, object: nil, userInfo: payload)
        }
    }

    @objc private func editMenuTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Edit Post", style: .default) { _ in
            self.showEditScreen()
        })

        alert.addAction(UIAlertAction(title: "Delete Post", style: .destructive) { _ in
            self.confirmDelete()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    // MARK: - Edit

    private func showEditScreen() {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let editVC = sb.instantiateViewController(withIdentifier: "EditPostViewController") as? EditPostViewController else { return }
        editVC.post = post
        editVC.onSave = { [weak self] updatedFields in
            self?.saveEdits(updatedFields)
        }
        editVC.modalPresentationStyle = .pageSheet
        if let sheet = editVC.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(editVC, animated: true)
    }

    private func saveEdits(_ fields: [String: Any]) {
        guard let postId = post.id else { return }

        FirebasePostService.shared.updatePost(id: postId, fields: fields) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Update local post fields so detail view reflects changes
                    if let self = self {
                        self.post = AstroPost(
                            id: self.post.id,
                            userId: self.post.userId,
                            userEmail: self.post.userEmail,
                            imageURL: self.post.imageURL,
                            imagePath: self.post.imagePath,
                            title: fields["title"] as? String ?? self.post.title,
                            description: fields["description"] as? String ?? self.post.description,
                            camera: fields["camera"] as? String ?? self.post.camera,
                            iso: fields["iso"] as? String ?? self.post.iso,
                            exposure: fields["exposure"] as? String ?? self.post.exposure,
                            focalLength: fields["focalLength"] as? String ?? self.post.focalLength,
                            locationName: fields["locationName"] as? String ?? self.post.locationName,
                            latitude: fields["latitude"] as? Double ?? self.post.latitude,
                            longitude: fields["longitude"] as? Double ?? self.post.longitude,
                            timestamp: self.post.timestamp,
                            starCount: self.post.starCount
                        )
                        self.onPostUpdated?()
                        self.rebuildMetadata()
                    }
                case .failure(let error):
                    let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
        }
    }

    private func rebuildMetadata() {
        // Remove old metadata and repopulate
        guard let metaContainer = contentStack.arrangedSubviews.last,
              let metaStack = metaContainer.viewWithTag(100) as? UIStackView else { return }
        metaStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        populateMetaStack(metaStack)
    }

    // MARK: - Delete

    private func confirmDelete() {
        let alert = UIAlertController(
            title: "Delete Post",
            message: "Are you sure you want to delete this post? This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.deletePost()
        })
        present(alert, animated: true)
    }

    private func deletePost() {
        activityIndicator.startAnimating()

        FirebasePostService.shared.deletePost(post) { [weak self] result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                switch result {
                case .success:
                    self?.onPostUpdated?()
                    self?.dismiss(animated: true)
                case .failure(let error):
                    let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
        }
    }

    private func resolveTabBarController() -> UITabBarController? {
        if let tab = presentingViewController?.tabBarController {
            return tab
        }
        if let nav = presentingViewController as? UINavigationController,
           let tab = nav.tabBarController {
            return tab
        }
        if let tab = presentingViewController?.view.window?.rootViewController as? UITabBarController {
            return tab
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController,
               let tab = findTabBarController(in: root) {
                return tab
            }
        }
        return nil
    }

    private func resolveMapTabIndex(in tabBarController: UITabBarController) -> Int {
        guard let tabs = tabBarController.viewControllers else { return 2 }
        return tabs.firstIndex(where: { controller in
            if controller.tabBarItem.title == "Map" {
                return true
            }
            if let nav = controller as? UINavigationController {
                return nav.viewControllers.first is MapViewController
            }
            return controller is MapViewController
        }) ?? 2
    }

    private func findTabBarController(in controller: UIViewController) -> UITabBarController? {
        if let tab = controller as? UITabBarController {
            return tab
        }
        if let nav = controller as? UINavigationController {
            for child in nav.viewControllers {
                if let tab = findTabBarController(in: child) {
                    return tab
                }
            }
        }
        for child in controller.children {
            if let tab = findTabBarController(in: child) {
                return tab
            }
        }
        if let presented = controller.presentedViewController {
            return findTabBarController(in: presented)
        }
        return nil
    }
}

// MARK: - Edit Post View Controller

final class EditPostViewController: UIViewController {
    private enum InputLimits {
        static let title = 50
        static let description = 200
        static let camera = 100
        static let isoDigits = 7
        static let focalLengthDigits = 4
        static let exposureDigits = 7
    }

    var post: AstroPost!
    var onSave: (([String: Any]) -> Void)?

    @IBOutlet weak var titleField: UITextField!
    @IBOutlet weak var descriptionField: UITextView!
    @IBOutlet weak var cameraField: UITextField!
    @IBOutlet weak var isoField: UITextField!
    @IBOutlet weak var exposureField: UITextField!
    @IBOutlet weak var focalLengthField: UITextField!
    @IBOutlet weak var locationField: UITextField!

    private var selectedCoordinate: CLLocationCoordinate2D?
    private var selectedPlaceName: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        populateFields()
        configureLocationPicker()
        titleField.delegate = self
        descriptionField.delegate = self
        cameraField.delegate = self
        isoField.delegate = self
        focalLengthField.delegate = self
        exposureField.delegate = self
        configureKeyboardTypes()

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func populateFields() {
        titleField.text = post.title
        descriptionField.text = post.description
        cameraField.text = post.camera
        isoField.text = post.iso
        exposureField.text = post.exposure
        focalLengthField.text = post.focalLength
        locationField.text = post.locationName
        if let lat = post.latitude, let lon = post.longitude {
            selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        selectedPlaceName = post.locationName
    }

    private func configureLocationPicker() {
        locationField.delegate = self
        locationField.placeholder = "Tap to pick on map"
        locationField.tintColor = .clear

        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "map"), for: .normal)
        button.addTarget(self, action: #selector(locationAccessoryTapped), for: .touchUpInside)
        locationField.rightView = button
        locationField.rightViewMode = .always
    }

    @objc private func locationAccessoryTapped() {
        presentMapPicker()
    }

    @IBAction func setLocationTapped(_ sender: Any) {
        presentMapPicker()
    }

    private func presentMapPicker() {
        let picker = MapPickerViewController()
        picker.delegate = self
        picker.initialCoordinate = selectedCoordinate
        picker.initialPlaceName = selectedPlaceName
        let navigationController = UINavigationController(rootViewController: picker)
        present(navigationController, animated: true)
    }

    private func configureKeyboardTypes() {
        isoField.keyboardType = .numberPad
        focalLengthField.keyboardType = .numberPad
        exposureField.keyboardType = .decimalPad
    }

    private func normalizedDigits(from text: String, maxDigits: Int) -> String {
        let digits = text.filter { $0.isWholeNumber }
        return String(digits.prefix(maxDigits))
    }

    private func normalizedExposureValue(from text: String, maxDigits: Int) -> String {
        var result = ""
        var hasDecimalPoint = false
        var digitCount = 0

        for character in text {
            if character.isWholeNumber {
                guard digitCount < maxDigits else { continue }
                result.append(character)
                digitCount += 1
            } else if character == ".", !hasDecimalPoint {
                if result.isEmpty {
                    result = "0"
                }
                result.append(character)
                hasDecimalPoint = true
            }
        }
        return result
    }

    private func formattedFocalLength(from text: String) -> String {
        let digits = normalizedDigits(from: text, maxDigits: InputLimits.focalLengthDigits)
        return digits.isEmpty ? "" : "\(digits)mm"
    }

    private func formattedExposure(from text: String) -> String {
        let normalized = normalizedExposureValue(from: text, maxDigits: InputLimits.exposureDigits)
        return normalized.isEmpty ? "" : "\(normalized)s"
    }

    @IBAction func saveTapped(_ sender: Any) {
        guard let title = titleField.text, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let alert = UIAlertController(title: "Error", message: "Title is required", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let normalizedTitle = String(
            title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(InputLimits.title)
        )
        let normalizedDescription = String(
            (descriptionField.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(InputLimits.description)
        )

        var fields: [String: Any] = [
            "title": normalizedTitle,
            "description": normalizedDescription,
            "camera": String((cameraField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(InputLimits.camera)),
            "iso": isoField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            "exposure": exposureField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            "focalLength": focalLengthField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            "locationName": selectedPlaceName ?? locationField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        ]
        if let coordinate = selectedCoordinate {
            fields["latitude"] = coordinate.latitude
            fields["longitude"] = coordinate.longitude
        }

        onSave?(fields)
        dismiss(animated: true)
    }
}

extension EditPostViewController: UITextFieldDelegate {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField == locationField {
            presentMapPicker()
            return false
        }
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let currentText = textField.text ?? ""
        guard let textRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: textRange, with: string)

        if textField == titleField {
            return updatedText.count <= InputLimits.title
        }

        if textField == cameraField {
            return updatedText.count <= InputLimits.camera
        }

        if textField == isoField {
            textField.text = normalizedDigits(from: updatedText, maxDigits: InputLimits.isoDigits)
            return false
        }

        if textField == focalLengthField {
            if string.isEmpty,
               currentText.hasSuffix("mm"),
               range.location >= max(0, currentText.count - 2) {
                let digits = normalizedDigits(from: currentText, maxDigits: InputLimits.focalLengthDigits)
                let trimmedDigits = String(digits.dropLast())
                textField.text = trimmedDigits.isEmpty ? "" : "\(trimmedDigits)mm"
            } else {
                textField.text = formattedFocalLength(from: updatedText)
            }
            return false
        }

        if textField == exposureField {
            if string.isEmpty,
               currentText.hasSuffix("s"),
               range.location >= max(0, currentText.count - 1) {
                let normalized = normalizedExposureValue(from: currentText, maxDigits: InputLimits.exposureDigits)
                let trimmed = String(normalized.dropLast())
                textField.text = trimmed.isEmpty ? "" : "\(trimmed)s"
            } else {
                textField.text = formattedExposure(from: updatedText)
            }
            return false
        }

        return true
    }
}

extension EditPostViewController: MapPickerDelegate {
    func mapPickerDidSelect(coordinate: CLLocationCoordinate2D, placeName: String) {
        selectedCoordinate = coordinate
        selectedPlaceName = placeName
        locationField.text = placeName
    }
}

extension EditPostViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard textView == descriptionField else { return true }
        let currentText = textView.text ?? ""
        guard let textRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: textRange, with: text)
        return updatedText.count <= InputLimits.description
    }
}
