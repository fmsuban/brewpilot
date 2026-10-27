import SwiftUI

struct BrewView: View {
    @EnvironmentObject var session: BrewSession

    var body: some View {
        ZStack {
            Color.espressoBlack.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text(session.phase.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.caramel)
                            .clipShape(Capsule())
                        Spacer()
                        Text(formatTimer(session.elapsedS))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.cream)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", session.weightG))
                                .font(.brewDisplay(88))
                                .monospacedDigit()
                                .foregroundStyle(Color.cream)
                            Text("g")
                                .font(.title.weight(.semibold))
                                .foregroundStyle(Color.creamDim)
                        }
                        Text("target \(Int(session.targetG)) g · Δ \(deltaText)")
                            .font(.subheadline)
                            .foregroundStyle(Color.creamDim)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionTitle(text: "Flow")
                            Spacer()
                            Text(String(format: "%.1f ml/s", session.flowMlS))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(flowColor)
                        }
                        FlowBar(flow: session.flowMlS)
                    }
                    .brewCard()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "Now")
                        Text(session.instruction)
                            .font(.headline)
                            .foregroundStyle(Color.cream)
                    }
                    .brewCard()

                    if !session.coachMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionTitle(text: "Coach")
                                .padding(.bottom, 8)
                            ForEach(session.coachMessages) { msg in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: msg.severity == "warning"
                                        ? "exclamationmark.triangle.fill"
                                        : "checkmark.circle.fill")
                                        .foregroundStyle(msg.severity == "warning"
                                            ? Color.brewRed : Color.brewGreen)
                                    Text(msg.text)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.cream)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                Divider().background(Color.espressoLine)
                            }
                        }
                        .brewCard()
                    }

                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.espressoCard)
                            VStack(spacing: 4) {
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(Color.creamDim)
                                Text("Camera")
                                    .font(.caption2)
                                    .foregroundStyle(Color.creamDim)
                            }
                        }
                        .frame(width: 110, height: 84)
                        Button(session.phase == .idle ? "Start brew" : "Brewing…") {
                            session.start(recipe: session.recipe)
                        }
                        .buttonStyle(BrewButtonStyle())
                        .disabled(session.phase != .idle)
                    }
                }
                .padding()
            }
        }
    }

    private var deltaText: String {
        String(format: "%+.1f g", session.weightG - session.targetG)
    }

    private var flowColor: Color {
        (4.0...7.0).contains(session.flowMlS) ? .brewGreen : .cream
    }
}

struct FlowBar: View {
    var flow: Double

    private let lo = 4.0, hi = 7.0, maxFlow = 12.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.espressoLine)
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.brewGreen.opacity(0.4))
                    .frame(width: zoneWidth(w), height: 10)
                    .offset(x: zoneOffset(w))
                Circle()
                    .fill(needleColor)
                    .frame(width: 16, height: 16)
                    .offset(x: needleOffset(w))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 20)
    }

    private func zoneWidth(_ w: CGFloat) -> CGFloat { w * CGFloat((hi - lo) / maxFlow) }
    private func zoneOffset(_ w: CGFloat) -> CGFloat { w * CGFloat(lo / maxFlow) }
    private func needleOffset(_ w: CGFloat) -> CGFloat {
        min(max(CGFloat(flow) / CGFloat(maxFlow), 0), 1) * w - 8
    }
    private var needleColor: Color {
        (lo...hi).contains(flow) ? .brewGreen : .caramel
    }
}
