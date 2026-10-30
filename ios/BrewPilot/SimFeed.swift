import UIKit

/// Dry-run feed: the `-simulateWeights` launch argument plays a virtual
/// barista into the state machine (no hardware). It doses, pours at a steady
/// rate until the stop cue (plus water still in the air), waits out the
/// rests, and taps Drained in the drawdown. Pulse 2 is poured too fast and
/// pulse 3 reacts late to the stop cue, to exercise flow + overshoot coaching.
@MainActor
enum SimFeed {
    private(set) static var isActive = false
    private static let dt = 0.1
    private static var timer: Timer?
    private static var t0 = Date()
    private static var raw = 0.0
    private static var sinceStopCue = 0.0
    private static var lastPhase: BrewPhase = .idle
    private static var phaseSince = Date()
    private static var anchor = 0.0
    private static var anchorSince = Date()

    static func start(_ session: BrewSession) {
        guard timer == nil else { return }
        isActive = true
        t0 = Date()
        print("[sim] dry run started")
        timer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { _ in
            Task { @MainActor in tick(session) }
        }
    }

    private static func tick(_ session: BrewSession) {
        let now = Date()
        if session.phase != lastPhase {
            lastPhase = session.phase
            phaseSince = now
        }
        let inPhase = now.timeIntervalSince(phaseSince)
        switch session.phase {
        case .idle where now.timeIntervalSince(t0) > 1:
            session.start(recipe: session.recipe)
        case .prep where inPhase > 1:
            session.confirmPrep()
        case .addCoffee:
            raw = min(raw + 6 * dt, 22.3) // spoon the dose in over ~4 s
        case .drawdown where inPhase > 25:
            session.markDrained()
        default:
            break
        }
        if session.awaitingPour {
            pour(session)
        } else {
            sinceStopCue = 0
        }
        session.onWeight(raw + Double.random(in: -0.15...0.15), settled: settled(now))
    }

    /// Steady pour; after the stop cue the stream takes a moment to stop.
    private static func pour(_ session: BrewSession) {
        let fast = session.phase == .pulse && session.pulseIndex == 1
        let late = session.phase == .pulse && session.pulseIndex == 2
        let tail = late ? 1.5 : 0.3 // seconds still pouring after the cue
        if session.stopCue {
            sinceStopCue += dt
            if sinceStopCue > tail { return }
        } else {
            sinceStopCue = 0
        }
        raw += (fast ? 9.0 : 6.0) * dt
    }

    /// Same rule as the firmware: within ±0.5 g for 1 s.
    private static func settled(_ now: Date) -> Bool {
        if abs(raw - anchor) > 0.5 {
            anchor = raw
            anchorSince = now
            return false
        }
        return now.timeIntervalSince(anchorSince) >= 1
    }

    /// Stand-in camera frame so vision calls run end-to-end in the simulator.
    static func frame() -> Data? {
        guard isActive else { return nil }
        let size = CGSize(width: 480, height: 640)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.93, green: 0.9, blue: 0.84, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cone = UIBezierPath()
            cone.move(to: CGPoint(x: 90, y: 220))
            cone.addLine(to: CGPoint(x: 390, y: 220))
            cone.addLine(to: CGPoint(x: 280, y: 470))
            cone.addLine(to: CGPoint(x: 200, y: 470))
            cone.close()
            UIColor.white.setFill()
            cone.fill()
            UIColor(red: 0.3, green: 0.18, blue: 0.1, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 130, y: 250, width: 220, height: 70)).fill()
        }
        return image.jpegData(compressionQuality: 0.6)
    }
}
