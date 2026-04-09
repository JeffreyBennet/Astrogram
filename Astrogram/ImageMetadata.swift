
//
//  ImageMetadata.swift
//  Astrogram
//


import UIKit
import Photos
import PhotosUI
import ImageIO


struct ImageMetadata {
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var fNumber: Double?
    var exposureTime: Double?
    var iso: [Int]?
    var latitude: Double?
    var longitude: Double?
    var focalLength: Double?

    var focalLengthFormatted: String? {
        guard let f = focalLength else { return nil }
        return "\(Int(f))mm"
    }
    
    var fNumberFormatted: String? {
        guard let f = fNumber else { return nil }
        return "f/\(f)"
    }

    var shutterSpeedFormatted: String? {
        guard let t = exposureTime else { return nil }
        if t >= 1 { return "\(t)s" }
        return "1/\(Int(round(1.0 / t)))s"
    }

    var isoFormatted: String? {
        guard let iso = iso?.first else { return nil }
        return "\(iso)"
    }

    var coordinateFormatted: String? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return "\(lat), \(lon)"
    }
}


class ImageMetadataExtractor {

    static func extract(from result: PHPickerResult, completion: @escaping (UIImage?, ImageMetadata?) -> Void) {
        guard let assetIdentifier = result.assetIdentifier else {
            completion(nil, nil)
            return
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            completion(nil, nil)
            return
        }

        let editOptions = PHContentEditingInputRequestOptions()
        editOptions.isNetworkAccessAllowed = true

        asset.requestContentEditingInput(with: editOptions) { input, _ in
            guard let url = input?.fullSizeImageURL else {
                completion(nil, nil)
                return
            }

            let metadata = Self.extractEXIF(from: url)

            let imageOptions = PHImageRequestOptions()
            imageOptions.isNetworkAccessAllowed = true
            imageOptions.deliveryMode = .highQualityFormat

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: imageOptions
            ) { image, _ in
                DispatchQueue.main.async {
                    completion(image, metadata)
                }
            }
        }
    }


    private static func extractEXIF(from url: URL) -> ImageMetadata {
        var meta = ImageMetadata()

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return meta }

        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            meta.cameraMake  = tiff[kCGImagePropertyTIFFMake as String] as? String
            meta.cameraModel = tiff[kCGImagePropertyTIFFModel as String] as? String
        }

        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            meta.lensModel    = exif[kCGImagePropertyExifLensModel as String] as? String
            meta.fNumber      = exif[kCGImagePropertyExifFNumber as String] as? Double
            meta.exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double
            meta.iso          = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int]
            meta.focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double
        }

        if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            let lat    = gps[kCGImagePropertyGPSLatitude as String] as? Double
            let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String
            let lon    = gps[kCGImagePropertyGPSLongitude as String] as? Double
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String

            meta.latitude  = (latRef == "S") ? -(lat ?? 0) : lat
            meta.longitude = (lonRef == "W") ? -(lon ?? 0) : lon
        }

        return meta
    }
}
