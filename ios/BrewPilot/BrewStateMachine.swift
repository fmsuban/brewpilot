import Foundation

// Deterministic brew state machine (SPEC 8.1). Timing, targets and flow math
// live here, never in a model call. AI only plans, perceives and talks.

enum BrewPhase: String, Codable {
    case idle, prep, addCoffee, tare, bloom, pulse, rest, drawdown, done, paused
}

enum GuardRail {
    static let dropGrams = 8.0
    static let dropWindowS = 1.0
    static let overshootG = 5.0
    static let silenceS = 1.5
    static let flowWindowS = 0.5
    static let coffeeToleranceG = 2.0
    static let pourStartG = 3.0 // +3 g after the coffee tare starts the brew clock
    static let stepDoneG = 3.0 // settled within 3 g of target = that pour is finished
    static let stopLeadS = 0.5 // water in the air + reaction + speech latency
    static let pouringFlowMlS = 1.0
    static let flowOffRangeS = 2.0
    static let restMinS = 5.0
    static let pulseWindowS = 30.0 // step length when the recipe gives no duration_s
    static let visionAfterStopS = 1.5 // after settle (~1 s): kettle out of frame, bed visible
    static let bloomVisionS = 10.0
    // Drawdown: the scale sits under mug + dripper, so total mass stays flat
    // while the bed drains. Only the camera (or the brewer) can see it finish.
    static let drainPollStartS = 15.0
    static let drainPollS = 5.0
    static let drawdownSlowS = 90.0
    static let drawdownTimeoutS = 180.0
}

enum BrewEnd { case vision, manual, lifted, timeout }

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
    @Published var stepResults: [StepResult] = []
    @Published var scaleConnected = false
    @Published var scaleLost = false // silent > 1.5 s mid-brew
    @Published var pulseIndex = 0
    @Published var stopCue = false // pour reached target minus the stop lead
    @Published var visionThinking = false
    @Published var useOunces = UserDefaults.standard.bool(forKey: "useOunces") {
        didSet { UserDefaults.standard.set(useOunces, forKey: "useOunces") }
    }
    @Published var voiceOn = UserDefaults.standard.object(forKey: "voiceOn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(voiceOn, forKey: "voiceOn")
            speaker.enabled = voiceOn
        }
    }
    @Published var voiceVolume = UserDefaults.standard.object(forKey: "voiceVolume") as? Double ?? 0.6 {
        didSet {
            UserDefaults.standard.set(voiceVolume, forKey: "voiceVolume")
            speaker.volume = Float(voiceVolume)
        }
    }

    static let gPerOz = 28.3495
    var unitLabel: String { useOunces ? "oz" : "g" }
    func inUnits(_ grams: Double) -> Double { useOunces ? grams / Self.gPerOz : grams }
    /// Whole-number readout ("023"), zero-padded like a kitchen scale.
    func displayWeight(_ grams: Double) -> String {
        let r = inUnits(grams).rounded()
        if abs(r) >= 1000 {
            return String(format: "%4.0f", r)
        }
        if r < 0 {
            return String(format: "%04.0f", r) // "-023"
        }
        return String(format: "%03.0f", r) // "023"
    }

    func displayDelta(_ grams: Double) -> String {
        let r = inUnits(grams).rounded()
        if abs(r) >= 1000 {
            return String(format: "%+4.0f", r)
        }
        return String(format: "%+04.0f", r) // "+023"
    }
    /// Whole-number units for instructions, e.g. "150 g" / "5.3 oz".
    func unitStr(_ grams: Double) -> String {
        useOunces
            ? String(format: "%.1f oz", grams / Self.gPerOz)
            : String(format: "%.0f g", grams)
    }

    /// Signed delta for coach notes, e.g. "+8 g" / "±0 g".
    func signedStr(_ grams: Double) -> String {
        let r = useOunces ? (grams / Self.gPerOz * 10).rounded() / 10 : grams.rounded()
        if r == 0 { return "±0 \(unitLabel)" }
        return useOunces ? String(format: "%+.1f oz", r) : String(format: "%+.0f g", r)
    }

    /// Spoken form: TTS reads "150 g" badly.
    private func spoken(_ grams: Double) -> String {
        useOunces
            ? String(format: "%.1f ounces", grams / Self.gPerOz)
            : String(format: "%.0f grams", grams)
    }

    let scale = ScaleBLEManager()
    let camera: CameraManager
    private let vision: VisionCoach
    private let speaker = Speaker()
    private(set) var eventFrames: [String: Data] = [:] // JPEG per vision event, for the report
    private(set) var visionNotes: [String] = [] // structured observations, for the report

    private var history: [(t: Date, w: Double)] = [] // last 2 s of net weight
    private var lastSampleAt = Date()
    private var lastRaw = 0.0
    private var tareOffset = 0.0
    private var pausedFrom: BrewPhase = .idle
    private var pauseStartAt: Date?
    private var pausedTotalS = 0.0
    private var brewStartAt: Date? // first pour
    private var brewEndAt: Date?
    private var stepStartAt = Date()
    private var pourStopAt = Date()
    private var bloomPoured = false
    private var restBaseG = 0.0
    private var drawdownStartAt = Date()
    private var lastDrainPollAt = Date.distantPast
    private var flowOffSince: Date?
    private var warned: Set<String> = [] // one-shot warnings, keyed per step
    private var visionFired: Set<String> = []
    private var housekeeping: Timer?

    init() {
        let cam = CameraManager()
        camera = cam
        vision = VisionCoach(camera: cam)
        speaker.enabled = voiceOn
        speaker.volume = Float(voiceVolume)
        scale.onWeight = { [weak self] grams, settled in
            Task { @MainActor in
                // Dry run owns the feed: a connected scale would interleave real grams.
                guard !SimFeed.isActive else { return }
                self?.onWeight(grams, settled: settled)
            }
        }
        scale.onConnectionChange = { [weak self] connected in
            Task { @MainActor in self?.scaleConnected = connected }
        }
        vision.onThinking = { [weak self] in self?.visionThinking = $0 }
        vision.onFrame = { [weak self] event, jpeg in self?.eventFrames[event.name] = jpeg }
        vision.onResult = { [weak self] event, result in self?.applyVision(event, result) }
        housekeeping = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.housekeep() }
        }
    }

    /// Brew clock: starts on the first pour, excludes pauses, freezes at done.
    var elapsedS: Double {
        guard let start = brewStartAt else { return 0 }
        let end = brewEndAt ?? pauseStartAt ?? Date()
        return max(0, end.timeIntervalSince(start) - pausedTotalS)
    }

    var pulseSteps: [PourStep] { recipe.steps.filter { $0.id != "bloom" && $0.targetTotalG != nil } }

    private var bloomStep: PourStep? { recipe.steps.first(where: { $0.id == "bloom" }) }

    private var bloomDuration: Double { Double(bloomStep?.durationS ?? 45) }

    /// Green zone for the flow bar: the current pour step's range.
    var flowRange: ClosedRange<Double> {
        let step = phase == .bloom ? bloomStep : pulseSteps[safe: pulseIndex]
        guard let r = step?.flowMlS, r.count == 2, r[0] < r[1] else { return 4...7 }
        return r[0]...r[1]
    }

    /// True while the brewer should be pouring (the dry-run feed reads it too).
    var awaitingPour: Bool { (phase == .bloom && !bloomPoured) || phase == .pulse }

    func start(recipe: Recipe) {
        self.recipe = recipe
        phase = .prep
        eventLog = []
        coachMessages = []
        stepResults = []
        eventFrames = [:]
        visionNotes = []
        history = []
        brewStartAt = nil
        brewEndAt = nil
        pauseStartAt = nil
        pausedTotalS = 0
        stepStartAt = Date()
        tareOffset = 0
        weightG = 0
        flowMlS = 0
        targetG = 0
        pulseIndex = 0
        bloomPoured = false
        stopCue = false
        scaleLost = false
        flowOffSince = nil
        warned = []
        visionFired = []
        pausedFrom = .idle
        vision.reset()
        ProxyClient.shared.warmUp() // wake the Modal container before the first vision check
        updateInstruction()
    }

    /// Prep done: zero the wet filter + mug (SPEC 8.1 TARE), then dose.
    func confirmPrep() {
        guard phase == .prep else { return }
        tareOffset = lastRaw
        weightG = 0
        history.removeAll()
        phase = .addCoffee
        targetG = recipe.coffeeG
        stepStartAt = Date()
        coach("Tared. Add \(unitStr(recipe.coffeeG)) of ground coffee.")
        updateInstruction()
    }

    func resume() {
        guard phase == .paused else { return }
        if let p = pauseStartAt {
            let d = Date().timeIntervalSince(p)
            pausedTotalS += d
            // Shift wall-clock anchors so rests and drawdown don't count the pause.
            stepStartAt += d
            pourStopAt += d
            drawdownStartAt += d
        }
        pauseStartAt = nil
        history.removeAll()
        phase = pausedFrom
        coach("Resumed.")
        updateInstruction()
    }

    /// "Drained" button: the brewer saw the bed go dry.
    func markDrained() {
        guard phase == .drawdown else { return }
        finishBrew(.manual, now: Date())
    }

    func coach(_ text: String, severity: String = "info", origin: CoachOrigin = .local) {
        coachMessages.append(CoachMessage(text: text, severity: severity, origin: origin))
    }

    /// Sample line for the volume slider.
    func previewVoice() {
        say("Pour to 150 grams.", interrupt: true)
    }

    private func say(_ text: String, interrupt: Bool = false) {
        speaker.say(text, interrupt: interrupt)
    }

    private func warnOnce(_ key: String, _ text: String, spoken: String) {
        guard !warned.contains(key) else { return }
        warned.insert(key)
        coach(text, severity: "warning")
        say(spoken)
    }

    /// Called at 10 Hz from BLE (raw grams + the scale's settled flag).
    /// Guard rails first, then logging, then phase transitions.
    func onWeight(_ raw: Double, settled: Bool) {
        let now = Date()
        lastSampleAt = now
        lastRaw = raw
        if scaleLost {
            scaleLost = false
            coach("Scale back — carry on.")
        }
        let grams = raw - tareOffset
        history.append((now, grams))
        history.removeAll { now.timeIntervalSince($0.t) > 2 }

        // Guard: rig lifted or moved (> 8 g lost within 1 s). Dosing is exempt:
        // spooning coffee back out is fine.
        if [.bloom, .pulse, .rest, .drawdown].contains(phase),
           let peak = history.filter({ now.timeIntervalSince($0.t) <= GuardRail.dropWindowS }).map(\.w).max(),
           peak - grams > GuardRail.dropGrams {
            weightG = grams
            if phase == .drawdown {
                finishBrew(.lifted, now: now) // lifting the dripper off ends the brew
            } else {
                pause(now: now)
                coach("Scale moved — put the rig back and resume.", severity: "warning")
                say("Scale moved. Put the rig back.")
            }
            return
        }

        let tail = history.filter { now.timeIntervalSince($0.t) <= GuardRail.flowWindowS }
        if let first = tail.first, tail.count > 1 {
            let span = now.timeIntervalSince(first.t)
            flowMlS = span > 0 ? (grams - first.w) / span : 0
        }
        weightG = grams

        if ![.idle, .prep, .done, .paused].contains(phase) {
            eventLog.append(BrewSample(
                tMs: Int(elapsedS * 1000),
                phase: phase.rawValue,
                weightG: grams,
                flowMlS: flowMlS
            ))
        }
        tick(now: now, grams: grams, settled: settled)
    }

    // MARK: - Transitions

    private func tick(now: Date, grams: Double, settled: Bool) {
        switch phase {
        case .addCoffee:
            targetG = recipe.coffeeG
            // Wait for settled: mid-pour the weight passes 20 g on its way to 22.
            if settled && abs(grams - recipe.coffeeG) <= GuardRail.coffeeToleranceG {
                tareOffset += grams
                weightG = 0
                history.removeAll()
                phase = .bloom
                bloomPoured = false
                stopCue = false
                flowOffSince = nil
                stepStartAt = now
                targetG = bloomStep?.targetAddG ?? 50
                coach("Coffee in. Bloom — saturate everything.")
                say("Coffee in. Bloom to \(spoken(targetG)).")
            }
        case .bloom:
            if brewStartAt == nil && grams >= GuardRail.pourStartG {
                brewStartAt = now
            }
            if !bloomPoured {
                trackPour("bloom", now: now, grams: grams)
                if brewStartAt != nil && settled && grams >= targetG - GuardRail.stepDoneG {
                    bloomPoured = true
                    stopCue = false
                    pourStopAt = now
                    restBaseG = grams
                    recordStep("bloom", label: "Bloom", grams: grams, now: now)
                }
            } else {
                fireVision("bloom", label: "Bloom",
                           when: now.timeIntervalSince(pourStopAt) >= GuardRail.bloomVisionS)
                // Nudge, never block: an early pour starts pulse 1.
                if grams - restBaseG > GuardRail.pourStartG || elapsedS >= bloomDuration {
                    enterPulse(0, now: now)
                }
            }
        case .pulse:
            guard let step = pulseSteps[safe: pulseIndex] else {
                enterDrawdown(now: now)
                break
            }
            targetG = step.targetTotalG ?? targetG
            trackPour(step.id, now: now, grams: grams)
            if settled && grams >= targetG - GuardRail.stepDoneG {
                recordStep(step.id, label: "Pulse \(pulseIndex + 1)", grams: grams, now: now)
                if pulseIndex + 1 < pulseSteps.count {
                    enterRest(now: now, grams: grams)
                } else {
                    enterDrawdown(now: now)
                }
            }
        case .rest:
            if let step = pulseSteps[safe: pulseIndex] {
                fireVision("pulse_\(step.id)", label: "Pulse \(pulseIndex + 1)",
                           when: now.timeIntervalSince(pourStopAt) >= GuardRail.visionAfterStopS)
            }
            if grams - restBaseG > GuardRail.pourStartG || now >= nextPulseAt {
                enterPulse(pulseIndex + 1, now: now)
            }
        case .drawdown:
            fireVision("drawdown", label: "Drawdown",
                       when: now.timeIntervalSince(pourStopAt) >= GuardRail.visionAfterStopS)
        default:
            break
        }
        updateInstruction()
    }

    /// Stop cue, overshoot and flow-zone coaching for the pour in progress.
    private func trackPour(_ stepId: String, now: Date, grams: Double) {
        let pouring = flowMlS > GuardRail.pouringFlowMlS
        let projected = grams + max(0, flowMlS) * GuardRail.stopLeadS
        if !stopCue && (grams >= targetG - 0.5 || (pouring && projected >= targetG)) {
            stopCue = true
            say("Stop.", interrupt: true)
        }
        if grams - targetG > GuardRail.overshootG {
            warnOnce("over_\(stepId)", "Over target — stop pouring.", spoken: "Over. Stop pouring.")
        }
        // Flow zone: mid-pour only, not the ramp-up or the last grams.
        let zone = flowRange
        guard pouring && grams < targetG - 10 && !zone.contains(flowMlS) else {
            flowOffSince = nil
            return
        }
        let since = flowOffSince ?? now
        flowOffSince = since
        guard now.timeIntervalSince(since) >= GuardRail.flowOffRangeS else { return }
        let aim = String(format: "%.1f ml/s, aim %.0f–%.0f", flowMlS, zone.lowerBound, zone.upperBound)
        if flowMlS > zone.upperBound {
            warnOnce("flow_\(stepId)", "Slow down — \(aim).", spoken: "Slow down.")
        } else {
            warnOnce("flow_\(stepId)", "Pour a little faster — \(aim).", spoken: "A little faster.")
        }
    }

    private func recordStep(_ id: String, label: String, grams: Double, now: Date) {
        let delta = grams - targetG
        stepResults.append(StepResult(
            id: id,
            targetG: targetG,
            actualG: grams,
            durationS: now.timeIntervalSince(stepStartAt)
        ))
        if delta >= GuardRail.stepDoneG {
            coach("\(label): \(signedStr(delta)) over target.", severity: "warning")
        } else {
            coach("\(label): on target (\(signedStr(delta))).")
        }
    }

    private var nextPulseAt: Date {
        let window = pulseSteps[safe: pulseIndex]?.durationS.map(Double.init) ?? GuardRail.pulseWindowS
        return max(stepStartAt.addingTimeInterval(window),
                   pourStopAt.addingTimeInterval(GuardRail.restMinS))
    }

    private func enterPulse(_ i: Int, now: Date) {
        guard let step = pulseSteps[safe: i] else {
            enterDrawdown(now: now)
            return
        }
        pulseIndex = i
        phase = .pulse
        stepStartAt = now
        stopCue = false
        flowOffSince = nil
        targetG = step.targetTotalG ?? targetG
        coach("Pulse \(i + 1) of \(pulseSteps.count) — pour to \(unitStr(targetG)).")
        say("Pour to \(spoken(targetG)).")
    }

    private func enterRest(now: Date, grams: Double) {
        phase = .rest
        stopCue = false
        pourStopAt = now
        restBaseG = grams
    }

    private func enterDrawdown(now: Date) {
        phase = .drawdown
        stopCue = false
        pourStopAt = now
        drawdownStartAt = now
        lastDrainPollAt = now
        targetG = recipe.waterG
        coach("Last pour done — drawdown. Watching the bed drain.")
        say("Let it drain.")
    }

    private func pause(now: Date) {
        guard phase != .paused else { return }
        pausedFrom = phase
        phase = .paused
        pauseStartAt = now
        stopCue = false
        updateInstruction()
    }

    private func finishBrew(_ end: BrewEnd, now: Date) {
        guard phase != .done else { return }
        phase = .done
        brewEndAt = now
        stopCue = false
        let drawdownS = now.timeIntervalSince(drawdownStartAt)
        let poured = stepResults.last?.actualG ?? weightG
        let how: String
        switch end {
        case .vision: how = "Camera saw the bed go dry."
        case .manual: how = "Drained."
        case .lifted: how = "Dripper off."
        case .timeout: how = "Drawdown cap reached."
        }
        coach("\(how) Finished in \(formatTimer(elapsedS)) (drawdown \(formatTimer(drawdownS))), \(unitStr(poured)) of \(unitStr(recipe.waterG)).")
        say("Brew complete.")
        fireVision("final", label: "Final bed", when: true)
        updateInstruction()
    }

    // MARK: - Vision + housekeeping

    private func fireVision(_ name: String, label: String, when ready: Bool) {
        guard ready, !visionFired.contains(name) else { return }
        visionFired.insert(name)
        vision.request(VisionEvent(name: name, label: label, context: visionContext(step: name)))
    }

    private func visionContext(step: String) -> VisionContext {
        VisionContext(step: step, elapsedS: elapsedS, targetG: targetG)
    }

    private func applyVision(_ event: VisionEvent, _ v: VisionResult) {
        if v.bedDrained == true && phase == .drawdown {
            finishBrew(.vision, now: Date())
        }
        guard !event.silent else { return }
        let text = v.coaching.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        visionNotes.append("\(event.label): \(text) (bubbles \(v.bubbles), pour \(v.pourPosition), bed even \(v.bedEven), channeling \(v.channeling))")
        coach("\(event.label) · \(text)", severity: v.severity == "warning" ? "warning" : "info", origin: .vision)
        say(text)
    }

    /// 2 Hz: checks that must run even when no weight arrives.
    private func housekeep() {
        guard [.addCoffee, .bloom, .pulse, .rest, .drawdown].contains(phase) else { return }
        let now = Date()
        if !scaleLost && now.timeIntervalSince(lastSampleAt) > GuardRail.silenceS {
            scaleLost = true
            coach("Scale signal lost — hold the pour, reconnecting…", severity: "warning")
            say("Scale signal lost. Hold the pour.")
        }
        if phase == .drawdown {
            let t = now.timeIntervalSince(drawdownStartAt)
            if t >= GuardRail.drainPollStartS && now.timeIntervalSince(lastDrainPollAt) >= GuardRail.drainPollS {
                lastDrainPollAt = now
                vision.request(VisionEvent(
                    name: "drawdown_poll",
                    label: "Drawdown",
                    context: visionContext(step: "drawdown"),
                    silent: true
                ))
            }
            if t >= GuardRail.drawdownSlowS {
                warnOnce("slowDrawdown",
                         "Drawdown past \(formatTimer(GuardRail.drawdownSlowS)) — grind coarser next time.",
                         spoken: "Slow drawdown. Grind coarser next time.")
            }
            if t >= GuardRail.drawdownTimeoutS {
                finishBrew(.timeout, now: now)
            }
        }
        updateInstruction()
    }

    private func updateInstruction() {
        switch phase {
        case .idle:
            instruction = "Set up the rig, then start."
        case .prep:
            instruction = "Rinse the filter, dump the rinse water, set the dripper on the mug — then confirm."
        case .addCoffee:
            let d = weightG - recipe.coffeeG
            if d < -GuardRail.coffeeToleranceG {
                instruction = "Add coffee: \(unitStr(weightG)) of \(unitStr(recipe.coffeeG))."
            } else if d > GuardRail.coffeeToleranceG {
                instruction = "Too much coffee — remove \(unitStr(d))."
            } else {
                instruction = "Coffee in — hold still, taring…"
            }
        case .bloom:
            if brewStartAt == nil {
                instruction = "Bloom: pour \(unitStr(targetG)) over all the grounds."
            } else if !bloomPoured {
                instruction = "Bloom: pour to \(unitStr(targetG))."
            } else {
                let left = max(0, Int(bloomDuration - elapsedS))
                instruction = "Bloom: wait \(left)s, swirl once."
            }
        case .pulse:
            let zone = flowRange
            instruction = String(
                format: "Pulse %d/%d: pour to %@ at %.0f–%.0f ml/s.",
                pulseIndex + 1, pulseSteps.count, unitStr(targetG), zone.lowerBound, zone.upperBound
            )
        case .rest:
            let left = max(0, Int(nextPulseAt.timeIntervalSinceNow.rounded(.up)))
            let next = pulseSteps[safe: pulseIndex + 1]?.targetTotalG ?? recipe.waterG
            instruction = "Rest — next pour to \(unitStr(next)) in \(left)s."
        case .drawdown:
            let t = formatTimer(Date().timeIntervalSince(drawdownStartAt))
            instruction = "Drawdown \(t) — watching the bed. Tap Drained when it's dry."
        case .done:
            instruction = "Brew complete. Enjoy your cup."
        case .paused:
            instruction = "Paused — put the rig back and resume."
        case .tare:
            break // transient in-app; device tare is a separate BLE write
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
