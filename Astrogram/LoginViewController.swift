import UIKit
import FirebaseAuth

final class LoginViewController: UIViewController {
    
    @IBOutlet private weak var userIDTextField: UITextField!
    @IBOutlet private weak var passwordTextField: UITextField!
    @IBOutlet private weak var statusLabel: UILabel!
    
    private let signUpViewControllerID = "SignUpViewController"
    private let tabBarControllerID = "TabViewController"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        statusLabel.text = ""
    }
    
    @IBAction private func signInButtonPressed(_ sender: Any) {
        guard let email = userIDTextField.text,
              let password = passwordTextField.text else {
            statusLabel.text = "Missing input fields"
            return
        }
        
        if email.isEmpty || password.isEmpty {
            statusLabel.text = "Please fill in all fields"
            return
        }
        
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                self.statusLabel.text = "Login failed: \(error.localizedDescription)"
            } else {
                self.statusLabel.text = ""
                self.userIDTextField.text = ""
                self.passwordTextField.text = ""
                self.goToTabBar()
            }
        }
    }
    
    @IBAction private func createAccountButtonPressed(_ sender: Any) {
        if let signUpVC = storyboard?.instantiateViewController(withIdentifier: signUpViewControllerID) {
            signUpVC.modalPresentationStyle = .fullScreen
            present(signUpVC, animated: true)
        }
    }
    
    private func goToTabBar() {
        if let tabBarVC = storyboard?.instantiateViewController(withIdentifier: tabBarControllerID) {
            tabBarVC.modalPresentationStyle = .fullScreen
            present(tabBarVC, animated: true)
        }
    }
}
