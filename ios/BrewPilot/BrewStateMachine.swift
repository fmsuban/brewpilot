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
    static let coffeeToleranceG = 2.0
}

@MainActor
final class BrewSession: ObservableObject {
    @Published var phase: BrewPhase = .idle
    @Published var recipe: Recipe = .canned
    @Published var weightG = 0.0 // net grams (app-side tare applied)
    @Published var flowMlS = 0.0
    @Published var targetG = 0.0
    @Published var instruction = "Set up the rig, then start."
    @Published var coachMessages: [CoachMessage] = []
    @Published var eventLog: [BrewSample] = []
    @Published var scaleConnected = false
    @Published var pulseIndex = 0

    let scale = ScaleBLEManager()
    private var history: [(t: Date, w: Double)] = []
    private var lastSampleAt = Date()
    private var startedAt = Date()
    private var tareOffset = 0.0
    private var pausedFrom: BrewPhase = .idle
    private var stepStartAt = Date()
    private var bloomPoured = false
    private var lowFlowStart: Date?
    private var visionFired: Set<String> = []
    var pendingVisionEvents: [String] = [] // day 5: drained by real Wonder calls

    init() {
        scale.onWeight = { [weak self] grams in
            Task { @MainActor in self?.onWeight(grams) }
        }
        scale.onConnectionChange = { [weak self] connected in
            Task { @MainActor in self?.scaleConnected = connected }
        }
    }

    var elapsedS: Double { Date().timeIntervalSince(startedAt) }

    var pulseSteps: [PourStep] { recipe.steps.filter { $0.targetTotalG != nil } }

    private var bloomDuration: Int {
        recipe.steps.first(where: { $0.id == "bloom" })?.durationS ?? 45
    }

    func start(recipe: Recipe) {
        self.recipe = recipe
        phase = .prep
        eventLog = []
        coachMessages = []
        history = []
        startedAt = Date()
        stepStartAt = Date()
        tareOffset = 0
        weightG = 0
        flowMlS = 0
        targetG = 0
        pulseIndex = 0
        bloomPoured = false
        lowFlowStart = nil
        visionFired = []
        pendingVisionEvents = []
        pausedFrom = .idle
        updateInstruction()
    }

    func confirmPrep() {
        guard phase == .prep else { return }
        phase = .addCoffee
        targetG = recipe.coffeeG
        stepStartAt = Date()
        updateInstruction()
    }

    func resume() {
        guard phase == .paused else { return }
        phase = pausedFrom
        coach("Resumed.")
    }

    func coach(_ text: String, severity: String = "info") {
        coachMessages.append(CoachMessage(text: text, severity: severity))
    }

    /// Called at 10 Hz from BLE (raw grams). Guard rails first, then logging,
    /// then phase transitions.
    func onWeight(_ raw: Double) {
        let now = Date()
        let dt = now.timeIntervalSince(lastSampleAt)
        lastSampleAt = now
        let grams = raw - tareOffset

        // Guard: rig lifted or moved.
        if dt > 0 && dt < GuardRail.dropWindowS && weightG - grams > GuardRail.dropGrams {
            if phase != .paused { pausedFrom = phase }
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
        tick(now: now, grams: grams)
    }

    // MARK: - Transitions

    private func tick(now: Date, grams: Double) {
        switch phase {
        case .addCoffee:
            targetG = recipe.coffeeG
            if abs(grams - recipe.coffeeG) <= GuardRail.coffeeToleranceG {
                tareOffset += grams
                weightG = 0
                history.removeAll()
                phase = .bloom
                bloomPoured = false
                stepStartAt = now
                targetG = recipe.steps.first(where: { $0.id == "bloom" })?.targetAddG ?? 50
                coach("Coffee in. Bloom — saturate everything.")
            }
            updateInstruction()
        case .bloom:
            fireVisionOnce("bloom+10", when: now.timeIntervalSince(stepStartAt) >= 10)
            if !bloomPoured {
                if grams >= targetG {
                    bloomPoured = true
                    stepStartAt = now
                    coach("Bloom poured. Let it sit.")
                }
            } else if now.timeIntervalSince(stepStartAt) >= Double(bloomDuration) {
                enterPulse(0, now: now)
            }
            updateInstruction()
        case .pulse:
            guard pulseIndex < pulseSteps.count else { enterDrawdown(now: now); return }
            targetG = pulseSteps[pulseIndex].targetTotalG ?? targetG
            if grams >= targetG - 1.0 {
                fireVision("pulse_\(pulseSteps[pulseIndex].id)")
                if pulseIndex + 1 < pulseSteps.count {
                    enterPulse(pulseIndex + 1, now: now)
                } else {
                    enterDrawdown(now: now)
                }
            }
            updateInstruction()
        case .drawdown:
            if flowMlS < GuardRail.drawdownFlowMlS {
                if lowFlowStart == nil { lowFlowStart = now }
                if now.timeIntervalSince(lowFlowStart!) >= GuardRail.drawdownSettleS {
                    finishBrew()
                }
            } else {
                lowFlowStart = nil
            }
            if now.timeIntervalSince(stepStartAt) >= GuardRail.drawdownTimeoutS {
                finishBrew()
            }
        default:
            break
        }
    }

    private func enterPulse(_ i: Int, now: Date) {
        pulseIndex = i
        phase = .pulse
        stepStartAt = now
        targetG = pulseSteps[i].targetTotalG ?? targetG
        coach("Pulse \(i + 1) of \(pulseSteps.count) — pour to \(Int(targetG)) g.")
        updateInstruction()
    }

    private func enterDrawdown(now: Date) {
        phase = .drawdown
        stepStartAt = now
        lowFlowStart = nil
        targetG = recipe.waterG
        fireVision("drawdown")
        updateInstruction()
    }

    private func finishBrew() {
        guard phase != .done else { return }
        phase = .done
        fireVision("final")
        coach(String(
            format: "Finished in %@ at %.0f g (target %.0f).",
            formatTimer(elapsedS), weightG, recipe.waterG
        ))
        updateInstruction()
    }

    private func fireVision(_ name: String) {
        guard !visionFired.contains(name) else { return }
        visionFired.insert(name)
        pendingVisionEvents.append(name)
        print("[vision] event: \(name)")
    }

    private func fireVisionOnce(_ name: String, when ready: Bool) {
        if ready { fireVision(name) }
    }

    private func updateInstruction() {
        switch phase {
        case .idle:
            instruction = "Set up the rig, then start."
        case .prep:
            instruction = "Rinse the filter, heat the kettle, then confirm."
        case .addCoffee:
            let d = weightG - recipe.coffeeG
            if d < -GuardRail.coffeeToleranceG {
                instruction = String(format: "Add coffee: %.0f g of %.0f.", weightG, recipe.coffeeG)
            } else if d > GuardRail.coffeeToleranceG {
                instruction = "Too much coffee — remove \(Int(d)) g."
            } else {
                instruction = "Coffee in — taring…"
            }
        case .bloom:
            if !bloomPoured {
                instruction = "Saturate all grounds — pour to \(Int(targetG)) g."
            } else {
                let left = max(0, bloomDuration - Int(Date().timeIntervalSince(stepStartAt)))
                instruction = "Bloom: wait \(left)s, swirl once."
            }
        case .pulse:
            if pulseIndex < pulseSteps.count {
                instruction = "Pulse \(pulseIndex + 1)/\(pulseSteps.count): pour to \(Int(targetG)) g."
            }
        case .drawdown:
            instruction = "Drawdown — let it drain."
        case .done:
            instruction = "Brew complete. Enjoy your cup."
        case .paused:
            instruction = "Paused — put the rig back and resume."
        case .tare:
            break // transient in-app; device tare is a separate BLE write
        }
    }
}
