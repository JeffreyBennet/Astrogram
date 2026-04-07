import UIKit
import FirebaseAuth

final class PostDetailViewController: UIViewController {

    var post: AstroPost!
    var cachedImage: UIImage?
    var onPostUpdated: (() -> Void)?

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let contentStack = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let starButton = UIButton(type: .system)
    private let starCountLabel = UILabel()
    private var isStarred = false
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private var isOwner: Bool {
        Auth.auth().currentUser?.uid == post.userId
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
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
        scrollView.backgroundColor = .black
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
        imageView.backgroundColor = .black
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
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        // Edit/Delete button for owner
        if isOwner {
            let editButton = UIButton(type: .system)
            editButton.translatesAutoresizingMaskIntoConstraints = false
            let editConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            editButton.setImage(UIImage(systemName: "ellipsis.circle.fill", withConfiguration: editConfig), for: .normal)
            editButton.tintColor = .white
            editButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
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

        // Star button (bottom-left overlay)
        starButton.translatesAutoresizingMaskIntoConstraints = false
        starButton.addTarget(self, action: #selector(starTapped), for: .touchUpInside)
        view.addSubview(starButton)

        starCountLabel.translatesAutoresizingMaskIntoConstraints = false
        starCountLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        starCountLabel.textColor = .white
        view.addSubview(starCountLabel)

        NSLayoutConstraint.activate([
            starButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            starButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            starButton.widthAnchor.constraint(equalToConstant: 44),
            starButton.heightAnchor.constraint(equalToConstant: 44),
            starCountLabel.centerYAnchor.constraint(equalTo: starButton.centerYAnchor),
            starCountLabel.leadingAnchor.constraint(equalTo: starButton.trailingAnchor, constant: 4)
        ])

        updateStarAppearance()

        // Activity indicator
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .white
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
        // Title
        let titleLabel = UILabel()
        titleLabel.text = post.title
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        metaStack.addArrangedSubview(titleLabel)

        // Author & date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let authorLabel = UILabel()
        authorLabel.text = "by \(post.userEmail)  •  \(dateFormatter.string(from: post.timestamp))"
        authorLabel.font = .systemFont(ofSize: 13)
        authorLabel.textColor = .lightGray
        authorLabel.numberOfLines = 0
        metaStack.addArrangedSubview(authorLabel)

        // Description
        if !post.description.isEmpty {
            let descLabel = UILabel()
            descLabel.text = post.description
            descLabel.font = .systemFont(ofSize: 16)
            descLabel.textColor = UIColor.white.withAlphaComponent(0.9)
            descLabel.numberOfLines = 0
            metaStack.addArrangedSubview(descLabel)
        }

        // Divider
        let divider = UIView()
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        metaStack.addArrangedSubview(divider)

        // Camera settings section
        let hasSettings = !post.camera.isEmpty || !post.iso.isEmpty || !post.exposure.isEmpty || !post.focalLength.isEmpty
        if hasSettings {
            let settingsTitle = UILabel()
            settingsTitle.text = "Camera Settings"
            settingsTitle.font = .systemFont(ofSize: 16, weight: .semibold)
            settingsTitle.textColor = .white
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
            locDivider.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            locDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
            metaStack.addArrangedSubview(locDivider)

            metaStack.addArrangedSubview(makeMetaRow(icon: "mappin.and.ellipse", label: "Location", value: post.locationName))
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
        labelText.textColor = .lightGray
        labelText.setContentHuggingPriority(.required, for: .horizontal)

        let valueText = UILabel()
        valueText.text = value
        valueText.font = .systemFont(ofSize: 14)
        valueText.textColor = .white
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
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        starButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        starButton.tintColor = isStarred ? .systemYellow : .white
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
                            latitude: self.post.latitude,
                            longitude: self.post.longitude,
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
}

// MARK: - Edit Post View Controller

final class EditPostViewController: UIViewController {

    var post: AstroPost!
    var onSave: (([String: Any]) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let titleField = UITextField()
    private let descriptionField = UITextView()
    private let cameraField = UITextField()
    private let isoField = UITextField()
    private let exposureField = UITextField()
    private let focalLengthField = UITextField()
    private let locationField = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        populateFields()

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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

        let header = UILabel()
        header.text = "Edit Post"
        header.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(header)

        styleField(titleField, placeholder: "Title")
        stack.addArrangedSubview(titleField)

        descriptionField.font = .systemFont(ofSize: 16)
        descriptionField.layer.borderColor = UIColor.separator.cgColor
        descriptionField.layer.borderWidth = 1
        descriptionField.layer.cornerRadius = 8
        descriptionField.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        descriptionField.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        descriptionField.backgroundColor = .secondarySystemBackground
        stack.addArrangedSubview(descriptionField)

        let descHint = UILabel()
        descHint.text = "Description"
        descHint.font = .systemFont(ofSize: 12)
        descHint.textColor = .secondaryLabel
        stack.addArrangedSubview(descHint)

        styleField(cameraField, placeholder: "Camera")
        stack.addArrangedSubview(cameraField)

        let settingsRow = UIStackView()
        settingsRow.axis = .horizontal
        settingsRow.spacing = 12
        settingsRow.distribution = .fillEqually
        styleField(isoField, placeholder: "ISO")
        styleField(exposureField, placeholder: "Exposure")
        styleField(focalLengthField, placeholder: "Focal Length")
        settingsRow.addArrangedSubview(isoField)
        settingsRow.addArrangedSubview(exposureField)
        settingsRow.addArrangedSubview(focalLengthField)
        stack.addArrangedSubview(settingsRow)

        styleField(locationField, placeholder: "Location")
        stack.addArrangedSubview(locationField)

        let saveButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "Save Changes"
        config.baseBackgroundColor = .systemIndigo
        config.cornerStyle = .large
        saveButton.configuration = config
        saveButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stack.addArrangedSubview(saveButton)
    }

    private func styleField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.backgroundColor = .secondarySystemBackground
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func populateFields() {
        titleField.text = post.title
        descriptionField.text = post.description
        cameraField.text = post.camera
        isoField.text = post.iso
        exposureField.text = post.exposure
        focalLengthField.text = post.focalLength
        locationField.text = post.locationName
    }

    @objc private func saveTapped() {
        guard let title = titleField.text, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            let alert = UIAlertController(title: "Error", message: "Title is required", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let fields: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespaces),
            "description": descriptionField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            "camera": cameraField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            "iso": isoField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            "exposure": exposureField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            "focalLength": focalLengthField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            "locationName": locationField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        ]

        onSave?(fields)
        dismiss(animated: true)
    }
}
