//
//  SkyObject.swift
//  Astrogram
//


import Foundation

// Sky object lookup utilities
// Queries the SIMBAD TAP service for notable astronomical objects near a given
// right ascension and declination. No API key is required.

struct SkyObject {
    let name: String
    let type: String        // For example: "Star", "Galaxy", or "Nebula".
    let typeEmoji: String
    let ra: Double          // Right ascension in degrees.
    let dec: Double         // Declination in degrees.
    let separation: Double  // Angular distance from the query center, in degrees.
    let magnitude: Double?  // V-band magnitude if available.
}

// Errors that can occur when looking up sky objects.
enum SkyObjectLookupError: Error {
    case networkError(Error)
    case parseError(String)
    case noResults
}

// Looks up nearby astronomical objects using the SIMBAD TAP API.
struct SkyObjectLookupService {

    // Base URL for the SIMBAD TAP endpoint.
    private static let tapURL = "https://simbad.u-strasbg.fr/simbad/sim-tap/sync"

    static func lookup(
        //Right ascension in hours (0–24).
        ra: Double,
        //Declination in degrees.
        dec: Double,
        //radiusDeg: Search radius in degrees. Defaults to 5 degrees.
        radiusDeg: Double = 5.0,
        //Maximum number of results to return. Defaults to 15.
        limit: Int = 15,
        //Called on the main thread with the lookup result.
        completion: @escaping (Result<[SkyObject], SkyObjectLookupError>) -> Void
    ) {
        // SIMBAD expects right ascension in degrees for ADQL queries.
        let raDeg = ra * 15.0

        // Query the basic catalog and join fluxes, keeping the brightest (lowest V) first.
        let adql = """
        SELECT TOP \(limit) main_id, ra, dec, otype, V
        FROM basic
        JOIN allfluxes ON oidref = oid
        WHERE CONTAINS(
            POINT('ICRS', ra, dec),
            CIRCLE('ICRS', \(raDeg), \(dec), \(radiusDeg))
        ) = 1
        AND otype NOT IN ('**', 'err', '?')
        ORDER BY V ASC
        """

        var components = URLComponents(string: tapURL)!
        components.queryItems = [
            URLQueryItem(name: "REQUEST", value: "doQuery"),
            URLQueryItem(name: "LANG",    value: "ADQL"),
            URLQueryItem(name: "FORMAT",  value: "json"),
            URLQueryItem(name: "QUERY",   value: adql)
        ]

        guard let url = components.url else {
            completion(.failure(.parseError("Failed to build request URL.")))
            return
        }

        var request = URLRequest(url: url)
        // Keep the request snappy; this is used interactively in the UI.
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            // Report errors back on the main thread since callers typically update UI.
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(.networkError(error)))
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async { completion(.failure(.noResults)) }
                return
            }

            DispatchQueue.main.async {
                completion(parse(data: data, queryRA: raDeg, queryDec: dec))
            }
        }.resume()
    }

    // MARK: - Parsing

    private static func parse(data: Data,
                               queryRA: Double,
                               queryDec: Double) -> Result<[SkyObject], SkyObjectLookupError> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataSection = json["data"] as? [[Any]] else {
            return .failure(.parseError("Unexpected JSON structure"))
        }

        if dataSection.isEmpty { return .failure(.noResults) }

        var objects: [SkyObject] = []

        for row in dataSection {
            //Expected columns: main_id, ra, dec, otype, V (V may be missing).
            guard row.count >= 4,
                  let name = row[0] as? String,
                  let raVal  = row[1] as? Double,
                  let decVal = row[2] as? Double,
                  let otype  = row[3] as? String else { continue }

            let mag = row.count >= 5 ? row[4] as? Double : nil

            let sep = SolarLunarPredictor.angularSeparation(
                ra1: queryRA / 15.0, dec1: queryDec,
                ra2: raVal   / 15.0, dec2: decVal
            )

            let (friendlyType, emoji) = classify(otype: otype)

            objects.append(SkyObject(
                name: name.trimmingCharacters(in: .whitespaces),
                type: friendlyType,
                typeEmoji: emoji,
                ra: raVal,
                dec: decVal,
                separation: sep,
                magnitude: mag
            ))
        }

        //Sort results by angular separation (closest first).
        return .success(objects.sorted { $0.separation < $1.separation })
    }

    //Converts SIMBAD object type codes into friendly labels and an emoji.
    private static func classify(otype: String) -> (String, String) {
        switch otype {
        case "Star", "*", "s*", "sg*", "MS*": return ("Star", "⭐️")
        case "**", "SB*", "EB*":              return ("Binary Star", "⭐️")
        case "V*", "RR*", "Ce*", "LP*":       return ("Variable Star", "✨")
        case "Nova", "SN*":                    return ("Nova/Supernova", "💥")
        case "Neb", "RNe", "SNR", "HII":      return ("Nebula", "🌌")
        case "GlC":                            return ("Globular Cluster", "🔮")
        case "OpC":                            return ("Open Cluster", "🌠")
        case "Galaxy", "GAL", "G", "GiG":     return ("Galaxy", "🌀")
        case "QSO", "AGN", "Sy1", "Sy2":      return ("Quasar/AGN", "🔭")
        case "BH":                             return ("Black Hole", "⚫️")
        case "Psr":                            return ("Pulsar", "📡")
        case "WD*":                            return ("White Dwarf", "🤍")
        case "N*", "NS":                       return ("Neutron Star", "⚡️")
        case "Planet":                         return ("Planet", "🪐")
        default:                               return (otype, "🔭")
        }
    }
}
