import AVFoundation
import SwiftUI

/// AVCaptureVideoPreviewLayer in SwiftUI. Aspect-fit in a 9:16 frame so the
/// framing box overlay matches the vision crop exactly.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let c = previewLayer.connection, c.isVideoRotationAngleSupported(90) {
                c.videoRotationAngle = 90
            }
        }
    }
}

/// Live preview + the dashed framing box. The preview layer only exists while
/// the card is on screen, so the Scale and Brew tabs never share one session
/// between two layers.
struct CameraCard: View {
    @ObservedObject var camera: CameraManager
    var height: CGFloat
    @State private var visible = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.espressoDeep)
            if camera.isRunning && visible {
                CameraPreview(session: camera.session)
                GeometryReader { geo in
                    let r = CameraManager.framingRect
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.caramel, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: geo.size.width * r.width, height: geo.size.height * r.height)
                        .position(x: geo.size.width * r.midX, y: geo.size.height * r.midY)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                    Text("No camera")
                        .font(.caption2)
                }
                .foregroundStyle(Color.creamDim)
            }
        }
        .frame(width: height * 9 / 16, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}
