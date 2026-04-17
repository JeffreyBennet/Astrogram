import UIKit
import FirebaseAuth

final class LoginViewController: UIViewController {
    
    @IBOutlet private weak var userIDTextField: UITextField!
    @IBOutlet private weak var passwordTextField: UITextField!
    @IBOutlet private weak var statusLabel: UILabel!
    private let passwordVisibilityButton = UIButton(type: .system)
    
    private let signUpViewControllerID = "SignUpViewController"
    private let tabBarControllerID = "TabViewController"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        statusLabel.text = ""
        configurePasswordField()
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

    private func configurePasswordField() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        passwordVisibilityButton.setImage(UIImage(systemName: "eye", withConfiguration: symbolConfig), for: .normal)
        passwordVisibilityButton.tintColor = .secondaryLabel
        passwordVisibilityButton.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)
        passwordTextField.rightView = makePasswordRightView(with: passwordVisibilityButton)
        passwordTextField.rightViewMode = .always
    }

    @objc private func togglePasswordVisibility() {
        passwordTextField.isSecureTextEntry.toggle()
        let symbolName = passwordTextField.isSecureTextEntry ? "eye" : "eye.slash"
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        passwordVisibilityButton.setImage(UIImage(systemName: symbolName, withConfiguration: symbolConfig), for: .normal)

        // Keep existing text rendering/caret stable when toggling secure entry.
        if let text = passwordTextField.text, passwordTextField.isFirstResponder {
            passwordTextField.text = ""
            passwordTextField.insertText(text)
        }
    }

    private func makePasswordRightView(with button: UIButton) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 34, height: 24))
        button.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        container.addSubview(button)
        return container
    }
}
