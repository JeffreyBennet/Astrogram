import UIKit

protocol MapFiltersDelegate: AnyObject {
    func filtersDidChange(showLight: Bool, showClouds: Bool, showRain: Bool, showVisibility: Bool)
}

final class MapFiltersViewController: UIViewController {

    weak var delegate: MapFiltersDelegate?

    @IBOutlet private weak var lightSwitch: UISwitch!
    @IBOutlet private weak var cloudsSwitch: UISwitch!
    @IBOutlet weak var precipitationSwitch: UISwitch!
    @IBOutlet weak var visibilityRatingSwitch: UISwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadFromSettings()
    }

    private func loadFromSettings() {
        let s = AppSettings.shared
        lightSwitch.isOn = s.showLightLayer
        cloudsSwitch.isOn = s.showCloudLayer
        precipitationSwitch.isOn = s.showRainLayer
        visibilityRatingSwitch.isOn = s.showVisibility
    }

    private func notifyDelegate() {
        delegate?.filtersDidChange(
            showLight: lightSwitch.isOn,
            showClouds: cloudsSwitch.isOn,
            showRain: precipitationSwitch.isOn,
            showVisibility: visibilityRatingSwitch.isOn
        )
    }

    @IBAction private func lightChanged(_ sender: UISwitch) {
        notifyDelegate()
    }

    @IBAction private func cloudsChanged(_ sender: UISwitch) {
        notifyDelegate()
    }
    
    @IBAction func precipitationChanged(_ sender: UISwitch) {
        notifyDelegate()
    }

    @IBAction func visibilityChanged(_ sender: Any) {
        notifyDelegate()
    }
}
