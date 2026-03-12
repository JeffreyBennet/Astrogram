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
    
    private let apiKey = "b36c476ba7d74a5c899220631261003"
    private var cache: [String: WeatherData] = [:]
    private var inFlight: Set<String> = []
    private let cacheQueue = DispatchQueue(label: "WeatherService.cache.queue")
    
    private func cacheKey(_ coord: CLLocationCoordinate2D) -> String {
        let bucketSize = 0.25
        let lat = (coord.latitude / bucketSize).rounded() * bucketSize
        let lon = (coord.longitude / bucketSize).rounded() * bucketSize
        return String(format: "%.2f,%.2f", lat, lon)
    }
    
    func cachedData(near coord: CLLocationCoordinate2D) -> WeatherData? {
        cacheQueue.sync {
            if let w = cache[cacheKey(coord)] { return w }
            return nil
        }
    }

    
    private func fetch(coord: CLLocationCoordinate2D) async {
        let key = cacheKey(coord)

        // Skip if already cached or already being fetched
        let shouldFetch = cacheQueue.sync { () -> Bool in
            if cache[key] != nil || inFlight.contains(key) { return false }
            inFlight.insert(key)
            return true
        }
        guard shouldFetch else { return }

        defer { cacheQueue.sync { inFlight.remove(key) } }

        let urlString = "https://api.weatherapi.com/v1/current.json?key=\(apiKey)&q=\(coord.latitude),\(coord.longitude)&aqi=no"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode(WeatherAPIResponse.self, from: data)
            let current = json.current

            let weather = WeatherData(
                coordinate: coord,
                cloudCoverFraction: Double(current.cloud) / 100.0,
                visibilityFraction: min(current.vis_km / 10.0, 1.0),
                humidityFraction: Double(current.humidity) / 100.0
            )

            cacheQueue.sync {
                cache[key] = weather
            }
        } catch {
            // fetch failed \(coord.latitude),\(coord.longitude): \(error)
        }
    }
    
    //fetch needed coordinates in parallel batches
    func fetchCoordinates(_ coords: [CLLocationCoordinate2D]) async {
        let toFetch = coords.filter { coord in
            let key = cacheKey(coord)
            return cacheQueue.sync { cache[key] == nil && !inFlight.contains(key) }
        }
        guard !toFetch.isEmpty else { return }

        for batchStart in stride(from: 0, to: toFetch.count, by: 8) {
            let batchEnd = min(batchStart + 8, toFetch.count)
            await withTaskGroup(of: Void.self) { group in
                for i in batchStart..<batchEnd {
                    let coord = toFetch[i]
                    group.addTask { await self.fetch(coord: coord) }
                }
            }
        }
    }

    // MARK: - Background crawler

    private var crawlTask: Task<Void, Never>?
    private var crawlCenter: CLLocationCoordinate2D?

    /// Start or restart the background crawler from a new center.
    /// Expands outward in rings, fetching weather at 0.25° intervals.
    /// Runs at low priority with pauses so it never impacts the UI.
    func startCrawling(from center: CLLocationCoordinate2D) {
        crawlTask?.cancel()
        crawlCenter = center

        crawlTask = Task(priority: .background) {
            let step = 0.25
            let maxRings = 20  // up to 5 degrees out in each direction

            for ring in 1...maxRings {
                guard !Task.isCancelled else { return }

                var ringCoords: [CLLocationCoordinate2D] = []
                let offset = Double(ring) * step

                // Top and bottom edges
                for col in -ring...ring {
                    let lon1 = center.longitude + Double(col) * step
                    ringCoords.append(CLLocationCoordinate2D(latitude: center.latitude + offset, longitude: lon1))
                    ringCoords.append(CLLocationCoordinate2D(latitude: center.latitude - offset, longitude: lon1))
                }
                // Left and right edges (excluding corners already added)
                for row in (-ring + 1)..<ring {
                    let lat1 = center.latitude + Double(row) * step
                    ringCoords.append(CLLocationCoordinate2D(latitude: lat1, longitude: center.longitude + offset))
                    ringCoords.append(CLLocationCoordinate2D(latitude: lat1, longitude: center.longitude - offset))
                }

                // Filter to uncached only
                let needed = ringCoords.filter { coord in
                    let key = self.cacheKey(coord)
                    return self.cacheQueue.sync { self.cache[key] == nil }
                }

                // Fetch in small batches with pauses
                for batchStart in stride(from: 0, to: needed.count, by: 4) {
                    guard !Task.isCancelled else { return }
                    let batchEnd = min(batchStart + 4, needed.count)
                    await withTaskGroup(of: Void.self) { group in
                        for i in batchStart..<batchEnd {
                            let coord = needed[i]
                            group.addTask { await self.fetch(coord: coord) }
                        }
                    }
                    // Pause between batches so foreground requests always win
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                }
            }
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
