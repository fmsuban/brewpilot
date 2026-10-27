import AVFoundation
import Foundation

// Rear camera, 720p, 1-deep frame buffer. Frames only leave the phone
// on state-machine events (SPEC 8.2): no continuous cloud streaming.

final class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false

    private let session = AVCaptureSession()
    private var latestFrame: CMSampleBuffer?
    private let lock = NSLock()

    func start() {
        guard !session.isRunning else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "brewpilot.camera"))
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
        isRunning = true
    }

    func stop() {
        session.stopRunning()
        isRunning = false
    }

    /// Grab the latest frame as ~640 px JPEG for one vision event.
    /// TODO(day 5): crop to overlay rect, downscale, JPEG q0.6.
    func grabJPEG() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard latestFrame != nil else { return nil }
        return nil // conversion lands with the vision wiring
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        lock.lock()
        latestFrame = sampleBuffer
        lock.unlock()
    }
}
