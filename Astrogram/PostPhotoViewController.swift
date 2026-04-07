import UIKit
import FirebaseAuth

final class PostPhotoViewController: UIViewController {

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let imageView = UIImageView()
    private let selectPhotoButton = UIButton(type: .system)
    private let titleField = UITextField()
    private let descriptionField = UITextView()
    private let cameraField = UITextField()
    private let isoField = UITextField()
    private let exposureField = UITextField()
    private let focalLengthField = UITextField()
    private let locationField = UITextField()
    private let postButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private var selectedImage: UIImage?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Post"
        view.backgroundColor = .systemBackground
        setupUI()
        setupKeyboardDismiss()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        // Image preview
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = .secondarySystemBackground
        imageView.heightAnchor.constraint(equalToConstant: 250).isActive = true

        let placeholderLabel = UILabel()
        placeholderLabel.text = "Tap to select a photo"
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.textAlignment = .center
        placeholderLabel.tag = 999
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        imageView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
        ])

        let imageTap = UITapGestureRecognizer(target: self, action: #selector(selectPhotoTapped))
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(imageTap)

        contentStack.addArrangedSubview(imageView)

        // Select photo button
        var selectConfig = UIButton.Configuration.tinted()
        selectConfig.title = "Choose Photo"
        selectConfig.image = UIImage(systemName: "photo.on.rectangle")
        selectConfig.imagePadding = 8
        selectPhotoButton.configuration = selectConfig
        selectPhotoButton.addTarget(self, action: #selector(selectPhotoTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(selectPhotoButton)

        // Section: Details
        contentStack.addArrangedSubview(makeSectionLabel("Details"))

        // Title
        styleTextField(titleField, placeholder: "Title *")
        contentStack.addArrangedSubview(titleField)

        // Description
        descriptionField.font = .systemFont(ofSize: 16)
        descriptionField.layer.borderColor = UIColor.separator.cgColor
        descriptionField.layer.borderWidth = 1
        descriptionField.layer.cornerRadius = 8
        descriptionField.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        descriptionField.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        descriptionField.backgroundColor = .secondarySystemBackground
        contentStack.addArrangedSubview(descriptionField)

        let descHint = UILabel()
        descHint.text = "Description"
        descHint.font = .systemFont(ofSize: 12)
        descHint.textColor = .secondaryLabel
        contentStack.addArrangedSubview(descHint)

        // Section: Camera Settings
        contentStack.addArrangedSubview(makeSectionLabel("Camera Settings"))

        let cameraRow = UIStackView()
        cameraRow.axis = .horizontal
        cameraRow.spacing = 12
        cameraRow.distribution = .fillEqually

        styleTextField(cameraField, placeholder: "Camera (e.g. Canon EOS R5)")
        contentStack.addArrangedSubview(cameraField)

        let settingsRow = UIStackView()
        settingsRow.axis = .horizontal
        settingsRow.spacing = 12
        settingsRow.distribution = .fillEqually
        styleTextField(isoField, placeholder: "ISO")
        isoField.keyboardType = .numberPad
        styleTextField(exposureField, placeholder: "Exposure (e.g. 30s)")
        styleTextField(focalLengthField, placeholder: "Focal Length")
        settingsRow.addArrangedSubview(isoField)
        settingsRow.addArrangedSubview(exposureField)
        settingsRow.addArrangedSubview(focalLengthField)
        contentStack.addArrangedSubview(settingsRow)

        // Section: Location
        contentStack.addArrangedSubview(makeSectionLabel("Location"))
        styleTextField(locationField, placeholder: "Location name (e.g. Big Bend National Park)")
        contentStack.addArrangedSubview(locationField)

        // Status label
        statusLabel.textColor = .systemRed
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.text = ""
        contentStack.addArrangedSubview(statusLabel)

        // Post button
        var postConfig = UIButton.Configuration.filled()
        postConfig.title = "Post"
        postConfig.cornerStyle = .large
        postConfig.baseBackgroundColor = .systemIndigo
        postButton.configuration = postConfig
        postButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        postButton.addTarget(self, action: #selector(postTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(postButton)

        // Activity indicator
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .label
        return label
    }

    private func styleTextField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.backgroundColor = .secondarySystemBackground
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func setupKeyboardDismiss() {
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    // MARK: - Actions

    @objc private func selectPhotoTapped() {
        let alert = UIAlertController(title: "Select Photo", message: nil, preferredStyle: .actionSheet)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Camera", style: .default) { _ in
                self.presentImagePicker(source: .camera)
            })
        }

        alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
            self.presentImagePicker(source: .photoLibrary)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = selectPhotoButton
        }

        present(alert, animated: true)
    }

    private func presentImagePicker(source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self
        picker.allowsEditing = false
        present(picker, animated: true)
    }

    @objc private func postTapped() {
        view.endEditing(true)

        guard let image = selectedImage else {
            statusLabel.text = "Please select a photo"
            return
        }
        guard let title = titleField.text, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            statusLabel.text = "Please enter a title"
            return
        }
        guard let user = Auth.auth().currentUser else {
            statusLabel.text = "You must be logged in to post"
            return
        }

        statusLabel.text = ""
        setPosting(true)

        FirebasePostService.shared.uploadImage(image) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let upload):
                    self?.createPostDocument(userId: user.uid,
                                             userEmail: user.email ?? "Unknown",
                                             imageURL: upload.url,
                                             imagePath: upload.path)
                case .failure(let error):
                    self?.setPosting(false)
                    self?.statusLabel.text = "Upload failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func createPostDocument(userId: String, userEmail: String, imageURL: String, imagePath: String) {
        let post = AstroPost(
            id: nil,
            userId: userId,
            userEmail: userEmail,
            imageURL: imageURL,
            imagePath: imagePath,
            title: titleField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            description: descriptionField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            camera: cameraField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            iso: isoField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            exposure: exposureField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            focalLength: focalLengthField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            locationName: locationField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            latitude: nil,
            longitude: nil,
            timestamp: Date()
        )

        FirebasePostService.shared.createPost(post) { [weak self] result in
            DispatchQueue.main.async {
                self?.setPosting(false)
                switch result {
                case .success:
                    self?.showSuccessAndReset()
                case .failure(let error):
                    self?.statusLabel.text = "Post failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func showSuccessAndReset() {
        let alert = UIAlertController(title: "Posted!", message: "Your astrophoto has been shared.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.resetForm()
            // Switch to feed tab
            self.tabBarController?.selectedIndex = 0
        })
        present(alert, animated: true)
    }

    private func resetForm() {
        selectedImage = nil
        imageView.image = nil
        imageView.viewWithTag(999)?.isHidden = false
        titleField.text = ""
        descriptionField.text = ""
        cameraField.text = ""
        isoField.text = ""
        exposureField.text = ""
        focalLengthField.text = ""
        locationField.text = ""
        statusLabel.text = ""
    }

    private func setPosting(_ posting: Bool) {
        postButton.isEnabled = !posting
        selectPhotoButton.isEnabled = !posting
        if posting {
            activityIndicator.startAnimating()
            postButton.configuration?.title = "Uploading..."
        } else {
            activityIndicator.stopAnimating()
            postButton.configuration?.title = "Post"
        }
    }
}

// MARK: - UIImagePickerControllerDelegate

extension PostPhotoViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let image = info[.originalImage] as? UIImage {
            selectedImage = image
            imageView.image = image
            imageView.viewWithTag(999)?.isHidden = true
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
