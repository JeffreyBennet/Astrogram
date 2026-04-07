import UIKit
import FirebaseAuth

final class FeedViewController: UIViewController {

    // MARK: - Properties

    private var collectionView: UICollectionView!
    private let refreshControl = UIRefreshControl()
    private var posts: [AstroPost] = []
    private var currentFilter = FeedFilter()
    private let emptyLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var imageCache = NSCache<NSString, UIImage>()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Feed"
        view.backgroundColor = .systemBackground
        setupNavBar()
        setupCollectionView()
        setupEmptyState()
        setupActivityIndicator()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadPosts()
    }

    // MARK: - Setup

    private func setupNavBar() {
        let filterButton = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(filterTapped)
        )
        navigationItem.rightBarButtonItem = filterButton
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 1
        layout.minimumLineSpacing = 1

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(FeedPhotoCell.self, forCellWithReuseIdentifier: FeedPhotoCell.reuseID)
        collectionView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupEmptyState() {
        emptyLabel.text = "No posts yet.\nBe the first to share an astrophoto!"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }

    private func setupActivityIndicator() {
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Data Loading

    private func loadPosts() {
        if posts.isEmpty {
            activityIndicator.startAnimating()
        }

        FirebasePostService.shared.fetchPosts(filter: currentFilter) { [weak self] result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.refreshControl.endRefreshing()

                switch result {
                case .success(let posts):
                    self?.posts = posts
                    self?.collectionView.reloadData()
                    self?.emptyLabel.isHidden = !posts.isEmpty
                case .failure(let error):
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func filterTapped() {
        let filterVC = FeedFilterViewController()
        filterVC.currentFilter = currentFilter
        filterVC.delegate = self
        filterVC.modalPresentationStyle = .pageSheet

        if let sheet = filterVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 18
            sheet.largestUndimmedDetentIdentifier = .medium
        }

        present(filterVC, animated: true)
    }

    @objc private func refreshPulled() {
        loadPosts()
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
            DispatchQueue.main.async {
                imageView.image = image
            }
        }.resume()
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension FeedViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        posts.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedPhotoCell.reuseID, for: indexPath) as! FeedPhotoCell
        let post = posts[indexPath.item]
        loadImage(for: post.imageURL, into: cell.imageView)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (collectionView.bounds.width - 2) / 3 // 3 columns, 1pt spacing
        return CGSize(width: width, height: width)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let post = posts[indexPath.item]
        let detailVC = PostDetailViewController()
        detailVC.post = post

        // Pass cached image if available
        let cacheKey = NSString(string: post.imageURL)
        detailVC.cachedImage = imageCache.object(forKey: cacheKey)

        detailVC.onPostUpdated = { [weak self] in
            self?.loadPosts()
        }
        detailVC.modalPresentationStyle = .fullScreen
        present(detailVC, animated: true)
    }
}

// MARK: - FeedFilterDelegate

extension FeedViewController: FeedFilterDelegate {
    func filtersDidApply(_ filter: FeedFilter) {
        currentFilter = filter
        loadPosts()
    }
}

// MARK: - Feed Photo Cell

final class FeedPhotoCell: UICollectionViewCell {
    static let reuseID = "FeedPhotoCell"

    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }
}
