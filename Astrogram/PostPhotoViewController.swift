import UIKit
import FirebaseAuth
import PhotosUI
import MapKit


final class PostPhotoViewController: UIViewController {
    private enum InputLimits {
        static let title = 50
        static let description = 200
        static let camera = 100
        static let isoDigits = 7
        static let focalLengthDigits = 4
        static let exposureDigits = 7
    }

    // MARK: - IBOutlets

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var selectPhotoButton: UIButton!
    @IBOutlet weak var titleField: UITextField!
    @IBOutlet weak var descriptionField: UITextView!
    @IBOutlet weak var cameraField: UITextField!
    @IBOutlet weak var isoField: UITextField!
    @IBOutlet weak var exposureField: UITextField!
    @IBOutlet weak var focalLengthField: UITextField!
    @IBOutlet weak var locationField: UITextField!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var postButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    private var selectedImage: UIImage?
    private var selectedCoordinate: CLLocationCoordinate2D?
    private var selectedPlaceName: String?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Post"
        descriptionField.layer.borderColor = UIColor.separator.cgColor
        descriptionField.layer.borderWidth = 1
        descriptionField.layer.cornerRadius = 8
        imageView.layer.cornerRadius = 12

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        configureLocationPicker()
        titleField.delegate = self
        descriptionField.delegate = self
        cameraField.delegate = self
        isoField.delegate = self
        focalLengthField.delegate = self
        exposureField.delegate = self
    }

    // MARK: - IBActions

    @IBAction func selectPhotoTapped(_ sender: Any) {
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
        if source == .camera {
            //camera can still use UIIMagePicker.. no need for exif
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = self
            present(picker, animated: true)
        //this is for maintaining metadata
        } else {
            var config = PHPickerConfiguration(photoLibrary: .shared())
            config.selectionLimit = 1
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            present(picker, animated: true)
        }
    }
    @IBAction func postTapped(_ sender: Any) {
        view.endEditing(true)

        guard let image = selectedImage else {
            statusLabel.text = "Please select a photo"
            return
        }
        guard let title = titleField.text, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

    @IBAction func setLocationTapped(_ sender: Any) {
        presentMapPicker()
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

    private func presentMapPicker() {
        let picker = MapPickerViewController()
        picker.delegate = self
        picker.initialCoordinate = selectedCoordinate
        picker.initialPlaceName = selectedPlaceName
        let navigationController = UINavigationController(rootViewController: picker)
        present(navigationController, animated: true)
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

    private func createPostDocument(userId: String, userEmail: String, imageURL: String, imagePath: String) {
        let normalizedTitle = (titleField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(InputLimits.title)
        let normalizedDescription = (descriptionField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(InputLimits.description)

        let post = AstroPost(
            id: nil,
            userId: userId,
            userEmail: userEmail,
            imageURL: imageURL,
            imagePath: imagePath,
            title: String(normalizedTitle),
            description: String(normalizedDescription),
            camera: String((cameraField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(InputLimits.camera)),
            iso: isoField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            exposure: exposureField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            focalLength: focalLengthField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            locationName: selectedPlaceName ?? "",
            latitude: selectedCoordinate?.latitude,
            longitude: selectedCoordinate?.longitude,
            timestamp: Date(),
            starCount: 0
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
            self.tabBarController?.selectedIndex = 3
        })
        present(alert, animated: true)
    }

    private func resetForm() {
        selectedImage = nil
        imageView.image = nil
        titleField.text = ""
        descriptionField.text = ""
        cameraField.text = ""
        isoField.text = ""
        exposureField.text = ""
        focalLengthField.text = ""
        locationField.text = ""
        selectedCoordinate = nil
        selectedPlaceName = nil
        statusLabel.text = ""
    }

    private func setPosting(_ posting: Bool) {
        postButton.isEnabled = !posting
        selectPhotoButton.isEnabled = !posting
        if posting {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
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
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
extension PostPhotoViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }

        ImageMetadataExtractor.extract(from: result) { [weak self] image, metadata in
            guard let self else { return }
            self.selectedImage = image
            self.imageView.image = image

            if let meta = metadata {
                let make                    = meta.cameraMake ?? ""
                let model                   = meta.cameraModel ?? ""
                self.cameraField.text = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
                
                self.isoField.text          = meta.isoFormatted ?? ""
                self.exposureField.text     = meta.shutterSpeedFormatted ?? ""
                self.focalLengthField.text = meta.focalLengthFormatted ?? ""
            }
        }
    }
}

extension PostPhotoViewController: UITextFieldDelegate {
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
            let digits = normalizedDigits(from: updatedText, maxDigits: InputLimits.isoDigits)
            textField.text = digits
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

extension PostPhotoViewController: MapPickerDelegate {
    func mapPickerDidSelect(coordinate: CLLocationCoordinate2D, placeName: String) {
        selectedCoordinate = coordinate
        selectedPlaceName = placeName
        locationField.text = placeName
    }
}

extension PostPhotoViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard textView == descriptionField else { return true }
        let currentText = textView.text ?? ""
        guard let textRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: textRange, with: text)
        return updatedText.count <= InputLimits.description
    }
}
