import Foundation

// Deterministic brew state machine (SPEC 8.1). Timing, targets and flow math
// live here, never in a model call. AI only plans, perceives and talks.

enum BrewPhase: String, Codable {
    case idle, prep, addCoffee, tare, bloom, pulse, drawdown, done, paused
}

enum GuardRail {
    static let dropGrams = 8.0
    static let dropWindowS = 1.0
    static let overshootG = 5.0
    static let silenceS = 1.5
    static let drawdownFlowMlS = 0.5
    static let drawdownSettleS = 10.0
    static let drawdownTimeoutS = 90.0
    static let flowWindowS = 0.5
}

@MainActor
final class BrewSession: ObservableObject {
    @Published var phase: BrewPhase = .idle
    @Published var recipe: Recipe = .canned
    @Published var weightG = 0.0
    @Published var flowMlS = 0.0
    @Published var targetG = 0.0
    @Published var instruction = "Set up the rig, then start."
    @Published var coachMessages: [CoachMessage] = []
    @Published var eventLog: [BrewSample] = []
    @Published var scaleConnected = false

    let scale = ScaleBLEManager()
    private var history: [(t: Date, w: Double)] = []
    private var lastSampleAt = Date()
    private var startedAt = Date()

    init() {
        scale.onWeight = { [weak self] grams in
            Task { @MainActor in self?.onWeight(grams) }
        }
        scale.onConnectionChange = { [weak self] connected in
            Task { @MainActor in self?.scaleConnected = connected }
        }
    }

    var elapsedS: Double { Date().timeIntervalSince(startedAt) }

    func start(recipe: Recipe) {
        self.recipe = recipe
        phase = .prep
        eventLog = []
        coachMessages = []
        history = []
        startedAt = Date()
        instruction = "Rinse the filter, heat the kettle, then confirm."
    }

    func coach(_ text: String, severity: String = "info") {
        coachMessages.append(CoachMessage(text: text, severity: severity))
    }

    /// Called at 10 Hz from BLE. Guard rails first, then logging.
    /// Full phase transitions land day 4; guards already protect every phase.
    func onWeight(_ grams: Double) {
        let now = Date()
        let dt = now.timeIntervalSince(lastSampleAt)
        lastSampleAt = now

        // Guard: rig lifted or moved.
        if dt > 0 && dt < GuardRail.dropWindowS && weightG - grams > GuardRail.dropGrams {
            phase = .paused
            coach("Scale moved — put the rig back and resume.", severity: "warning")
            return
        }
        // Guard: pour overshoot.
        if targetG > 0 && grams - targetG > GuardRail.overshootG {
            coach("You're \(Int(grams - targetG)) g over target — ease off.", severity: "warning")
        }

        weightG = grams
        history.append((now, grams))
        history.removeAll { now.timeIntervalSince($0.t) > GuardRail.flowWindowS }
        if let first = history.first, history.count > 1 {
            let span = now.timeIntervalSince(first.t)
            flowMlS = span > 0 ? (grams - first.w) / span : 0
        }

        eventLog.append(BrewSample(
            tMs: Int(elapsedS * 1000),
            phase: phase.rawValue,
            weightG: grams,
            flowMlS: flowMlS
        ))
        // TODO(day 4): phase transitions (ADD_COFFEE weight gate, BLOOM timer,
        // PULSE targets, DRAWDOWN settle detection) + vision event triggers.
    }
}
