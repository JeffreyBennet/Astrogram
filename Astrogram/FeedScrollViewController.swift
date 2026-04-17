import UIKit
import FirebaseAuth

final class FeedScrollViewController: UIViewController {

    var posts: [AstroPost] = []
    var startIndex: Int = 0
    var imageCache = NSCache<NSString, UIImage>()
    var onPostUpdated: (() -> Void)?

    private let tableView = UITableView()
    private var starredPostIds: Set<String> = []
    private var didScrollToStart = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(FeedPostCell.self, forCellReuseIdentifier: FeedPostCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 600
        view.addSubview(tableView)

        let closeBtn = UIButton(type: .system)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        closeBtn.tintColor = .label
        closeBtn.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
        closeBtn.layer.cornerRadius = 18
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeBtn.widthAnchor.constraint(equalToConstant: 36),
            closeBtn.heightAnchor.constraint(equalToConstant: 36)
        ])

        checkAllStarStatuses()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didScrollToStart && startIndex > 0 && startIndex < posts.count {
            didScrollToStart = true
            tableView.scrollToRow(at: IndexPath(row: startIndex, section: 0), at: .top, animated: false)
        }
    }

    override var prefersStatusBarHidden: Bool { true }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - Star Status

    private func checkAllStarStatuses() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        for post in posts {
            guard let postId = post.id else { continue }
            FirebasePostService.shared.isStarred(postId: postId, userId: uid) { [weak self] starred in
                if starred {
                    DispatchQueue.main.async {
                        self?.starredPostIds.insert(postId)
                        if let idx = self?.posts.firstIndex(where: { $0.id == postId }) {
                            self?.tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Image Loading

    func loadImage(for urlString: String, into imageView: UIImageView) {
        let cacheKey = NSString(string: urlString)
        if let cached = imageCache.object(forKey: cacheKey) {
            imageView.image = cached
            return
        }
        imageView.image = nil
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            self?.imageCache.setObject(image, forKey: cacheKey)
            DispatchQueue.main.async { imageView.image = image }
        }.resume()
    }
}

// MARK: - UITableView

extension FeedScrollViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        posts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FeedPostCell.reuseID, for: indexPath) as! FeedPostCell
        let post = posts[indexPath.row]
        let isStarred = starredPostIds.contains(post.id ?? "")
        cell.configure(with: post, isStarred: isStarred)
        loadImage(for: post.imageURL, into: cell.postImageView)

        cell.onStarTapped = { [weak self] in
            self?.toggleStar(at: indexPath)
        }
        cell.onLocationTapped = { [weak self] in
            self?.openPostOnMap(post)
        }
        return cell
    }

    private func toggleStar(at indexPath: IndexPath) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var post = posts[indexPath.row]
        guard let postId = post.id else { return }

        FirebasePostService.shared.toggleStar(postId: postId, userId: uid) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let nowStarred) = result {
                    if nowStarred {
                        self?.starredPostIds.insert(postId)
                    } else {
                        self?.starredPostIds.remove(postId)
                    }
                    post.starCount += nowStarred ? 1 : -1
                    self?.posts[indexPath.row] = post
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                    self?.onPostUpdated?()
                }
            }
        }
    }

    private func openPostOnMap(_ post: AstroPost) {
        guard let lat = post.latitude, let lon = post.longitude else { return }
        let payload: [String: Any] = [
            "postId": post.id ?? "",
            "lat": lat,
            "lon": lon,
            "imageURL": post.imageURL
        ]

        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            guard let tabBarController = self.resolveRootTabBarController(),
                  let mapIndex = self.resolveMapTabIndex(in: tabBarController) else { return }

            tabBarController.selectedIndex = mapIndex
            self.resolveMapViewController(in: tabBarController, at: mapIndex)?.loadViewIfNeeded()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .showPostOnMap, object: nil, userInfo: payload)
            }
        }
    }

    private func resolveRootTabBarController() -> UITabBarController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController,
               let tab = findTabBarController(in: root) {
                return tab
            }
        }
        return presentingViewController?.tabBarController
    }

    private func resolveMapTabIndex(in tabBarController: UITabBarController) -> Int? {
        guard let controllers = tabBarController.viewControllers else { return nil }
        return controllers.firstIndex(where: { controller in
            if controller.tabBarItem.title == "Map" {
                return true
            }
            if let nav = controller as? UINavigationController {
                return nav.viewControllers.first is MapViewController
            }
            return controller is MapViewController
        })
    }

    private func resolveMapViewController(in tabBarController: UITabBarController, at index: Int) -> MapViewController? {
        guard let controllers = tabBarController.viewControllers, controllers.indices.contains(index) else { return nil }
        let controller = controllers[index]
        if let nav = controller as? UINavigationController {
            return nav.viewControllers.first(where: { $0 is MapViewController }) as? MapViewController
        }
        return controller as? MapViewController
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

// MARK: - Feed Post Cell

final class FeedPostCell: UITableViewCell {

    static let reuseID = "FeedPostCell"

    let postImageView = UIImageView()
    private let starRow = UIStackView()
    private let starButton = UIButton(type: .system)
    private let locationButton = UIButton(type: .system)
    private let starCountLabel = UILabel()
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let descLabel = UILabel()
    private let cameraLabel = UILabel()
    private let isoLabel = UILabel()
    private let exposureLabel = UILabel()
    private let focalLabel = UILabel()
    private let locationLabel = UILabel()
    private let divider = UIView()
    private let metaStack = UIStackView()

    var onStarTapped: (() -> Void)?
    var onLocationTapped: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        postImageView.contentMode = .scaleAspectFill
        postImageView.clipsToBounds = true
        postImageView.backgroundColor = .secondarySystemBackground
        postImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(postImageView)

        // Star row
        starRow.axis = .horizontal
        starRow.spacing = 4
        starRow.alignment = .center
        starRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(starRow)

        starButton.addTarget(self, action: #selector(starTap), for: .touchUpInside)
        locationButton.addTarget(self, action: #selector(locationTap), for: .touchUpInside)
        starCountLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        starCountLabel.textColor = .label
        starRow.addArrangedSubview(starButton)
        starRow.addArrangedSubview(starCountLabel)
        starRow.addArrangedSubview(locationButton)

        // Title
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Author
        authorLabel.font = .systemFont(ofSize: 12)
        authorLabel.textColor = .secondaryLabel
        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(authorLabel)

        // Description
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .label
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descLabel)

        // Divider
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)

        // Metadata stack
        metaStack.axis = .vertical
        metaStack.spacing = 4
        metaStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(metaStack)

        [cameraLabel, isoLabel, exposureLabel, focalLabel, locationLabel].forEach {
            $0.font = .systemFont(ofSize: 13)
            $0.textColor = .secondaryLabel
            $0.numberOfLines = 1
            metaStack.addArrangedSubview($0)
        }

        // Bottom separator
        let bottomSep = UIView()
        bottomSep.backgroundColor = .separator
        bottomSep.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomSep)

        NSLayoutConstraint.activate([
            postImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            postImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            postImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            postImageView.heightAnchor.constraint(equalTo: postImageView.widthAnchor),

            starRow.topAnchor.constraint(equalTo: postImageView.bottomAnchor, constant: 10),
            starRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),

            titleLabel.topAnchor.constraint(equalTo: starRow.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            authorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            authorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            authorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            descLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            descLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            divider.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            metaStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            metaStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            metaStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            bottomSep.topAnchor.constraint(equalTo: metaStack.bottomAnchor, constant: 16),
            bottomSep.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomSep.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomSep.heightAnchor.constraint(equalToConstant: 8),
            bottomSep.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func configure(with post: AstroPost, isStarred: Bool) {
        titleLabel.text = post.title

        let df = DateFormatter()
        df.dateStyle = .medium
        authorLabel.text = "\(post.userEmail)  •  \(df.string(from: post.timestamp))"

        descLabel.text = post.description.isEmpty ? nil : post.description
        descLabel.isHidden = post.description.isEmpty

        // Star
        let iconName = isStarred ? "star.fill" : "star"
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        starButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        starButton.tintColor = isStarred ? .systemYellow : .label
        starCountLabel.text = post.starCount > 0 ? "\(post.starCount)" : ""

        let hasLocation = post.latitude != nil && post.longitude != nil
        locationButton.isHidden = !hasLocation
        locationButton.isEnabled = hasLocation
        locationButton.setImage(UIImage(systemName: "mappin.and.ellipse", withConfiguration: config), for: .normal)
        locationButton.tintColor = .label

        // Metadata
        cameraLabel.text = post.camera.isEmpty ? nil : "Camera: \(post.camera)"
        cameraLabel.isHidden = post.camera.isEmpty

        isoLabel.text = post.iso.isEmpty ? nil : "ISO: \(post.iso)"
        isoLabel.isHidden = post.iso.isEmpty

        exposureLabel.text = post.exposure.isEmpty ? nil : "Exposure: \(post.exposure)"
        exposureLabel.isHidden = post.exposure.isEmpty

        focalLabel.text = post.focalLength.isEmpty ? nil : "Focal Length: \(post.focalLength)"
        focalLabel.isHidden = post.focalLength.isEmpty

        locationLabel.text = post.locationName.isEmpty ? nil : "Location: \(post.locationName)"
        locationLabel.isHidden = post.locationName.isEmpty

        // Hide divider if no metadata at all
        let hasAnyMeta = !post.camera.isEmpty || !post.iso.isEmpty || !post.exposure.isEmpty || !post.focalLength.isEmpty || !post.locationName.isEmpty
        divider.isHidden = !hasAnyMeta
    }

    @objc private func starTap() {
        onStarTapped?()
    }

    @objc private func locationTap() {
        onLocationTapped?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        postImageView.image = nil
        onStarTapped = nil
        onLocationTapped = nil
    }
}
