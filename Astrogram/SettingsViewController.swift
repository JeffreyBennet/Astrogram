import UIKit
import FirebaseAuth

final class SettingsViewController: UIViewController {

    @IBOutlet weak var nightModeSwitch: UISwitch!
    @IBOutlet weak var myPostsCollectionView: UICollectionView!
    @IBOutlet weak var emailLabel: UILabel!
    @IBOutlet weak var collectionHeightConstraint: NSLayoutConstraint!

    private var myPosts: [AstroPost] = []
    private var imageCache = NSCache<NSString, UIImage>()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        loadSettings()

        emailLabel.text = Auth.auth().currentUser?.email ?? ""

        myPostsCollectionView.delegate = self
        myPostsCollectionView.dataSource = self
        myPostsCollectionView.register(FeedPhotoCell.self, forCellWithReuseIdentifier: FeedPhotoCell.reuseID)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSettings()
        loadMyPosts()
    }

    // MARK: - Settings

    private func loadSettings() {
        let s = AppSettings.shared
        nightModeSwitch.isOn = s.nightMode
    }

    @IBAction func nightModeChanged(_ sender: UISwitch) {
        AppSettings.shared.nightMode = sender.isOn
        view.window?.overrideUserInterfaceStyle = sender.isOn ? .dark : .light
    }

    // MARK: - My Posts

    private func loadMyPosts() {
        var filter = FeedFilter()
        filter.myPostsOnly = true
        FirebasePostService.shared.fetchPosts(filter: filter) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let posts):
                    print("[Profile] Loaded \(posts.count) of my posts")
                    self?.myPosts = posts
                    self?.updateCollectionHeight()
                    self?.myPostsCollectionView.reloadData()
                case .failure(let error):
                    print("[Profile] ERROR loading my posts: \(error.localizedDescription)")
                }
            }
        }
    }

    private func updateCollectionHeight() {
        let columns: CGFloat = 3
        let spacing: CGFloat = 1
        let cellWidth = (myPostsCollectionView.bounds.width - (columns - 1) * spacing) / columns
        let rows = ceil(CGFloat(myPosts.count) / columns)
        let height = max(rows * (cellWidth + spacing), 100)
        collectionHeightConstraint.constant = height
        view.layoutIfNeeded()
    }

    // MARK: - Log Out

    @IBAction func logOutTapped(_ sender: Any) {
        let alert = UIAlertController(title: "Log Out", message: "Are you sure?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { _ in
            do {
                try Auth.auth().signOut()
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let loginVC = storyboard.instantiateViewController(withIdentifier: "LoginViewController")
                loginVC.modalPresentationStyle = .fullScreen
                self.present(loginVC, animated: true)
            } catch {
                let errorAlert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Image Loading

    private func loadImage(for urlString: String, into imageView: UIImageView) {
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

// MARK: - UICollectionView

extension SettingsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        myPosts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedPhotoCell.reuseID, for: indexPath) as! FeedPhotoCell
        loadImage(for: myPosts[indexPath.item].imageURL, into: cell.imageView)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (collectionView.bounds.width - 2) / 3
        return CGSize(width: width, height: width)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let post = myPosts[indexPath.item]
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let detailVC = sb.instantiateViewController(withIdentifier: "PostDetailViewController") as? PostDetailViewController else { return }
        detailVC.post = post
        detailVC.allowsEditing = true

        let cacheKey = NSString(string: post.imageURL)
        detailVC.cachedImage = imageCache.object(forKey: cacheKey)

        detailVC.onPostUpdated = { [weak self] in
            self?.loadMyPosts()
        }
        detailVC.modalPresentationStyle = .fullScreen
        present(detailVC, animated: true)
    }
}
