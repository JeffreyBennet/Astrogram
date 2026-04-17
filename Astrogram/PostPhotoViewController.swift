import UIKit
import FirebaseAuth
import PhotosUI
import MapKit


final class PostPhotoViewController: UIViewController {

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

    private func createPostDocument(userId: String, userEmail: String, imageURL: String, imagePath: String) {
        let post = AstroPost(
            id: nil,
            userId: userId,
            userEmail: userEmail,
            imageURL: imageURL,
            imagePath: imagePath,
            title: titleField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            description: descriptionField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            camera: cameraField.text?.trimmingCharacters(in: .whitespaces) ?? "",
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
}

extension PostPhotoViewController: MapPickerDelegate {
    func mapPickerDidSelect(coordinate: CLLocationCoordinate2D, placeName: String) {
        selectedCoordinate = coordinate
        selectedPlaceName = placeName
        locationField.text = placeName
    }
}
