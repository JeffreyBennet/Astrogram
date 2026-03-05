import UIKit

protocol MapFiltersDelegate: AnyObject {
    func filtersDidChange(showLight: Bool, showClouds: Bool, nightMode: Bool)
}

final class MapFiltersViewController: UIViewController {

    weak var delegate: MapFiltersDelegate?

    @IBOutlet private weak var lightSwitch: UISwitch!
    @IBOutlet private weak var cloudsSwitch: UISwitch!
    @IBOutlet private weak var nightModeSwitch: UISwitch!

    override func viewDidLoad() {
        super.viewDidLoad()
        loadFromSettings()
    }

    private func loadFromSettings() {
        let s = AppSettings.shared
        lightSwitch.isOn = s.showLightLayer
        cloudsSwitch.isOn = s.showCloudLayer
        nightModeSwitch.isOn = s.nightMode
    }

    private func notifyDelegate() {
        delegate?.filtersDidChange(
            showLight: lightSwitch.isOn,
            showClouds: cloudsSwitch.isOn,
            nightMode: nightModeSwitch.isOn
        )
    }

    @IBAction private func lightChanged(_ sender: UISwitch) {
        notifyDelegate()
    }

    @IBAction private func cloudsChanged(_ sender: UISwitch) {
        notifyDelegate()
    }

    @IBAction private func nightChanged(_ sender: UISwitch) {
        notifyDelegate()
    }
}
