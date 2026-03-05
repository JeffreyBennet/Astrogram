import Foundation
import CoreLocation

struct VisibilitySummary {
    let coordinate: CLLocationCoordinate2D
    let lightPollutionIndex: Double   // 0 (best/dark) ... 1 (worst/bright)
    let cloudCover: Double            // 0 (clear) ... 1 (overcast)
    let overallScore: Int             // 0...100 higher is better
    let label: String
}

final class VisibilityCalculator {

    private func seededNoise(lat: Double, lon: Double, salt: Double) -> Double {
        let x = sin((lat + salt) * 12.9898 + (lon - salt) * 78.233) * 43758.5453
        return x - floor(x) // 0..1
    }

    func lightPollutionIndex(at coord: CLLocationCoordinate2D) -> Double {
        // mock: ~0.15..0.95
        let n = seededNoise(lat: coord.latitude, lon: coord.longitude, salt: 1.7)
        return 0.15 + 0.80 * n
    }

    func cloudCover(at coord: CLLocationCoordinate2D) -> Double {
        // mock: ~0.05..0.95
        let n = seededNoise(lat: coord.latitude, lon: coord.longitude, salt: 9.3)
        return 0.05 + 0.90 * n
    }

    func summary(at coord: CLLocationCoordinate2D) -> VisibilitySummary {
        let lp = lightPollutionIndex(at: coord)
        let cc = cloudCover(at: coord)

        // simple scoring: penalize both (clouds slightly more)
        let scoreDouble = 100.0 - (lp * 55.0) - (cc * 65.0)
        let clamped = max(0, min(100, Int(scoreDouble.rounded())))

        let label: String
        switch clamped {
        case 80...100: label = "Great"
        case 60...79:  label = "Good"
        case 40...59:  label = "Okay"
        case 20...39:  label = "Poor"
        default:       label = "Bad"
        }

        return VisibilitySummary(
            coordinate: coord,
            lightPollutionIndex: lp,
            cloudCover: cc,
            overallScore: clamped,
            label: label
        )
    }
}
