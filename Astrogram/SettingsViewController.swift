import UIKit

final class SettingsViewController: UIViewController {

    @IBOutlet private weak var startupSegment: UISegmentedControl!
    @IBOutlet private weak var nightModeSwitch: UISwitch!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    private func load() {
        let s = AppSettings.shared
        startupSegment.selectedSegmentIndex = s.startupLayer.rawValue
        nightModeSwitch.isOn = s.nightMode
    }

    @IBAction private func startupChanged(_ sender: UISegmentedControl) {
        AppSettings.shared.startupLayer = StartupLayer(rawValue: sender.selectedSegmentIndex) ?? .none
    }

    @IBAction private func nightModeChanged(_ sender: UISwitch) {
        AppSettings.shared.nightMode = sender.isOn
    }
}
