import UIKit
import FirebaseAuth

final class FeedViewController: UIViewController {

    // MARK: - IBOutlets

    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var emptyLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    // MARK: - Properties

    private let refreshControl = UIRefreshControl()
    private var posts: [AstroPost] = []
    private var currentFilter = FeedFilter()
    private var imageCache = NSCache<NSString, UIImage>()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Feed"
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(FeedPhotoCell.self, forCellWithReuseIdentifier: FeedPhotoCell.reuseID)
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        collectionView.refreshControl = refreshControl
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadPosts()
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

    @IBAction func filterTapped(_ sender: Any) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let filterVC = sb.instantiateViewController(withIdentifier: "FeedFilterViewController") as? FeedFilterViewController else { return }
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
        let width = (collectionView.bounds.width - 2) / 3
        return CGSize(width: width, height: width)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let post = posts[indexPath.item]
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let detailVC = sb.instantiateViewController(withIdentifier: "PostDetailViewController") as? PostDetailViewController else { return }
        detailVC.post = post

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
