//
//  WeatherConfig.swift
//  Astrogram
//
//  Created by suva on 3/10/26.
//

import Foundation

struct WeatherConfig {
    // API KEY
    static let apiKey = "e73d71665bab05c032bf29ab127c5d08"
    
    // Cloud layer tile endpoint
    static let cloudTileURL = "https://tile.openweathermap.org/map/clouds_new/{z}/{x}/{y}.png?appid="
    
    // Precipitation layer tile endpoint
    static let precipitationTileURL = "https://tile.openweathermap.org/map/precipitation_new/{z}/{x}/{y}.png?appid="
}
