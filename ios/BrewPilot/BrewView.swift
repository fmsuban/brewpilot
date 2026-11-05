import SwiftUI

struct BrewView: View {
    @EnvironmentObject var session: BrewSession

    var body: some View {
        ZStack {
            Color.espressoBlack.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        Text(session.phase.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.caramel)
                            .clipShape(Capsule())
                        Spacer()
                        Button { session.voiceOn.toggle() } label: {
                            Image(systemName: session.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        }
                        .foregroundStyle(session.voiceOn ? Color.caramel : Color.creamDim)
                        .accessibilityLabel(session.voiceOn ? "Mute voice coach" : "Unmute voice coach")
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

                    if session.scaleLost {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.brewRed)
                            Text("Scale signal lost — hold the pour, reconnecting…")
                                .font(.subheadline)
                                .foregroundStyle(Color.cream)
                        }
                        .brewCard()
                    }

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
                        SectionTitle(text: "Now")
                        if session.stopCue {
                            Text("STOP")
                                .font(.brewDisplay(44))
                                .foregroundStyle(Color.brewRed)
                        } else {
                            Text(session.instruction)
                                .font(.headline)
                                .foregroundStyle(Color.cream)
                        }
                    }
                    .brewCard()

                    if !session.coachMessages.isEmpty || session.visionThinking {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                SectionTitle(text: "Coach")
                                Spacer()
                                if session.visionThinking {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(Color.caramel)
                                        Text("Looking…")
                                            .font(.caption)
                                            .foregroundStyle(Color.creamDim)
                                    }
                                }
                            }
                            .padding(.bottom, 8)
                            ForEach(recentCoach) { msg in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: icon(for: msg))
                                        .foregroundStyle(iconColor(for: msg))
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
                        CameraCard(camera: session.camera, height: 150)
                        phaseButton
                    }
                }
                .padding()
            }
        }
        .onAppear {
            session.camera.start()
            if CommandLine.arguments.contains("-simulateWeights") {
                SimFeed.start(session)
            }
        }
        .onChange(of: session.phase) { _, p in
            UIApplication.shared.isIdleTimerDisabled = !(p == .idle || p == .done)
        }
    }

    /// Newest first; the full list lives in the Report tab.
    private var recentCoach: [CoachMessage] {
        Array(session.coachMessages.suffix(6).reversed())
    }

    private func icon(for msg: CoachMessage) -> String {
        if msg.origin == .vision { return "eye.fill" }
        return msg.severity == "warning" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private func iconColor(for msg: CoachMessage) -> Color {
        if msg.severity == "warning" { return .brewRed }
        return msg.origin == .vision ? .caramel : .brewGreen
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
        case .drawdown:
            Button("Drained") { session.markDrained() }
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

}

