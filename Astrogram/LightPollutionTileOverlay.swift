import MapKit
import UIKit


final class LightPollutionTileOverlay: MKTileOverlay {

    private static let sampleZoom = 6
    private static let sampleCache = NSCache<NSString, NSNumber>()

    /// Sync cache-only lookup for renderer draw calls.
    static func cachedLightPollutionIndex(at coord: CLLocationCoordinate2D) -> Double {
        let key = String(format: "%.3f,%.3f", coord.latitude, coord.longitude) as NSString
        return sampleCache.object(forKey: key)?.doubleValue ?? 0.0
    }

    /// Returns a light pollution index (0 = dark, 1 = bright) for the given coordinate
    /// by sampling the ArcGIS tile pixel brightness.
    static func lightPollutionIndex(at coord: CLLocationCoordinate2D) async -> Double {
        let key = String(format: "%.3f,%.3f", coord.latitude, coord.longitude) as NSString
        if let cached = sampleCache.object(forKey: key) {
            return cached.doubleValue
        }

        let z = sampleZoom
        let n = Double(1 << z)
        let latRad = coord.latitude * .pi / 180.0
        let tileX = Int((coord.longitude + 180.0) / 360.0 * n)
        let tileY = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)

        let url = URL(string:
            "https://tiles.arcgis.com/tiles/lDFzr3JyGEn5Eymu/arcgis/rest/services/0961_LightPollution/MapServer/tile/\(z)/\(tileY)/\(tileX)"
        )!

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data), let cgImage = image.cgImage else { return 0.0 }

            // Find pixel position within the tile
            let fracX = (coord.longitude + 180.0) / 360.0 * n - Double(tileX)
            let fracY = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n - Double(tileY)
            let px = min(Int(fracX * Double(cgImage.width)), cgImage.width - 1)
            let py = min(Int(fracY * Double(cgImage.height)), cgImage.height - 1)

            // Read pixel
            guard let provider = cgImage.dataProvider, let pixelData = provider.data else { return 0.0 }
            let ptr = CFDataGetBytePtr(pixelData)!
            let bytesPerPixel = cgImage.bitsPerPixel / 8
            let bytesPerRow = cgImage.bytesPerRow
            let offset = py * bytesPerRow + px * bytesPerPixel

            let r = Double(ptr[offset]) / 255.0
            let g = Double(ptr[offset + 1]) / 255.0
            let b = Double(ptr[offset + 2]) / 255.0
            let a = bytesPerPixel >= 4 ? Double(ptr[offset + 3]) / 255.0 : 1.0

            // Transparent = no light pollution data = dark sky
            guard a > 0.1 else {
                sampleCache.setObject(NSNumber(value: 0.0), forKey: key)
                return 0.0
            }

            // Brightness as light pollution index
            let brightness = (r + g + b) / 3.0
            sampleCache.setObject(NSNumber(value: brightness), forKey: key)
            return brightness
        } catch {
            return 0.0
        }
    }

    private let tileMaxZ = 6

    override init(urlTemplate: String?) {
        super.init(urlTemplate: nil)
        minimumZ = 1
        maximumZ = 20
        canReplaceMapContent = false
        tileSize = CGSize(width: 256, height: 256)
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let z = min(path.z, tileMaxZ)
        let diff = path.z - z
        let x = path.x >> diff
        let y = path.y >> diff

        return URL(string:
            "https://tiles.arcgis.com/tiles/lDFzr3JyGEn5Eymu/arcgis/rest/services/0961_LightPollution/MapServer/tile/\(z)/\(y)/\(x)"
        )!
    }

    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, Error?) -> Void) {
        guard path.z > tileMaxZ else {
            super.loadTile(at: path, result: result)
            return
        }

        // Zoom exceeds API max — fetch the parent tile at tileMaxZ
        // and crop + scale the relevant sub-region.
        let diff = path.z - tileMaxZ
        let scale = 1 << diff

        var parentPath = path
        parentPath.z = tileMaxZ
        parentPath.x = path.x >> diff
        parentPath.y = path.y >> diff

        let parentURL = url(forTilePath: parentPath)

        URLSession.shared.dataTask(with: parentURL) { [tileSize] data, _, error in
            guard let data = data, let parentImage = UIImage(data: data) else {
                result(nil, error)
                return
            }

            let localX = path.x % scale
            let localY = path.y % scale

            // Draw the parent image scaled up so only the sub-tile portion
            // is visible in the 256x256 output context.
            let renderer = UIGraphicsImageRenderer(size: tileSize)
            let tileData = renderer.pngData { _ in
                let scaledSize = CGSize(width: tileSize.width * CGFloat(scale),
                                        height: tileSize.height * CGFloat(scale))
                let origin = CGPoint(x: -CGFloat(localX) * tileSize.width,
                                     y: -CGFloat(localY) * tileSize.height)
                parentImage.draw(in: CGRect(origin: origin, size: scaledSize))
            }

            result(tileData, nil)
        }.resume()
    }
}
