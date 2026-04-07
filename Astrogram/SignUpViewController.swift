import UIKit
import FirebaseAuth

final class SignUpViewController: UIViewController {
    
    @IBOutlet private weak var userIDTextField: UITextField!
    @IBOutlet private weak var passwordTextField: UITextField!
    @IBOutlet private weak var confirmPasswordTextField: UITextField!
    @IBOutlet private weak var statusLabel: UILabel!
    
    private let tabBarControllerID = "TabViewController"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        statusLabel.text = ""
    }
    
    @IBAction private func signUpButtonPressed(_ sender: Any) {
        guard let email = userIDTextField.text,
              let password = passwordTextField.text,
              let confirmPassword = confirmPasswordTextField.text else {
            statusLabel.text = "Missing input fields"
            return
        }
        
        if email.isEmpty || password.isEmpty || confirmPassword.isEmpty {
            statusLabel.text = "Please fill in all fields"
            return
        }
        
        if password != confirmPassword {
            statusLabel.text = "Passwords do not match"
            return
        }
        
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            if let error = error {
                self.statusLabel.text = "Sign up failed: \(error.localizedDescription)"
            } else {
                self.statusLabel.text = ""
                self.userIDTextField.text = ""
                self.passwordTextField.text = ""
                self.confirmPasswordTextField.text = ""
                self.goToTabBar()
            }
        }
    }
    
    @IBAction private func backToLoginButtonPressed(_ sender: Any) {
        dismiss(animated: true)
    }
    
    private func goToTabBar() {
        if let tabBarVC = storyboard?.instantiateViewController(withIdentifier: tabBarControllerID) {
            tabBarVC.modalPresentationStyle = .fullScreen
            present(tabBarVC, animated: true)
        }
    }
}
