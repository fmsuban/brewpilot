import Foundation

/// Dry-run feed: the `-simulateWeights` launch argument drives a scripted
/// pour curve into the state machine (Day-4 verification without hardware).
enum SimFeed {
    private static var timer: Timer?
    private static var t0 = Date()

    static func start(_ session: BrewSession) {
        guard timer == nil else { return }
        t0 = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in tick(session) }
        }
    }

    @MainActor private static func tick(_ session: BrewSession) {
        let t = Date().timeIntervalSince(t0)
        if session.phase == .idle && t > 1 { session.start(recipe: session.recipe) }
        if session.phase == .prep && t > 2 { session.confirmPrep() }
        session.onWeight(simWeight(t))
    }

    /// Scripted absolute scale reading for the canned 22/350 recipe.
    /// App-side tare zeroes at 22 g, so pulse targets are +22 raw.
    private static func simWeight(_ t: Double) -> Double {
        let base: Double
        switch t {
        case ..<2: base = 0
        case ..<8: base = 22 * (t - 2) / 6 // add coffee 0→22
        case ..<16: base = 22 + 50 * (t - 8) / 8 // bloom pour →72
        case ..<61: base = 72 // bloom hold 45 s
        case ..<76: base = 72 + 100 * (t - 61) / 15 // p1 →172
        case ..<93: base = 172 + 100 * (t - 76) / 17 // p2 →272
        case ..<110: base = 272 + 100 * (t - 93) / 17 // p3 →372
        default: base = 372 // drawdown flat → done ≈ t+10 s
        }
        return base + Double.random(in: -0.3...0.3)
    }
}
