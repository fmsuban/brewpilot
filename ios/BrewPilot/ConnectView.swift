import SwiftUI

/// Scale screen: connection, live weight, tare, units, timer and calibration.
/// The scale is headless — everything the old TFT + buttons did lives here.
struct ConnectView: View {
    @EnvironmentObject var session: BrewSession
    @ObservedObject var scale: ScaleBLEManager
    @StateObject private var stopwatch = ScaleStopwatch()

    @State private var calStep = 0 // 0 empty+tare, 1 place mass, 2 done
    @State private var calPreset = "200"
    @State private var calCustom = ""
    @State private var calPending: Double? // mass awaiting device confirmation
    @State private var calError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.espressoBlack.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        connectionCard
                        weightCard
                        timerCard
                        voiceCard
                        calibrationCard
                        framingCard
                        checklistCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Scale")
            .toolbarBackground(Color.espressoBlack, for: .navigationBar)
            .onAppear {
                session.scale.startScanning()
                session.camera.start()
            }
            .onChange(of: scale.weightG) { _, g in
                stopwatch.onWeight(g)
                if let pending = calPending, abs(g - pending) <= max(3, pending * 0.2) {
                    calPending = nil
                    calError = nil
                    calStep = 2
                }
            }
        }
    }

    // MARK: - Connection

    private var connectionCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(session.scaleConnected ? Color.brewGreen : Color.caramel)
                    .frame(width: 12, height: 12)
                Text(session.scaleConnected ? "Scale connected" : "Looking for scale…")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.cream)
                Spacer()
            }
            HStack(spacing: 10) {
                Image(systemName: "scalemass")
                Text(scale.peripheralName ?? "BrewPilot-Scale")
                Spacer()
                if session.scaleConnected {
                    Text("\(scale.droppedPackets) dropped")
                        .monospacedDigit()
                    Text("🔋 \(scale.batteryPct)%")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.creamDim)
            if session.scaleConnected {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let last = scale.lastPacketAt, Date().timeIntervalSince(last) > 1.5 {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.brewRed)
                            Text("Scale silent — reconnecting…")
                                .font(.subheadline)
                                .foregroundStyle(Color.cream)
                        }
                    }
                }
            }
        }
        .brewCard()
    }

    // MARK: - Live weight

    private var weightCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(scale.settled ? Color.brewGreen : Color.caramel)
                    .frame(width: 10, height: 10)
                Text(session.displayWeight(scale.weightG))
                    .font(.brewDisplay(52))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(scale.overload ? Color.brewRed : Color.cream)
                Text(session.unitLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.creamDim)
                Spacer()
                Text(String(format: "%5.1f ml/s", session.flowMlS))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(Color.creamDim)
            }
            .frame(height: 64)
            if scale.overload {
                Text("Overload — remove weight (max 1 kg).")
                    .font(.subheadline)
                    .foregroundStyle(Color.brewRed)
            }
            HStack(spacing: 10) {
                OptionChips(
                    options: [("g", "g"), ("oz", "oz")],
                    selection: Binding(
                        get: { session.useOunces ? "oz" : "g" },
                        set: { session.useOunces = ($0 == "oz") }
                    )
                )
                Spacer()
                Button("Tare") { scale.tare() }
                    .buttonStyle(BrewButtonStyle(
                        accent: session.scaleConnected ? .caramel : .espressoLine,
                        label: session.scaleConnected ? .black : .creamDim
                    ))
                    .disabled(!session.scaleConnected)
                    .frame(maxWidth: 160)
            }
        }
        .brewCard()
    }

    // MARK: - Timer

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Timer")
            HStack(alignment: .firstTextBaseline) {
                Text(formatTimer(stopwatch.elapsed))
                    .font(.brewDisplay(44))
                    .monospacedDigit()
                    .foregroundStyle(Color.cream)
                Spacer()
                Toggle("Auto-start", isOn: $stopwatch.autoStart)
                    .font(.subheadline)
                    .foregroundStyle(Color.creamDim)
                    .frame(maxWidth: 150)
            }
            Text("Auto-start begins on the first pour (+3 g).")
                .font(.caption)
                .foregroundStyle(Color.creamDim)
            HStack(spacing: 10) {
                if stopwatch.running {
                    Button("Stop") { stopwatch.stop() }
                        .buttonStyle(BrewButtonStyle())
                } else {
                    Button("Start") { stopwatch.start() }
                        .buttonStyle(BrewButtonStyle())
                }
                Button("Reset") { stopwatch.reset() }
                    .buttonStyle(BrewButtonStyle(accent: .espressoLine, label: .cream))
            }
        }
        .brewCard()
    }

    // MARK: - Voice coach

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "Voice coach")
                Spacer()
                Toggle("", isOn: $session.voiceOn)
                    .labelsHidden()
                    .tint(Color.caramel)
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(Color.creamDim)
                Slider(value: $session.voiceVolume, in: 0.1...1) { editing in
                    if !editing { session.previewVoice() }
                }
                .tint(Color.caramel)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(Color.creamDim)
            }
            .disabled(!session.voiceOn)
            .opacity(session.voiceOn ? 1 : 0.5)
            Text("Relative to the phone's media volume. Release the slider to hear a sample.")
                .font(.caption)
                .foregroundStyle(Color.creamDim)
        }
        .brewCard()
    }

    // MARK: - Calibration

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Calibration")
            if calStep == 0 {
                Text("1. Empty the scale, then tare.")
                    .font(.subheadline)
                    .foregroundStyle(Color.cream)
                Button("Tare empty scale") {
                    scale.tare()
                    calStep = 1
                }
                .buttonStyle(BrewButtonStyle())
                .disabled(!session.scaleConnected)
            } else if calStep == 1 {
                Text("2. Place a known mass, pick its weight, then save.")
                    .font(.subheadline)
                    .foregroundStyle(Color.cream)
                Text("On scale: \(session.displayWeight(scale.weightG)) \(session.unitLabel)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.cream)
                Text("The number looks wrong until the first calibration — that's normal. The mass must be on the scale before you tap Save.")
                    .font(.caption)
                    .foregroundStyle(Color.creamDim)
                if scale.weightG < -1000 {
                    Text("Negative before calibration is fine — the scale handles inverted wiring automatically.")
                        .font(.caption)
                        .foregroundStyle(Color.creamDim)
                }
                OptionChips(
                    options: [("100", "100 g"), ("200", "200 g"), ("500", "500 g"), ("custom", "Custom")],
                    selection: $calPreset
                )
                if calPreset == "custom" {
                    TextField("Mass in grams", text: $calCustom)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                Button(calPending == nil ? "Save calibration" : "Confirming…") {
                    guard let grams = calibrationMass else { return }
                    scale.calibrate(knownGrams: Float(grams))
                    calPending = grams
                    calError = nil
                    Task { @MainActor in // the device must report ~mass within 3 s
                        try? await Task.sleep(for: .seconds(3))
                        guard calPending == grams else { return } // confirmed already
                        calPending = nil
                        calError = "The scale didn't confirm. Was the mass on it? If so, check the load cell wiring."
                    }
                }
                .buttonStyle(BrewButtonStyle())
                .disabled(!session.scaleConnected || calibrationMass == nil || calPending != nil)
                .opacity(!session.scaleConnected || calibrationMass == nil || calPending != nil ? 0.5 : 1)
                if calPending != nil {
                    Text("Keep the mass on the scale…")
                        .font(.caption)
                        .foregroundStyle(Color.creamDim)
                }
                if let calError {
                    Text(calError)
                        .font(.caption)
                        .foregroundStyle(Color.brewRed)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brewGreen)
                    Text("Calibration saved on the scale.")
                        .font(.subheadline)
                        .foregroundStyle(Color.cream)
                }
                Button("Recalibrate") { calStep = 0 }
                    .buttonStyle(BrewButtonStyle(accent: .espressoLine, label: .cream))
            }
        }
        .brewCard()
    }

    private var calibrationMass: Double? {
        if calPreset == "custom" {
            guard let v = Double(calCustom), v > 0, v <= 1000 else { return nil }
            return v
        }
        return Double(calPreset)
    }

    // MARK: - Camera + checklist

    private var framingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Camera framing")
            HStack {
                Spacer()
                CameraCard(camera: session.camera, height: 280)
                Spacer()
            }
            Text("Keep the dripper and the coffee bed inside the dashed box — that's all the coach sees.")
                .font(.caption)
                .foregroundStyle(Color.creamDim)
        }
        .brewCard()
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Rig checklist")
            ForEach(rigTips, id: \.self) { tip in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brewGreen)
                    Text(tip)
                        .font(.subheadline)
                        .foregroundStyle(Color.cream)
                    Spacer()
                }
            }
        }
        .brewCard()
    }

    private var rigTips: [String] {
        [
            "Scale under mug + dripper, nothing touching",
            "iPhone on stand, 30 cm from the brewer",
            "Kettle hot, filter rinsed",
        ]
    }
}
