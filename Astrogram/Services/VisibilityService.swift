//
//  VisibilityService.swift
//  Astrogram
//
//  Created by suva on 3/10/26.
//

import Foundation
import MapKit

final class VisibilityService {
    static let shared = VisibilityService()
    private init() {}
    
    // Tile cache
    private let tileCache = NSCache<NSString, CacheEntry>()
    
    // MARK: Weather layer generation
    func weatherLayer(type: WeatherLayerType) -> WeatherTileLayer {

        let urlTemplate: String

        switch type {
        case .clouds:
            urlTemplate = WeatherConfig.cloudTileURL + WeatherConfig.apiKey

        case .precipitation:
            urlTemplate = WeatherConfig.precipitationTileURL + WeatherConfig.apiKey
        }

        return WeatherTileLayer (
            urlTemplate: urlTemplate,
            cache: tileCache
        )
    }
}

// MARK: Cache entry definition
final class CacheEntry {
    let data: Data
    let timestamp: Date
    
    init(data: Data) {
        self.data = data
        self.timestamp = Date()
    }
}

// MARK: Cached tile overlay
final class WeatherTileLayer: MKTileOverlay {
    private let cache: NSCache<NSString, CacheEntry>

        init(urlTemplate: String, cache: NSCache<NSString, CacheEntry>) {
            self.cache = cache
            super.init(urlTemplate: urlTemplate)
            self.canReplaceMapContent = false
        }

        override func loadTile(at path: MKTileOverlayPath,
                               result: @escaping (Data?, Error?) -> Void) {

            let urlTemplate = urlTemplate ?? "weather"
            let cacheKey = "\(urlTemplate)-\(path.z)-\(path.x)-\(path.y)" as NSString

            // Check cache first
            if let cached = cache.object(forKey: cacheKey) {
                result(cached.data, nil)
                return
            }

            // Build tile URL
            let tileURL = self.url(forTilePath: path)

            // Fetch tile
            let task = URLSession.shared.dataTask(with: tileURL) { [weak self] data, _, error in

                guard let self = self else { return }

                if let data = data {
                    self.cache.setObject(CacheEntry(data: data), forKey: cacheKey)
                    result(data, nil)
                } else {
                    result(nil, error)
                }
            }

            task.resume()
        }
}
