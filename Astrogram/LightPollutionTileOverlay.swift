import MapKit


final class LightPollutionTileOverlay: MKTileOverlay {

    //api has very limited zoom levels (global -> ~ size of texas)
    private let tileMinZ = 1
    private let tileMaxZ = 6

    override init(urlTemplate: String?) {
        super.init(urlTemplate: nil)
        minimumZ = tileMinZ
        maximumZ = tileMaxZ
        canReplaceMapContent = false
        tileSize = CGSize(width: 256, height: 256)
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        guard path.z >= tileMinZ && path.z <= tileMaxZ else {
            return URL(string: "about:blank")!
        }

        //this api kind of sucks but oh well, probably will remove it
        return URL(string:
            "https://tiles.arcgis.com/tiles/lDFzr3JyGEn5Eymu/arcgis/rest/services/0961_LightPollution/MapServer/tile/\(path.z)/\(path.y)/\(path.x)"
        )!
    }
}
