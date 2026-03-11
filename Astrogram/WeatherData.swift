//
//  WeatherData.swift
//  Astrogram
//
//  Created by Helial Mordahl on 3/10/26.
//


import Foundation
import CoreLocation
import MapKit

struct WeatherData {
    let coordinate: CLLocationCoordinate2D
    let cloudCoverFraction: Double  // 0..1
    let visibilityFraction: Double  // 0..1 (normalized from 0..10km)
    let humidityFraction: Double    // 0..1
}

final class WeatherService {
    static let shared = WeatherService()
    private init() {}

    private let apiKey = SECRET_KEY
    private var cache: [String: WeatherData] = [:]
//    private let cachePrecision = 1

    private func cacheKey(_ coord: CLLocationCoordinate2D) -> String {
        let lat = (coord.latitude  * 10).rounded()
        let lon = (coord.longitude * 10).rounded()
        return "\(lat),\(lon)"
    }

    func cachedData(near coord: CLLocationCoordinate2D) -> WeatherData? {
        cache[cacheKey(coord)]
    }

    //non concurrent fetch implementation
    //TODO: make fetch grid concurrent
    func fetchGrid(for region: MKCoordinateRegion, steps: Int = 6) async {
        let latStep = region.span.latitudeDelta / Double(steps)
        let lonStep = region.span.longitudeDelta / Double(steps)

        for row in 0..<steps {
            for col in 0..<steps {
                let lat = region.center.latitude - region.span.latitudeDelta / 2 + latStep * (Double(row) + 0.5)
                let lon = region.center.longitude - region.span.longitudeDelta / 2 + lonStep * (Double(col) + 0.5)
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                let key = cacheKey(coord)

                guard cache[key] == nil else { continue }
                await fetch(coord: coord)
            }
        }
    }

    //fetches api response,
    private func fetch(coord: CLLocationCoordinate2D) async {
        print("Fetching: \(coord.latitude), \(coord.longitude)")
        let urlString = "https://api.weatherapi.com/v1/current.json?key=\(apiKey)&q=\(coord.latitude),\(coord.longitude)&aqi=no"
        guard let url = URL(string: urlString) else {   print("Bad URL"); return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let raw = String(data: data, encoding: .utf8) {
                     print("Response: \(raw.prefix(200))")
                 }
            let json = try JSONDecoder().decode(WeatherAPIResponse.self, from: data)
            let current = json.current

            let weather = WeatherData(
                coordinate: coord,
                cloudCoverFraction: Double(current.cloud) / 100.0,
                visibilityFraction: min(current.vis_km / 10.0, 1.0),  // cap at 10km
                humidityFraction: Double(current.humidity) / 100.0
            )

            cache[cacheKey(coord)] = weather
        } catch {
            print("WeatherService fetch error: \(error)")
        }
    }
}

//struct format for api response, handles vis sometimes being double
//note: api has more data in it, but this is all i feel is necessary.
//can easily expand 
private struct WeatherAPIResponse: Decodable {
    let current: Current

    //need this for varying returns of double or int
    struct Current: Decodable {
        let cloud: Int
        let vis_km: Double
        let humidity: Int

        enum CodingKeys: String, CodingKey {
            case cloud, vis_km, humidity
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cloud = try c.decode(Int.self, forKey: .cloud)
            humidity = try c.decode(Int.self, forKey: .humidity)
            if let d = try? c.decode(Double.self, forKey: .vis_km) {
                vis_km = d
            } else {
                vis_km = Double(try c.decode(Int.self, forKey: .vis_km))
            }
        }
    }
}
