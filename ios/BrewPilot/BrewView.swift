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
                        Button("Tare") { session.scale.tare() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(session.scaleConnected ? Color.caramel : Color.creamDim)
                            .disabled(!session.scaleConnected)
                        Text(formatTimer(session.elapsedS))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.cream)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(session.displayWeight(session.weightG))
                                .font(.brewDisplay(72))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .foregroundStyle(Color.cream)
                            Text(session.unitLabel)
                                .font(.title.weight(.semibold))
                                .foregroundStyle(Color.creamDim)
                        }
                        .frame(height: 88)
                        Text("target \(session.unitStr(session.targetG)) · Δ \(deltaText)")
                            .font(.subheadline)
                            .foregroundStyle(Color.creamDim)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionTitle(text: "Flow")
                            Spacer()
                            Text(String(format: "%5.1f ml/s", session.flowMlS))
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
                        phaseButton
                    }
                }
                .padding()
            }
        }
        .onAppear {
            if CommandLine.arguments.contains("-simulateWeights") {
                SimFeed.start(session)
            }
        }
        .onChange(of: session.phase) { _, p in
            UIApplication.shared.isIdleTimerDisabled = !(p == .idle || p == .done)
        }
    }

    @ViewBuilder
    private var phaseButton: some View {
        switch session.phase {
        case .idle:
            Button("Start brew") { session.start(recipe: session.recipe) }
                .buttonStyle(BrewButtonStyle())
        case .prep:
            Button("Confirm ready") { session.confirmPrep() }
                .buttonStyle(BrewButtonStyle())
        case .paused:
            Button("Resume") { session.resume() }
                .buttonStyle(BrewButtonStyle(accent: .brewGreen))
        case .done:
            Button("New brew") { session.start(recipe: session.recipe) }
                .buttonStyle(BrewButtonStyle())
        default:
            Button("Brewing…") {}
                .buttonStyle(BrewButtonStyle())
                .disabled(true)
        }
    }

    private var deltaText: String {
        "\(session.displayDelta(session.weightG - session.targetG)) \(session.unitLabel)"
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
