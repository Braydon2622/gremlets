import Testing
@testable import GremletsCore

@Suite struct WeatherTests {
    @Test func wmoCodesMapToSkies() {
        #expect(Sky(wmo: 0) == .clear)
        #expect(Sky(wmo: 3) == .cloudy)
        #expect(Sky(wmo: 45) == .fog)
        #expect(Sky(wmo: 53) == .drizzle)
        #expect(Sky(wmo: 63) == .rain)
        #expect(Sky(wmo: 81) == .rain)
        #expect(Sky(wmo: 73) == .snow)
        #expect(Sky(wmo: 95) == .storm)
        #expect(Sky.storm.splashRate > Sky.rain.splashRate && Sky.rain.splashRate > Sky.drizzle.splashRate)
    }

    @Test func snowPilesUpThenMelts() {
        let w = World(seed: 61)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        w.setWeather(LocalWeather(sky: .snow, tempC: -2))
        for _ in 0..<(60 * 600) { w.step(1.0 / 60) }        // ten minutes
        #expect(w.snowDepth > 0.4 && w.snowDepth < 0.6)
        w.setWeather(LocalWeather(sky: .clear, tempC: 6))
        for _ in 0..<(60 * 1300) { w.step(1.0 / 60) }
        #expect(w.snowDepth == 0)
    }

    @Test func previewEndsAndLiveWeatherReturns() {
        let w = World(seed: 62)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        w.setWeather(LocalWeather(sky: .cloudy))
        w.setWeather(LocalWeather(sky: .storm), previewSeconds: 5)
        #expect(w.weather?.sky == .storm)
        for _ in 0..<(60 * 6) { w.step(1.0 / 60) }
        #expect(w.weather?.sky == .cloudy)
    }

    @Test func gremletsHoldALeafInTheRainOnly() {
        let w = World(seed: 63)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = grounded(w, [400])[0]
        c.set(.walk, duration: 5)
        #expect(!w.holdsLeaf(c))
        w.setWeather(LocalWeather(sky: .rain))
        #expect(w.holdsLeaf(c))
        c.set(.sleep, duration: 5)
        #expect(!w.holdsLeaf(c))
    }

    @Test func noKitesInTheRain() {
        let w = World(seed: 64)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        let c = grounded(w, [400])[0]
        w.setWeather(LocalWeather(sky: .rain, windKmh: 40))
        var names: [String] = []
        w.kiteChoices(for: c) { n, _, _ in names.append(n) }
        #expect(!names.contains("kite"))
    }

    @Test func gremletsRollASnowGremletTogether() {
        let w = World(seed: 65)
        w.setEnvironment(screens: [screen], windowsFrontToBack: [])
        _ = grounded(w, [300, 360, 700])
        w.setWeather(LocalWeather(sky: .snow, tempC: -3))
        #expect(w.startSnowmanNow())
        var finished = false
        for _ in 0..<(60 * 120) {
            w.step(1.0 / 60)
            if w.snowmen.contains(where: { $0.built >= 1 }) { finished = true; break }
        }
        #expect(finished, "built: \(w.snowmen.map(\.built))")
        #expect(w.snowmen.count <= World.snowmanLimit)
        // Snow stops, it all melts away.
        w.setWeather(LocalWeather(sky: .clear, tempC: 8))
        for _ in 0..<(60 * 1500) { w.step(1.0 / 60) }
        #expect(w.snowmen.isEmpty)
        #expect(w.creatures.allSatisfy { $0.snowmanTask == nil })
    }
}
