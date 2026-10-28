import Foundation

/// Standalone pour timer (replaces the old on-device MANUAL/AUTO timer).
/// Auto-start: the first +3 g rise after reset starts it, like AUTO POUR did.
@MainActor
final class ScaleStopwatch: ObservableObject {
    @Published var elapsed = 0.0
    @Published var running = false
    @Published var autoStart = true

    private var accum = 0.0
    private var startAt = Date()
    private var base: Double?
    private var ticker: Timer?

    func onWeight(_ g: Double) {
        if base == nil { base = g }
        if autoStart, !running, elapsed == 0, let b = base, g - b > 3 {
            start()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        startAt = Date()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.elapsed = self.accum + Date().timeIntervalSince(self.startAt)
            }
        }
    }

    func stop() {
        guard running else { return }
        accum = elapsed
        running = false
        ticker?.invalidate()
    }

    func reset() {
        ticker?.invalidate()
        running = false
        accum = 0
        elapsed = 0
        base = nil
    }
}
