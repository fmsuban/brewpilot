import AVFoundation
import CoreImage
import ImageIO

// Rear camera, 720p portrait, 1-deep frame buffer. Frames only leave the phone
// on state-machine events (SPEC 8.2): no continuous cloud streaming.

final class CameraManager: NSObject, ObservableObject {
    /// Framing box in normalized portrait coordinates (top-left origin). The
    /// preview draws it and vision frames are cropped to it.
    static let framingRect = CGRect(x: 0.08, y: 0.18, width: 0.84, height: 0.64)

    @Published var isRunning = false
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "brewpilot.camera.session")
    private let frameQueue = DispatchQueue(label: "brewpilot.camera.frames")
    private var configured = false
    private var latestFrame: CVPixelBuffer?
    private let lock = NSLock()
    private let ciContext = CIContext()

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.run() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.sessionQueue.async { self.run() } }
            }
        default:
            break // denied: the brew runs on weight + local coaching only
        }
    }

    func stop() {
        sessionQueue.async {
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func run() {
        if !configured { configure() }
        guard configured else { return }
        if !session.isRunning { session.startRunning() }
        let running = session.isRunning
        DispatchQueue.main.async { self.isRunning = running }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return } // simulator: no camera
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)
        if let c = output.connection(with: .video), c.isVideoRotationAngleSupported(90) {
            c.videoRotationAngle = 90 // portrait buffers, matching the preview
        }
        configured = true
    }

    /// Latest frame cropped to the framing box, ≤ 320 px long edge, JPEG q0.6.
    /// 320 px saves ~2 s of Wonder latency vs 640 (7 s vs 9 s measured).
    func grabJPEG() -> Data? {
        lock.lock()
        let buffer = latestFrame
        lock.unlock()
        guard let buffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        let e = image.extent
        let r = Self.framingRect
        // CIImage has a bottom-left origin; framingRect is top-left.
        let crop = CGRect(x: e.minX + r.minX * e.width, y: e.minY + (1 - r.maxY) * e.height,
                          width: r.width * e.width, height: r.height * e.height)
        let scale = min(1, 320 / max(crop.width, crop.height))
        let out = image.cropped(to: crop).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return ciContext.jpegRepresentation(of: out, colorSpace: srgb, options: [quality: 0.6])
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        latestFrame = pixels
        lock.unlock()
    }
}
