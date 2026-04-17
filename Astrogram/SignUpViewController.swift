import UIKit
import FirebaseAuth

final class SignUpViewController: UIViewController {
    
    @IBOutlet private weak var userIDTextField: UITextField!
    @IBOutlet private weak var passwordTextField: UITextField!
    @IBOutlet private weak var confirmPasswordTextField: UITextField!
    @IBOutlet private weak var statusLabel: UILabel!
    private let passwordVisibilityButton = UIButton(type: .system)
    
    private let tabBarControllerID = "TabViewController"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        statusLabel.text = ""
        configurePasswordFields()
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

    private func configurePasswordFields() {
        configureSecureField(
            passwordTextField,
            button: passwordVisibilityButton,
            contentType: .newPassword,
            action: #selector(togglePasswordVisibility)
        )
        confirmPasswordTextField.isSecureTextEntry = true
        confirmPasswordTextField.textContentType = .newPassword
        confirmPasswordTextField.autocorrectionType = .no
        confirmPasswordTextField.autocapitalizationType = .none
        confirmPasswordTextField.rightView = nil
        confirmPasswordTextField.rightViewMode = .never
    }

    private func configureSecureField(
        _ textField: UITextField,
        button: UIButton,
        contentType: UITextContentType,
        action: Selector
    ) {
        textField.isSecureTextEntry = true
        textField.textContentType = contentType
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        button.setImage(UIImage(systemName: "eye", withConfiguration: symbolConfig), for: .normal)
        button.tintColor = .secondaryLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        textField.rightView = makePasswordRightView(with: button)
        textField.rightViewMode = .always
    }

    @objc private func togglePasswordVisibility() {
        toggleSecureEntry(for: passwordTextField, button: passwordVisibilityButton)
    }

    private func toggleSecureEntry(for textField: UITextField, button: UIButton) {
        textField.isSecureTextEntry.toggle()
        let symbolName = textField.isSecureTextEntry ? "eye" : "eye.slash"
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        button.setImage(UIImage(systemName: symbolName, withConfiguration: symbolConfig), for: .normal)

        // Keep existing text rendering/caret stable when toggling secure entry.
        if let text = textField.text, textField.isFirstResponder {
            textField.text = ""
            textField.insertText(text)
        }
    }

    private func makePasswordRightView(with button: UIButton) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 34, height: 24))
        button.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        container.addSubview(button)
        return container
    }
}
