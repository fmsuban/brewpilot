import Foundation

/// One vision check requested by the state machine.
struct VisionEvent {
    var name: String // "bloom", "pulse_p1", "drawdown", "drawdown_poll", "final"
    var label: String // shown before the coaching, e.g. "Pulse 1"
    var context: VisionContext
    var silent = false // drawdown polls: only bed_drained matters, no bubble
}

/// Runs vision checks off the timing loop: grabs a frame, asks Muse Wonder via
/// the proxy, hands the observation back. One call in flight; polls are
/// dropped rather than queued so results never pile up behind the brew.
/// Proxy fallbacks are ignored: a canned line is not something the camera saw.
@MainActor
final class VisionCoach {
    var onThinking: ((Bool) -> Void)?
    var onFrame: ((VisionEvent, Data) -> Void)?
    var onResult: ((VisionEvent, VisionResult) -> Void)?

    private let camera: CameraManager
    private var queue: [VisionEvent] = []
    private var inFlight = false
    private var generation = 0 // bumps on reset so a stale reply can't reach a new brew

    init(camera: CameraManager) {
        self.camera = camera
    }

    func request(_ event: VisionEvent) {
        if event.silent && (inFlight || !queue.isEmpty) { return }
        queue.append(event)
        pump()
    }

    func reset() {
        queue.removeAll()
        generation += 1
    }

    private func pump() {
        guard !inFlight, !queue.isEmpty else { return }
        let event = queue.removeFirst()
        let gen = generation
        let camera = self.camera
        inFlight = true
        onThinking?(true)
        Task {
            let grabbed = await Task.detached { camera.grabJPEG() }.value
            if let frame = grabbed ?? SimFeed.frame() {
                if !event.silent { onFrame?(event, frame) }
                do {
                    let reply = try await ProxyClient.shared.postVision(frame: frame, context: event.context)
                    if reply.source != "model" {
                        print("[vision] \(event.name): proxy fallback, ignored")
                    } else if gen == generation {
                        onResult?(event, reply.vision)
                    }
                } catch {
                    print("[vision] \(event.name) failed: \(error)")
                }
            } else {
                print("[vision] \(event.name): no frame")
            }
            inFlight = false
            onThinking?(false)
            pump()
        }
    }
}
