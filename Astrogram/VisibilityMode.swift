import Foundation
import CoreLocation

struct VisibilitySummary {
    let coordinate: CLLocationCoordinate2D
    let lightPollutionIndex: Double
    let cloudCover: Double
    let visibility: Double
    let humidity: Double
    let overallScore: Int
    let label: String
    let isRealData: Bool
}

final class VisibilityCalculator {

    private func seededNoise(lat: Double, lon: Double, salt: Double) -> Double {
        let x = sin((lat + salt) * 12.9898 + (lon - salt) * 78.233) * 43758.5453
        return x - floor(x)
    }

    /// Async version — fetches tile from network if not cached. Use for tap interactions.
    func lightPollutionIndex(at coord: CLLocationCoordinate2D) async -> Double {
        return await LightPollutionTileOverlay.lightPollutionIndex(at: coord)
    }

    /// Sync version — returns cached value or 0. Use for renderer draw calls.
    func lightPollutionIndexCached(at coord: CLLocationCoordinate2D) -> Double {
        return LightPollutionTileOverlay.cachedLightPollutionIndex(at: coord)
    }

    func cloudCover(at coord: CLLocationCoordinate2D) -> Double {
        if let w = WeatherService.shared.cachedData(near: coord) {
            return w.cloudCoverFraction
        }
        let n = seededNoise(lat: coord.latitude, lon: coord.longitude, salt: 9.3)
        return 0.05 + 0.90 * n
    }

    /// Async summary — fetches light pollution from network. Use for tap interactions.
    func summary(at coord: CLLocationCoordinate2D) async -> VisibilitySummary {
        let lp = await lightPollutionIndex(at: coord)
        return buildSummary(at: coord, lp: lp)
    }

    /// Sync summary — uses cached light pollution only. Use for renderer draw calls.
    func summaryCached(at coord: CLLocationCoordinate2D) -> VisibilitySummary {
        let lp = lightPollutionIndexCached(at: coord)
        return buildSummary(at: coord, lp: lp)
    }

    private func buildSummary(at coord: CLLocationCoordinate2D, lp: Double) -> VisibilitySummary {
        let weather = WeatherService.shared.cachedData(near: coord)
        let cc = weather?.cloudCoverFraction ?? cloudCover(at: coord)
        let vis = weather?.visibilityFraction ?? 1.0
        let hum = weather?.humidityFraction ?? 0.5
        let isReal = weather != nil

        // clouds and light pollution hurt most, low visibility and high humidity also penalize
        let score = 100.0 - (lp * 40.0) - (cc * 40.0) - ((1.0 - vis) * 10.0) - (hum * 10.0)
        let clamped = max(0, min(100, Int(score.rounded())))

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
            visibility: vis,
            humidity: hum,
            overallScore: clamped,
            label: label,
            isRealData: isReal
        )
    }
}
