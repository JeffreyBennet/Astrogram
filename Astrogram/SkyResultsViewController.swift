//
//  SkyResultsViewController.swift
//  Astrogram
//

import UIKit
import CoreLocation

/// Shows captured sky coordinates with nearby objects and Sun/Moon passes
final class SkyResultsViewController: UIViewController {

    var capturedRA: Double  = 0
    var capturedDec: Double = 0
    var capturedAlt: Double = 0
    var capturedAz: Double  = 0
    var observerLocation: CLLocationCoordinate2D?

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var headerLabel: UILabel!
    private var skyObjects: [SkyObject] = []
    private var passEvents: [SkyPassEvent] = []
    private var isLoadingObjects = true
    private var isLoadingEvents  = true

    private enum Section: Int, CaseIterable {
        case coordinates, objects, events
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sky Analysis"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        configureOutlets()
        updateHeaderLabel()
        startLoading()
    }

    private func configureOutlets() {
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    private func updateHeaderLabel() {
        let raH = Int(capturedRA)
        let raM = Int((capturedRA - Double(raH)) * 60)
        let raS = ((capturedRA - Double(raH)) * 60 - Double(raM)) * 60

        headerLabel.text = String(format:
            "RA %02dh %02dm %04.1fs  ·  Dec %+.2f°\nAz %.1f°  ·  Alt %+.1f°",
            raH, raM, raS, capturedDec, capturedAz, capturedAlt)
    }

    private func startLoading() {
        activityIndicator.startAnimating()

        // Lookup nearby celestial objects
        SkyObjectLookupService.lookup(ra: capturedRA, dec: capturedDec, radiusDeg: 5.0) { [weak self] result in
            guard let self else { return }
            self.isLoadingObjects = false
            switch result {
            case .success(let objects):
                self.skyObjects = objects
            case .failure:
                self.skyObjects = []
            }
            self.checkDoneLoading()
        }

        // Calculate Sun/Moon pass events
        guard let observer = observerLocation else {
            isLoadingEvents = false
            checkDoneLoading()
            return
        }

        SolarLunarPredictor.findPassEvents(
            targetRA: capturedRA,
            targetDec: capturedDec,
            observer: observer,
            daysAhead: 30,
            stepMinutes: 10,
            thresholdDeg: 2.0
        ) { [weak self] events in
            guard let self else { return }
            self.isLoadingEvents = false
            self.passEvents = events
            self.checkDoneLoading()
        }
    }

    private func checkDoneLoading() {
        guard !isLoadingObjects && !isLoadingEvents else { return }
        activityIndicator.stopAnimating()
        tableView.reloadData()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func relativeTime(from date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        let hours = Int(diff / 3600)
        if hours < 24 {
            return "in \(hours)h \(Int((diff.truncatingRemainder(dividingBy: 3600)) / 60))m"
        }
        let days = hours / 24
        return "in \(days)d \(hours % 24)h"
    }
}

extension SkyResultsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .coordinates: return 0
        case .objects:
            if isLoadingObjects { return 1 }
            return skyObjects.isEmpty ? 1 : skyObjects.count
        case .events:
            if isLoadingEvents { return 1 }
            return passEvents.isEmpty ? 1 : passEvents.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .coordinates: return nil
        case .objects:     return "🔭  Nearby Objects (within 5°)"
        case .events:      return "☀️🌙  Next Sun & Moon Passes (30 days)"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.selectionStyle = .none

        switch Section(rawValue: indexPath.section)! {

        case .coordinates:
            break

        case .objects:
            if isLoadingObjects {
                content.text = "Searching Simbad catalog…"
                content.textProperties.color = .secondaryLabel
            } else if skyObjects.isEmpty {
                content.text = "No notable objects found nearby"
                content.textProperties.color = .secondaryLabel
            } else {
                let obj = skyObjects[indexPath.row]
                content.text = "\(obj.typeEmoji) \(obj.name)"
                content.textProperties.font = .systemFont(ofSize: 15, weight: .medium)

                var detail = obj.type
                detail += String(format: "  ·  %.2f° away", obj.separation)
                if let mag = obj.magnitude {
                    detail += String(format: "  ·  mag %.1f", mag)
                }
                content.secondaryText = detail
                content.secondaryTextProperties.color = .secondaryLabel
                content.secondaryTextProperties.font = .systemFont(ofSize: 13)
            }

        case .events:
            if isLoadingEvents {
                content.text = "Calculating passes…"
                content.textProperties.color = .secondaryLabel
            } else if passEvents.isEmpty {
                content.text = "No Sun or Moon passes within 2° in the next 30 days"
                content.textProperties.numberOfLines = 0
                content.textProperties.color = .secondaryLabel
            } else {
                let event = passEvents[indexPath.row]
                let bodyLabel = event.body == .sun ? "☀️ Sun" : "🌙 Moon"
                let visLabel  = event.isVisible ? "  · above horizon" : "  · below horizon"

                content.text = "\(bodyLabel)  \(relativeTime(from: event.date))\(visLabel)"
                content.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
                content.secondaryText = formattedDate(event.date)
                    + String(format: "  ·  %.2f° separation", event.separation)
                content.secondaryTextProperties.color = .secondaryLabel
                content.secondaryTextProperties.font = .systemFont(ofSize: 13)
            }
        }

        cell.contentConfiguration = content
        return cell
    }
}

extension SkyResultsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
}
