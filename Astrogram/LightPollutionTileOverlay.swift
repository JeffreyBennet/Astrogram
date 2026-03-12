import MapKit
import UIKit


final class LightPollutionTileOverlay: MKTileOverlay {

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
