import UIKit

class SplashScreenViewController: UIViewController {

    private var starLayers: [CALayer] = []
    private var splashTimeoutWorkItem: DispatchWorkItem?
    private var didRequestTransition = false

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // I messed around with this count
        // I settled on 60 being the best looking without cluttering too intensely.
        scatterStars(count: 60)
        
        // Add the app icon after the stars so the stars don't appear over the icon
        let appIcon = UIImage(named: "appIconNoBG")!
        
        let iconView = UIImageView(image: appIcon)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconView)
        
        // Allow tap-to-skip, but also schedule a timeout to auto-advance
        let tap = UITapGestureRecognizer(target: self, action: #selector(splashTapped))
        view.addGestureRecognizer(tap)
        scheduleSplashTimeout(seconds: 2.0)
        
        // Make constraints that line up with the launch screen icon:
        // Centered in the screen & 172x172
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 172),
            iconView.heightAnchor.constraint(equalToConstant: 172)
        ])
        
    }

    // MARK: - Star creation

    private func scatterStars(count: Int) {
        // Clean up any existing stars
        for l in starLayers {
            l.removeAllAnimations()
            l.removeFromSuperlayer()
        }
        starLayers.removeAll()
        
        // Keep track of where stars are placed to prevent stars overlapping
        var placed: [(center: CGPoint, radius: CGFloat)] = []

        for _ in 0..<count {
            let size = CGFloat.random(in: 16...24)
            let radius = size / 2

            // Define an allowed rect so stars remain fully visible
            let inset: CGFloat = size
            let allowedRect = view.bounds.insetBy(dx: inset, dy: inset)

            // Try to find a non-overlapping position
            guard let pos = randomNonOverlappingPosition(
                radius: radius,
                in: allowedRect,
                existing: placed,
                padding: 20,
                maxAttempts: 30) else {
                // If no spot found after several attempts, skip this star
                continue
            }

            let node = makeStarLayer(size: size, glowColor: .systemYellow)
            node.position = pos
            view.layer.addSublayer(node)

            // Animate ONLY the glow via the container to keep grouping simple
            addGlowPulse(to: node,
                         minOpacity: 0.0,
                         maxOpacity: 0.90,
                         duration: Double.random(in: 0.4...0.9),
                         desync: true)

            starLayers.append(node)
            placed.append((center: pos, radius: radius))
        }
    }

    // Creates a container layer with two sublayers:
    // - glow (a soft circle) that will pulse its opacity
    // - sparkle (static image) on top
    private func makeStarLayer(size: CGFloat, glowColor: UIColor) -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        let scale: CGFloat = (self.view.window?.windowScene?.screen.scale)
        ?? self.traitCollection.displayScale
        container.contentsScale = scale

        // Sparkle's underglow
        let glowDiameter = size * 0.55
        let glowLayer = CAShapeLayer()
        glowLayer.path = UIBezierPath(ovalIn: CGRect(
            x: (size - glowDiameter) / 2,
            y: (size - glowDiameter) / 2,
            width: glowDiameter,
            height: glowDiameter
        )).cgPath
        glowLayer.fillColor = glowColor.cgColor
        glowLayer.opacity = 0.0 // start dim
        glowLayer.shadowColor = glowColor.cgColor
        glowLayer.shadowOpacity = 1.0
        glowLayer.shadowRadius = max(8, size * 0.35)
        glowLayer.shadowOffset = .zero

        // Sparkle image on top
        let sparkleLayer = CALayer()
        let baseSymbol = UIImage(systemName: "sparkle")
        let configured = baseSymbol?.applyingSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: size)) ?? baseSymbol
        let tinted = configured?.withTintColor(glowColor, renderingMode: .alwaysOriginal)

        if let tinted {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: container.bounds.size, format: format)
            let rendered = renderer.image { _ in
                tinted.draw(in: CGRect(origin: .zero, size: container.bounds.size))
            }
            sparkleLayer.contents = rendered.cgImage
        }

        sparkleLayer.contentsScale = scale
        sparkleLayer.contentsGravity = .resizeAspect
        sparkleLayer.frame = container.bounds
        sparkleLayer.opacity = 1.0 // static

        // Add glow first so that glow layer is below, sparkle above
        container.addSublayer(glowLayer)
        container.addSublayer(sparkleLayer)

        return container
    }

    // Animates the glow sublayer's opacity only. Sparkle remains static.
    private func addGlowPulse(to container: CALayer,
                              minOpacity: Float,
                              maxOpacity: Float,
                              duration: Double,
                              desync: Bool) {
        guard let glow = container.sublayers?.first(where: { $0 is CAShapeLayer }) else { return }
        
        // Set model layer to mid value to avoid visual jump when animation starts
        let mid = (minOpacity + maxOpacity) / 2
        glow.opacity = mid
        
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = minOpacity
        pulse.toValue = maxOpacity
        pulse.duration = duration
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        if desync {
            pulse.beginTime = CACurrentMediaTime() + Double.random(in: 0...1.2)
            pulse.fillMode = .backwards
        }
        
        glow.add(pulse, forKey: "glowPulse")
    }

    // Returns a random position that does not overlap existing circles (by radius) within the given rect.
    private func randomNonOverlappingPosition(radius: CGFloat,
                                              in rect: CGRect,
                                              existing: [(center: CGPoint, radius: CGFloat)],
                                              padding: CGFloat,
                                              maxAttempts: Int) -> CGPoint? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        for _ in 0..<maxAttempts {
            let x = CGFloat.random(in: rect.minX...rect.maxX)
            let y = CGFloat.random(in: rect.minY...rect.maxY)
            let candidate = CGPoint(x: x, y: y)

            var ok = true
            for (c, r) in existing {
                let dx = candidate.x - c.x
                let dy = candidate.y - c.y
                let minDist = radius + r + padding
                if (dx*dx + dy*dy) < (minDist * minDist) {
                    ok = false
                    break
                }
            }
            if ok { return candidate }
        }
        return nil
    }

    @objc private func splashTapped(_ gesture: UITapGestureRecognizer) {
        transitionToLogin()
    }

    private func scheduleSplashTimeout(seconds: TimeInterval = 2.0) {
        splashTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.transitionToLogin()
        }
        splashTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func transitionToLogin() {
        // Ensure we only transition once
        guard !didRequestTransition else { return }
        didRequestTransition = true
        splashTimeoutWorkItem?.cancel()

        // Present the LoginViewController full-screen
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let loginVC = storyboard.instantiateViewController(withIdentifier: "LoginViewController")
        loginVC.modalPresentationStyle = .fullScreen
        present(loginVC, animated: true)
    }

    deinit {
        splashTimeoutWorkItem?.cancel()
        // Clean up animations
        for l in starLayers {
            l.removeAllAnimations()
            l.removeFromSuperlayer()
        }
        starLayers.removeAll()
    }
}
