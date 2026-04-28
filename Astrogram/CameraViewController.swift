import UIKit
import AVFoundation
import CoreLocation
import CoreMotion

// Shows a live camera preview with a crosshair and overlays sky coordinates as you move the device.
final class CameraViewController: UIViewController {

    @IBOutlet weak var crosshairView: CrosshairView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var coordinateLabel: UILabel!
    
    // Layer for displaying camera preview
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")

    // Location and motion managers for device location and orientation
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()

    // Current device attitude and location
    private var currentAttitude: CMAttitude?
    private var currentLocation: CLLocation?

    // Last captured coordinates (default to zero for safety)
    var lastRA: Double = 0
    var lastDec: Double = 0
    var lastAlt: Double = 0
    var lastAz: Double = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        // Set up camera, location, and motion so we can compute and display sky coordinates.
        view.backgroundColor = .black
        setupCamera()
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        setupLocation()
        setupMotion()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Start the camera session and begin receiving motion updates.
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
        motionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical,
                                               to: .main) { [weak self] motion, _ in
            guard let self = self else { return }
            self.currentAttitude = motion?.attitude
            self.updateCoordinateLabel()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop the camera and motion updates when the view goes away.
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
        motionManager.stopDeviceMotionUpdates()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        // Configure a simple rear-camera preview.
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showCameraUnavailableMessage()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        previewLayer.session = captureSession
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)
    }

    private func showCameraUnavailableMessage() {
        // Fallback UI if the device camera isn't available.
        let label = UILabel()
        label.text = "Camera unavailable"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Location Setup

    private func setupLocation() {
        // Ask for location so we can compute RA/Dec from Alt/Az.
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // MARK: - Device Motion Setup

    // Prepare Core Motion to deliver orientation updates at ~30 fps.
    private func setupMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
    }

    // MARK: - Coordinate Calculations

    // Convert device attitude (pitch/yaw) into altitude and azimuth angles.
    private func altAz(from attitude: CMAttitude) -> (altitude: Double, azimuth: Double) {
        let altitudeDeg = attitude.pitch * (180.0 / .pi)
        var azimuthDeg = attitude.yaw * (180.0 / .pi)
        if azimuthDeg < 0 { azimuthDeg += 360 }
        return (altitudeDeg, azimuthDeg)
    }

    // Convert horizontal coordinates (Alt/Az) to equatorial coordinates (RA/Dec).
    private func equatorial(altitude: Double, azimuth: Double,
                             latitude: Double,
                             lst: Double) -> (ra: Double, dec: Double) {
        let altR = altitude * .pi / 180
        let azR  = azimuth  * .pi / 180
        let latR = latitude * .pi / 180

        let sinDec = sin(altR) * sin(latR) + cos(altR) * cos(latR) * cos(azR)
        let decR = asin(sinDec)

        let cosH = (sin(altR) - sin(latR) * sinDec) / (cos(latR) * cos(decR))
        var hourAngle = acos(max(-1, min(1, cosH))) * (180 / .pi) / 15.0 // hours
        if sin(azR) > 0 { hourAngle = 24 - hourAngle }

        var ra = lst - hourAngle
        if ra < 0 { ra += 24 }
        if ra >= 24 { ra -= 24 }

        return (ra, decR * 180 / .pi)
    }

    // Calculate local sidereal time for the given longitude and date.
    private func localSiderealTime(longitude: Double, date: Date) -> Double {
        let J2000 = Date(timeIntervalSince1970: 946728000)
        let daysSinceJ2000 = date.timeIntervalSince(J2000) / 86400.0
        let gmst = 18.697374558 + 24.06570982441908 * daysSinceJ2000
        let lst = (gmst + longitude / 15.0).truncatingRemainder(dividingBy: 24)
        return lst < 0 ? lst + 24 : lst
    }

    // MARK: - UI Updates

    private func updateCoordinateLabel() {
        // Build a friendly status string with Alt/Az, and RA/Dec when location is available.
        guard let attitude = currentAttitude else {
            coordinateLabel.text = "  Waiting for motion data...  "
            return
        }

        let (alt, az) = altAz(from: attitude)

        var text = String(format: "  Az: %06.2f°   Alt: %+.2f°  ", az, alt)

        if let location = currentLocation {
            let lst = localSiderealTime(longitude: location.coordinate.longitude, date: Date())
            let (ra, dec) = equatorial(altitude: alt, azimuth: az,
                                       latitude: location.coordinate.latitude,
                                       lst: lst)
            let raH  = Int(ra)
            let raM  = Int((ra - Double(raH)) * 60)
            let raS  = ((ra - Double(raH)) * 60 - Double(raM)) * 60
            text += String(format: "\n  RA: %02dh %02dm %04.1fs   Dec: %+.2f°  ", raH, raM, raS, dec)
        }

        coordinateLabel.text = text
    }

    // MARK: - Capture Button Action

    @objc private func captureTapped() {
        // Ensure device attitude is available before processing capture.
        guard let attitude = currentAttitude else {
            presentAlert(title: "Motion Data Unavailable",
                         message: "Could not read device orientation. Please try again.")
            return
        }

        // Compute current altitude and azimuth from device attitude.
        let (alt, az) = altAz(from: attitude)

        // Give a quick flash on the crosshair to confirm the tap.
        UIView.animate(withDuration: 0.08, animations: {
            self.crosshairView.alpha = 0.2
        }, completion: { _ in
            UIView.animate(withDuration: 0.15) {
                self.crosshairView.alpha = 1
            }
        })

        // Ensure current location is available to compute RA/Dec.
        guard let location = currentLocation else {
            presentAlert(title: "Location Needed",
                         message: "Enable location access to get RA/Dec and sky predictions.")
            return
        }

        // Calculate Local Sidereal Time and equatorial coordinates.
        let lst = localSiderealTime(longitude: location.coordinate.longitude, date: Date())
        let (ra, dec) = equatorial(altitude: alt, azimuth: az,
                                   latitude: location.coordinate.latitude,
                                   lst: lst)

        // Store the last captured coordinates for external use.
        self.lastRA = ra
        self.lastDec = dec
        self.lastAlt = alt
        self.lastAz = az

        // Show the results sheet with captured coordinates and predictions.
        let resultsVC = SkyResultsViewController()
        resultsVC.capturedRA  = ra
        resultsVC.capturedDec = dec
        resultsVC.capturedAlt = alt
        resultsVC.capturedAz  = az
        resultsVC.observerLocation = location.coordinate

        let nav = UINavigationController(rootViewController: resultsVC)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 18
        }
        present(nav, animated: true)
    }

    // MARK: - Helper

    /// Presents an alert with given title and message on the main thread.
    private func presentAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title,
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension CameraViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Optionally handle location errors here for robustness.
    }
}

// MARK: - Crosshair Overlay

@IBDesignable
final class CrosshairView: UIView {
    
    /// Size of the crosshair; triggers redraw on change.
    @IBInspectable var crosshairSize: CGFloat = 80 {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: crosshairSize, height: crosshairSize)
    }

    override func draw(_ rect: CGRect) {
        // Draw a minimal crosshair with center ticks and corner brackets.
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let color = UIColor.white
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let arm: CGFloat = 12
        let gap: CGFloat = 8
        let cornerLen: CGFloat = 14
        let lineWidth: CGFloat = 1.5

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        // Horizontal and vertical center ticks.
        ctx.move(to: CGPoint(x: center.x - arm - gap, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x - gap, y: center.y))
        ctx.move(to: CGPoint(x: center.x + gap, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x + arm + gap, y: center.y))

        // Vertical ticks.
        ctx.move(to: CGPoint(x: center.x, y: center.y - arm - gap))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y - gap))
        ctx.move(to: CGPoint(x: center.x, y: center.y + gap))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + arm + gap))

        ctx.strokePath()

        // Corner brackets to frame the view.
        ctx.setLineWidth(lineWidth * 1.2)
        let inset: CGFloat = 4
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // top-left
            (CGPoint(x: inset, y: inset + cornerLen),
             CGPoint(x: inset, y: inset),
             CGPoint(x: inset + cornerLen, y: inset)),
            // top-right
            (CGPoint(x: rect.width - inset - cornerLen, y: inset),
             CGPoint(x: rect.width - inset, y: inset),
             CGPoint(x: rect.width - inset, y: inset + cornerLen)),
            // bottom-left
            (CGPoint(x: inset, y: rect.height - inset - cornerLen),
             CGPoint(x: inset, y: rect.height - inset),
             CGPoint(x: inset + cornerLen, y: rect.height - inset)),
            // bottom-right
            (CGPoint(x: rect.width - inset - cornerLen, y: rect.height - inset),
             CGPoint(x: rect.width - inset, y: rect.height - inset),
             CGPoint(x: rect.width - inset, y: rect.height - inset - cornerLen))
        ]

        for (a, b, c) in corners {
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.addLine(to: c)
        }
        ctx.strokePath()
    }
}

