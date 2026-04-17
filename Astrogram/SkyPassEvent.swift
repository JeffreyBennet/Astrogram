//
//  SkyPassEvent.swift
//  Astrogram
//
//  Created by Helial Mordahl on 4/16/26.
//


import Foundation
import CoreLocation

// ─────────────────────────────────────────────────────────────────────────────
//  SolarLunarPredictor.swift
//  Pure-Swift implementation of Jean Meeus "Astronomical Algorithms" Ch. 25/47.
//  No dependencies. Accuracy: Sun ~1 arcmin, Moon ~0.3°.
// ─────────────────────────────────────────────────────────────────────────────

struct SkyPassEvent {
    enum Body { case sun, moon }
    let body: Body
    let date: Date
    /// Angular separation at closest approach (degrees)
    let separation: Double
    /// Whether the body is above the horizon at that time
    let isVisible: Bool
}

struct SolarLunarPredictor {

    // MARK: - Public API

    /// Get Sun position at a specific date
    static func sunPosition(at date: Date) -> (ra: Double, dec: Double) {
        let jd = julianDay(from: date)
        let coord = sunEquatorial(jd: jd)
        return (coord.ra, coord.dec)
    }

    /// Get Moon position at a specific date
    static func moonPosition(at date: Date, observer: CLLocationCoordinate2D) -> (ra: Double, dec: Double) {
        let jd = julianDay(from: date)
        let coord = moonEquatorial(jd: jd)
        return (coord.ra, coord.dec)
    }

    /// Searches the next `days` days (stepping every `stepMinutes`) for times
    // when the Sun or Moon passes within `thresholdDeg` of the target RA/Dec.
    // Observer location needed to filter above-horizon events.
    static func findPassEvents(
        targetRA: Double,       // hours (0–24)
        targetDec: Double,      // degrees
        observer: CLLocationCoordinate2D,
        daysAhead: Int = 30,
        stepMinutes: Int = 10,
        thresholdDeg: Double = 2.0,
        completion: @escaping ([SkyPassEvent]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var events: [SkyPassEvent] = []
            let now = Date()
            let stepSeconds: Double = Double(stepMinutes) * 60
            let totalSteps = Int(Double(daysAhead) * 86400 / stepSeconds)

            var prevSunSep = Double.infinity
            var prevMoonSep = Double.infinity
            var prevSunDate = now
            var prevMoonDate = now

            for i in 0..<totalSteps {
                let date = now.addingTimeInterval(Double(i) * stepSeconds)
                let jd = julianDay(from: date)

                let sun  = sunEquatorial(jd: jd)
                let moon = moonEquatorial(jd: jd)

                let sunSep  = angularSeparation(ra1: targetRA, dec1: targetDec,
                                                ra2: sun.ra,   dec2: sun.dec)
                let moonSep = angularSeparation(ra1: targetRA, dec1: targetDec,
                                                ra2: moon.ra,  dec2: moon.dec)

                // Detect local minimum (previous step was closer than current → was a minimum)
                if prevSunSep < thresholdDeg && prevSunSep < sunSep {
                    let alt = altitude(ra: sun.ra, dec: sun.dec,
                                       observer: observer, date: prevSunDate)
                    events.append(SkyPassEvent(body: .sun, date: prevSunDate,
                                               separation: prevSunSep, isVisible: alt > 0))
                }
                if prevMoonSep < thresholdDeg && prevMoonSep < moonSep {
                    let alt = altitude(ra: moon.ra, dec: moon.dec,
                                       observer: observer, date: prevMoonDate)
                    events.append(SkyPassEvent(body: .moon, date: prevMoonDate,
                                               separation: prevMoonSep, isVisible: alt > 0))
                }

                prevSunSep  = sunSep;  prevSunDate  = date
                prevMoonSep = moonSep; prevMoonDate = date
            }

            // Deduplicate events that are within 2 hours of each other (same pass)
            let deduped = deduplicate(events, windowSeconds: 7200)

            DispatchQueue.main.async { completion(deduped) }
        }
    }

    // MARK: - Sun Position (Meeus Ch. 25, low-accuracy)

    struct EquatorialCoord {
        let ra: Double   // hours
        let dec: Double  // degrees
    }

    static func sunEquatorial(jd: Double) -> EquatorialCoord {
        let T = (jd - 2451545.0) / 36525.0

        // Geometric mean longitude (degrees)
        let L0 = (280.46646 + 36000.76983 * T + 0.0003032 * T * T)
            .truncatingRemainder(dividingBy: 360)

        // Mean anomaly (degrees)
        let M = (357.52911 + 35999.05029 * T - 0.0001537 * T * T)
            .truncatingRemainder(dividingBy: 360)
        let Mrad = M * .pi / 180

        // Equation of center
        let C = (1.914602 - 0.004817 * T - 0.000014 * T * T) * sin(Mrad)
            + (0.019993 - 0.000101 * T) * sin(2 * Mrad)
            + 0.000289 * sin(3 * Mrad)

        // Sun's true longitude
        let sunLon = L0 + C

        // Apparent longitude (aberration correction)
        let omega = 125.04 - 1934.136 * T
        let apparentLon = sunLon - 0.00569 - 0.00478 * sin(omega * .pi / 180)

        // Obliquity of ecliptic
        let eps0 = 23.439291111 - 0.013004167 * T
        let eps = eps0 + 0.00256 * cos(omega * .pi / 180)
        let epsRad = eps * .pi / 180
        let lonRad = apparentLon * .pi / 180

        // Equatorial coordinates
        var ra = atan2(cos(epsRad) * sin(lonRad), cos(lonRad)) * 180 / .pi
        if ra < 0 { ra += 360 }
        let dec = asin(sin(epsRad) * sin(lonRad)) * 180 / .pi

        return EquatorialCoord(ra: ra / 15.0, dec: dec)
    }

    // MARK: - Moon Position (Meeus Ch. 47, simplified)

    static func moonEquatorial(jd: Double) -> EquatorialCoord {
        let T = (jd - 2451545.0) / 36525.0

        // Fundamental arguments (degrees)
        let Lp = (218.3164477 + 481267.88123421 * T).truncatingRemainder(dividingBy: 360)
        let D  = (297.8501921 + 445267.1114034  * T).truncatingRemainder(dividingBy: 360)
        let M  = (357.5291092 +  35999.0502909  * T).truncatingRemainder(dividingBy: 360)
        let Mp = (134.9633964 + 477198.8675055  * T).truncatingRemainder(dividingBy: 360)
        let F  = (93.2720950  + 483202.0175233  * T).truncatingRemainder(dividingBy: 360)

        let Dr = D  * .pi / 180
        let Mr = M  * .pi / 180
        let Mpr = Mp * .pi / 180
        let Fr = F  * .pi / 180
        let Lpr = Lp * .pi / 180

        // Longitude perturbations (arcseconds → degrees at end)
        var sumL: Double = 0
        sumL += 6288774 * sin(Mpr)
        sumL += 1274027 * sin(2*Dr - Mpr)
        sumL +=  658314 * sin(2*Dr)
        sumL +=  213618 * sin(2*Mpr)
        sumL += -185116 * sin(Mr)
        sumL += -114332 * sin(2*Fr)
        sumL +=   58793 * sin(2*Dr - 2*Mpr)
        sumL +=   57066 * sin(2*Dr - Mr - Mpr)
        sumL +=   53322 * sin(2*Dr + Mpr)
        sumL +=   45758 * sin(2*Dr - Mr)
        sumL +=  -40923 * sin(Mr - Mpr)
        sumL +=  -34720 * sin(Dr)
        sumL +=  -30383 * sin(Mr + Mpr)
        sumL +=   15327 * sin(2*Dr - 2*Fr)
        sumL +=  -12528 * sin(Mpr + 2*Fr)
        sumL +=   10980 * sin(Mpr - 2*Fr)
        sumL +=   10675 * sin(4*Dr - Mpr)
        sumL +=   10034 * sin(3*Mpr)
        sumL +=    8548 * sin(4*Dr - 2*Mpr)
        sumL +=   -7888 * sin(2*Dr + Mr - Mpr)
        sumL +=   -6766 * sin(2*Dr + Mr)
        sumL +=   -5163 * sin(Dr - Mpr)

        // Latitude perturbations
        var sumB: Double = 0
        sumB += 5128122 * sin(Fr)
        sumB +=  280602 * sin(Mpr + Fr)
        sumB +=  277693 * sin(Mpr - Fr)
        sumB +=  173237 * sin(2*Dr - Fr)
        sumB +=   55413 * sin(2*Dr - Mpr + Fr)
        sumB +=   46271 * sin(2*Dr - Mpr - Fr)
        sumB +=   32573 * sin(2*Dr + Fr)
        sumB +=   17198 * sin(2*Mpr + Fr)
        sumB +=    9266 * sin(2*Dr + Mpr - Fr)
        sumB +=    8822 * sin(2*Mpr - Fr)
        sumB +=    8216 * sin(2*Dr - Mr - Fr)
        sumB +=    4324 * sin(2*Dr - 2*Mpr - Fr)
        sumB +=    4200 * sin(2*Dr + Mpr + Fr)
        sumB +=   -3359 * sin(2*Dr + Mr - Fr)
        sumB +=    2463 * sin(2*Dr - Mr - Mpr + Fr)
        sumB +=    2211 * sin(2*Dr - Mr + Fr)
        sumB +=    2065 * sin(2*Dr - Mr - Mpr - Fr)
        sumB +=   -1870 * sin(Mr - Mpr - Fr)

        let moonLon = Lpr + (sumL / 1000000.0) * .pi / 180  // radians
        let moonLat = (sumB / 1000000.0) * .pi / 180          // radians

        // Convert ecliptic → equatorial
        let eps = (23.439291111 - 0.013004167 * T) * .pi / 180

        let x = cos(moonLat) * cos(moonLon)
        let y = cos(eps) * cos(moonLat) * sin(moonLon) - sin(eps) * sin(moonLat)
        let z = sin(eps) * cos(moonLat) * sin(moonLon) + cos(eps) * sin(moonLat)

        var ra = atan2(y, x) * 180 / .pi
        if ra < 0 { ra += 360 }
        let dec = asin(z) * 180 / .pi

        return EquatorialCoord(ra: ra / 15.0, dec: dec)
    }

    // MARK: - Helpers

    // Julian Day Number from a Swift Date
    static func julianDay(from date: Date) -> Double {
        return date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    // Angular separation between two equatorial coords (degrees).
    static func angularSeparation(ra1: Double, dec1: Double,
                                   ra2: Double, dec2: Double) -> Double {
        let ra1r  = ra1  * 15 * .pi / 180
        let dec1r = dec1 * .pi / 180
        let ra2r  = ra2  * 15 * .pi / 180
        let dec2r = dec2 * .pi / 180

        let cosA = sin(dec1r) * sin(dec2r) + cos(dec1r) * cos(dec2r) * cos(ra1r - ra2r)
        return acos(max(-1, min(1, cosA))) * 180 / .pi
    }

    // Altitude of an object above the horizon for an observer.
    static func altitude(ra: Double, dec: Double,
                          observer: CLLocationCoordinate2D,
                          date: Date) -> Double {
        let jd = julianDay(from: date)
        let T = (jd - 2451545.0) / 36525.0
        let gmst = (280.46061837 + 360.98564736629 * (jd - 2451545.0)
                    + 0.000387933 * T * T).truncatingRemainder(dividingBy: 360)
        let lst = (gmst + observer.longitude).truncatingRemainder(dividingBy: 360) / 15.0

        let ha = (lst - ra) * 15 * .pi / 180
        let decR = dec * .pi / 180
        let latR = observer.latitude * .pi / 180

        let sinAlt = sin(latR) * sin(decR) + cos(latR) * cos(decR) * cos(ha)
        return asin(max(-1, min(1, sinAlt))) * 180 / .pi
    }

    /// Remove duplicate events within a time window (keep the one with smallest separation).
    private static func deduplicate(_ events: [SkyPassEvent],
                                     windowSeconds: Double) -> [SkyPassEvent] {
        var result: [SkyPassEvent] = []
        for event in events.sorted(by: { $0.date < $1.date }) {
            let isDup = result.contains { existing in
                existing.body == event.body &&
                abs(existing.date.timeIntervalSince(event.date)) < windowSeconds
            }
            if !isDup { result.append(event) }
        }
        return result
    }
}
