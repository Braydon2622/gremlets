import Foundation
import GremletsCore

/// Real weather from Open-Meteo (free, no key, no account). Off until you type a city in the menu
/// (Gremlets → Weather → Set Your City…): no location permission is asked for. Only the city's name (once, to look up
/// its coordinates) and those coordinates (every 20 minutes) leave your Mac.
final class WeatherService {
    struct Place: Codable, Equatable { let name: String; let lat: Double; let lon: Double }

    private let world: World
    private var timer: Timer?
    var onChange: () -> Void = {}
    private(set) var current: LocalWeather?
    private(set) var lastError: String?

    var place: Place? {
        get { UserDefaults.standard.data(forKey: "weather.place").flatMap { try? JSONDecoder().decode(Place.self, from: $0) } }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "weather.place")
            if newValue == nil { current = nil; world.setWeather(nil) }
            restart()
        }
    }

    init(world: World) { self.world = world }

    func restart() {
        timer?.invalidate(); timer = nil
        guard place != nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard let p = place else { return }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", p.lat)), .init(name: "longitude", value: String(format: "%.2f", p.lon)),
            .init(name: "current", value: "weather_code,wind_speed_10m,temperature_2m"),
        ]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, err in
            let parsed = data.flatMap { Self.parse($0, place: p.name) }
            DispatchQueue.main.async {
                guard let self else { return }
                if let w = parsed {
                    self.current = w; self.lastError = nil
                    self.world.setWeather(w)
                } else {
                    self.lastError = err?.localizedDescription ?? "no weather in the reply"
                }
                self.onChange()
            }
        }.resume()
    }

    static func parse(_ data: Data, place: String) -> LocalWeather? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let cur = j["current"] as? [String: Any],
              let code = (cur["weather_code"] as? NSNumber)?.intValue else { return nil }
        return LocalWeather(sky: Sky(wmo: code), windKmh: (cur["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 0,
                            tempC: (cur["temperature_2m"] as? NSNumber)?.doubleValue ?? 12, place: place)
    }

    /// Looks a city up (Open-Meteo's geocoder) and switches weather on for it.
    func setCity(_ name: String, done: @escaping (Place?) -> Void) {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { done(nil); return }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: q), .init(name: "count", value: "1")]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, _ in
            var found: Place?
            if let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let r = (j["results"] as? [[String: Any]])?.first,
               let lat = (r["latitude"] as? NSNumber)?.doubleValue, let lon = (r["longitude"] as? NSNumber)?.doubleValue {
                let n = (r["name"] as? String) ?? q
                found = Place(name: n, lat: lat, lon: lon)
            }
            DispatchQueue.main.async {
                if let f = found { self?.place = f }
                done(found)
            }
        }.resume()
    }

    /// "Rain · Seattle 9°", for the menu.
    var summary: String? {
        guard let w = current else { return place.map { "\($0.name) · checking…" } }
        return "\(w.sky.label)\(w.windy ? ", windy" : "") · \(w.place) \(Int(w.tempC.rounded()))°"
    }
}
